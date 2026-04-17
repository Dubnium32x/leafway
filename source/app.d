/*

    Leafway - A simple 3D DOOM style map maker for Playdate made with raylib in D.

    This project is open source and licensed under the GPL-3.0 License.
    You can find the source code and contribute to the project.

    Run the project with `dub run` if not already compiled.

*/

import std.stdio;
import std.conv : to;
import std.string;
import std.string : strip;
import std.process : execute, executeShell;
import core.stdc.math : fmod, floor, atan2, sin, cos, fabs, sqrt, tan;
import std.file;
import std.path : baseName, buildPath;
import std.array;
import std.exception;
import std.algorithm;

import raylib;
import raygui;

enum toolbarHeight = 40.0f;
enum toolbarPadding = 8.0f;
enum backgroundSpeed = 28.0f;
enum mapGridCellSize = 8.0f;
enum majorGridInterval = 8;
enum chunkPreviewTextureWidth = 320;
enum chunkPreviewTextureHeight = 200;

struct GridCell {
    int column;
    int row;
}

struct MapChunk {
    int column;
    int row;
    int width;
    int height;
    int layer = 0;
}

enum ChunkTool {
    draw,
    move,
    resize,
    deleteChunk,
    edit,
}

enum AppScreen {
    map,
    chunkEditor,
}

enum ChunkEditorTool {
    placePoint,
    selectPoint,
    placeEntity,
    placeObject,
}

enum EntityType {
    player,
    npc,
    fishCommon,
    fishRare,
    fishLegendary,
    bird,
    insect,
    treasureChest,
    festivalDecoration,
}

enum ObjectType {
    hut,
    tree,
    rock,
    crate,
    chair,
    table,
    boat,
    dock,
    building,
    buoy,
    fishingNet,
    coral,
    underwaterRock,
    festivalProp,
}

struct ChunkEntity {
    float x;
    float z;
    float rotationX;
    float rotationY;  // Yaw - horizontal rotation (look direction)
    float rotationZ;
    float scaleX;
    float scaleY;
    float scaleZ;
    EntityType type;
}

struct ChunkObject {
    float x;
    float y;  // Objects have height!
    float z;
    float rotationX;
    float rotationY;  // Yaw - horizontal rotation (look direction)
    float rotationZ;
    float scaleX;
    float scaleY;
    float scaleZ;
    ObjectType type;
}

struct ChunkPoint {
    int x;
    int z;
}

struct ChunkFace {
    int[] pointIndices;
    int floorHeight;
    int ceilingHeight;
    int paletteIndex;
    bool autoWallFromHeightDifference;
    bool sameFloorAndCeiling;
}

struct ChunkWall {
    int startPointIndex;
    int endPointIndex;
    int floorHeight;
    int ceilingHeight;
    int paletteIndex;
}

struct ChunkGeometry {
    ChunkPoint[] points;
    ChunkFace[] faces;
    ChunkWall[] walls;
    ChunkEntity[] entities;
    ChunkObject[] objects;
}

struct GridLayout {
    Rectangle canvasRect;
    Camera2D camera;
    float cellSize;
}

struct PreviewWorldBounds {
    Rectangle horizontal;
    float minHeight;
    float maxHeight;
}

private int clampInt(int value, int minimum, int maximum)
{
    if (value < minimum) return minimum;
    if (value > maximum) return maximum;
    return value;
}

private float absFloat(float value)
{
    return value < 0.0f ? -value : value;
}

private int positiveModulo(int value, int divisor)
{
    const remainder = value % divisor;
    return remainder < 0 ? remainder + divisor : remainder;
}

private Rectangle getMapCanvasRect(bool showInspector)
{
    const leftMargin = 24.0f;
    const top = toolbarHeight + 24.0f;
    const rightInset = showInspector ? 320.0f : 24.0f;
    const width = cast(float)GetScreenWidth() - leftMargin - rightInset;
    const height = cast(float)GetScreenHeight() - top - 24.0f;
    return Rectangle(leftMargin, top, width, height);
}

private Rectangle getInspectorRect()
{
    const width = 272.0f;
    const x = cast(float)GetScreenWidth() - width - 24.0f;
    const y = toolbarHeight + 24.0f;
    const height = cast(float)GetScreenHeight() - y - 24.0f;
    return Rectangle(x, y, width, height);
}

private Rectangle getChunkPreviewPanelRect(Rectangle canvasRect)
{
    const panelWidth = cast(float)chunkPreviewTextureWidth + 16.0f;
    const panelHeight = cast(float)chunkPreviewTextureHeight + 32.0f;
    return Rectangle(
        canvasRect.x + canvasRect.width - panelWidth - 16.0f,
        canvasRect.y + 16.0f,
        panelWidth,
        panelHeight
    );
}

private Rectangle getChunkPreviewContentRect(Rectangle panelRect)
{
    return Rectangle(panelRect.x + 8.0f, panelRect.y + 24.0f, chunkPreviewTextureWidth, chunkPreviewTextureHeight);
}

private GridLayout getGridLayout(Rectangle canvasRect, Camera2D camera)
{
    return GridLayout(canvasRect, camera, mapGridCellSize);
}

private GridCell getGridCellAtPoint(Vector2 mousePosition, GridLayout gridLayout)
{
    const worldPosition = GetScreenToWorld2D(mousePosition, gridLayout.camera);
    return GridCell(
        cast(int)floor(worldPosition.x / gridLayout.cellSize),
        cast(int)floor(worldPosition.y / gridLayout.cellSize)
    );
}

private MapChunk makeChunkFromCells(GridCell startCell, GridCell endCell)
{
    const left = startCell.column < endCell.column ? startCell.column : endCell.column;
    const top = startCell.row < endCell.row ? startCell.row : endCell.row;
    const right = startCell.column > endCell.column ? startCell.column : endCell.column;
    const bottom = startCell.row > endCell.row ? startCell.row : endCell.row;

    return MapChunk(left, top, right - left + 1, bottom - top + 1);
}

private Rectangle getChunkRect(MapChunk chunk, GridLayout gridLayout)
{
    return Rectangle(
        chunk.column * gridLayout.cellSize,
        chunk.row * gridLayout.cellSize,
        chunk.width * gridLayout.cellSize,
        chunk.height * gridLayout.cellSize
    );
}

private Rectangle getNormalizedRectangleFromPoints(Vector2 startPoint, Vector2 endPoint)
{
    const minX = startPoint.x < endPoint.x ? startPoint.x : endPoint.x;
    const minY = startPoint.y < endPoint.y ? startPoint.y : endPoint.y;
    const maxX = startPoint.x > endPoint.x ? startPoint.x : endPoint.x;
    const maxY = startPoint.y > endPoint.y ? startPoint.y : endPoint.y;
    return Rectangle(minX, minY, maxX - minX, maxY - minY);
}

private bool chunksOverlap(MapChunk a, MapChunk b)
{
    const aRight = a.column + a.width - 1;
    const aBottom = a.row + a.height - 1;
    const bRight = b.column + b.width - 1;
    const bBottom = b.row + b.height - 1;

    return !(aRight < b.column || bRight < a.column || aBottom < b.row || bBottom < a.row);
}

private bool isChunkPlacementValid(MapChunk candidate, MapChunk[] placedChunks, int ignoredIndex = -1)
{
    if (candidate.width <= 0 || candidate.height <= 0) {
        return false;
    }

    foreach (index, chunk; placedChunks) {
        if (cast(int)index == ignoredIndex) {
            continue;
        }

        if (candidate.layer == chunk.layer && chunksOverlap(candidate, chunk)) {
            return false;
        }
    }

    return true;
}

private bool chunkContainsCell(MapChunk chunk, GridCell cell)
{
    return cell.column >= chunk.column
        && cell.column < chunk.column + chunk.width
        && cell.row >= chunk.row
        && cell.row < chunk.row + chunk.height;
}

private int findChunkAtCell(MapChunk[] placedChunks, GridCell cell)
{
    for (int index = cast(int)placedChunks.length - 1; index >= 0; index--) {
        if (chunkContainsCell(placedChunks[index], cell)) {
            return index;
        }
    }

    return -1;
}

private ChunkPoint getChunkPointAtWorldPosition(Vector2 worldPosition, MapChunk chunk)
{
    const maxX = chunk.width * cast(int)mapGridCellSize;
    const maxZ = chunk.height * cast(int)mapGridCellSize;
    const snappedX = cast(int)floor(worldPosition.x / mapGridCellSize + 0.5f) * cast(int)mapGridCellSize;
    const snappedZ = cast(int)floor(worldPosition.y / mapGridCellSize + 0.5f) * cast(int)mapGridCellSize;
    return ChunkPoint(
        clampInt(snappedX, 0, maxX),
        clampInt(snappedZ, 0, maxZ)
    );
}

private Vector2 getChunkPointPosition(ChunkPoint point)
{
    return Vector2(cast(float)point.x, cast(float)point.z);
}

private bool chunkGeometryHasPoint(ChunkGeometry geometry, ChunkPoint point)
{
    foreach (existingPoint; geometry.points) {
        if (existingPoint.x == point.x && existingPoint.z == point.z) {
            return true;
        }
    }

    return false;
}

private int findPointAtWorldPosition(ChunkGeometry geometry, Vector2 worldPosition, float threshold)
{
    for (int index = cast(int)geometry.points.length - 1; index >= 0; index--) {
        const pointPosition = getChunkPointPosition(geometry.points[index]);
        const deltaX = pointPosition.x - worldPosition.x;
        const deltaY = pointPosition.y - worldPosition.y;
        if (deltaX * deltaX + deltaY * deltaY <= threshold * threshold) {
            return index;
        }
    }

    return -1;
}

private Vector2 getFaceCentroid(ChunkGeometry geometry, ChunkFace face)
{
    float sumX = 0.0f;
    float sumY = 0.0f;

    foreach (pointIndex; face.pointIndices) {
        if (pointIndex >= 0 && pointIndex < cast(int)geometry.points.length) {
            const pointPosition = getChunkPointPosition(geometry.points[pointIndex]);
            sumX += pointPosition.x;
            sumY += pointPosition.y;
        }
    }

    if (face.pointIndices.length == 0) {
        return Vector2.zero;
    }

    return Vector2(sumX / face.pointIndices.length, sumY / face.pointIndices.length);
}

private int findFaceAtWorldPosition(ChunkGeometry geometry, Vector2 worldPosition, float threshold)
{
    for (int index = cast(int)geometry.faces.length - 1; index >= 0; index--) {
        const polygonPoints = getFacePolygonPoints(geometry, geometry.faces[index]);
        if (polygonPoints.length >= 3 && pointInPolygon(worldPosition, polygonPoints)) {
            return index;
        }

        const centroid = getFaceCentroid(geometry, geometry.faces[index]);
        const deltaX = centroid.x - worldPosition.x;
        const deltaY = centroid.y - worldPosition.y;
        if (deltaX * deltaX + deltaY * deltaY <= threshold * threshold) {
            return index;
        }
    }

    return -1;
}

private bool wallMatchesPoints(ChunkWall wall, int pointAIndex, int pointBIndex)
{
    return (wall.startPointIndex == pointAIndex && wall.endPointIndex == pointBIndex)
        || (wall.startPointIndex == pointBIndex && wall.endPointIndex == pointAIndex);
}

private bool chunkGeometryHasWall(ChunkGeometry geometry, int pointAIndex, int pointBIndex)
{
    foreach (wall; geometry.walls) {
        if (wallMatchesPoints(wall, pointAIndex, pointBIndex)) {
            return true;
        }
    }

    return false;
}

private float distanceSquaredToSegment(Vector2 point, Vector2 segmentStart, Vector2 segmentEnd)
{
    const deltaX = segmentEnd.x - segmentStart.x;
    const deltaY = segmentEnd.y - segmentStart.y;
    const segmentLengthSquared = deltaX * deltaX + deltaY * deltaY;
    if (segmentLengthSquared <= 0.0f) {
        const pointDeltaX = point.x - segmentStart.x;
        const pointDeltaY = point.y - segmentStart.y;
        return pointDeltaX * pointDeltaX + pointDeltaY * pointDeltaY;
    }

    float t = ((point.x - segmentStart.x) * deltaX + (point.y - segmentStart.y) * deltaY) / segmentLengthSquared;
    if (t < 0.0f) t = 0.0f;
    if (t > 1.0f) t = 1.0f;

    const closestPoint = Vector2(segmentStart.x + t * deltaX, segmentStart.y + t * deltaY);
    const closestDeltaX = point.x - closestPoint.x;
    const closestDeltaY = point.y - closestPoint.y;
    return closestDeltaX * closestDeltaX + closestDeltaY * closestDeltaY;
}

private int findWallAtWorldPosition(ChunkGeometry geometry, Vector2 worldPosition, float threshold)
{
    const thresholdSquared = threshold * threshold;

    for (int index = cast(int)geometry.walls.length - 1; index >= 0; index--) {
        const wall = geometry.walls[index];
        if (wall.startPointIndex < 0 || wall.startPointIndex >= cast(int)geometry.points.length) continue;
        if (wall.endPointIndex < 0 || wall.endPointIndex >= cast(int)geometry.points.length) continue;

        const startPoint = getChunkPointPosition(geometry.points[wall.startPointIndex]);
        const endPoint = getChunkPointPosition(geometry.points[wall.endPointIndex]);
        if (distanceSquaredToSegment(worldPosition, startPoint, endPoint) <= thresholdSquared) {
            return index;
        }
    }

    return -1;
}

private bool pointIsUsedByFace(ChunkGeometry geometry, int pointIndex)
{
    foreach (face; geometry.faces) {
        foreach (facePointIndex; face.pointIndices) {
            if (facePointIndex == pointIndex) {
                return true;
            }
        }
    }

    return false;
}

private bool pointIsUsedByWall(ChunkGeometry geometry, int pointIndex)
{
    foreach (wall; geometry.walls) {
        if (wall.startPointIndex == pointIndex || wall.endPointIndex == pointIndex) {
            return true;
        }
    }

    return false;
}

private void removePointAt(ref ChunkGeometry geometry, int pointIndex)
{
    geometry.points = geometry.points[0 .. pointIndex] ~ geometry.points[pointIndex + 1 .. $];

    foreach (ref face; geometry.faces) {
        foreach (ref facePointIndex; face.pointIndices) {
            if (facePointIndex > pointIndex) {
                facePointIndex--;
            }
        }
    }

    ChunkWall[] remainingWalls;
    foreach (wall; geometry.walls) {
        if (wall.startPointIndex == pointIndex || wall.endPointIndex == pointIndex) {
            continue;
        }

        ChunkWall nextWall = wall;
        if (nextWall.startPointIndex > pointIndex) nextWall.startPointIndex--;
        if (nextWall.endPointIndex > pointIndex) nextWall.endPointIndex--;
        remainingWalls ~= nextWall;
    }
    geometry.walls = remainingWalls;
}

private void removeFaceAt(ref ChunkGeometry geometry, int faceIndex)
{
    geometry.faces = geometry.faces[0 .. faceIndex] ~ geometry.faces[faceIndex + 1 .. $];
}

private void removeWallAt(ref ChunkGeometry geometry, int wallIndex)
{
    geometry.walls = geometry.walls[0 .. wallIndex] ~ geometry.walls[wallIndex + 1 .. $];
}

private bool selectedPointIndicesContain(int[] selectedPointIndices, int pointIndex)
{
    foreach (selectedIndex; selectedPointIndices) {
        if (selectedIndex == pointIndex) {
            return true;
        }
    }

    return false;
}

private bool selectedFaceIndicesContain(int[] selectedFaceIndices, int faceIndex)
{
    foreach (selectedIndex; selectedFaceIndices) {
        if (selectedIndex == faceIndex) {
            return true;
        }
    }

    return false;
}

private bool selectedWallIndicesContain(int[] selectedWallIndices, int wallIndex)
{
    foreach (selectedIndex; selectedWallIndices) {
        if (selectedIndex == wallIndex) {
            return true;
        }
    }

    return false;
}

private bool selectedPointsUsedByUnselectedFaces(ChunkGeometry geometry, int[] selectedPointIndices, int[] selectedFaceIndices)
{
    foreach (faceIndex, face; geometry.faces) {
        if (selectedFaceIndicesContain(selectedFaceIndices, cast(int)faceIndex)) {
            continue;
        }

        foreach (facePointIndex; face.pointIndices) {
            if (selectedPointIndicesContain(selectedPointIndices, facePointIndex)) {
                return true;
            }
        }
    }

    return false;
}

private int[] sortFacePointIndices(ChunkGeometry geometry, int[] pointIndices)
{
    if (pointIndices.length <= 2) {
        return pointIndices.dup;
    }

    float centroidX = 0.0f;
    float centroidY = 0.0f;
    int validPointCount = 0;

    foreach (pointIndex; pointIndices) {
        if (pointIndex >= 0 && pointIndex < cast(int)geometry.points.length) {
            const point = geometry.points[pointIndex];
            centroidX += point.x;
            centroidY += point.z;
            validPointCount++;
        }
    }

    if (validPointCount <= 2) {
        return pointIndices.dup;
    }

    centroidX /= validPointCount;
    centroidY /= validPointCount;

    auto orderedIndices = pointIndices.dup;
    orderedIndices.sort!((leftIndex, rightIndex) {
        const leftPoint = geometry.points[leftIndex];
        const rightPoint = geometry.points[rightIndex];
        const leftAngle = atan2(cast(double)leftPoint.z - centroidY, cast(double)leftPoint.x - centroidX);
        const rightAngle = atan2(cast(double)rightPoint.z - centroidY, cast(double)rightPoint.x - centroidX);
        return leftAngle < rightAngle;
    });

    float signedArea = 0.0f;
    for (int index = 0; index < cast(int)orderedIndices.length; index++) {
        const currentPoint = geometry.points[orderedIndices[index]];
        const nextPoint = geometry.points[orderedIndices[(index + 1) % cast(int)orderedIndices.length]];
        signedArea += cast(float)(currentPoint.x * nextPoint.z - nextPoint.x * currentPoint.z);
    }

    if (signedArea > 0.0f) {
        orderedIndices.reverse();
    }

    return orderedIndices;
}

private bool pointsEqual(Vector2 left, Vector2 right)
{
    return left.x == right.x && left.y == right.y;
}

private float signedTriangleArea(Vector2 a, Vector2 b, Vector2 c)
{
    return (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x);
}

private bool pointOnSegment(Vector2 point, Vector2 segmentStart, Vector2 segmentEnd)
{
    const area = signedTriangleArea(segmentStart, segmentEnd, point);
    if (area != 0.0f) {
        return false;
    }

    const minX = segmentStart.x < segmentEnd.x ? segmentStart.x : segmentEnd.x;
    const maxX = segmentStart.x > segmentEnd.x ? segmentStart.x : segmentEnd.x;
    const minY = segmentStart.y < segmentEnd.y ? segmentStart.y : segmentEnd.y;
    const maxY = segmentStart.y > segmentEnd.y ? segmentStart.y : segmentEnd.y;
    return point.x >= minX && point.x <= maxX && point.y >= minY && point.y <= maxY;
}

private bool segmentsOverlapOrIntersect(Vector2 a1, Vector2 a2, Vector2 b1, Vector2 b2)
{
    const area1 = signedTriangleArea(a1, a2, b1);
    const area2 = signedTriangleArea(a1, a2, b2);
    const area3 = signedTriangleArea(b1, b2, a1);
    const area4 = signedTriangleArea(b1, b2, a2);

    const sharedEndpoint = pointsEqual(a1, b1) || pointsEqual(a1, b2) || pointsEqual(a2, b1) || pointsEqual(a2, b2);
    if ((area1 == 0.0f && pointOnSegment(b1, a1, a2)) ||
        (area2 == 0.0f && pointOnSegment(b2, a1, a2)) ||
        (area3 == 0.0f && pointOnSegment(a1, b1, b2)) ||
        (area4 == 0.0f && pointOnSegment(a2, b1, b2))) {
        return !sharedEndpoint;
    }

    return (area1 > 0.0f) != (area2 > 0.0f) && (area3 > 0.0f) != (area4 > 0.0f);
}

private bool polygonHasSelfIntersection(const(Vector2)[] polygonPoints)
{
    if (polygonPoints.length < 4) {
        return false;
    }

    for (int index = 0; index < cast(int)polygonPoints.length; index++) {
        const nextIndex = (index + 1) % cast(int)polygonPoints.length;
        for (int otherIndex = index + 1; otherIndex < cast(int)polygonPoints.length; otherIndex++) {
            const otherNextIndex = (otherIndex + 1) % cast(int)polygonPoints.length;
            if (index == otherIndex || nextIndex == otherIndex || index == otherNextIndex) {
                continue;
            }

            if (segmentsOverlapOrIntersect(
                polygonPoints[index],
                polygonPoints[nextIndex],
                polygonPoints[otherIndex],
                polygonPoints[otherNextIndex]
            )) {
                return true;
            }
        }
    }

    return false;
}

private bool pointInPolygon(Vector2 point, const(Vector2)[] polygonPoints)
{
    bool inside = false;
    for (int index = 0, previous = cast(int)polygonPoints.length - 1; index < cast(int)polygonPoints.length; previous = index, index++) {
        const current = polygonPoints[index];
        const prior = polygonPoints[previous];
        if (pointOnSegment(point, prior, current)) {
            return false;
        }

        const intersects = ((current.y > point.y) != (prior.y > point.y))
            && (point.x < (prior.x - current.x) * (point.y - current.y) / (prior.y - current.y) + current.x);
        if (intersects) {
            inside = !inside;
        }
    }

    return inside;
}

private bool faceOverlapsExistingFaces(ChunkGeometry geometry, const(int)[] orderedPointIndices)
{
    ChunkFace candidateFace = ChunkFace(orderedPointIndices.dup, 0, 16, 0, true, false);
    const candidatePolygon = getFacePolygonPoints(geometry, candidateFace);
    if (candidatePolygon.length < 3 || polygonHasSelfIntersection(candidatePolygon)) {
        return true;
    }

    foreach (existingFace; geometry.faces) {
        const existingPolygon = getFacePolygonPoints(geometry, existingFace);
        if (existingPolygon.length < 3) {
            continue;
        }

        for (int index = 0; index < cast(int)candidatePolygon.length; index++) {
            const nextIndex = (index + 1) % cast(int)candidatePolygon.length;
            for (int otherIndex = 0; otherIndex < cast(int)existingPolygon.length; otherIndex++) {
                const otherNextIndex = (otherIndex + 1) % cast(int)existingPolygon.length;
                if (segmentsOverlapOrIntersect(
                    candidatePolygon[index],
                    candidatePolygon[nextIndex],
                    existingPolygon[otherIndex],
                    existingPolygon[otherNextIndex]
                )) {
                    return true;
                }
            }
        }

        foreach (candidatePoint; candidatePolygon) {
            if (pointInPolygon(candidatePoint, existingPolygon)) {
                return true;
            }
        }

        foreach (existingPoint; existingPolygon) {
            if (pointInPolygon(existingPoint, candidatePolygon)) {
                return true;
            }
        }
    }

    return false;
}

private Rectangle getChunkBoundsRect(MapChunk chunk)
{
    return Rectangle(0.0f, 0.0f, chunk.width * mapGridCellSize, chunk.height * mapGridCellSize);
}

private Vector2 getChunkWorldOffset(MapChunk chunk)
{
    return Vector2(chunk.column * mapGridCellSize, chunk.row * mapGridCellSize);
}

private PreviewWorldBounds getChunkPreviewBounds(MapChunk[] placedChunks, ChunkGeometry[] chunkGeometries)
{
    if (placedChunks.length == 0) {
        return PreviewWorldBounds(
            Rectangle(-mapGridCellSize * 0.5f, -mapGridCellSize * 0.5f, mapGridCellSize, mapGridCellSize),
            0.0f,
            mapGridCellSize * 2.0f
        );
    }

    const firstOffset = getChunkWorldOffset(placedChunks[0]);
    float minX = firstOffset.x;
    float minZ = firstOffset.y;
    float maxX = firstOffset.x + placedChunks[0].width * mapGridCellSize;
    float maxZ = firstOffset.y + placedChunks[0].height * mapGridCellSize;
    float minHeight = 0.0f;
    float maxHeight = mapGridCellSize * 2.0f;

    foreach (index, chunk; placedChunks) {
        const chunkOffset = getChunkWorldOffset(chunk);
        const chunkMaxX = chunkOffset.x + chunk.width * mapGridCellSize;
        const chunkMaxZ = chunkOffset.y + chunk.height * mapGridCellSize;

        if (chunkOffset.x < minX) minX = chunkOffset.x;
        if (chunkOffset.y < minZ) minZ = chunkOffset.y;
        if (chunkMaxX > maxX) maxX = chunkMaxX;
        if (chunkMaxZ > maxZ) maxZ = chunkMaxZ;

        if (index >= chunkGeometries.length) {
            continue;
        }

        foreach (face; chunkGeometries[index].faces) {
            if (face.floorHeight < minHeight) minHeight = face.floorHeight;
            if (face.ceilingHeight < minHeight) minHeight = face.ceilingHeight;
            if (face.floorHeight > maxHeight) maxHeight = face.floorHeight;
            if (face.ceilingHeight > maxHeight) maxHeight = face.ceilingHeight;
        }

        foreach (wall; chunkGeometries[index].walls) {
            if (wall.floorHeight < minHeight) minHeight = wall.floorHeight;
            if (wall.ceilingHeight < minHeight) minHeight = wall.ceilingHeight;
            if (wall.floorHeight > maxHeight) maxHeight = wall.floorHeight;
            if (wall.ceilingHeight > maxHeight) maxHeight = wall.ceilingHeight;
        }
    }

    return PreviewWorldBounds(Rectangle(minX, minZ, maxX - minX, maxZ - minZ), minHeight, maxHeight);
}

private float getChunkPreviewDefaultDistance(PreviewWorldBounds bounds)
{
    const horizontalSpan = max(bounds.horizontal.width, bounds.horizontal.height);
    const verticalSpan = max(bounds.maxHeight - bounds.minHeight, mapGridCellSize * 2.0f);
    const sceneSpan = max(horizontalSpan, verticalSpan);
    return sceneSpan * 1.8f + 64.0f;
}

private float getChunkPreviewMaxDistance(PreviewWorldBounds bounds)
{
    return max(640.0f, getChunkPreviewDefaultDistance(bounds) * 4.0f);
}

private int getPaletteTileSize(Image ditherImage)
{
    return ditherImage.height >= 2 ? ditherImage.height / 2 : 1;
}

private int getPaletteCount(Image ditherImage)
{
    const tileSize = getPaletteTileSize(ditherImage);
    return tileSize > 0 ? (ditherImage.width / tileSize) * (ditherImage.height / tileSize) : 1;
}

private Vector2 getPaletteTileOrigin(Image ditherImage, int paletteIndex)
{
    const tileSize = getPaletteTileSize(ditherImage);
    const columns = tileSize > 0 ? ditherImage.width / tileSize : 1;
    const rows = tileSize > 0 ? ditherImage.height / tileSize : 1;
    const paletteCount = columns * rows;
    const safePaletteIndex = paletteCount > 0 ? positiveModulo(paletteIndex, paletteCount) : 0;
    const column = columns - 1 - (safePaletteIndex / rows);
    const row = rows - 1 - (safePaletteIndex % rows);
    return Vector2(column * tileSize, row * tileSize);
}

private Color getPalettePixel(Image ditherImage, int paletteIndex, int sampleX, int sampleY)
{
    const tileSize = getPaletteTileSize(ditherImage);
    const tileOrigin = getPaletteTileOrigin(ditherImage, paletteIndex);
    return GetImageColor(
        ditherImage,
        cast(int)tileOrigin.x + positiveModulo(sampleX, tileSize),
        cast(int)tileOrigin.y + positiveModulo(sampleY, tileSize)
    );
}

private Vector2[] getFacePolygonPoints(ChunkGeometry geometry, ChunkFace face, Vector2 offset = Vector2.zero)
{
    Vector2[] points;

    foreach (pointIndex; face.pointIndices) {
        if (pointIndex >= 0 && pointIndex < cast(int)geometry.points.length) {
            const point = geometry.points[pointIndex];
            points ~= Vector2(offset.x + point.x, offset.y + point.z);
        }
    }

    return points;
}

private void drawFilledFace(ChunkGeometry geometry, ChunkFace face, Color fillColor, Vector2 offset = Vector2.zero)
{
    auto polygonPoints = getFacePolygonPoints(geometry, face, offset);
    if (polygonPoints.length < 3) {
        return;
    }

    Vector2 centroid = Vector2.zero;
    foreach (point; polygonPoints) {
        centroid.x += point.x;
        centroid.y += point.y;
    }
    centroid.x /= polygonPoints.length;
    centroid.y /= polygonPoints.length;

    for (int index = 0; index < cast(int)polygonPoints.length; index++) {
        Vector2 pointA = polygonPoints[index];
        Vector2 pointB = polygonPoints[(index + 1) % cast(int)polygonPoints.length];
        const signedArea = (pointA.x - centroid.x) * (pointB.y - centroid.y)
            - (pointA.y - centroid.y) * (pointB.x - centroid.x);

        if (signedArea > 0.0f) {
            const temp = pointA;
            pointA = pointB;
            pointB = temp;
        }

        DrawTriangle(centroid, pointA, pointB, fillColor);
    }
}

private void drawPaletteFace(ChunkGeometry geometry, ChunkFace face, Image ditherImage, float opacity, Vector2 offset = Vector2.zero)
{
    auto polygonPoints = getFacePolygonPoints(geometry, face, offset);
    if (polygonPoints.length < 3) {
        return;
    }

    int minX = cast(int)floor(polygonPoints[0].x);
    int maxX = cast(int)floor(polygonPoints[0].x);
    int minY = cast(int)floor(polygonPoints[0].y);
    int maxY = cast(int)floor(polygonPoints[0].y);

    foreach (point; polygonPoints) {
        const pointX = cast(int)floor(point.x);
        const pointY = cast(int)floor(point.y);
        if (pointX < minX) minX = pointX;
        if (pointX > maxX) maxX = pointX;
        if (pointY < minY) minY = pointY;
        if (pointY > maxY) maxY = pointY;
    }

    for (int y = minY; y <= maxY; y++) {
        for (int x = minX; x <= maxX; x++) {
            const samplePoint = Vector2(x + 0.5f, y + 0.5f);
            if (!pointInPolygon(samplePoint, polygonPoints)) {
                continue;
            }

            const palettePixel = getPalettePixel(ditherImage, face.paletteIndex, x, y);
            DrawPixel(x, y, Fade(palettePixel, opacity));
        }
    }
}

private Color getPalettePreviewColor(Image ditherImage, int paletteIndex)
{
    const tileSize = getPaletteTileSize(ditherImage);
    if (tileSize <= 0) {
        return Colors.LIGHTGRAY;
    }

    const tileOrigin = getPaletteTileOrigin(ditherImage, paletteIndex);
    int brightnessSum = 0;
    for (int y = 0; y < tileSize; y++) {
        for (int x = 0; x < tileSize; x++) {
            const pixel = GetImageColor(ditherImage, cast(int)tileOrigin.x + x, cast(int)tileOrigin.y + y);
            brightnessSum += pixel.r;
        }
    }

    const averageBrightness = cast(ubyte)(brightnessSum / (tileSize * tileSize));
    return Color(averageBrightness, averageBrightness, averageBrightness, 255);
}

private bool faceHasEdge(ChunkFace face, int pointAIndex, int pointBIndex)
{
    if (face.pointIndices.length < 2) {
        return false;
    }

    for (int index = 0; index < cast(int)face.pointIndices.length; index++) {
        const currentPointIndex = face.pointIndices[index];
        const nextPointIndex = face.pointIndices[(index + 1) % cast(int)face.pointIndices.length];
        if ((currentPointIndex == pointAIndex && nextPointIndex == pointBIndex)
            || (currentPointIndex == pointBIndex && nextPointIndex == pointAIndex)) {
            return true;
        }
    }

    return false;
}

private int findAdjacentFaceForEdge(ChunkGeometry geometry, int ignoredFaceIndex, int pointAIndex, int pointBIndex)
{
    foreach (faceIndex, face; geometry.faces) {
        if (cast(int)faceIndex == ignoredFaceIndex) {
            continue;
        }

        if (faceHasEdge(face, pointAIndex, pointBIndex)) {
            return cast(int)faceIndex;
        }
    }

    return -1;
}

private void drawDoubleSidedTriangle3D(Vector3 a, Vector3 b, Vector3 c, Color color)
{
    DrawTriangle3D(a, b, c, color);
    DrawTriangle3D(c, b, a, color);
}

private void drawChunkFacePreview3D(ChunkGeometry geometry, ChunkFace face, Image ditherImage, Vector2 offset = Vector2.zero)
{
    auto polygonPoints = getFacePolygonPoints(geometry, face, offset);
    if (polygonPoints.length < 3) {
        return;
    }

    Vector2 centroid2D = Vector2.zero;
    foreach (point; polygonPoints) {
        centroid2D.x += point.x;
        centroid2D.y += point.y;
    }
    centroid2D.x /= polygonPoints.length;
    centroid2D.y /= polygonPoints.length;

    const baseColor = getPalettePreviewColor(ditherImage, face.paletteIndex);
    const floorColor = baseColor;
    const ceilingBrightness = cast(ubyte)(baseColor.r + (255 - baseColor.r) / 4);
    const ceilingColor = Color(ceilingBrightness, ceilingBrightness, ceilingBrightness, 255);
    const floorCentroid = Vector3(centroid2D.x, face.floorHeight, centroid2D.y);
    const ceilingCentroid = Vector3(centroid2D.x, face.ceilingHeight, centroid2D.y);

    for (int index = 0; index < cast(int)polygonPoints.length; index++) {
        const pointA = polygonPoints[index];
        const pointB = polygonPoints[(index + 1) % cast(int)polygonPoints.length];
        drawDoubleSidedTriangle3D(
            floorCentroid,
            Vector3(pointB.x, face.floorHeight, pointB.y),
            Vector3(pointA.x, face.floorHeight, pointA.y),
            floorColor
        );
        drawDoubleSidedTriangle3D(
            ceilingCentroid,
            Vector3(pointA.x, face.ceilingHeight, pointA.y),
            Vector3(pointB.x, face.ceilingHeight, pointB.y),
            ceilingColor
        );
    }

    for (int index = 0; index < cast(int)polygonPoints.length; index++) {
        const pointA = polygonPoints[index];
        const pointB = polygonPoints[(index + 1) % cast(int)polygonPoints.length];
        DrawLine3D(Vector3(pointA.x, face.floorHeight, pointA.y), Vector3(pointB.x, face.floorHeight, pointB.y), Colors.BLACK);
        DrawLine3D(Vector3(pointA.x, face.ceilingHeight, pointA.y), Vector3(pointB.x, face.ceilingHeight, pointB.y), Colors.DARKGRAY);
    }
}

private void drawChunkWallPreview3D(ChunkGeometry geometry, ChunkWall wall, Image ditherImage, Vector2 offset = Vector2.zero)
{
    if (wall.startPointIndex < 0 || wall.startPointIndex >= cast(int)geometry.points.length) return;
    if (wall.endPointIndex < 0 || wall.endPointIndex >= cast(int)geometry.points.length) return;

    const startPoint = getChunkPointPosition(geometry.points[wall.startPointIndex]);
    const endPoint = getChunkPointPosition(geometry.points[wall.endPointIndex]);
    const color = getPalettePreviewColor(ditherImage, wall.paletteIndex);

    const lowerA = Vector3(offset.x + startPoint.x, wall.floorHeight, offset.y + startPoint.y);
    const upperA = Vector3(offset.x + startPoint.x, wall.ceilingHeight, offset.y + startPoint.y);
    const lowerB = Vector3(offset.x + endPoint.x, wall.floorHeight, offset.y + endPoint.y);
    const upperB = Vector3(offset.x + endPoint.x, wall.ceilingHeight, offset.y + endPoint.y);

    drawDoubleSidedTriangle3D(lowerA, lowerB, upperA, color);
    drawDoubleSidedTriangle3D(upperA, lowerB, upperB, color);
    DrawLine3D(lowerA, lowerB, Colors.MAROON);
    DrawLine3D(upperA, upperB, Colors.MAROON);
    DrawLine3D(lowerA, upperA, Colors.MAROON);
    DrawLine3D(lowerB, upperB, Colors.MAROON);
}

private void drawPreviewWallSegment(Vector2 startPoint, Vector2 endPoint, int lowerHeight, int upperHeight, Color color)
{
    if (upperHeight <= lowerHeight) {
        return;
    }

    const lowerA = Vector3(startPoint.x, lowerHeight, startPoint.y);
    const upperA = Vector3(startPoint.x, upperHeight, startPoint.y);
    const lowerB = Vector3(endPoint.x, lowerHeight, endPoint.y);
    const upperB = Vector3(endPoint.x, upperHeight, endPoint.y);

    drawDoubleSidedTriangle3D(lowerA, lowerB, upperA, color);
    drawDoubleSidedTriangle3D(upperA, lowerB, upperB, color);
    DrawLine3D(lowerA, lowerB, Fade(Colors.MAROON, 0.9f));
    DrawLine3D(upperA, upperB, Fade(Colors.MAROON, 0.9f));
}

private void drawChunkAutoWallsPreview3D(ChunkGeometry geometry, int faceIndex, Image ditherImage, Vector2 offset = Vector2.zero)
{
    if (faceIndex < 0 || faceIndex >= cast(int)geometry.faces.length) {
        return;
    }

    const face = geometry.faces[faceIndex];
    if (!face.autoWallFromHeightDifference || face.pointIndices.length < 2) {
        return;
    }

    const wallColor = getPalettePreviewColor(ditherImage, face.paletteIndex);

    for (int index = 0; index < cast(int)face.pointIndices.length; index++) {
        const pointAIndex = face.pointIndices[index];
        const pointBIndex = face.pointIndices[(index + 1) % cast(int)face.pointIndices.length];
        if (pointAIndex < 0 || pointAIndex >= cast(int)geometry.points.length) continue;
        if (pointBIndex < 0 || pointBIndex >= cast(int)geometry.points.length) continue;

        const localStartPoint = getChunkPointPosition(geometry.points[pointAIndex]);
        const localEndPoint = getChunkPointPosition(geometry.points[pointBIndex]);
        const startPoint = Vector2(offset.x + localStartPoint.x, offset.y + localStartPoint.y);
        const endPoint = Vector2(offset.x + localEndPoint.x, offset.y + localEndPoint.y);
        const adjacentFaceIndex = findAdjacentFaceForEdge(geometry, faceIndex, pointAIndex, pointBIndex);

        if (adjacentFaceIndex < 0) {
            drawPreviewWallSegment(startPoint, endPoint, face.floorHeight, face.ceilingHeight, wallColor);
            continue;
        }

        const adjacentFace = geometry.faces[adjacentFaceIndex];
        if (adjacentFace.autoWallFromHeightDifference && adjacentFaceIndex < faceIndex) {
            continue;
        }

        const lowerFloor = face.floorHeight < adjacentFace.floorHeight ? face.floorHeight : adjacentFace.floorHeight;
        const upperFloor = face.floorHeight > adjacentFace.floorHeight ? face.floorHeight : adjacentFace.floorHeight;
        drawPreviewWallSegment(startPoint, endPoint, lowerFloor, upperFloor, wallColor);

        const lowerCeiling = face.ceilingHeight < adjacentFace.ceilingHeight ? face.ceilingHeight : adjacentFace.ceilingHeight;
        const upperCeiling = face.ceilingHeight > adjacentFace.ceilingHeight ? face.ceilingHeight : adjacentFace.ceilingHeight;
        drawPreviewWallSegment(startPoint, endPoint, lowerCeiling, upperCeiling, wallColor);
    }
}

// Cast a picking ray from a pixel in the 3D preview render texture.
private Ray getPreviewRay(Vector2 mouseInTexture, Camera3D camera, float texW, float texH)
{
    const ndcX = (2.0f * mouseInTexture.x / texW) - 1.0f;
    const ndcY = 1.0f - (2.0f * mouseInTexture.y / texH);

    // Build camera basis (forward, right, recalculated-up).
    float fwX = camera.target.x - camera.position.x;
    float fwY = camera.target.y - camera.position.y;
    float fwZ = camera.target.z - camera.position.z;
    const fwLen = cast(float)sqrt(cast(double)(fwX*fwX + fwY*fwY + fwZ*fwZ));
    if (fwLen > 0.0f) { fwX /= fwLen; fwY /= fwLen; fwZ /= fwLen; }

    float rx = fwY * camera.up.z - fwZ * camera.up.y;
    float ry = fwZ * camera.up.x - fwX * camera.up.z;
    float rz = fwX * camera.up.y - fwY * camera.up.x;
    const rLen = cast(float)sqrt(cast(double)(rx*rx + ry*ry + rz*rz));
    if (rLen > 0.0f) { rx /= rLen; ry /= rLen; rz /= rLen; }

    // Up = right x forward (ensure orthogonality).
    const ux = ry * fwZ - rz * fwY;
    const uy = rz * fwX - rx * fwZ;
    const uz = rx * fwY - ry * fwX;

    const halfFovY = cast(float)tan(cast(double)(camera.fovy * 3.14159265f / 360.0f));
    const aspect = texW / texH;

    float dirX = fwX + ndcX * aspect * halfFovY * rx + ndcY * halfFovY * ux;
    float dirY = fwY + ndcX * aspect * halfFovY * ry + ndcY * halfFovY * uy;
    float dirZ = fwZ + ndcX * aspect * halfFovY * rz + ndcY * halfFovY * uz;
    const dirLen = cast(float)sqrt(cast(double)(dirX*dirX + dirY*dirY + dirZ*dirZ));
    if (dirLen > 0.0f) { dirX /= dirLen; dirY /= dirLen; dirZ /= dirLen; }

    return Ray(camera.position, Vector3(dirX, dirY, dirZ));
}

// Möller–Trumbore ray-triangle intersection. Returns true and sets outT on hit.
private bool rayHitsTriangle(Ray ray, Vector3 v0, Vector3 v1, Vector3 v2, ref float outT)
{
    const e1x = v1.x - v0.x; const e1y = v1.y - v0.y; const e1z = v1.z - v0.z;
    const e2x = v2.x - v0.x; const e2y = v2.y - v0.y; const e2z = v2.z - v0.z;
    const hx = ray.direction.y * e2z - ray.direction.z * e2y;
    const hy = ray.direction.z * e2x - ray.direction.x * e2z;
    const hz = ray.direction.x * e2y - ray.direction.y * e2x;
    const det = e1x * hx + e1y * hy + e1z * hz;
    if (det > -1e-6f && det < 1e-6f) return false;
    const invDet = 1.0f / det;
    const sx = ray.position.x - v0.x;
    const sy = ray.position.y - v0.y;
    const sz = ray.position.z - v0.z;
    const u = (sx * hx + sy * hy + sz * hz) * invDet;
    if (u < 0.0f || u > 1.0f) return false;
    const qx = sy * e1z - sz * e1y;
    const qy = sz * e1x - sx * e1z;
    const qz = sx * e1y - sy * e1x;
    const v = (ray.direction.x * qx + ray.direction.y * qy + ray.direction.z * qz) * invDet;
    if (v < 0.0f || u + v > 1.0f) return false;
    const t = (e2x * qx + e2y * qy + e2z * qz) * invDet;
    if (t < 0.001f) return false;
    outT = t;
    return true;
}

// Ray vs a wall quad (two triangles). Returns true and sets outT to nearest hit.
private bool rayHitsWallQuad(Ray ray, Vector3 v0, Vector3 v1, Vector3 v2, Vector3 v3, ref float outT)
{
    float t1 = float.infinity;
    float t2 = float.infinity;
    const hit1 = rayHitsTriangle(ray, v0, v1, v2, t1);
    const hit2 = rayHitsTriangle(ray, v0, v2, v3, t2);
    if (!hit1 && !hit2) return false;
    outT = hit1 ? (hit2 ? (t1 < t2 ? t1 : t2) : t1) : t2;
    return true;
}

// Find the nearest explicit (ChunkWall) in the editing chunk hit by a ray.
// Returns the wall index, or -1. Sets outT to the hit distance.
private int findExplicitWallHitByRay(ChunkGeometry geometry, Ray ray, Vector2 offset, ref float outT)
{
    int bestIndex = -1;
    float bestT = float.infinity;

    foreach (wallIndex, wall; geometry.walls) {
        if (wall.startPointIndex < 0 || wall.startPointIndex >= cast(int)geometry.points.length) continue;
        if (wall.endPointIndex   < 0 || wall.endPointIndex   >= cast(int)geometry.points.length) continue;

        const sp = geometry.points[wall.startPointIndex];
        const ep = geometry.points[wall.endPointIndex];
        const v0 = Vector3(offset.x + sp.x, cast(float)wall.floorHeight,   offset.y + sp.z);
        const v1 = Vector3(offset.x + ep.x, cast(float)wall.floorHeight,   offset.y + ep.z);
        const v2 = Vector3(offset.x + ep.x, cast(float)wall.ceilingHeight, offset.y + ep.z);
        const v3 = Vector3(offset.x + sp.x, cast(float)wall.ceilingHeight, offset.y + sp.z);

        float t;
        if (rayHitsWallQuad(ray, v0, v1, v2, v3, t) && t < bestT) {
            bestT = t;
            bestIndex = cast(int)wallIndex;
        }
    }

    outT = bestT;
    return bestIndex;
}

// Find the face (index) whose auto-wall is nearest to the ray. Returns -1 if none.
private int findAutoWallFaceHitByRay(ChunkGeometry geometry, Ray ray, Vector2 offset, ref float outT)
{
    int bestFaceIndex = -1;
    float bestT = float.infinity;

    foreach (faceIndex, face; geometry.faces) {
        if (!face.autoWallFromHeightDifference || face.pointIndices.length < 2) continue;

        for (int ei = 0; ei < cast(int)face.pointIndices.length; ei++) {
            const pointAIndex = face.pointIndices[ei];
            const pointBIndex = face.pointIndices[(ei + 1) % cast(int)face.pointIndices.length];
            if (pointAIndex < 0 || pointAIndex >= cast(int)geometry.points.length) continue;
            if (pointBIndex < 0 || pointBIndex >= cast(int)geometry.points.length) continue;

            const ptA = geometry.points[pointAIndex];
            const ptB = geometry.points[pointBIndex];
            const adjFaceIndex = findAdjacentFaceForEdge(geometry, cast(int)faceIndex, pointAIndex, pointBIndex);

            void testQuad(int lowerY, int upperY) {
                if (upperY <= lowerY) return;
                const v0 = Vector3(offset.x + ptA.x, cast(float)lowerY, offset.y + ptA.z);
                const v1 = Vector3(offset.x + ptB.x, cast(float)lowerY, offset.y + ptB.z);
                const v2 = Vector3(offset.x + ptB.x, cast(float)upperY, offset.y + ptB.z);
                const v3 = Vector3(offset.x + ptA.x, cast(float)upperY, offset.y + ptA.z);
                float t;
                if (rayHitsWallQuad(ray, v0, v1, v2, v3, t) && t < bestT) {
                    bestT = t;
                    bestFaceIndex = cast(int)faceIndex;
                }
            }

            if (adjFaceIndex < 0) {
                testQuad(face.floorHeight, face.ceilingHeight);
            } else {
                const adjFace = geometry.faces[adjFaceIndex];
                if (adjFace.autoWallFromHeightDifference && adjFaceIndex < cast(int)faceIndex) continue;
                const lowerFloor   = face.floorHeight   < adjFace.floorHeight   ? face.floorHeight   : adjFace.floorHeight;
                const upperFloor   = face.floorHeight   > adjFace.floorHeight   ? face.floorHeight   : adjFace.floorHeight;
                const lowerCeiling = face.ceilingHeight < adjFace.ceilingHeight ? face.ceilingHeight : adjFace.ceilingHeight;
                const upperCeiling = face.ceilingHeight > adjFace.ceilingHeight ? face.ceilingHeight : adjFace.ceilingHeight;
                testQuad(lowerFloor, upperFloor);
                testQuad(lowerCeiling, upperCeiling);
            }
        }
    }

    outT = bestT;
    return bestFaceIndex;
}

private Camera3D getChunkPreviewCamera(PreviewWorldBounds bounds, float yaw, float pitch, float distance)
{
    const target = Vector3(
        bounds.horizontal.x + bounds.horizontal.width * 0.5f,
        (bounds.minHeight + bounds.maxHeight) * 0.5f,
        bounds.horizontal.y + bounds.horizontal.height * 0.5f
    );

    return Camera3D(
        Vector3(
            target.x + cast(float)(cos(pitch) * cos(yaw)) * distance,
            target.y + cast(float)sin(pitch) * distance,
            target.z + cast(float)(cos(pitch) * sin(yaw)) * distance
        ),
        target,
        Vector3(0.0f, 1.0f, 0.0f),
        45.0f,
        CameraProjection.CAMERA_PERSPECTIVE
    );
}

private void renderChunkPreview3D(
    RenderTexture2D renderTexture,
    Camera3D camera,
    MapChunk[] placedChunks,
    ChunkGeometry[] chunkGeometries,
    int highlightedChunkIndex,
    PreviewWorldBounds bounds,
    Image ditherImage,
)
{
    BeginTextureMode(renderTexture);
    scope(exit) EndTextureMode();

    ClearBackground(Color(206, 220, 255, 255));
    BeginMode3D(camera);
    scope(exit) EndMode3D();

    const minX = bounds.horizontal.x;
    const maxX = bounds.horizontal.x + bounds.horizontal.width;
    const minZ = bounds.horizontal.y;
    const maxZ = bounds.horizontal.y + bounds.horizontal.height;
    const farthestX = max(absFloat(minX), absFloat(maxX));
    const farthestZ = max(absFloat(minZ), absFloat(maxZ));
    const gridRadius = max(farthestX, farthestZ) + mapGridCellSize * 4.0f;
    const gridSize = max(8, cast(int)(gridRadius / mapGridCellSize) * 2);
    DrawGrid(gridSize, mapGridCellSize);

    foreach (index, chunk; placedChunks) {
        const chunkOffset = getChunkWorldOffset(chunk);

        if (index < chunkGeometries.length) {
            foreach (faceIndex, face; chunkGeometries[index].faces) {
                drawChunkFacePreview3D(chunkGeometries[index], face, ditherImage, chunkOffset);
                drawChunkAutoWallsPreview3D(chunkGeometries[index], cast(int)faceIndex, ditherImage, chunkOffset);
            }

            foreach (wall; chunkGeometries[index].walls) {
                drawChunkWallPreview3D(chunkGeometries[index], wall, ditherImage, chunkOffset);
            }

            foreach (entity; chunkGeometries[index].entities) {
                const floorY = getFloorHeightAtXZ(chunkGeometries[index], entity.x, entity.z);
                const entityPos = Vector3(chunkOffset.x + entity.x, floorY, chunkOffset.y + entity.z);
                Color entityColor;
                final switch (entity.type) {
                    case EntityType.player:             entityColor = Colors.GREEN; break;
                    case EntityType.npc:                entityColor = Colors.ORANGE; break;
                    case EntityType.fishCommon:         entityColor = Colors.SKYBLUE; break;
                    case EntityType.fishRare:           entityColor = Colors.BLUE; break;
                    case EntityType.fishLegendary:      entityColor = Colors.GOLD; break;
                    case EntityType.bird:               entityColor = Color(135, 206, 235, 255); break;
                    case EntityType.insect:             entityColor = Color(100, 200, 50, 255); break;
                    case EntityType.treasureChest:      entityColor = Colors.YELLOW; break;
                    case EntityType.festivalDecoration: entityColor = Colors.VIOLET; break;
                }
                DrawCylinder(entityPos, 4.0f, 4.0f, 16.0f, 6, entityColor);
                DrawCylinderWires(entityPos, 4.0f, 4.0f, 16.0f, 6, Fade(Colors.BLACK, 0.5f));
                const dirLen = 10.0f;
                const dirEnd = Vector3(
                    entityPos.x + cast(float)sin(entity.rotationY) * dirLen,
                    entityPos.y + 16.0f,
                    entityPos.z + cast(float)cos(entity.rotationY) * dirLen
                );
                DrawLine3D(Vector3(entityPos.x, entityPos.y + 16.0f, entityPos.z), dirEnd, Fade(Colors.WHITE, 0.9f));
            }

            foreach (obj; chunkGeometries[index].objects) {
                const objPos = Vector3(chunkOffset.x + obj.x, obj.y, chunkOffset.y + obj.z);
                Color objColor;
                final switch (obj.type) {
                    case ObjectType.hut:           objColor = Color(160, 120, 80, 255); break;
                    case ObjectType.tree:          objColor = Color(34, 85, 34, 255); break;
                    case ObjectType.rock:          objColor = Colors.GRAY; break;
                    case ObjectType.crate:         objColor = Color(139, 90, 43, 255); break;
                    case ObjectType.chair:         objColor = Color(180, 140, 90, 255); break;
                    case ObjectType.table:         objColor = Color(200, 160, 100, 255); break;
                    case ObjectType.boat:          objColor = Color(70, 130, 180, 255); break;
                    case ObjectType.dock:          objColor = Color(101, 67, 33, 255); break;
                    case ObjectType.building:      objColor = Color(180, 160, 120, 255); break;
                    case ObjectType.buoy:          objColor = Colors.RED; break;
                    case ObjectType.fishingNet:    objColor = Color(200, 200, 150, 255); break;
                    case ObjectType.coral:         objColor = Color(255, 127, 80, 255); break;
                    case ObjectType.underwaterRock:objColor = Color(100, 120, 140, 255); break;
                    case ObjectType.festivalProp:  objColor = Colors.PINK; break;
                }
                DrawCube(objPos, 8.0f, 8.0f, 8.0f, objColor);
                DrawCubeWiresV(objPos, Vector3(8.0f, 8.0f, 8.0f), Fade(Colors.BLACK, 0.5f));
                const dirLen = 10.0f;
                const dirEnd = Vector3(
                    objPos.x + cast(float)sin(obj.rotationY) * dirLen,
                    objPos.y + 4.0f,
                    objPos.z + cast(float)cos(obj.rotationY) * dirLen
                );
                DrawLine3D(Vector3(objPos.x, objPos.y + 4.0f, objPos.z), dirEnd, Fade(Colors.WHITE, 0.9f));
            }
        }

        const chunkCenter = Vector3(
            chunkOffset.x + chunk.width * mapGridCellSize * 0.5f,
            mapGridCellSize,
            chunkOffset.y + chunk.height * mapGridCellSize * 0.5f
        );
        const outlineColor = cast(int)index == highlightedChunkIndex
            ? Fade(Colors.GOLD, 0.85f)
            : Fade(Colors.RAYWHITE, 0.35f);
        DrawCubeWiresV(
            chunkCenter,
            Vector3(chunk.width * mapGridCellSize, mapGridCellSize * 2.0f, chunk.height * mapGridCellSize),
            outlineColor
        );
    }
}

private void drawMapCanvas(
    Rectangle canvasRect,
    GridLayout gridLayout,
    MapChunk[] placedChunks,
    ChunkGeometry[] chunkGeometries,
    Image ditherImage,
    int selectedChunkIndex,
    bool showGrid,
    bool showChunkBounds,
    bool isDraggingChunk,
    MapChunk previewChunk,
    bool previewPlacementValid,
    int currentLayer,
)
{
    DrawRectangleRec(canvasRect, Fade(Colors.BLACK, 0.24f));
    DrawRectangleLinesEx(canvasRect, 2.0f, Fade(Colors.RAYWHITE, 0.4f));

    BeginScissorMode(cast(int)canvasRect.x, cast(int)canvasRect.y, cast(int)canvasRect.width, cast(int)canvasRect.height);
    scope(exit) EndScissorMode();

    BeginMode2D(gridLayout.camera);
    scope(exit) EndMode2D();

    const topLeft = GetScreenToWorld2D(Vector2(canvasRect.x, canvasRect.y), gridLayout.camera);
    const bottomRight = GetScreenToWorld2D(Vector2(canvasRect.x + canvasRect.width, canvasRect.y + canvasRect.height), gridLayout.camera);

    const minX = topLeft.x < bottomRight.x ? topLeft.x : bottomRight.x;
    const maxX = topLeft.x > bottomRight.x ? topLeft.x : bottomRight.x;
    const minY = topLeft.y < bottomRight.y ? topLeft.y : bottomRight.y;
    const maxY = topLeft.y > bottomRight.y ? topLeft.y : bottomRight.y;

    const visibleWorldRect = Rectangle(minX, minY, maxX - minX, maxY - minY);
    DrawRectangleRec(visibleWorldRect, Fade(Colors.SKYBLUE, 0.08f));

    if (showGrid) {
        const startColumn = cast(int)floor(minX / gridLayout.cellSize) - 1;
        const endColumn = cast(int)floor(maxX / gridLayout.cellSize) + 1;
        const startRow = cast(int)floor(minY / gridLayout.cellSize) - 1;
        const endRow = cast(int)floor(maxY / gridLayout.cellSize) + 1;

        for (int column = startColumn; column <= endColumn; column++) {
            const x = column * gridLayout.cellSize;
            const isAxis = column == 0;
            const isMajor = positiveModulo(column, majorGridInterval) == 0;
            const lineColor = isAxis
                ? Fade(Colors.WHITE, 0.72f)
                : (isMajor ? Fade(Colors.RAYWHITE, 0.22f) : Fade(Colors.RAYWHITE, 0.10f));
            DrawLineV(Vector2(x, minY), Vector2(x, maxY), lineColor);
        }

        for (int row = startRow; row <= endRow; row++) {
            const y = row * gridLayout.cellSize;
            const isAxis = row == 0;
            const isMajor = positiveModulo(row, majorGridInterval) == 0;
            const lineColor = isAxis
                ? Fade(Colors.WHITE, 0.72f)
                : (isMajor ? Fade(Colors.RAYWHITE, 0.22f) : Fade(Colors.RAYWHITE, 0.10f));
            DrawLineV(Vector2(minX, y), Vector2(maxX, y), lineColor);
        }
    }

    foreach (index, chunk; placedChunks) {
        const chunkRect = getChunkRect(chunk, gridLayout);
        const isSelected = cast(int)index == selectedChunkIndex;
        const isActiveLayer = chunk.layer == currentLayer;
        const dimFactor = isActiveLayer ? 1.0f : 0.28f;

        DrawRectangleRec(chunkRect, Fade(Colors.DARKBLUE, (isSelected ? 0.60f : 0.42f) * dimFactor));

        if (index < chunkGeometries.length) {
            const chunkOffset = Vector2(chunkRect.x, chunkRect.y);
            foreach (faceIndex, face; chunkGeometries[index].faces) {
                drawPaletteFace(chunkGeometries[index], face, ditherImage, (isSelected ? 0.28f : 0.22f) * dimFactor, chunkOffset);
                if (isSelected) {
                    drawFilledFace(chunkGeometries[index], face, Fade(Colors.GOLD, 0.10f * dimFactor), chunkOffset);
                }

                const polygonPoints = getFacePolygonPoints(chunkGeometries[index], face, chunkOffset);
                for (int pointIndex = 0; pointIndex < cast(int)polygonPoints.length; pointIndex++) {
                    const nextPointIndex = (pointIndex + 1) % cast(int)polygonPoints.length;
                    DrawLineV(polygonPoints[pointIndex], polygonPoints[nextPointIndex], Fade(Colors.WHITE, 0.45f * dimFactor));
                }
            }

            foreach (wall; chunkGeometries[index].walls) {
                if (wall.startPointIndex < 0 || wall.startPointIndex >= cast(int)chunkGeometries[index].points.length) continue;
                if (wall.endPointIndex < 0 || wall.endPointIndex >= cast(int)chunkGeometries[index].points.length) continue;

                const startPoint = getChunkPointPosition(chunkGeometries[index].points[wall.startPointIndex]);
                const endPoint = getChunkPointPosition(chunkGeometries[index].points[wall.endPointIndex]);
                DrawLineV(
                    Vector2(chunkOffset.x + startPoint.x, chunkOffset.y + startPoint.y),
                    Vector2(chunkOffset.x + endPoint.x, chunkOffset.y + endPoint.y),
                    Fade(Colors.MAROON, 0.85f * dimFactor)
                );
            }
        }

        DrawRectangleLinesEx(
            chunkRect,
            isSelected ? 3.0f : (showChunkBounds ? 2.5f : 1.5f),
            isSelected ? Fade(Colors.GOLD, 0.95f * dimFactor) : Fade(Colors.WHITE, 0.85f * dimFactor)
        );

        // Layer label in the top-left corner of the chunk
        const labelPos = Vector2(chunkRect.x + 4.0f / gridLayout.camera.zoom, chunkRect.y + 2.0f / gridLayout.camera.zoom);
        const labelFontSize = 14.0f / gridLayout.camera.zoom;
        DrawTextPro(GetFontDefault(), TextFormat("L%d", chunk.layer), labelPos, Vector2(0, 0), 0.0f, labelFontSize, labelFontSize / 10.0f, Fade(isActiveLayer ? Colors.RAYWHITE : Colors.GRAY, 0.85f * dimFactor));
    }

    if (isDraggingChunk) {
        const previewRect = getChunkRect(previewChunk, gridLayout);
        const previewFill = previewPlacementValid ? Fade(Colors.GREEN, 0.25f) : Fade(Colors.RED, 0.25f);
        const previewOutline = previewPlacementValid ? Fade(Colors.LIME, 0.95f) : Fade(Colors.MAROON, 0.95f);
        DrawRectangleRec(previewRect, previewFill);
        DrawRectangleLinesEx(previewRect, 3.0f, previewOutline);
    }

    DrawCircleV(Vector2.zero, 2.5f / gridLayout.camera.zoom, Fade(Colors.GOLD, 0.95f));
}

private void drawChunkEditorCanvas(
    Rectangle canvasRect,
    GridLayout gridLayout,
    MapChunk[] placedChunks,
    ChunkGeometry[] chunkGeometries,
    Image ditherImage,
    int editingChunkIndex,
    MapChunk chunk,
    ChunkGeometry geometry,
    int[] selectedPointIndices,
    int[] selectedFaceIndices,
    int[] selectedWallIndices,
    int[] selectedEntityIndices,
    int[] selectedObjectIndices,
    bool isBoxSelecting,
    Rectangle boxSelectRect,
    bool showGrid,
    ChunkEditorTool editorTool,
)
{
    DrawRectangleRec(canvasRect, Fade(Colors.BLACK, 0.24f));
    DrawRectangleLinesEx(canvasRect, 2.0f, Fade(Colors.RAYWHITE, 0.4f));

    BeginScissorMode(cast(int)canvasRect.x, cast(int)canvasRect.y, cast(int)canvasRect.width, cast(int)canvasRect.height);
    scope(exit) EndScissorMode();

    BeginMode2D(gridLayout.camera);
    scope(exit) EndMode2D();

    const topLeft = GetScreenToWorld2D(Vector2(canvasRect.x, canvasRect.y), gridLayout.camera);
    const bottomRight = GetScreenToWorld2D(Vector2(canvasRect.x + canvasRect.width, canvasRect.y + canvasRect.height), gridLayout.camera);

    const minX = topLeft.x < bottomRight.x ? topLeft.x : bottomRight.x;
    const maxX = topLeft.x > bottomRight.x ? topLeft.x : bottomRight.x;
    const minY = topLeft.y < bottomRight.y ? topLeft.y : bottomRight.y;
    const maxY = topLeft.y > bottomRight.y ? topLeft.y : bottomRight.y;

    const visibleWorldRect = Rectangle(minX, minY, maxX - minX, maxY - minY);
    DrawRectangleRec(visibleWorldRect, Fade(Colors.SKYBLUE, 0.05f));

    if (showGrid) {
        const startColumn = cast(int)floor(minX / gridLayout.cellSize) - 1;
        const endColumn = cast(int)floor(maxX / gridLayout.cellSize) + 1;
        const startRow = cast(int)floor(minY / gridLayout.cellSize) - 1;
        const endRow = cast(int)floor(maxY / gridLayout.cellSize) + 1;

        for (int column = startColumn; column <= endColumn; column++) {
            const x = column * gridLayout.cellSize;
            const isMajor = positiveModulo(column, majorGridInterval) == 0;
            DrawLineV(Vector2(x, minY), Vector2(x, maxY), isMajor ? Fade(Colors.RAYWHITE, 0.20f) : Fade(Colors.RAYWHITE, 0.08f));
        }

        for (int row = startRow; row <= endRow; row++) {
            const y = row * gridLayout.cellSize;
            const isMajor = positiveModulo(row, majorGridInterval) == 0;
            DrawLineV(Vector2(minX, y), Vector2(maxX, y), isMajor ? Fade(Colors.RAYWHITE, 0.20f) : Fade(Colors.RAYWHITE, 0.08f));
        }
    }

    const chunkBounds = getChunkBoundsRect(chunk);

    foreach (index, otherChunk; placedChunks) {
        if (cast(int)index == editingChunkIndex) {
            continue;
        }

        const chunkOffset = Vector2(
            (otherChunk.column - chunk.column) * gridLayout.cellSize,
            (otherChunk.row - chunk.row) * gridLayout.cellSize
        );
        const otherChunkRect = Rectangle(
            chunkOffset.x,
            chunkOffset.y,
            otherChunk.width * gridLayout.cellSize,
            otherChunk.height * gridLayout.cellSize
        );

        DrawRectangleRec(otherChunkRect, Fade(Colors.DARKBLUE, 0.10f));

        if (index < chunkGeometries.length) {
            foreach (face; chunkGeometries[index].faces) {
                drawPaletteFace(chunkGeometries[index], face, ditherImage, 0.10f, chunkOffset);

                const polygonPoints = getFacePolygonPoints(chunkGeometries[index], face, chunkOffset);
                for (int pointIndex = 0; pointIndex < cast(int)polygonPoints.length; pointIndex++) {
                    const nextPointIndex = (pointIndex + 1) % cast(int)polygonPoints.length;
                    DrawLineV(polygonPoints[pointIndex], polygonPoints[nextPointIndex], Fade(Colors.RAYWHITE, 0.18f));
                }
            }

            foreach (wall; chunkGeometries[index].walls) {
                if (wall.startPointIndex < 0 || wall.startPointIndex >= cast(int)chunkGeometries[index].points.length) continue;
                if (wall.endPointIndex < 0 || wall.endPointIndex >= cast(int)chunkGeometries[index].points.length) continue;

                const startPoint = getChunkPointPosition(chunkGeometries[index].points[wall.startPointIndex]);
                const endPoint = getChunkPointPosition(chunkGeometries[index].points[wall.endPointIndex]);
                DrawLineV(
                    Vector2(chunkOffset.x + startPoint.x, chunkOffset.y + startPoint.y),
                    Vector2(chunkOffset.x + endPoint.x, chunkOffset.y + endPoint.y),
                    Fade(Colors.MAROON, 0.30f)
                );
            }
        }

        DrawRectangleLinesEx(otherChunkRect, 2.0f, Fade(Colors.RAYWHITE, 0.24f));
    }

    DrawRectangleRec(chunkBounds, Fade(Colors.DARKBLUE, 0.16f));
    DrawRectangleLinesEx(chunkBounds, 3.0f, Fade(Colors.GOLD, 0.95f));

    foreach (faceIndex, face; geometry.faces) {
        if (face.pointIndices.length < 2) {
            continue;
        }

        const isSelected = selectedFaceIndicesContain(selectedFaceIndices, cast(int)faceIndex);
        const edgeColor = isSelected ? Fade(Colors.GOLD, 0.96f) : Fade(Colors.WHITE, 0.86f);
        drawPaletteFace(geometry, face, ditherImage, isSelected ? 0.36f : 0.26f);
        if (isSelected) {
            drawFilledFace(geometry, face, Fade(Colors.GOLD, 0.12f));
        }

        for (int index = 0; index < cast(int)face.pointIndices.length; index++) {
            const currentPointIndex = face.pointIndices[index];
            const nextPointIndex = face.pointIndices[(index + 1) % cast(int)face.pointIndices.length];
            if (currentPointIndex < 0 || currentPointIndex >= cast(int)geometry.points.length) continue;
            if (nextPointIndex < 0 || nextPointIndex >= cast(int)geometry.points.length) continue;

            DrawLineV(
                getChunkPointPosition(geometry.points[currentPointIndex]),
                getChunkPointPosition(geometry.points[nextPointIndex]),
                edgeColor
            );
        }
    }

    foreach (wallIndex, wall; geometry.walls) {
        if (wall.startPointIndex < 0 || wall.startPointIndex >= cast(int)geometry.points.length) continue;
        if (wall.endPointIndex < 0 || wall.endPointIndex >= cast(int)geometry.points.length) continue;

        const isSelected = selectedWallIndicesContain(selectedWallIndices, cast(int)wallIndex);
        const startPoint = getChunkPointPosition(geometry.points[wall.startPointIndex]);
        const endPoint = getChunkPointPosition(geometry.points[wall.endPointIndex]);
        DrawLineV(startPoint, endPoint, isSelected ? Fade(Colors.RED, 0.98f) : Fade(Colors.MAROON, 0.92f));
        if (isSelected) {
            DrawCircleV(startPoint, 2.5f / gridLayout.camera.zoom, Fade(Colors.RED, 0.95f));
            DrawCircleV(endPoint, 2.5f / gridLayout.camera.zoom, Fade(Colors.RED, 0.95f));
        }
    }

    foreach (entityIndex, entity; geometry.entities) {
        const entityPosition = Vector2(entity.x, entity.z);
        const isSelected = selectedEntityIndicesContain(selectedEntityIndices, cast(int)entityIndex);
        
        Color entityColor;
        final switch (entity.type) {
        case EntityType.player:
            entityColor = Colors.GREEN;
            break;
        case EntityType.npc:
            entityColor = Colors.ORANGE;
            break;
        case EntityType.fishCommon:
            entityColor = Colors.SKYBLUE;
            break;
        case EntityType.fishRare:
            entityColor = Colors.BLUE;
            break;
        case EntityType.fishLegendary:
            entityColor = Colors.GOLD;
            break;
        case EntityType.bird:
            entityColor = Color(135, 206, 235, 255);
            break;
        case EntityType.insect:
            entityColor = Color(100, 200, 50, 255);
            break;
        case EntityType.treasureChest:
            entityColor = Colors.YELLOW;
            break;
        case EntityType.festivalDecoration:
            entityColor = Colors.VIOLET;
            break;
        }
        
        const radius = (isSelected ? 7.0f : 5.0f) / gridLayout.camera.zoom;
        DrawCircleV(entityPosition, radius, Fade(entityColor, 0.85f));
        DrawCircleLinesV(entityPosition, radius * 1.2f, isSelected ? Fade(Colors.WHITE, 0.98f) : Fade(Colors.BLACK, 0.60f));
        
        // Draw purple direction indicator
        const directionLength = radius * 2.2f;
        const directionAngle = entity.rotationY * (3.14159265f / 180.0f); // Convert to radians
        const directionEndX = entityPosition.x + cos(directionAngle) * directionLength;
        const directionEndY = entityPosition.y + sin(directionAngle) * directionLength;
        const directionEnd = Vector2(directionEndX, directionEndY);
        DrawLineEx(entityPosition, directionEnd, 2.5f / gridLayout.camera.zoom, Fade(Colors.PURPLE, 0.95f));
        DrawCircleV(directionEnd, 2.5f / gridLayout.camera.zoom, Fade(Colors.PURPLE, 0.95f));
        
        DrawCircleV(entityPosition, 1.5f / gridLayout.camera.zoom, Fade(Colors.BLACK, 0.85f));
        
        // Draw entity info text
        const textOffset = Vector2(0, -radius - 12.0f / gridLayout.camera.zoom);
        const textPos = Vector2(entityPosition.x + textOffset.x, entityPosition.y + textOffset.y);
        const typeText = getEntityTypeName(entity.type);
        const fontSize = 14.0f / gridLayout.camera.zoom;
        const textWidth = MeasureTextEx(GetFontDefault(), typeText.ptr, fontSize, fontSize / 10.0f).x;
        DrawTextPro(GetFontDefault(), typeText.ptr, Vector2(textPos.x - textWidth / 2, textPos.y), Vector2(0, 0), 0.0f, fontSize, fontSize / 10.0f, Fade(Colors.BLACK, 0.95f));
        DrawTextPro(GetFontDefault(), typeText.ptr, Vector2(textPos.x - textWidth / 2 - 1.0f / gridLayout.camera.zoom, textPos.y - 1.0f / gridLayout.camera.zoom), Vector2(0, 0), 0.0f, fontSize, fontSize / 10.0f, Fade(Colors.WHITE, 0.95f));
    }

    foreach (objectIndex, obj; geometry.objects) {
        const objectPosition = Vector2(obj.x, obj.z);
        const isSelected = selectedObjectIndicesContain(selectedObjectIndices, cast(int)objectIndex);
        
        Color objectColor;
        final switch (obj.type) {
        case ObjectType.hut:
            objectColor = Color(160, 120, 80, 255);
            break;
        case ObjectType.tree:
            objectColor = Color(34, 139, 34, 255); // Forest green
            break;
        case ObjectType.rock:
            objectColor = Colors.GRAY;
            break;
        case ObjectType.crate:
            objectColor = Colors.BROWN;
            break;
        case ObjectType.chair:
            objectColor = Color(180, 140, 90, 255);
            break;
        case ObjectType.table:
            objectColor = Color(200, 160, 100, 255);
            break;
        case ObjectType.boat:
            objectColor = Color(70, 130, 180, 255); // Steel blue
            break;
        case ObjectType.dock:
            objectColor = Color(101, 67, 33, 255);
            break;
        case ObjectType.building:
            objectColor = Color(180, 160, 120, 255);
            break;
        case ObjectType.buoy:
            objectColor = Colors.RED;
            break;
        case ObjectType.fishingNet:
            objectColor = Color(200, 200, 150, 255);
            break;
        case ObjectType.coral:
            objectColor = Color(255, 127, 80, 255); // Coral
            break;
        case ObjectType.underwaterRock:
            objectColor = Color(100, 120, 140, 255);
            break;
        case ObjectType.festivalProp:
            objectColor = Colors.PINK;
            break;
        }
        
        const radius = (isSelected ? 7.5f : 5.5f) / gridLayout.camera.zoom;
        DrawCircleV(objectPosition, radius, Fade(objectColor, 0.75f));
        DrawCircleLinesV(objectPosition, radius * 1.2f, isSelected ? Fade(Colors.WHITE, 0.98f) : Fade(Colors.BLACK, 0.60f));
        
        // Draw purple direction indicator
        const directionLength = radius * 2.2f;
        const directionAngle = obj.rotationY * (3.14159265f / 180.0f);
        const directionEndX = objectPosition.x + cos(directionAngle) * directionLength;
        const directionEndY = objectPosition.y + sin(directionAngle) * directionLength;
        const directionEnd = Vector2(directionEndX, directionEndY);
        DrawLineEx(objectPosition, directionEnd, 2.5f / gridLayout.camera.zoom, Fade(Colors.PURPLE, 0.95f));
        DrawCircleV(directionEnd, 2.5f / gridLayout.camera.zoom, Fade(Colors.PURPLE, 0.95f));
        
        // Draw height indicator (skyblue vertical line)
        const heightLineLength = fabs(obj.y) * 0.5f;
        if (heightLineLength > 0.5f) {
            const heightEnd = Vector2(objectPosition.x, objectPosition.y - heightLineLength);
            DrawLineEx(objectPosition, heightEnd, 2.0f / gridLayout.camera.zoom, Fade(Colors.SKYBLUE, 0.85f));
            DrawCircleV(heightEnd, 2.0f / gridLayout.camera.zoom, Fade(Colors.SKYBLUE, 0.85f));
        }
        
        DrawCircleV(objectPosition, 1.5f / gridLayout.camera.zoom, Fade(Colors.BLACK, 0.85f));
        
        // Draw object info text
        const textOffset = Vector2(0, -radius - 12.0f / gridLayout.camera.zoom);
        const textPos = Vector2(objectPosition.x + textOffset.x, objectPosition.y + textOffset.y);
        const typeText = getObjectTypeName(obj.type);
        const heightText = to!string(TextFormat("%s (Y:%.1f)", typeText.ptr, obj.y));
        const fontSize = 14.0f / gridLayout.camera.zoom;
        const textWidth = MeasureTextEx(GetFontDefault(), heightText.ptr, fontSize, fontSize / 10.0f).x;
        DrawTextPro(GetFontDefault(), heightText.ptr, Vector2(textPos.x - textWidth / 2, textPos.y), Vector2(0, 0), 0.0f, fontSize, fontSize / 10.0f, Fade(Colors.BLACK, 0.95f));
        DrawTextPro(GetFontDefault(), heightText.ptr, Vector2(textPos.x - textWidth / 2 - 1.0f / gridLayout.camera.zoom, textPos.y - 1.0f / gridLayout.camera.zoom), Vector2(0, 0), 0.0f, fontSize, fontSize / 10.0f, Fade(Colors.WHITE, 0.95f));
    }

    foreach (pointIndex, point; geometry.points) {
        const pointPosition = getChunkPointPosition(point);
        const isSelected = selectedPointIndicesContain(selectedPointIndices, cast(int)pointIndex);
        DrawCircleV(pointPosition, (isSelected ? 4.0f : 3.0f) / gridLayout.camera.zoom, isSelected ? Fade(Colors.GOLD, 0.98f) : Fade(Colors.LIME, 0.92f));
    }

    if (isBoxSelecting) {
        DrawRectangleRec(boxSelectRect, Fade(Colors.SKYBLUE, 0.12f));
        DrawRectangleLinesEx(boxSelectRect, 1.5f / gridLayout.camera.zoom, Fade(Colors.WHITE, 0.72f));
    }

    if (editorTool == ChunkEditorTool.placePoint) {
        DrawCircleV(Vector2.zero, 2.5f / gridLayout.camera.zoom, Fade(Colors.SKYBLUE, 0.95f));
    }
}

private string[] getMenuOptions(int toolbarIndex)
{
    switch (toolbarIndex) {
    case 0:
        return ["New Map", "Open Map", "Save Map", "Quit"];
    case 1:
        return [];
    case 2:
        return ["Toggle Grid", "Toggle Inspector", "Toggle Chunk Bounds", "Reset Layout"];
    case 3:
        return [];
    case 4:
        return ["Center Camera", "Zoom to Fit", "Clear All Chunks"];
    case 5:
        return ["Select All Points", "Deselect All", "Validate Geometry"];
    case 6:
        return ["About Leafway", "Keyboard Shortcuts"];
    default:
        return [];
    }
}

private bool isMenuOptionEnabled(int toolbarIndex, int optionIndex, bool hasActiveMap)
{
    if (hasActiveMap) {
        return true;
    }

    switch (toolbarIndex) {
    case 0:
        return optionIndex >= 0 && optionIndex <= 2;
    case 2:
        return true;
    default:
        return false;
    }
}

private bool isToolbarEnabled(int toolbarIndex, bool hasActiveMap)
{
    const options = getMenuOptions(toolbarIndex);
    foreach (optionIndex, _; options) {
        if (isMenuOptionEnabled(toolbarIndex, cast(int)optionIndex, hasActiveMap)) {
            return true;
        }
    }

    return false;
}

private string getToolbarLabel(int toolbarIndex)
{
    switch (toolbarIndex) {
    case 0:
        return "File";
    case 1:
        return "Edit";
    case 2:
        return "View";
    case 3:
        return "Project";
    case 4:
        return "Map";
    case 5:
        return "Chunk";
    case 6:
        return "Help";
    default:
        return "";
    }
}

private int[] getVisibleToolbarIndices(bool hasActiveMap, AppScreen appScreen)
{
    if (!hasActiveMap) {
        return [0, 2, 6];
    }

    return appScreen == AppScreen.chunkEditor
        ? [0, 1, 2, 5, 6]
        : [0, 2, 4, 6];
}

private Rectangle getToolbarMenuRect(Rectangle anchor, size_t itemCount)
{
    const menuWidth = 220.0f;
    const menuHeight = 18.0f + itemCount * 34.0f;
    float menuX = anchor.x;

    if (menuX + menuWidth > GetScreenWidth() - 16.0f) {
        menuX = GetScreenWidth() - menuWidth - 16.0f;
    }

    return Rectangle(menuX, toolbarHeight + 6.0f, menuWidth, menuHeight);
}

private void drawActiveToolHighlight(Rectangle bounds)
{
    const highlightBounds = Rectangle(bounds.x - 2.0f, bounds.y - 2.0f, bounds.width + 4.0f, bounds.height + 4.0f);
    DrawRectangleLinesEx(highlightBounds, 2.0f, Fade(Colors.GOLD, 0.96f));
}

private void clearChunkEditorSelection(
    ref int[] selectedPointIndices,
    ref int[] selectedFaceIndices,
    ref int[] selectedWallIndices,
    ref int[] selectedEntityIndices,
    ref int[] selectedObjectIndices,
)
{
    selectedPointIndices.length = 0;
    selectedFaceIndices.length = 0;
    selectedWallIndices.length = 0;
    selectedEntityIndices.length = 0;
    selectedObjectIndices.length = 0;
}

private void setMapChunkTool(ref ChunkTool activeChunkTool, ChunkTool nextTool, ref string chunkToolMessage, Sound clickSound)
{
    activeChunkTool = nextTool;

    final switch (nextTool) {
    case ChunkTool.draw:
        chunkToolMessage = "Draw mode: drag on the canvas to create a new chunk.";
        break;
    case ChunkTool.move:
        chunkToolMessage = "Move mode: drag a chunk to reposition it.";
        break;
    case ChunkTool.resize:
        chunkToolMessage = "Resize is disabled to preserve chunk geometry.";
        break;
    case ChunkTool.deleteChunk:
        chunkToolMessage = "Delete mode: click a chunk to remove it.";
        break;
    case ChunkTool.edit:
        chunkToolMessage = "Edit mode: click a chunk to inspect it.";
        break;
    }

    PlaySound(clickSound);
}

private void setChunkEditorTool(ref ChunkEditorTool chunkEditorTool, ChunkEditorTool nextTool, ref string chunkEditorMessage, Sound clickSound)
{
    chunkEditorTool = nextTool;
    
    final switch (nextTool) {
    case ChunkEditorTool.placePoint:
        chunkEditorMessage = "Point mode: click to place snapped points inside the chunk bounds.";
        break;
    case ChunkEditorTool.selectPoint:
        chunkEditorMessage = "Select mode: click points or face centers.";
        break;
    case ChunkEditorTool.placeEntity:
        chunkEditorMessage = "Entity mode: click to place entities (enemies, NPCs, players).";
        break;
    case ChunkEditorTool.placeObject:
        chunkEditorMessage = "Object mode: click to place 3D objects with height.";
        break;
    }
    
    PlaySound(clickSound);
}

private void createSelectedFace(
    ref ChunkGeometry geometry,
    ref int[] selectedPointIndices,
    ref int[] selectedFaceIndices,
    ref string chunkEditorMessage,
    Sound connectSound,
    Sound touchSound,
)
{
    if (selectedPointIndices.length < 3) {
        chunkEditorMessage = "Select at least 3 points to create a face.";
        PlaySound(touchSound);
        return;
    }

    const orderedPointIndices = sortFacePointIndices(geometry, selectedPointIndices);
    if (faceOverlapsExistingFaces(geometry, orderedPointIndices)) {
        chunkEditorMessage = "Face is invalid: it overlaps another face or crosses itself.";
        PlaySound(touchSound);
        return;
    }

    geometry.faces ~= ChunkFace(orderedPointIndices.dup, 0, 16, 0, true, false);
    selectedFaceIndices = [cast(int)geometry.faces.length - 1];
    selectedPointIndices.length = 0;
    chunkEditorMessage = to!string(TextFormat("Created face %d.", selectedFaceIndices[0] + 1));
    PlaySound(connectSound);
}

private void deleteSelectedFaces(
    ref ChunkGeometry geometry,
    ref int[] selectedFaceIndices,
    ref string chunkEditorMessage,
    Sound deleteSound,
    Sound touchSound,
)
{
    if (selectedFaceIndices.length == 0) {
        chunkEditorMessage = "Select one or more faces to delete.";
        PlaySound(touchSound);
        return;
    }

    auto faceIndicesToDelete = selectedFaceIndices.dup;
    faceIndicesToDelete.sort!((a, b) => a > b);
    foreach (faceIndex; faceIndicesToDelete) {
        if (faceIndex >= 0 && faceIndex < cast(int)geometry.faces.length) {
            removeFaceAt(geometry, faceIndex);
        }
    }

    chunkEditorMessage = to!string(TextFormat("Deleted %d face(s).", cast(int)faceIndicesToDelete.length));
    selectedFaceIndices.length = 0;
    PlaySound(deleteSound);
}

private void createSelectedWall(
    ref ChunkGeometry geometry,
    ref int[] selectedPointIndices,
    ref int[] selectedFaceIndices,
    ref int[] selectedWallIndices,
    ref string chunkEditorMessage,
    Sound connectSound,
    Sound touchSound,
)
{
    if (selectedPointIndices.length != 2) {
        chunkEditorMessage = "Select exactly 2 points to create a wall.";
        PlaySound(touchSound);
        return;
    }

    const pointAIndex = selectedPointIndices[0];
    const pointBIndex = selectedPointIndices[1];
    if (pointAIndex == pointBIndex) {
        chunkEditorMessage = "Pick two different points to create a wall.";
        PlaySound(touchSound);
        return;
    }
    if (chunkGeometryHasWall(geometry, pointAIndex, pointBIndex)) {
        chunkEditorMessage = "That wall already exists.";
        PlaySound(touchSound);
        return;
    }

    geometry.walls ~= ChunkWall(pointAIndex, pointBIndex, 0, 16, 0);
    selectedWallIndices = [cast(int)geometry.walls.length - 1];
    selectedPointIndices.length = 0;
    selectedFaceIndices.length = 0;
    chunkEditorMessage = to!string(TextFormat("Created wall %d.", selectedWallIndices[0] + 1));
    PlaySound(connectSound);
}

private void deleteSelectedWalls(
    ref ChunkGeometry geometry,
    ref int[] selectedWallIndices,
    ref string chunkEditorMessage,
    Sound deleteSound,
    Sound touchSound,
)
{
    if (selectedWallIndices.length == 0) {
        chunkEditorMessage = "Select one or more walls to delete.";
        PlaySound(touchSound);
        return;
    }

    auto wallIndicesToDelete = selectedWallIndices.dup;
    wallIndicesToDelete.sort!((a, b) => a > b);
    foreach (wallIndex; wallIndicesToDelete) {
        if (wallIndex >= 0 && wallIndex < cast(int)geometry.walls.length) {
            removeWallAt(geometry, wallIndex);
        }
    }

    chunkEditorMessage = to!string(TextFormat("Deleted %d wall(s).", cast(int)wallIndicesToDelete.length));
    selectedWallIndices.length = 0;
    PlaySound(deleteSound);
}

private void deleteSelectedPoints(
    ref ChunkGeometry geometry,
    ref int[] selectedPointIndices,
    ref int[] selectedFaceIndices,
    ref int[] selectedWallIndices,
    ref int[] selectedEntityIndices,
    ref int[] selectedObjectIndices,
    ref string chunkEditorMessage,
    Sound deleteSound,
    Sound touchSound,
)
{
    if (selectedPointIndices.length == 0) {
        chunkEditorMessage = "Select one or more points to delete.";
        PlaySound(touchSound);
        return;
    }

    bool pointUsedByWall = false;
    foreach (selectedPointIndex; selectedPointIndices) {
        if (pointIsUsedByWall(geometry, selectedPointIndex)) {
            pointUsedByWall = true;
            break;
        }
    }

    if (selectedPointsUsedByUnselectedFaces(geometry, selectedPointIndices, selectedFaceIndices) || pointUsedByWall) {
        chunkEditorMessage = pointUsedByWall
            ? "Delete linked walls first before removing those points."
            : "Delete linked faces first, or select those faces too.";
        PlaySound(touchSound);
        return;
    }

    auto pointIndicesToDelete = selectedPointIndices.dup;
    pointIndicesToDelete.sort!((a, b) => a > b);
    foreach (pointIndex; pointIndicesToDelete) {
        if (pointIndex >= 0 && pointIndex < cast(int)geometry.points.length) {
            removePointAt(geometry, pointIndex);
        }
    }

    clearChunkEditorSelection(selectedPointIndices, selectedFaceIndices, selectedWallIndices, selectedEntityIndices, selectedObjectIndices);
    chunkEditorMessage = to!string(TextFormat("Deleted %d point(s).", cast(int)pointIndicesToDelete.length));
    PlaySound(deleteSound);
}

private void deleteCurrentChunkEditorSelection(
    ref ChunkGeometry geometry,
    ref int[] selectedPointIndices,
    ref int[] selectedFaceIndices,
    ref int[] selectedWallIndices,
    ref int[] selectedEntityIndices,
    ref int[] selectedObjectIndices,
    ref string chunkEditorMessage,
    Sound deleteSound,
    Sound touchSound,
)
{
    if (selectedFaceIndices.length > 0) {
        deleteSelectedFaces(geometry, selectedFaceIndices, chunkEditorMessage, deleteSound, touchSound);
        return;
    }
    if (selectedWallIndices.length > 0) {
        deleteSelectedWalls(geometry, selectedWallIndices, chunkEditorMessage, deleteSound, touchSound);
        return;
    }
    if (selectedEntityIndices.length > 0) {
        deleteSelectedEntities(geometry, selectedEntityIndices, chunkEditorMessage, deleteSound, touchSound);
        return;
    }
    if (selectedObjectIndices.length > 0) {
        deleteSelectedObjects(geometry, selectedObjectIndices, chunkEditorMessage, deleteSound, touchSound);
        return;
    }

    deleteSelectedPoints(geometry, selectedPointIndices, selectedFaceIndices, selectedWallIndices, selectedEntityIndices, selectedObjectIndices, chunkEditorMessage, deleteSound, touchSound);
}

private void selectAllChunkPoints(
    ChunkGeometry geometry,
    ref int[] selectedPointIndices,
    ref int[] selectedFaceIndices,
    ref int[] selectedWallIndices,
    ref int[] selectedEntityIndices,
    ref int[] selectedObjectIndices,
    ref string chunkEditorMessage,
    Sound clickSound,
    Sound touchSound,
)
{
    if (geometry.points.length == 0) {
        chunkEditorMessage = "There are no points to select.";
        PlaySound(touchSound);
        return;
    }

    selectedPointIndices.length = 0;
    selectedPointIndices.reserve(geometry.points.length);
    foreach (index; 0 .. geometry.points.length) {
        selectedPointIndices ~= cast(int)index;
    }
    selectedFaceIndices.length = 0;
    selectedWallIndices.length = 0;
    selectedEntityIndices.length = 0;
    selectedObjectIndices.length = 0;
    chunkEditorMessage = to!string(TextFormat("Selected %d point(s).", cast(int)selectedPointIndices.length));
    PlaySound(clickSound);
}

private void returnToMapFromChunkEditor(
    ref AppScreen appScreen,
    ref int selectedChunkIndex,
    ref int editingChunkIndex,
    ref int[] selectedPointIndices,
    ref int[] selectedFaceIndices,
    ref int[] selectedWallIndices,
    ref int[] selectedEntityIndices,
    ref int[] selectedObjectIndices,
    ref bool isBoxSelecting,
    ref string chunkEditorMessage,
    ref string chunkToolMessage,
    Sound clickSound,
)
{
    appScreen = AppScreen.map;
    selectedChunkIndex = editingChunkIndex;
    clearChunkEditorSelection(selectedPointIndices, selectedFaceIndices, selectedWallIndices, selectedEntityIndices, selectedObjectIndices);
    isBoxSelecting = false;
    editingChunkIndex = -1;
    chunkEditorMessage = "Returned to the map canvas.";
    chunkToolMessage = "Edit mode: click a chunk to inspect it.";
    PlaySound(clickSound);
}

private string getEntityTypeName(EntityType type)
{
    final switch (type) {
    case EntityType.player:
        return "Player";
    case EntityType.npc:
        return "NPC";
    case EntityType.fishCommon:
        return "Fish (Common)";
    case EntityType.fishRare:
        return "Fish (Rare)";
    case EntityType.fishLegendary:
        return "Fish (Legendary)";
    case EntityType.bird:
        return "Bird";
    case EntityType.insect:
        return "Insect";
    case EntityType.treasureChest:
        return "Treasure Chest";
    case EntityType.festivalDecoration:
        return "Festival Decoration";
    }
}

private bool selectedEntityIndicesContain(int[] selectedEntityIndices, int entityIndex)
{
    foreach (index; selectedEntityIndices) {
        if (index == entityIndex) return true;
    }
    return false;
}

// Returns the floor height of the face containing (x, z), or 0 if none found.
private float getFloorHeightAtXZ(ChunkGeometry geometry, float x, float z)
{
    const pt = Vector2(x, z);
    foreach (face; geometry.faces) {
        const poly = getFacePolygonPoints(geometry, face);
        if (poly.length < 3) continue;
        // Ray-casting point-in-polygon test
        bool inside = false;
        for (int i = 0, j = cast(int)poly.length - 1; i < cast(int)poly.length; j = i++) {
            const xi = poly[i].x, yi = poly[i].y;
            const xj = poly[j].x, yj = poly[j].y;
            if (((yi > pt.y) != (yj > pt.y)) &&
                (pt.x < (xj - xi) * (pt.y - yi) / (yj - yi) + xi))
                inside = !inside;
        }
        if (inside) return cast(float)face.floorHeight;
    }
    return 0.0f;
}

private int findEntityAtWorldPosition(ChunkGeometry geometry, Vector2 worldPosition, float threshold)
{
    foreach_reverse (entityIndex, entity; geometry.entities) {
        const entityPos = Vector2(entity.x, entity.z);
        const distance = Vector2Distance(entityPos, worldPosition);
        if (distance < threshold) {
            return cast(int)entityIndex;
        }
    }
    return -1;
}

private void deleteSelectedEntities(
    ref ChunkGeometry geometry,
    ref int[] selectedEntityIndices,
    ref string chunkEditorMessage,
    Sound deleteSound,
    Sound touchSound,
)
{
    if (selectedEntityIndices.length == 0) {
        chunkEditorMessage = "Select one or more entities to delete.";
        PlaySound(touchSound);
        return;
    }

    auto entitiesToDelete = selectedEntityIndices.dup;
    entitiesToDelete.sort!((a, b) => a > b);
    foreach (entityIndex; entitiesToDelete) {
        if (entityIndex >= 0 && entityIndex < cast(int)geometry.entities.length) {
            geometry.entities = geometry.entities[0 .. entityIndex] ~ geometry.entities[entityIndex + 1 .. $];
        }
    }

    chunkEditorMessage = to!string(TextFormat("Deleted %d entity/entities.", cast(int)entitiesToDelete.length));
    selectedEntityIndices.length = 0;
    PlaySound(deleteSound);
}

private string getObjectTypeName(ObjectType type)
{
    final switch (type) {
    case ObjectType.hut:
        return "Hut";
    case ObjectType.tree:
        return "Tree";
    case ObjectType.rock:
        return "Rock";
    case ObjectType.crate:
        return "Crate";
    case ObjectType.chair:
        return "Chair";
    case ObjectType.table:
        return "Table";
    case ObjectType.boat:
        return "Boat";
    case ObjectType.dock:
        return "Dock";
    case ObjectType.building:
        return "Building";
    case ObjectType.buoy:
        return "Buoy";
    case ObjectType.fishingNet:
        return "Fishing Net";
    case ObjectType.coral:
        return "Coral";
    case ObjectType.underwaterRock:
        return "Underwater Rock";
    case ObjectType.festivalProp:
        return "Festival Prop";
    }
}

private bool selectedObjectIndicesContain(int[] selectedObjectIndices, int objectIndex)
{
    foreach (index; selectedObjectIndices) {
        if (index == objectIndex) return true;
    }
    return false;
}

private int findObjectAtWorldPosition(ChunkGeometry geometry, Vector2 worldPosition, float threshold)
{
    foreach (objectIndex, obj; geometry.objects) {
        const objectPosition = Vector2(obj.x, obj.z);
        if (Vector2Distance(objectPosition, worldPosition) <= threshold) {
            return cast(int)objectIndex;
        }
    }
    return -1;
}

private void deleteSelectedObjects(
    ref ChunkGeometry geometry,
    ref int[] selectedObjectIndices,
    ref string chunkEditorMessage,
    Sound deleteSound,
    Sound touchSound,
)
{
    if (selectedObjectIndices.length == 0) {
        chunkEditorMessage = "Select one or more objects to delete.";
        PlaySound(touchSound);
        return;
    }

    auto objectsToDelete = selectedObjectIndices.dup;
    objectsToDelete.sort!((a, b) => a > b);
    foreach (objectIndex; objectsToDelete) {
        if (objectIndex >= 0 && objectIndex < cast(int)geometry.objects.length) {
            geometry.objects = geometry.objects[0 .. objectIndex] ~ geometry.objects[objectIndex + 1 .. $];
        }
    }

    chunkEditorMessage = to!string(TextFormat("Deleted %d object(s).", cast(int)objectsToDelete.length));
    selectedObjectIndices.length = 0;
    PlaySound(deleteSound);
}

private void applyToolbarAction(
    int toolbarIndex,
    int optionIndex,
    ref string selectedMapPath,
    ref bool hasActiveMap,
    ref AppScreen appScreen,
    ref int editingChunkIndex,
    ref bool pendingOpenMapDialog,
    ref bool showGrid,
    ref bool showInspector,
    ref bool showChunkBounds,
    ref MapChunk[] placedChunks,
    ref ChunkGeometry[] chunkGeometries,
    ref bool shouldExit,
    ref Camera2D mapCamera,
    ref Camera2D chunkEditorCamera,
    ref int[] selectedPointIndices,
    ref int[] selectedFaceIndices,
    ref int[] selectedWallIndices,
    ref int[] selectedEntityIndices,
    ref int[] selectedObjectIndices,
    ref string chunkToolMessage,
    ref string chunkEditorMessage,
    ref bool showAboutDialog,
    ref bool showShortcutsDialog,
    ref bool pendingSaveMapDialog,
)
{
    switch (toolbarIndex) {
    case 0:
        switch (optionIndex) {
        case 0:
            selectedMapPath = "A new untitled map session is ready";
            hasActiveMap = true;
            appScreen = AppScreen.map;
            editingChunkIndex = -1;
            placedChunks.length = 0;
            chunkGeometries.length = 0;
            break;
        case 1:
            pendingOpenMapDialog = true;
            break;
        case 2:
            pendingSaveMapDialog = true;
            break;
        case 3:
            shouldExit = true;
            break;
        default:
            break;
        }
        break;
    case 1:
        switch (optionIndex) {
        case 0:
            break;
        case 1:
            break;
        case 2:
            break;
        case 3:
            break;
        default:
            break;
        }
        break;
    case 2:
        switch (optionIndex) {
        case 0:
            showGrid = !showGrid;
            break;
        case 1:
            showInspector = !showInspector;
            break;
        case 2:
            showChunkBounds = !showChunkBounds;
            break;
        case 3:
            showGrid = true;
            showInspector = true;
            showChunkBounds = false;
            break;
        default:
            break;
        }
        break;
    case 3:
        switch (optionIndex) {
        case 0:
            break;
        case 1:
            break;
        case 2:
            break;
        default:
            break;
        }
        break;
    case 4:
        switch (optionIndex) {
        case 0:
            mapCamera.target = Vector2(0.0f, 0.0f);
            mapCamera.zoom = 1.0f;
            chunkToolMessage = "Camera centered at origin.";
            break;
        case 1:
            if (placedChunks.length > 0) {
                const bounds = getChunkPreviewBounds(placedChunks, chunkGeometries);
                mapCamera.target = Vector2(
                    bounds.horizontal.x + bounds.horizontal.width * 0.5f,
                    bounds.horizontal.y + bounds.horizontal.height * 0.5f
                );
                const maxSpan = max(bounds.horizontal.width, bounds.horizontal.height);
                mapCamera.zoom = maxSpan > 0.0f ? min(4.0f, 300.0f / maxSpan) : 1.0f;
                chunkToolMessage = "Camera zoomed to fit all chunks.";
            } else {
                chunkToolMessage = "No chunks to fit.";
            }
            break;
        case 2:
            placedChunks.length = 0;
            chunkGeometries.length = 0;
            chunkToolMessage = "All chunks cleared.";
            break;
        default:
            break;
        }
        break;
    case 5:
        switch (optionIndex) {
        case 0:
            if (editingChunkIndex >= 0 && editingChunkIndex < cast(int)chunkGeometries.length) {
                selectedPointIndices.length = 0;
                selectedPointIndices.reserve(chunkGeometries[editingChunkIndex].points.length);
                foreach (i; 0 .. chunkGeometries[editingChunkIndex].points.length) {
                    selectedPointIndices ~= cast(int)i;
                }
                selectedFaceIndices.length = 0;
                selectedWallIndices.length = 0;
                selectedEntityIndices.length = 0;
                selectedObjectIndices.length = 0;
                chunkEditorMessage = to!string(TextFormat("Selected %d point(s).", cast(int)selectedPointIndices.length));
            }
            break;
        case 1:
            clearChunkEditorSelection(selectedPointIndices, selectedFaceIndices, selectedWallIndices, selectedEntityIndices, selectedObjectIndices);
            chunkEditorMessage = "All selections cleared.";
            break;
        case 2:
            if (editingChunkIndex >= 0 && editingChunkIndex < cast(int)chunkGeometries.length) {
                int issueCount = 0;
                foreach (face; chunkGeometries[editingChunkIndex].faces) {
                    const polygonPoints = getFacePolygonPoints(chunkGeometries[editingChunkIndex], face);
                    if (polygonPoints.length < 3 || polygonHasSelfIntersection(polygonPoints)) {
                        issueCount++;
                    }
                }
                chunkEditorMessage = issueCount > 0
                    ? to!string(TextFormat("Warning: %d invalid face(s) found.", issueCount))
                    : "Geometry validation passed: all faces are valid.";
            }
            break;
        default:
            break;
        }
        break;
    case 6:
        switch (optionIndex) {
        case 0:
            showAboutDialog = true;
            break;
        case 1:
            showShortcutsDialog = true;
            break;
        default:
            break;
        }
        break;
    default:
        break;
    }
}

private Rectangle makeToolbarButtonRect(int index, float width)
{
    return Rectangle(
        toolbarPadding + index * (width + toolbarPadding),
        toolbarPadding,
        width,
        toolbarHeight - toolbarPadding * 2.0f
    );
}

private void drawPanningBackground(Texture2D waterTexture, Vector2 offset)
{
    const screenWidth = cast(float)GetScreenWidth();
    const screenHeight = cast(float)GetScreenHeight();

    Rectangle source = Rectangle(
        offset.x,
        offset.y,
        screenWidth,
        screenHeight
    );

    Rectangle destination = Rectangle(0.0f, 0.0f, screenWidth, screenHeight);
    DrawTexturePro(waterTexture, source, destination, Vector2.zero, 0.0f, Colors.WHITE);

    DrawRectangleGradientV(0, 0, cast(int)screenWidth, cast(int)screenHeight, Fade(Colors.SKYBLUE, 0.12f), Fade(Colors.DARKBLUE, 0.35f));
}

private string serializeChunkToLeaf(MapChunk chunk, ChunkGeometry geometry)
{
    import std.array : appender;
    import std.format : format;

    auto buf = appender!string();

    // i [MAX_POINTS]
    buf ~= format("i %d\n", cast(int)geometry.points.length);

    // Faces: s x z ... p palette  f y0 y1
    foreach (face; geometry.faces) {
        foreach (pointIndex; face.pointIndices) {
            if (pointIndex < 0 || pointIndex >= cast(int)geometry.points.length) continue;
            const pt = geometry.points[pointIndex];
            buf ~= format("s %d %d\n", pt.x, pt.z);
        }
        buf ~= format("p %d\n", face.paletteIndex);
        buf ~= format("f %d %d\n", face.floorHeight, face.ceilingHeight);
        buf ~= "\n";
    }

    // Walls: w startX startZ  w endX endZ  p palette  f y0 y1
    foreach (wall; geometry.walls) {
        if (wall.startPointIndex < 0 || wall.startPointIndex >= cast(int)geometry.points.length) continue;
        if (wall.endPointIndex   < 0 || wall.endPointIndex   >= cast(int)geometry.points.length) continue;
        const startPt = geometry.points[wall.startPointIndex];
        const endPt   = geometry.points[wall.endPointIndex];
        buf ~= format("w %d %d\n", startPt.x, startPt.z);
        buf ~= format("w %d %d\n", endPt.x,   endPt.z);
        buf ~= format("p %d\n", wall.paletteIndex);
        buf ~= format("f %d %d\n", wall.floorHeight, wall.ceilingHeight);
        buf ~= "\n";
    }

    // Auto-walls: computed from faces with autoWallFromHeightDifference
    for (int faceIndex = 0; faceIndex < cast(int)geometry.faces.length; faceIndex++) {
        const face = geometry.faces[faceIndex];
        if (!face.autoWallFromHeightDifference || face.pointIndices.length < 2) continue;

        for (int ei = 0; ei < cast(int)face.pointIndices.length; ei++) {
            const pointAIndex = face.pointIndices[ei];
            const pointBIndex = face.pointIndices[(ei + 1) % cast(int)face.pointIndices.length];
            if (pointAIndex < 0 || pointAIndex >= cast(int)geometry.points.length) continue;
            if (pointBIndex < 0 || pointBIndex >= cast(int)geometry.points.length) continue;
            const ptA = geometry.points[pointAIndex];
            const ptB = geometry.points[pointBIndex];

            const adjFaceIndex = findAdjacentFaceForEdge(geometry, faceIndex, pointAIndex, pointBIndex);

            if (adjFaceIndex < 0) {
                // Exterior edge - full wall
                buf ~= format("w %d %d\n", ptA.x, ptA.z);
                buf ~= format("w %d %d\n", ptB.x, ptB.z);
                buf ~= format("p %d\n", face.paletteIndex);
                buf ~= format("f %d %d\n", face.floorHeight, face.ceilingHeight);
                buf ~= "\n";
            } else {
                const adjFace = geometry.faces[adjFaceIndex];
                // Dedup: only emit once per shared edge
                if (adjFace.autoWallFromHeightDifference && adjFaceIndex < faceIndex) continue;

                // Floor step wall
                const lowerFloor = face.floorHeight < adjFace.floorHeight ? face.floorHeight : adjFace.floorHeight;
                const upperFloor = face.floorHeight > adjFace.floorHeight ? face.floorHeight : adjFace.floorHeight;
                if (upperFloor > lowerFloor) {
                    buf ~= format("w %d %d\n", ptA.x, ptA.z);
                    buf ~= format("w %d %d\n", ptB.x, ptB.z);
                    buf ~= format("p %d\n", face.paletteIndex);
                    buf ~= format("f %d %d\n", lowerFloor, upperFloor);
                    buf ~= "\n";
                }

                // Ceiling step wall
                const lowerCeiling = face.ceilingHeight < adjFace.ceilingHeight ? face.ceilingHeight : adjFace.ceilingHeight;
                const upperCeiling = face.ceilingHeight > adjFace.ceilingHeight ? face.ceilingHeight : adjFace.ceilingHeight;
                if (upperCeiling > lowerCeiling) {
                    buf ~= format("w %d %d\n", ptA.x, ptA.z);
                    buf ~= format("w %d %d\n", ptB.x, ptB.z);
                    buf ~= format("p %d\n", face.paletteIndex);
                    buf ~= format("f %d %d\n", lowerCeiling, upperCeiling);
                    buf ~= "\n";
                }
            }
        }
    }

    // Objects: o x y z rx ry rz sx sy sz i
    foreach (obj; geometry.objects) {
        buf ~= format("o %.4f %.4f %.4f %.4f %.4f %.4f %.4f %.4f %.4f %d\n",
            obj.x, obj.y, obj.z,
            obj.rotationX, obj.rotationY, obj.rotationZ,
            obj.scaleX, obj.scaleY, obj.scaleZ,
            cast(int)obj.type);
    }

    // Entities: e x z rx ry rz sx sy sz i
    foreach (entity; geometry.entities) {
        buf ~= format("e %.4f %.4f %.4f %.4f %.4f %.4f %.4f %.4f %d\n",
            entity.x, entity.z,
            entity.rotationX, entity.rotationY, entity.rotationZ,
            entity.scaleX, entity.scaleY, entity.scaleZ,
            cast(int)entity.type);
    }

    buf ~= "ok\n";
    return buf.data;
}

private void saveAllChunks(MapChunk[] placedChunks, ChunkGeometry[] chunkGeometries, string saveDir, string mapName, ref string message)
{
    import std.path : buildPath;

    const baseName = mapName.length > 0 ? mapName : "chunk";
    int saved = 0;
    for (int i = 0; i < cast(int)placedChunks.length && i < cast(int)chunkGeometries.length; i++) {
        const filename = buildPath(saveDir, format("%s_%d.leaf", baseName, i));
        const content = serializeChunkToLeaf(placedChunks[i], chunkGeometries[i]);
        std.file.write(filename, content);
        saved++;
    }
    message = format("Saved %d chunk(s) to: %s", saved, saveDir);
}

// Parses the leaf section for one chunk (lines starting after the "chunk ..." header).
// Advances lineIdx past the "ok" terminator. Returns false if parsing fails.
private bool parseLeafSection(string[] lines, ref int lineIdx, ref ChunkGeometry geometry)
{
    geometry = ChunkGeometry.init;

    // Skip 'i' (point count) header line
    if (lineIdx < lines.length && lines[lineIdx].strip().startsWith("i ")) lineIdx++;

    int[string] pointMap; // "x_z" -> index into geometry.points

    auto getOrAddPoint = (int x, int z) {
        const key = format("%d_%d", x, z);
        if (const p = key in pointMap) return *p;
        const idx = cast(int)geometry.points.length;
        geometry.points ~= ChunkPoint(x, z);
        pointMap[key] = idx;
        return idx;
    };

    while (lineIdx < lines.length) {
        const line = lines[lineIdx].strip();

        if (line == "ok") { lineIdx++; return true; }

        // Face: one or more 's x z' tokens
        if (line.length >= 2 && line[0] == 's') {
            ChunkFace face;
            while (lineIdx < lines.length) {
                const fl = lines[lineIdx].strip();
                if (fl.length >= 2 && fl[0] == 's') {
                    const parts = fl[2..$].split(' ');
                    if (parts.length >= 2) {
                        try { face.pointIndices ~= getOrAddPoint(parts[0].to!int, parts[1].to!int); }
                        catch (Exception) {}
                    }
                    lineIdx++;
                } else break;
            }
            if (lineIdx < lines.length) {
                const fl = lines[lineIdx].strip();
                if (fl.length >= 2 && fl[0] == 'p') {
                    try { face.paletteIndex = fl[2..$].to!int; } catch (Exception) {}
                    lineIdx++;
                }
            }
            if (lineIdx < lines.length) {
                const fl = lines[lineIdx].strip();
                if (fl.length >= 2 && fl[0] == 'f') {
                    const parts = fl[2..$].split(' ');
                    if (parts.length >= 2) {
                        try { face.floorHeight = parts[0].to!int; face.ceilingHeight = parts[1].to!int; }
                        catch (Exception) {}
                    }
                    lineIdx++;
                }
            }
            if (lineIdx < lines.length && lines[lineIdx].strip() == "") lineIdx++;
            geometry.faces ~= face;
            continue;
        }

        // Wall: 'w x z' start, 'w x z' end
        if (line.length >= 2 && line[0] == 'w') {
            ChunkWall wall;
            {
                const parts = line[2..$].split(' ');
                if (parts.length >= 2) {
                    try { wall.startPointIndex = getOrAddPoint(parts[0].to!int, parts[1].to!int); }
                    catch (Exception) {}
                }
                lineIdx++;
            }
            if (lineIdx < lines.length) {
                const fl = lines[lineIdx].strip();
                if (fl.length >= 2 && fl[0] == 'w') {
                    const parts = fl[2..$].split(' ');
                    if (parts.length >= 2) {
                        try { wall.endPointIndex = getOrAddPoint(parts[0].to!int, parts[1].to!int); }
                        catch (Exception) {}
                    }
                    lineIdx++;
                }
            }
            if (lineIdx < lines.length) {
                const fl = lines[lineIdx].strip();
                if (fl.length >= 2 && fl[0] == 'p') {
                    try { wall.paletteIndex = fl[2..$].to!int; } catch (Exception) {}
                    lineIdx++;
                }
            }
            if (lineIdx < lines.length) {
                const fl = lines[lineIdx].strip();
                if (fl.length >= 2 && fl[0] == 'f') {
                    const parts = fl[2..$].split(' ');
                    if (parts.length >= 2) {
                        try { wall.floorHeight = parts[0].to!int; wall.ceilingHeight = parts[1].to!int; }
                        catch (Exception) {}
                    }
                    lineIdx++;
                }
            }
            if (lineIdx < lines.length && lines[lineIdx].strip() == "") lineIdx++;
            geometry.walls ~= wall;
            continue;
        }

        // Object: o x y z rx ry rz sx sy sz type
        if (line.length >= 2 && line[0] == 'o') {
            const parts = line[2..$].split(' ');
            if (parts.length >= 10) {
                ChunkObject obj;
                try {
                    obj.x = parts[0].to!float; obj.y = parts[1].to!float; obj.z = parts[2].to!float;
                    obj.rotationX = parts[3].to!float; obj.rotationY = parts[4].to!float; obj.rotationZ = parts[5].to!float;
                    obj.scaleX = parts[6].to!float; obj.scaleY = parts[7].to!float; obj.scaleZ = parts[8].to!float;
                    obj.type = cast(ObjectType)parts[9].to!int;
                    geometry.objects ~= obj;
                } catch (Exception) {}
            }
            lineIdx++;
            continue;
        }

        // Entity: e x z rx ry rz sx sy sz type
        if (line.length >= 2 && line[0] == 'e') {
            const parts = line[2..$].split(' ');
            if (parts.length >= 9) {
                ChunkEntity entity;
                try {
                    entity.x = parts[0].to!float; entity.z = parts[1].to!float;
                    entity.rotationX = parts[2].to!float; entity.rotationY = parts[3].to!float; entity.rotationZ = parts[4].to!float;
                    entity.scaleX = parts[5].to!float; entity.scaleY = parts[6].to!float; entity.scaleZ = parts[7].to!float;
                    entity.type = cast(EntityType)parts[8].to!int;
                    geometry.entities ~= entity;
                } catch (Exception) {}
            }
            lineIdx++;
            continue;
        }

        lineIdx++; // skip unknown/blank lines
    }
    return false;
}

private string serializeMapToLm(MapChunk[] placedChunks, ChunkGeometry[] chunkGeometries, string mapName)
{
    auto buf = appender!string();
    buf ~= format("lm %s\n", mapName.length > 0 ? mapName : "Untitled");
    const count = cast(int)(placedChunks.length < chunkGeometries.length ? placedChunks.length : chunkGeometries.length);
    buf ~= format("%d\n", count);
    for (int i = 0; i < count; i++) {
        const chunk = placedChunks[i];
        buf ~= format("chunk %d %d %d %d %d\n", chunk.column, chunk.row, chunk.width, chunk.height, chunk.layer);
        buf ~= serializeChunkToLeaf(placedChunks[i], chunkGeometries[i]);
    }
    return buf.data;
}

private bool loadMapFromLm(string content, ref MapChunk[] placedChunks, ref ChunkGeometry[] chunkGeometries, ref string mapName)
{
    auto lines = content.lineSplitter().array;
    int lineIdx = 0;

    if (lineIdx >= lines.length) return false;
    const firstLine = lines[lineIdx++].strip();
    if (firstLine.length < 3 || firstLine[0 .. 3] != "lm ") return false;
    mapName = firstLine[3 .. $].idup;

    if (lineIdx >= lines.length) return false;
    int numChunks;
    try { numChunks = lines[lineIdx++].strip().to!int; } catch (Exception) { return false; }

    placedChunks.length = 0;
    chunkGeometries.length = 0;

    for (int ci = 0; ci < numChunks; ci++) {
        if (lineIdx >= lines.length) return false;
        const chunkLine = lines[lineIdx++].strip();
        if (!chunkLine.startsWith("chunk ")) return false;
        const chunkParts = chunkLine[6 .. $].split(' ');
        if (chunkParts.length < 4) return false;
        int col, row, w, h, layer;
        try {
            col = chunkParts[0].to!int; row = chunkParts[1].to!int;
            w   = chunkParts[2].to!int; h   = chunkParts[3].to!int;
            layer = chunkParts.length >= 5 ? chunkParts[4].to!int : 0;
        } catch (Exception) { return false; }

        ChunkGeometry geometry;
        if (!parseLeafSection(lines, lineIdx, geometry)) return false;

        placedChunks   ~= MapChunk(col, row, w, h, layer);
        chunkGeometries ~= geometry;
    }
    return true;
}

private string saveMapDirectoryDialog()
{
    version (Windows) {
        const result = execute([
            "powershell",
            "-NoProfile",
            "-STA",
            "-Command",
            "Add-Type -AssemblyName System.Windows.Forms; " ~
            "$dialog = New-Object System.Windows.Forms.FolderBrowserDialog; " ~
            "$dialog.Description = 'Choose a folder to save .leaf chunk files'; " ~
            "$dialog.ShowNewFolderButton = $true; " ~
            "if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { Write-Output $dialog.SelectedPath }"
        ]);
        if (result.status != 0) return "";
        return result.output.strip().idup;
    } else version (linux) {
        const result = executeShell(
            "zenity --file-selection --directory --title='Choose Folder to Save Leaf Files' --filename=./ 2>/dev/null"
        );
        if (result.status != 0) return "";
        return result.output.strip().idup;
    } else {
        return "";
    }
}

private string saveMapLmFileDialog()
{
    version (Windows) {
        const result = execute([
            "powershell", "-NoProfile", "-STA", "-Command",
            "Add-Type -AssemblyName System.Windows.Forms; " ~
            "$dialog = New-Object System.Windows.Forms.SaveFileDialog; " ~
            "$dialog.Title = 'Save Leafway Map'; " ~
            "$dialog.DefaultExt = 'lm'; " ~
            "$dialog.Filter = 'Leafway Map (*.lm)|*.lm|All Files (*.*)|*.*'; " ~
            "if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { Write-Output $dialog.FileName }"
        ]);
        if (result.status != 0) return "";
        return result.output.strip().idup;
    } else version (linux) {
        const result = executeShell(
            "zenity --file-selection --save --confirm-overwrite " ~
            "--title='Save Leafway Map' --filename=./Untitled.lm " ~
            "'--file-filter=Leafway Map | *.lm' " ~
            "'--file-filter=All Files | *' 2>/dev/null"
        );
        if (result.status != 0) return "";
        return result.output.strip().idup;
    } else {
        return "";
    }
}

private string openMapFileDialog()
{
    version (Windows) {
        const result = execute([
            "powershell",
            "-NoProfile",
            "-STA",
            "-Command",
            "Add-Type -AssemblyName System.Windows.Forms; " ~
            "$dialog = New-Object System.Windows.Forms.OpenFileDialog; " ~
            "$dialog.Title = 'Open Map'; " ~
            "$dialog.InitialDirectory = (Get-Location).Path; " ~
            "$dialog.Filter = 'Leafway Map (*.lm)|*.lm|All Files (*.*)|*.*'; " ~
            "if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { Write-Output $dialog.FileName }"
        ]);

        if (result.status != 0) {
            return "";
        }

        return result.output.strip().idup;
    } else version (linux) {
        const result = executeShell(
            "zenity --file-selection --title='Open Map' --filename=./ " ~
            "'--file-filter=Leafway Map | *.lm' " ~
            "'--file-filter=All Files | *' 2>/dev/null"
        );

        if (result.status != 0) {
            return "";
        }

        return result.output.strip().idup;
    } else {
        return "";
    }
}

private ChunkGeometry dupGeometry(const ChunkGeometry g)
{
    ChunkGeometry result;
    result.points = g.points.dup;
    result.walls = g.walls.dup;
    result.entities = g.entities.dup;
    result.objects = g.objects.dup;
    result.faces.reserve(g.faces.length);
    foreach (f; g.faces) {
        result.faces ~= ChunkFace(f.pointIndices.dup, f.floorHeight, f.ceilingHeight, f.paletteIndex, f.autoWallFromHeightDifference, f.sameFloorAndCeiling);
    }
    return result;
}

struct MapSnapshot {
    MapChunk[] chunks;
    ChunkGeometry[] geometries;
}

private enum maxUndoDepth = 50;

private void pushMapUndo(ref MapSnapshot[] stack, MapChunk[] chunks, ChunkGeometry[] geoms)
{
    MapSnapshot snap;
    snap.chunks = chunks.dup;
    snap.geometries.reserve(geoms.length);
    foreach (g; geoms) snap.geometries ~= dupGeometry(g);
    stack ~= snap;
    if (stack.length > maxUndoDepth) stack = stack[$ - maxUndoDepth .. $];
}

private void pushChunkUndo(ref ChunkGeometry[] stack, ChunkGeometry geom)
{
    stack ~= dupGeometry(geom);
    if (stack.length > maxUndoDepth) stack = stack[$ - maxUndoDepth .. $];
}

// Draw text word-wrapped inside bounds, matching raygui label style.
private void drawWrappedLabel(Rectangle bounds, string text)
{
    enum int fontSize = 10;
    enum int lineH    = 14;
    const Color labelColor = Color(102, 102, 102, 255);
    const int maxW = cast(int)bounds.width;

    import std.string : split, toStringz;
    const words = text.split(' ');
    string curLine = "";
    int y = cast(int)bounds.y;
    const int bottomEdge = cast(int)(bounds.y + bounds.height);

    foreach (word; words) {
        const testLine = curLine.length > 0 ? curLine ~ " " ~ word : word;
        if (MeasureText(toStringz(testLine), fontSize) > maxW && curLine.length > 0) {
            DrawText(toStringz(curLine), cast(int)bounds.x, y, fontSize, labelColor);
            y += lineH;
            curLine = word;
            if (y + lineH > bottomEdge) break;
        } else {
            curLine = testLine;
        }
    }
    if (curLine.length > 0 && y < bottomEdge) {
        DrawText(toStringz(curLine), cast(int)bounds.x, y, fontSize, labelColor);
    }
}

int main()
{
    SetExitKey(KeyboardKey.KEY_NULL); // Disable default exit key so ESC never closes the window
    SetConfigFlags(ConfigFlags.FLAG_WINDOW_RESIZABLE | ConfigFlags.FLAG_VSYNC_HINT);
    InitWindow(1280, 720, "Leafway Editor - Prototype");
    SetWindowMinSize(960, 540);
    SetTargetFPS(60);

    InitAudioDevice();

    Texture2D waterTexture = LoadTexture("resources/image/water.png");
    Image ditherImage = LoadImage("resources/image/dither.png");
    const paletteCount = getPaletteCount(ditherImage);
    RenderTexture2D chunkPreviewTexture = LoadRenderTexture(chunkPreviewTextureWidth, chunkPreviewTextureHeight);
    SetTextureFilter(waterTexture, TextureFilter.TEXTURE_FILTER_BILINEAR);
    SetTextureWrap(waterTexture, TextureWrap.TEXTURE_WRAP_REPEAT);

    Music oceanMusic = LoadMusicStream("resources/audio/water_waves.mp3");
    SetMusicVolume(oceanMusic, 0.55f);
    PlayMusicStream(oceanMusic);

    Sound clickSound = LoadSound("resources/audio/click.wav");
    Sound placeSound = LoadSound("resources/audio/place.wav");
    Sound moveSound = LoadSound("resources/audio/move.wav");
    Sound deleteSound = LoadSound("resources/audio/delete.wav");
    Sound touchSound = LoadSound("resources/audio/touch.wav");
    Sound connectSound = LoadSound("resources/audio/connect.wav");
    Sound applySound = LoadSound("resources/audio/apply.wav");
    SetSoundVolume(clickSound, 0.55f);
    SetSoundVolume(placeSound, 0.55f);
    SetSoundVolume(moveSound, 0.55f);
    SetSoundVolume(deleteSound, 0.55f);
    SetSoundVolume(touchSound, 0.45f);
    SetSoundVolume(connectSound, 0.55f);
    SetSoundVolume(applySound, 0.55f);

    int selectedToolbarIndex = -1;
    Rectangle selectedToolbarButtonRect = Rectangle(0.0f, 0.0f, 0.0f, 0.0f);
    Vector2 waterOffset = Vector2.zero;
    string selectedMapPath = "No map selected";
    bool hasActiveMap = false;
    AppScreen appScreen = AppScreen.map;
    bool pendingOpenMapDialog = false;
    bool pendingSaveMapDialog = false;
    char[128] mapNameBuf = 0;
    mapNameBuf[0 .. "Untitled".length] = "Untitled";
    bool mapNameEditMode = false;
    bool showGrid = true;
    bool showInspector = true;
    bool showChunkBounds = false;
    MapChunk[] placedChunks;
    ChunkGeometry[] chunkGeometries;
    Camera2D mapCamera = Camera2D(Vector2.zero, Vector2.zero, 0.0f, 1.0f);
    Camera2D chunkEditorCamera = Camera2D(Vector2.zero, Vector2.zero, 0.0f, 2.0f);
    float chunkPreviewYaw = 0.75f;
    float chunkPreviewPitch = 0.55f;
    float chunkPreviewDistance = 220.0f;
    ChunkTool activeChunkTool = ChunkTool.draw;
    int selectedChunkIndex = -1;
    int editingChunkIndex = -1;
    bool isDraggingChunk = false;
    bool isPanningCanvas = false;
    GridCell chunkDragStart = GridCell(0, 0);
    GridCell dragCellOffset = GridCell(0, 0);
    MapChunk previewChunk = MapChunk(0, 0, 1, 1);
    MapChunk interactionStartChunk = MapChunk(0, 0, 1, 1);
    bool previewPlacementValid = true;
    int currentLayer = 0;
    MapSnapshot[] mapUndoStack;
    ChunkGeometry[] chunkUndoStack;
    int mapSnapMultiplier = 1;    // 1, 2, 4, 8 cells per snap unit
    int chunkEditorSnapSize = 8;  // geometry snap in px: 2, 4, 8, 16, 32
    string chunkToolMessage = "Draw mode: drag on the canvas to create a new chunk.";
    ChunkEditorTool chunkEditorTool = ChunkEditorTool.placePoint;
    int[] selectedPointIndices;
    int[] selectedFaceIndices;
    int[] selectedWallIndices;
    int[] selectedEntityIndices;
    int[] selectedObjectIndices;
    EntityType currentEntityType = EntityType.player;
    float currentEntityRotationY = 0.0f;
    bool isBoxSelecting = false;
    Vector2 boxSelectStartWorld = Vector2.zero;
    Vector2 boxSelectEndWorld = Vector2.zero;
    Vector2 boxSelectStartScreen = Vector2.zero;
    bool isDraggingEntity = false;
    Vector2 entityDragStart = Vector2.zero;
    ObjectType currentObjectType = ObjectType.crate;
    float currentObjectRotationY = 0.0f;
    float currentObjectHeight = 0.0f;
    bool isDraggingObject = false;
    Vector2 objectDragStart = Vector2.zero;
    float chunkInspectorScrollY = 0.0f;
    bool faceFloorEditMode = false;
    bool faceCeilingEditMode = false;
    int faceFloorInputValue = 0;
    int faceCeilingInputValue = 16;
    bool batchFaceFloorEditMode = false;
    bool batchFaceCeilingEditMode = false;
    int batchFaceFloorValue = 0;
    int batchFaceCeilingValue = 16;
    string chunkEditorMessage = "Point mode: click to place snapped points inside the chunk bounds.";
    bool shouldExit = false;
    bool showAboutDialog = false;
    bool showShortcutsDialog = false;

    while (!shouldExit) {
        const frameTime = GetFrameTime();
        const canvasRect = getMapCanvasRect(showInspector);
        const inspectorRect = getInspectorRect();
        const chunkPreviewPanelRect = getChunkPreviewPanelRect(canvasRect);
        const chunkPreviewContentRect = getChunkPreviewContentRect(chunkPreviewPanelRect);
        const chunkPreviewBounds = (appScreen == AppScreen.chunkEditor && editingChunkIndex >= 0 && editingChunkIndex < cast(int)placedChunks.length)
            ? getChunkPreviewBounds(
                [placedChunks[editingChunkIndex]],
                editingChunkIndex < cast(int)chunkGeometries.length ? [chunkGeometries[editingChunkIndex]] : cast(ChunkGeometry[])[])
            : getChunkPreviewBounds(placedChunks, chunkGeometries);
        const chunkPreviewMaxDistance = getChunkPreviewMaxDistance(chunkPreviewBounds);
        const wantsWindowClose = WindowShouldClose();
        if (wantsWindowClose && !IsKeyPressed(KeyboardKey.KEY_ESCAPE)) {
            break;
        }
        if (activeChunkTool == ChunkTool.resize) {
            activeChunkTool = ChunkTool.draw;
            chunkToolMessage = "Resize is disabled to preserve chunk geometry.";
        }
        mapCamera.offset = Vector2(canvasRect.x + canvasRect.width * 0.5f, canvasRect.y + canvasRect.height * 0.5f);
        const gridLayout = getGridLayout(canvasRect, mapCamera);
        const mousePosition = GetMousePosition();

        if (pendingOpenMapDialog) {
            pendingOpenMapDialog = false;

            const chosenMap = openMapFileDialog();
            if (chosenMap.length > 0) {
                hasActiveMap = true;
                appScreen = AppScreen.map;
                placedChunks.length = 0;
                chunkGeometries.length = 0;
                selectedChunkIndex = -1;
                editingChunkIndex = -1;
                if (chosenMap.endsWith(".lm")) {
                    string loadedName;
                    const loadedContent = cast(string)std.file.read(chosenMap);
                    if (loadMapFromLm(loadedContent, placedChunks, chunkGeometries, loadedName)) {
                        selectedMapPath = chosenMap;
                        mapNameBuf[] = 0;
                        const nameLen = loadedName.length < mapNameBuf.length - 1 ? loadedName.length : mapNameBuf.length - 1;
                        mapNameBuf[0 .. nameLen] = loadedName[0 .. nameLen];
                        chunkToolMessage = format("Loaded %d chunk(s) from: %s", placedChunks.length, chosenMap);
                    } else {
                        chunkToolMessage = "Failed to load .lm file.";
                        hasActiveMap = false;
                    }
                } else {
                    selectedMapPath = chosenMap;
                }
                PlaySound(connectSound);
            }
        }

        if (pendingSaveMapDialog) {
            pendingSaveMapDialog = false;
            if (placedChunks.length == 0) {
                chunkToolMessage = "No chunks to save.";
            } else {
                const savePath = saveMapLmFileDialog();
                if (savePath.length > 0) {
                    // Derive map name from the chosen filename (strip dir + .lm)
                    string derivedName = baseName(savePath);
                    if (derivedName.endsWith(".lm"))
                        derivedName = derivedName[0 .. $ - 3];
                    mapNameBuf[] = 0;
                    const nameLen = derivedName.length < mapNameBuf.length - 1 ? derivedName.length : mapNameBuf.length - 1;
                    mapNameBuf[0 .. nameLen] = derivedName[0 .. nameLen];

                    const lmContent = serializeMapToLm(placedChunks, chunkGeometries, derivedName);
                    std.file.write(savePath, lmContent);
                    chunkToolMessage = format("Saved map to: %s", savePath);
                    PlaySound(connectSound);
                }
            }
        }

        if (hasActiveMap && selectedToolbarIndex < 0 && appScreen == AppScreen.map) {
            const mouseInsideCanvas = CheckCollisionPointRec(mousePosition, canvasRect);
            const wheelMove = mouseInsideCanvas ? GetMouseWheelMove() : 0.0f;
            const ctrlDown = IsKeyDown(KeyboardKey.KEY_LEFT_CONTROL) || IsKeyDown(KeyboardKey.KEY_RIGHT_CONTROL);

            if (ctrlDown && IsKeyPressed(KeyboardKey.KEY_Z) && mapUndoStack.length > 0) {
                const snap = mapUndoStack[$ - 1];
                placedChunks = snap.chunks.dup;
                chunkGeometries.length = 0;
                foreach (g; snap.geometries) chunkGeometries ~= dupGeometry(g);
                mapUndoStack = mapUndoStack[0 .. $ - 1];
                if (selectedChunkIndex >= cast(int)placedChunks.length) selectedChunkIndex = -1;
                chunkToolMessage = to!string(TextFormat("Undo: %d step(s) remaining.", cast(int)mapUndoStack.length));
                PlaySound(clickSound);
            }

            if (!isDraggingChunk) {
                if (IsKeyPressed(KeyboardKey.KEY_D)) {
                    setMapChunkTool(activeChunkTool, ChunkTool.draw, chunkToolMessage, clickSound);
                } else if (IsKeyPressed(KeyboardKey.KEY_M)) {
                    setMapChunkTool(activeChunkTool, ChunkTool.move, chunkToolMessage, clickSound);
                } else if (IsKeyPressed(KeyboardKey.KEY_DELETE) || IsKeyPressed(KeyboardKey.KEY_BACKSPACE)) {
                    setMapChunkTool(activeChunkTool, ChunkTool.deleteChunk, chunkToolMessage, clickSound);
                } else if (IsKeyPressed(KeyboardKey.KEY_E)) {
                    setMapChunkTool(activeChunkTool, ChunkTool.edit, chunkToolMessage, clickSound);
                } else if (IsKeyPressed(KeyboardKey.KEY_ESCAPE) && selectedChunkIndex >= 0) {
                    selectedChunkIndex = -1;
                    chunkToolMessage = "Chunk selection cleared.";
                    PlaySound(touchSound);
                }
            }

            if (wheelMove != 0.0f) {
                mapCamera.zoom += wheelMove * 0.125f;
                if (mapCamera.zoom < 0.5f) mapCamera.zoom = 0.5f;
                if (mapCamera.zoom > 4.0f) mapCamera.zoom = 4.0f;
            }

            if (IsMouseButtonPressed(MouseButton.MOUSE_BUTTON_MIDDLE) && mouseInsideCanvas) {
                isPanningCanvas = true;
            }

            if (isPanningCanvas) {
                if (IsMouseButtonDown(MouseButton.MOUSE_BUTTON_MIDDLE)) {
                    const mouseDelta = GetMouseDelta();
                    mapCamera.target.x -= mouseDelta.x / mapCamera.zoom;
                    mapCamera.target.y -= mouseDelta.y / mapCamera.zoom;
                } else {
                    isPanningCanvas = false;
                }
            }

            if (IsMouseButtonPressed(MouseButton.MOUSE_BUTTON_LEFT) && mouseInsideCanvas && !isPanningCanvas) {
                const clickedCell = getGridCellAtPoint(mousePosition, gridLayout);
                const clickedChunkIndex = findChunkAtCell(placedChunks, clickedCell);

                final switch (activeChunkTool) {
                case ChunkTool.draw:
                    isDraggingChunk = true;
                    chunkDragStart = clickedCell;
                    previewChunk = makeChunkFromCells(chunkDragStart, chunkDragStart);
                    previewChunk.layer = currentLayer;
                    previewPlacementValid = isChunkPlacementValid(previewChunk, placedChunks);
                    break;
                case ChunkTool.move:
                    if (clickedChunkIndex >= 0) {
                        if (placedChunks[clickedChunkIndex].layer != currentLayer) {
                            chunkToolMessage = to!string(TextFormat("Chunk is on layer %d. Switch to that layer to move it.", placedChunks[clickedChunkIndex].layer));
                            PlaySound(touchSound);
                        } else {
                            selectedChunkIndex = clickedChunkIndex;
                            interactionStartChunk = placedChunks[selectedChunkIndex];
                            dragCellOffset = GridCell(clickedCell.column - interactionStartChunk.column, clickedCell.row - interactionStartChunk.row);
                            previewChunk = interactionStartChunk;
                            previewPlacementValid = true;
                            isDraggingChunk = true;
                        }
                    } else {
                        PlaySound(touchSound);
                    }
                    break;
                case ChunkTool.resize:
                    chunkToolMessage = "Resize is disabled to preserve chunk geometry.";
                    PlaySound(touchSound);
                    break;
                case ChunkTool.deleteChunk:
                    if (clickedChunkIndex >= 0) {
                        if (placedChunks[clickedChunkIndex].layer != currentLayer) {
                            chunkToolMessage = to!string(TextFormat("Chunk is on layer %d. Switch to that layer to delete it.", placedChunks[clickedChunkIndex].layer));
                            PlaySound(touchSound);
                        } else {
                            pushMapUndo(mapUndoStack, placedChunks, chunkGeometries);
                            placedChunks = placedChunks[0 .. clickedChunkIndex] ~ placedChunks[clickedChunkIndex + 1 .. $];
                            chunkGeometries = chunkGeometries[0 .. clickedChunkIndex] ~ chunkGeometries[clickedChunkIndex + 1 .. $];
                            if (selectedChunkIndex == clickedChunkIndex) {
                                selectedChunkIndex = -1;
                            } else if (selectedChunkIndex > clickedChunkIndex) {
                                selectedChunkIndex--;
                            }
                            chunkToolMessage = "Chunk deleted.";
                            PlaySound(deleteSound);
                        }
                    } else {
                        PlaySound(touchSound);
                    }
                    break;
                case ChunkTool.edit:
                    if (clickedChunkIndex >= 0) {
                        if (placedChunks[clickedChunkIndex].layer != currentLayer) {
                            chunkToolMessage = to!string(TextFormat("Chunk is on layer %d. Switch to that layer to edit it.", placedChunks[clickedChunkIndex].layer));
                            PlaySound(touchSound);
                        } else {
                            selectedChunkIndex = clickedChunkIndex;
                            editingChunkIndex = clickedChunkIndex;
                            appScreen = AppScreen.chunkEditor;
                            selectedPointIndices.length = 0;
                            selectedFaceIndices.length = 0;
                            selectedWallIndices.length = 0;
                            selectedEntityIndices.length = 0;
                            isBoxSelecting = false;
                            chunkEditorTool = ChunkEditorTool.placePoint;
                            chunkEditorMessage = to!string(TextFormat("Editing chunk %d. Place or select points to build faces.", clickedChunkIndex + 1));
                            const editChunk = placedChunks[editingChunkIndex];
                            chunkEditorCamera.target = Vector2(editChunk.width * mapGridCellSize * 0.5f, editChunk.height * mapGridCellSize * 0.5f);
                            chunkEditorCamera.zoom = 2.0f;
                            chunkPreviewYaw = 0.75f;
                            chunkPreviewPitch = 0.55f;
                            chunkPreviewDistance = getChunkPreviewDefaultDistance(chunkPreviewBounds);
                            chunkUndoStack.length = 0;
                            PlaySound(connectSound);
                        }
                    } else {
                        selectedChunkIndex = -1;
                        PlaySound(touchSound);
                    }
                    break;
                }
            }

            if (isDraggingChunk) {
                const currentCell = getGridCellAtPoint(mousePosition, gridLayout);

                final switch (activeChunkTool) {
                case ChunkTool.draw:
                    previewChunk = makeChunkFromCells(chunkDragStart, currentCell);
                    previewChunk.layer = currentLayer;
                    previewPlacementValid = isChunkPlacementValid(previewChunk, placedChunks);
                    break;
                case ChunkTool.move:
                    previewChunk = MapChunk(
                        currentCell.column - dragCellOffset.column,
                        currentCell.row - dragCellOffset.row,
                        interactionStartChunk.width,
                        interactionStartChunk.height
                    );
                    previewPlacementValid = isChunkPlacementValid(previewChunk, placedChunks, selectedChunkIndex);
                    break;
                case ChunkTool.resize:
                    previewPlacementValid = false;
                    break;
                case ChunkTool.deleteChunk:
                    previewPlacementValid = false;
                    break;
                case ChunkTool.edit:
                    previewPlacementValid = false;
                    break;
                }

                if (IsMouseButtonReleased(MouseButton.MOUSE_BUTTON_LEFT)) {
                    final switch (activeChunkTool) {
                    case ChunkTool.draw:
                        if (previewPlacementValid) {
                            pushMapUndo(mapUndoStack, placedChunks, chunkGeometries);
                            placedChunks ~= previewChunk;
                            chunkGeometries ~= ChunkGeometry.init;
                            selectedChunkIndex = cast(int)placedChunks.length - 1;
                            chunkToolMessage = to!string(TextFormat("Chunk %d created on layer %d.", selectedChunkIndex + 1, currentLayer));
                            PlaySound(placeSound);
                        } else {
                            chunkToolMessage = "Chunks cannot overlap on the same layer.";
                            PlaySound(touchSound);
                        }
                        break;
                    case ChunkTool.move:
                        if (selectedChunkIndex >= 0 && previewPlacementValid) {
                            pushMapUndo(mapUndoStack, placedChunks, chunkGeometries);
                            placedChunks[selectedChunkIndex] = previewChunk;
                            chunkToolMessage = "Chunk moved.";
                            PlaySound(moveSound);
                        } else {
                            chunkToolMessage = "Move blocked by another chunk.";
                            PlaySound(touchSound);
                        }
                        break;
                    case ChunkTool.resize:
                        chunkToolMessage = "Resize is disabled to preserve chunk geometry.";
                        PlaySound(touchSound);
                        break;
                    case ChunkTool.deleteChunk:
                        break;
                    case ChunkTool.edit:
                        break;
                    }

                    isDraggingChunk = false;
                }
            }
        } else if (hasActiveMap && selectedToolbarIndex < 0 && appScreen == AppScreen.chunkEditor && editingChunkIndex >= 0 && editingChunkIndex < cast(int)placedChunks.length) {
            chunkEditorCamera.offset = Vector2(canvasRect.x + canvasRect.width * 0.5f, canvasRect.y + canvasRect.height * 0.5f);
            const chunkEditorLayout = getGridLayout(canvasRect, chunkEditorCamera);
            const mouseInsidePreview = CheckCollisionPointRec(mousePosition, chunkPreviewContentRect);
            const mouseInsideCanvas = CheckCollisionPointRec(mousePosition, canvasRect) && !mouseInsidePreview;
            const wheelMove = mouseInsideCanvas ? GetMouseWheelMove() : 0.0f;
            const controlDown = IsKeyDown(KeyboardKey.KEY_LEFT_CONTROL) || IsKeyDown(KeyboardKey.KEY_RIGHT_CONTROL);
            const hasSelection = selectedPointIndices.length > 0 || selectedFaceIndices.length > 0 || selectedWallIndices.length > 0 || selectedEntityIndices.length > 0 || selectedObjectIndices.length > 0;
            const keyboardShortcutsEnabled = !faceFloorEditMode && !faceCeilingEditMode && !batchFaceFloorEditMode && !batchFaceCeilingEditMode;

            if (keyboardShortcutsEnabled) {
                if (controlDown && IsKeyPressed(KeyboardKey.KEY_Z) && chunkUndoStack.length > 0) {
                    chunkGeometries[editingChunkIndex] = dupGeometry(chunkUndoStack[$ - 1]);
                    chunkUndoStack = chunkUndoStack[0 .. $ - 1];
                    clearChunkEditorSelection(selectedPointIndices, selectedFaceIndices, selectedWallIndices, selectedEntityIndices, selectedObjectIndices);
                    chunkEditorMessage = to!string(TextFormat("Undo: %d step(s) remaining.", cast(int)chunkUndoStack.length));
                    PlaySound(clickSound);
                } else if (IsKeyPressed(KeyboardKey.KEY_ONE)) {
                    setChunkEditorTool(chunkEditorTool, ChunkEditorTool.placePoint, chunkEditorMessage, clickSound);
                } else if (IsKeyPressed(KeyboardKey.KEY_TWO)) {
                    setChunkEditorTool(chunkEditorTool, ChunkEditorTool.selectPoint, chunkEditorMessage, clickSound);
                } else if (IsKeyPressed(KeyboardKey.KEY_THREE)) {
                    setChunkEditorTool(chunkEditorTool, ChunkEditorTool.placeEntity, chunkEditorMessage, clickSound);
                } else if (IsKeyPressed(KeyboardKey.KEY_FOUR)) {
                    setChunkEditorTool(chunkEditorTool, ChunkEditorTool.placeObject, chunkEditorMessage, clickSound);
                } else if (IsKeyPressed(KeyboardKey.KEY_TAB)) {
                    ChunkEditorTool nextTool;
                    if (chunkEditorTool == ChunkEditorTool.placePoint) {
                        nextTool = ChunkEditorTool.selectPoint;
                    } else if (chunkEditorTool == ChunkEditorTool.selectPoint) {
                        nextTool = ChunkEditorTool.placeEntity;
                    } else if (chunkEditorTool == ChunkEditorTool.placeEntity) {
                        nextTool = ChunkEditorTool.placeObject;
                    } else {
                        nextTool = ChunkEditorTool.placePoint;
                    }
                    setChunkEditorTool(chunkEditorTool, nextTool, chunkEditorMessage, clickSound);
                } else if (IsKeyPressed(KeyboardKey.KEY_F)) {
                    pushChunkUndo(chunkUndoStack, chunkGeometries[editingChunkIndex]);
                    createSelectedFace(
                        chunkGeometries[editingChunkIndex],
                        selectedPointIndices,
                        selectedFaceIndices,
                        chunkEditorMessage,
                        connectSound,
                        touchSound
                    );
                } else if (IsKeyPressed(KeyboardKey.KEY_W)) {
                    pushChunkUndo(chunkUndoStack, chunkGeometries[editingChunkIndex]);
                    createSelectedWall(
                        chunkGeometries[editingChunkIndex],
                        selectedPointIndices,
                        selectedFaceIndices,
                        selectedWallIndices,
                        chunkEditorMessage,
                        connectSound,
                        touchSound
                    );
                } else if (IsKeyPressed(KeyboardKey.KEY_DELETE) || IsKeyPressed(KeyboardKey.KEY_BACKSPACE)) {
                    pushChunkUndo(chunkUndoStack, chunkGeometries[editingChunkIndex]);
                    deleteCurrentChunkEditorSelection(
                        chunkGeometries[editingChunkIndex],
                        selectedPointIndices,
                        selectedFaceIndices,
                        selectedWallIndices,
                        selectedEntityIndices,
                        selectedObjectIndices,
                        chunkEditorMessage,
                        deleteSound,
                        touchSound
                    );
                } else if (controlDown && IsKeyPressed(KeyboardKey.KEY_A)) {
                    selectAllChunkPoints(
                        chunkGeometries[editingChunkIndex],
                        selectedPointIndices,
                        selectedFaceIndices,
                        selectedWallIndices,
                        selectedEntityIndices,
                        selectedObjectIndices,
                        chunkEditorMessage,
                        clickSound,
                        touchSound
                    );
                } else if (IsKeyPressed(KeyboardKey.KEY_ESCAPE)) {
                    if (hasSelection || isBoxSelecting) {
                        clearChunkEditorSelection(selectedPointIndices, selectedFaceIndices, selectedWallIndices, selectedEntityIndices, selectedObjectIndices);
                        isBoxSelecting = false;
                        chunkEditorMessage = "Selection cleared.";
                        PlaySound(touchSound);
                    } else {
                        returnToMapFromChunkEditor(
                            appScreen,
                            selectedChunkIndex,
                            editingChunkIndex,
                            selectedPointIndices,
                            selectedFaceIndices,
                            selectedWallIndices,
                            selectedEntityIndices,
                            selectedObjectIndices,
                            isBoxSelecting,
                            chunkEditorMessage,
                            chunkToolMessage,
                            clickSound
                        );
                    }
                }
            }

            if (wheelMove != 0.0f) {
                chunkEditorCamera.zoom += wheelMove * 0.125f;
                if (chunkEditorCamera.zoom < 0.5f) chunkEditorCamera.zoom = 0.5f;
                if (chunkEditorCamera.zoom > 6.0f) chunkEditorCamera.zoom = 6.0f;
            }

            if (mouseInsidePreview) {
                const previewWheel = GetMouseWheelMove();
                if (previewWheel != 0.0f) {
                    chunkPreviewDistance -= previewWheel * 16.0f;
                    if (chunkPreviewDistance < 48.0f) chunkPreviewDistance = 48.0f;
                    if (chunkPreviewDistance > chunkPreviewMaxDistance) chunkPreviewDistance = chunkPreviewMaxDistance;
                }

                if (IsMouseButtonDown(MOUSE_RIGHT_BUTTON)) {
                    const mouseDelta = GetMouseDelta();
                    chunkPreviewYaw -= mouseDelta.x * 0.01f;
                    chunkPreviewPitch -= mouseDelta.y * 0.01f;
                    if (chunkPreviewPitch < 0.20f) chunkPreviewPitch = 0.20f;
                    if (chunkPreviewPitch > 1.35f) chunkPreviewPitch = 1.35f;
                }

                if (IsMouseButtonPressed(MouseButton.MOUSE_BUTTON_LEFT)) {
                    const pickCamera = getChunkPreviewCamera(chunkPreviewBounds, chunkPreviewYaw, chunkPreviewPitch, chunkPreviewDistance);
                    const texMouseX = mousePosition.x - chunkPreviewContentRect.x;
                    const texMouseY = mousePosition.y - chunkPreviewContentRect.y;
                    const pickRay = getPreviewRay(Vector2(texMouseX, texMouseY), pickCamera, chunkPreviewTextureWidth, chunkPreviewTextureHeight);
                    const editChunkOffset = getChunkWorldOffset(placedChunks[editingChunkIndex]);
                    float wallT = float.infinity;
                    float autoT = float.infinity;
                    const pickedWallIndex = findExplicitWallHitByRay(chunkGeometries[editingChunkIndex], pickRay, editChunkOffset, wallT);
                    const pickedAutoFaceIndex = findAutoWallFaceHitByRay(chunkGeometries[editingChunkIndex], pickRay, editChunkOffset, autoT);
                    if (pickedWallIndex >= 0 && wallT <= autoT) {
                        selectedWallIndices = [pickedWallIndex];
                        selectedFaceIndices.length = 0;
                        selectedPointIndices.length = 0;
                        selectedEntityIndices.length = 0;
                        selectedObjectIndices.length = 0;
                        chunkEditorMessage = to!string(TextFormat("Selected wall %d from 3D view.", pickedWallIndex + 1));
                        PlaySound(applySound);
                    } else if (pickedAutoFaceIndex >= 0) {
                        selectedFaceIndices = [pickedAutoFaceIndex];
                        selectedWallIndices.length = 0;
                        selectedPointIndices.length = 0;
                        selectedEntityIndices.length = 0;
                        selectedObjectIndices.length = 0;
                        chunkEditorMessage = to!string(TextFormat("Auto-wall: selected parent face %d.", pickedAutoFaceIndex + 1));
                        PlaySound(clickSound);
                    }
                }
            }

            if (IsMouseButtonPressed(MouseButton.MOUSE_BUTTON_MIDDLE) && mouseInsideCanvas) {
                isPanningCanvas = true;
            }

            if (isPanningCanvas) {
                if (IsMouseButtonDown(MouseButton.MOUSE_BUTTON_MIDDLE)) {
                    const mouseDelta = GetMouseDelta();
                    chunkEditorCamera.target.x -= mouseDelta.x / chunkEditorCamera.zoom;
                    chunkEditorCamera.target.y -= mouseDelta.y / chunkEditorCamera.zoom;
                } else {
                    isPanningCanvas = false;
                }
            }

            if (IsMouseButtonDown(MouseButton.MOUSE_BUTTON_LEFT) && isDraggingEntity && mouseInsideCanvas) {
                const worldPosition = GetScreenToWorld2D(mousePosition, chunkEditorLayout.camera);
                const dragOffset = Vector2(worldPosition.x - entityDragStart.x, worldPosition.y - entityDragStart.y);
                
                foreach (entityIndex; selectedEntityIndices) {
                    if (entityIndex >= 0 && entityIndex < cast(int)chunkGeometries[editingChunkIndex].entities.length) {
                        auto entity = &chunkGeometries[editingChunkIndex].entities[entityIndex];
                        entity.x += dragOffset.x;
                        entity.z += dragOffset.y;
                    }
                }
                
                entityDragStart = worldPosition;
            } else if (IsMouseButtonReleased(MouseButton.MOUSE_BUTTON_LEFT) && isDraggingEntity) {
                isDraggingEntity = false;
                if (selectedEntityIndices.length > 0) {
                    chunkEditorMessage = to!string(TextFormat("Moved %d entity/entities.", cast(int)selectedEntityIndices.length));
                    PlaySound(clickSound);
                }
            } else if (IsMouseButtonDown(MouseButton.MOUSE_BUTTON_LEFT) && isDraggingObject && mouseInsideCanvas) {
                const worldPosition = GetScreenToWorld2D(mousePosition, chunkEditorLayout.camera);
                const dragOffset = Vector2(worldPosition.x - objectDragStart.x, worldPosition.y - objectDragStart.y);
                
                foreach (objectIndex; selectedObjectIndices) {
                    if (objectIndex >= 0 && objectIndex < cast(int)chunkGeometries[editingChunkIndex].objects.length) {
                        auto obj = &chunkGeometries[editingChunkIndex].objects[objectIndex];
                        obj.x += dragOffset.x;
                        obj.z += dragOffset.y;
                    }
                }
                
                objectDragStart = worldPosition;
            } else if (IsMouseButtonReleased(MouseButton.MOUSE_BUTTON_LEFT) && isDraggingObject) {
                isDraggingObject = false;
                if (selectedObjectIndices.length > 0) {
                    chunkEditorMessage = to!string(TextFormat("Moved %d object(s).", cast(int)selectedObjectIndices.length));
                    PlaySound(clickSound);
                }
            } else if (IsMouseButtonPressed(MouseButton.MOUSE_BUTTON_LEFT) && mouseInsideCanvas && !isPanningCanvas) {
                const worldPosition = GetScreenToWorld2D(mousePosition, chunkEditorLayout.camera);
                const editChunk = placedChunks[editingChunkIndex];

                if (chunkEditorTool == ChunkEditorTool.placePoint) {
                    const point = getChunkPointAtWorldPosition(worldPosition, editChunk);
                    if (!chunkGeometryHasPoint(chunkGeometries[editingChunkIndex], point)) {
                        pushChunkUndo(chunkUndoStack, chunkGeometries[editingChunkIndex]);
                        chunkGeometries[editingChunkIndex].points ~= point;
                        selectedPointIndices = [cast(int)chunkGeometries[editingChunkIndex].points.length - 1];
                        selectedFaceIndices.length = 0;
                        selectedWallIndices.length = 0;
                        selectedEntityIndices.length = 0;
                        chunkEditorMessage = to!string(TextFormat("Placed point at %d, %d.", point.x, point.z));
                        PlaySound(placeSound);
                    } else {
                        chunkEditorMessage = "A point already exists at that snapped location.";
                        PlaySound(touchSound);
                    }
                } else if (chunkEditorTool == ChunkEditorTool.placeEntity) {
                    const newEntity = ChunkEntity(
                        worldPosition.x, worldPosition.y,
                        0.0f, currentEntityRotationY, 0.0f,
                        1.0f, 1.0f, 1.0f,
                        currentEntityType
                    );
                    pushChunkUndo(chunkUndoStack, chunkGeometries[editingChunkIndex]);
                    chunkGeometries[editingChunkIndex].entities ~= newEntity;
                    selectedEntityIndices = [cast(int)chunkGeometries[editingChunkIndex].entities.length - 1];
                    selectedPointIndices.length = 0;
                    selectedFaceIndices.length = 0;
                    selectedWallIndices.length = 0;
                    selectedObjectIndices.length = 0;
                    chunkEditorMessage = to!string(TextFormat("Placed entity: %s at %.1f, %.1f.", getEntityTypeName(currentEntityType).ptr, worldPosition.x, worldPosition.y));
                    PlaySound(placeSound);
                } else if (chunkEditorTool == ChunkEditorTool.placeObject) {
                    const newObject = ChunkObject(
                        worldPosition.x, currentObjectHeight, worldPosition.y,
                        0.0f, currentObjectRotationY, 0.0f,
                        1.0f, 1.0f, 1.0f,
                        currentObjectType
                    );
                    pushChunkUndo(chunkUndoStack, chunkGeometries[editingChunkIndex]);
                    chunkGeometries[editingChunkIndex].objects ~= newObject;
                    selectedObjectIndices = [cast(int)chunkGeometries[editingChunkIndex].objects.length - 1];
                    selectedPointIndices.length = 0;
                    selectedFaceIndices.length = 0;
                    selectedWallIndices.length = 0;
                    selectedEntityIndices.length = 0;
                    chunkEditorMessage = to!string(TextFormat("Placed object: %s at %.1f, %.1f, %.1f.", getObjectTypeName(currentObjectType).ptr, worldPosition.x, currentObjectHeight, worldPosition.y));
                    PlaySound(placeSound);
                } else {
                    const objectIndex = findObjectAtWorldPosition(chunkGeometries[editingChunkIndex], worldPosition, 12.0f / chunkEditorCamera.zoom);
                    if (objectIndex >= 0) {
                        if (selectedObjectIndicesContain(selectedObjectIndices, objectIndex)) {
                            // Clicked on already selected object - start dragging
                            isDraggingObject = true;
                            objectDragStart = worldPosition;
                        } else {
                            selectedObjectIndices ~= objectIndex;
                            selectedPointIndices.length = 0;
                            selectedFaceIndices.length = 0;
                            selectedWallIndices.length = 0;
                            selectedEntityIndices.length = 0;
                            chunkEditorMessage = to!string(TextFormat("Selected %d object(s).", cast(int)selectedObjectIndices.length));
                            PlaySound(clickSound);
                        }
                    } else {
                        const entityIndex = findEntityAtWorldPosition(chunkGeometries[editingChunkIndex], worldPosition, 12.0f / chunkEditorCamera.zoom);
                        if (entityIndex >= 0) {
                            if (selectedEntityIndicesContain(selectedEntityIndices, entityIndex)) {
                                // Clicked on already selected entity - start dragging
                                isDraggingEntity = true;
                                entityDragStart = worldPosition;
                            } else {
                                selectedEntityIndices ~= entityIndex;
                                selectedPointIndices.length = 0;
                                selectedFaceIndices.length = 0;
                                selectedWallIndices.length = 0;
                                selectedObjectIndices.length = 0;
                                chunkEditorMessage = to!string(TextFormat("Selected %d entity/entities.", cast(int)selectedEntityIndices.length));
                                PlaySound(clickSound);
                            }
                        } else {
                        const pointIndex = findPointAtWorldPosition(chunkGeometries[editingChunkIndex], worldPosition, 9.0f / chunkEditorCamera.zoom);
                        if (pointIndex >= 0) {
                            if (selectedPointIndicesContain(selectedPointIndices, pointIndex)) {
                                selectedPointIndices = selectedPointIndices.filter!(index => index != pointIndex).array;
                            } else {
                                selectedPointIndices ~= pointIndex;
                            }
                            selectedFaceIndices.length = 0;
                            selectedWallIndices.length = 0;
                            selectedEntityIndices.length = 0;
                            chunkEditorMessage = to!string(TextFormat("Selected %d point(s).", cast(int)selectedPointIndices.length));
                            PlaySound(clickSound);
                        } else {
                            const wallIndex = findWallAtWorldPosition(chunkGeometries[editingChunkIndex], worldPosition, 7.0f / chunkEditorCamera.zoom);
                            if (wallIndex >= 0) {
                                if (selectedWallIndicesContain(selectedWallIndices, wallIndex)) {
                                    selectedWallIndices = selectedWallIndices.filter!(index => index != wallIndex).array;
                                } else {
                                    selectedWallIndices ~= wallIndex;
                                }
                                selectedPointIndices.length = 0;
                                selectedFaceIndices.length = 0;
                                selectedEntityIndices.length = 0;
                                selectedObjectIndices.length = 0;
                                chunkEditorMessage = to!string(TextFormat("Selected %d wall(s).", cast(int)selectedWallIndices.length));
                                PlaySound(applySound);
                            } else {
                                const faceIndex = findFaceAtWorldPosition(chunkGeometries[editingChunkIndex], worldPosition, 14.0f / chunkEditorCamera.zoom);
                                if (faceIndex >= 0) {
                                    if (selectedFaceIndicesContain(selectedFaceIndices, faceIndex)) {
                                        selectedFaceIndices = selectedFaceIndices.filter!(index => index != faceIndex).array;
                                    } else {
                                        selectedFaceIndices ~= faceIndex;
                                    }
                                    selectedPointIndices.length = 0;
                                    selectedWallIndices.length = 0;
                                    selectedEntityIndices.length = 0;
                                    chunkEditorMessage = to!string(TextFormat("Selected %d face(s).", cast(int)selectedFaceIndices.length));
                                    PlaySound(clickSound);
                                } else {
                                    isBoxSelecting = true;
                                    boxSelectStartWorld = worldPosition;
                                    boxSelectEndWorld = worldPosition;
                                    boxSelectStartScreen = mousePosition;
                                }
                            }
                        }
                    }
                        }
                    }
                }

            if (isBoxSelecting) {
                if (IsMouseButtonDown(MouseButton.MOUSE_BUTTON_LEFT)) {
                    boxSelectEndWorld = GetScreenToWorld2D(mousePosition, chunkEditorLayout.camera);
                } else {
                    const dragDistanceX = mousePosition.x - boxSelectStartScreen.x;
                    const dragDistanceY = mousePosition.y - boxSelectStartScreen.y;
                    const boxSelectRect = getNormalizedRectangleFromPoints(boxSelectStartWorld, boxSelectEndWorld);

                    const dragDistanceExceeded = dragDistanceX <= -4.0f || dragDistanceX >= 4.0f
                        || dragDistanceY <= -4.0f || dragDistanceY >= 4.0f;

                    if (dragDistanceExceeded) {
                        int[] boxSelectedPointIndices;
                        foreach (pointIndex, point; chunkGeometries[editingChunkIndex].points) {
                            if (CheckCollisionPointRec(getChunkPointPosition(point), boxSelectRect)) {
                                boxSelectedPointIndices ~= cast(int)pointIndex;
                            }
                        }

                        selectedPointIndices = boxSelectedPointIndices;
                        selectedFaceIndices.length = 0;
                        selectedWallIndices.length = 0;
                        chunkEditorMessage = boxSelectedPointIndices.length > 0
                            ? to!string(TextFormat("Box selected %d point(s).", cast(int)boxSelectedPointIndices.length))
                            : "No points found in selection box.";
                        PlaySound(boxSelectedPointIndices.length > 0 ? clickSound : touchSound);
                    } else {
                        selectedPointIndices.length = 0;
                        selectedFaceIndices.length = 0;
                        selectedWallIndices.length = 0;
                        selectedEntityIndices.length = 0;
                        selectedObjectIndices.length = 0;
                        chunkEditorMessage = "Selection cleared.";
                        PlaySound(touchSound);
                    }

                    isBoxSelecting = false;
                }
            }
        } else {
            isDraggingChunk = false;
            isPanningCanvas = false;
            isBoxSelecting = false;
            isDraggingEntity = false;
        }

        waterOffset.x = cast(float)fmod(waterOffset.x + backgroundSpeed * frameTime, cast(double)waterTexture.width);
        waterOffset.y = cast(float)fmod(waterOffset.y + backgroundSpeed * frameTime, cast(double)waterTexture.height);

        UpdateMusicStream(oceanMusic);
        if (!IsMusicStreamPlaying(oceanMusic)) {
            PlayMusicStream(oceanMusic);
        }

        BeginDrawing();
        scope(exit) EndDrawing();

        ClearBackground(Colors.BLACK);
        drawPanningBackground(waterTexture, waterOffset);

        DrawRectangle(0, 0, GetScreenWidth(), cast(int)toolbarHeight, Fade(Colors.RAYWHITE, 0.88f));
        DrawLine(0, cast(int)toolbarHeight, GetScreenWidth(), cast(int)toolbarHeight, Fade(Colors.DARKGRAY, 0.5f));

        const visibleToolbarIndices = getVisibleToolbarIndices(hasActiveMap, appScreen);
        bool selectedToolbarStillVisible = false;
        foreach (toolbarIndex; visibleToolbarIndices) {
            if (toolbarIndex == selectedToolbarIndex) {
                selectedToolbarStillVisible = true;
                break;
            }
        }
        if (!selectedToolbarStillVisible) {
            selectedToolbarIndex = -1;
        }

        float nextButtonX = toolbarPadding;
        foreach (toolbarIndex; visibleToolbarIndices) {
            const toolbarLabel = getToolbarLabel(toolbarIndex);
            const buttonWidth = cast(float)MeasureText(toolbarLabel.ptr, 20) + 28.0f;
            Rectangle bounds = Rectangle(nextButtonX, toolbarPadding, buttonWidth, toolbarHeight - toolbarPadding * 2.0f);
            const toolbarEnabled = isToolbarEnabled(toolbarIndex, hasActiveMap);

            if (!toolbarEnabled) GuiDisable();
            const clicked = GuiButton(bounds, toolbarLabel.ptr);
            if (!toolbarEnabled) GuiEnable();

            if (clicked && toolbarEnabled) {
                selectedToolbarIndex = selectedToolbarIndex == toolbarIndex
                    ? -1
                    : toolbarIndex;
                selectedToolbarButtonRect = bounds;
                PlaySound(clickSound);
            }

            nextButtonX += buttonWidth + toolbarPadding;
        }

        if (hasActiveMap && appScreen == AppScreen.map) {
            const layerBtnSize = toolbarHeight - toolbarPadding * 2.0f;
            const layerLabelWidth = cast(float)MeasureText(TextFormat("Layer: %d", currentLayer), 20) + 16.0f;
            const layerControlWidth = layerLabelWidth + layerBtnSize * 2.0f + toolbarPadding * 2.0f;
            const layerControlX = cast(float)GetScreenWidth() - layerControlWidth - toolbarPadding;
            GuiLabel(Rectangle(layerControlX, toolbarPadding, layerLabelWidth, layerBtnSize), TextFormat("Layer: %d", currentLayer));
            if (GuiButton(Rectangle(layerControlX + layerLabelWidth + toolbarPadding, toolbarPadding, layerBtnSize, layerBtnSize), "-")) {
                if (currentLayer > 0) currentLayer--;
                PlaySound(clickSound);
            }
            if (GuiButton(Rectangle(layerControlX + layerLabelWidth + layerBtnSize + toolbarPadding * 2.0f, toolbarPadding, layerBtnSize, layerBtnSize), "+")) {
                currentLayer++;
                PlaySound(clickSound);
            }
        }

        if (hasActiveMap) {
            if (appScreen == AppScreen.map) {
                drawMapCanvas(canvasRect, gridLayout, placedChunks, chunkGeometries, ditherImage, selectedChunkIndex, showGrid, showChunkBounds, isDraggingChunk, previewChunk, previewPlacementValid, currentLayer);

                if (showInspector) {
                GuiPanel(inspectorRect, "Map Canvas");
                GuiLabel(Rectangle(inspectorRect.x + 16.0f, inspectorRect.y + 42.0f, inspectorRect.width - 32.0f, 24.0f), "Chunk Tools");

                const drawToolBounds = Rectangle(inspectorRect.x + 16.0f, inspectorRect.y + 68.0f, 74.0f, 28.0f);
                const moveToolBounds = Rectangle(inspectorRect.x + 98.0f, inspectorRect.y + 68.0f, 74.0f, 28.0f);
                const resizeToolBounds = Rectangle(inspectorRect.x + 180.0f, inspectorRect.y + 68.0f, 74.0f, 28.0f);
                const deleteToolBounds = Rectangle(inspectorRect.x + 16.0f, inspectorRect.y + 104.0f, 114.0f, 28.0f);
                const editToolBounds = Rectangle(inspectorRect.x + 140.0f, inspectorRect.y + 104.0f, 114.0f, 28.0f);

                if (GuiButton(drawToolBounds, "Draw")) {
                    activeChunkTool = ChunkTool.draw;
                    chunkToolMessage = "Draw mode: drag on the canvas to create a new chunk.";
                    PlaySound(clickSound);
                }
                if (GuiButton(moveToolBounds, "Move")) {
                    activeChunkTool = ChunkTool.move;
                    chunkToolMessage = "Move mode: drag a chunk to reposition it.";
                    PlaySound(clickSound);
                }
                GuiDisable();
                GuiButton(resizeToolBounds, "Resize");
                GuiEnable();
                if (GuiButton(deleteToolBounds, "Delete")) {
                    activeChunkTool = ChunkTool.deleteChunk;
                    chunkToolMessage = "Delete mode: click a chunk to remove it.";
                    PlaySound(clickSound);
                }
                if (GuiButton(editToolBounds, "Enter Edit")) {
                    activeChunkTool = ChunkTool.edit;
                    chunkToolMessage = "Edit mode: click a chunk to inspect it.";
                    PlaySound(clickSound);
                }

                final switch (activeChunkTool) {
                case ChunkTool.draw:
                    drawActiveToolHighlight(drawToolBounds);
                    break;
                case ChunkTool.move:
                    drawActiveToolHighlight(moveToolBounds);
                    break;
                case ChunkTool.resize:
                    break;
                case ChunkTool.deleteChunk:
                    drawActiveToolHighlight(deleteToolBounds);
                    break;
                case ChunkTool.edit:
                    drawActiveToolHighlight(editToolBounds);
                    break;
                }

                drawWrappedLabel(Rectangle(inspectorRect.x + 16.0f, inspectorRect.y + 144.0f, inspectorRect.width - 32.0f, 56.0f), chunkToolMessage);
                GuiLabel(Rectangle(inspectorRect.x + 16.0f, inspectorRect.y + 206.0f, inspectorRect.width - 32.0f, 24.0f), TextFormat("Snap Size: %d px", cast(int)gridLayout.cellSize));
                GuiLabel(Rectangle(inspectorRect.x + 16.0f, inspectorRect.y + 232.0f, inspectorRect.width - 32.0f, 24.0f), TextFormat("Chunks: %d", cast(int)placedChunks.length));
                GuiLabel(Rectangle(inspectorRect.x + 16.0f, inspectorRect.y + 258.0f, inspectorRect.width - 32.0f, 24.0f), TextFormat("Zoom: %d%%", cast(int)(mapCamera.zoom * 100.0f)));
                GuiLabel(Rectangle(inspectorRect.x + 16.0f, inspectorRect.y + 284.0f, inspectorRect.width - 32.0f, 24.0f), TextFormat("Camera: %d, %d", cast(int)mapCamera.target.x, cast(int)mapCamera.target.y));
                GuiLabel(Rectangle(inspectorRect.x + 16.0f, inspectorRect.y + 316.0f, inspectorRect.width - 32.0f, 24.0f), "Map Name:");
                if (GuiTextBox(Rectangle(inspectorRect.x + 16.0f, inspectorRect.y + 342.0f, inspectorRect.width - 32.0f, 28.0f), mapNameBuf.ptr, cast(int)mapNameBuf.length - 1, mapNameEditMode)) {
                    mapNameEditMode = !mapNameEditMode;
                }

                if (selectedChunkIndex >= 0 && selectedChunkIndex < cast(int)placedChunks.length) {
                    const selectedChunk = placedChunks[selectedChunkIndex];
                    GuiLabel(Rectangle(inspectorRect.x + 16.0f, inspectorRect.y + 392.0f, inspectorRect.width - 32.0f, 24.0f), TextFormat("Selected Chunk: %d", selectedChunkIndex + 1));
                    GuiLabel(Rectangle(inspectorRect.x + 16.0f, inspectorRect.y + 418.0f, inspectorRect.width - 32.0f, 24.0f), TextFormat("Origin: %d, %d", selectedChunk.column, selectedChunk.row));
                    GuiLabel(Rectangle(inspectorRect.x + 16.0f, inspectorRect.y + 444.0f, inspectorRect.width - 32.0f, 24.0f), TextFormat("Size: %d x %d", selectedChunk.width, selectedChunk.height));
                    GuiLabel(Rectangle(inspectorRect.x + 16.0f, inspectorRect.y + 470.0f, 60.0f, 24.0f), "Layer:");
                    const layerBtnW = 24.0f;
                    if (GuiButton(Rectangle(inspectorRect.x + 82.0f, inspectorRect.y + 470.0f, layerBtnW, 24.0f), "-")) {
                        if (placedChunks[selectedChunkIndex].layer > 0) {
                            const candidate = MapChunk(selectedChunk.column, selectedChunk.row, selectedChunk.width, selectedChunk.height, selectedChunk.layer - 1);
                            if (isChunkPlacementValid(candidate, placedChunks, selectedChunkIndex)) {
                                pushMapUndo(mapUndoStack, placedChunks, chunkGeometries);
                                placedChunks[selectedChunkIndex].layer--;
                                chunkToolMessage = to!string(TextFormat("Chunk %d moved to layer %d.", selectedChunkIndex + 1, placedChunks[selectedChunkIndex].layer));
                            } else {
                                chunkToolMessage = "Layer change blocked: overlap on target layer.";
                            }
                            PlaySound(clickSound);
                        }
                    }
                    GuiLabel(Rectangle(inspectorRect.x + 112.0f, inspectorRect.y + 470.0f, 32.0f, 24.0f), TextFormat("%d", selectedChunk.layer));
                    if (GuiButton(Rectangle(inspectorRect.x + 148.0f, inspectorRect.y + 470.0f, layerBtnW, 24.0f), "+")) {
                        const candidate = MapChunk(selectedChunk.column, selectedChunk.row, selectedChunk.width, selectedChunk.height, selectedChunk.layer + 1);
                        if (isChunkPlacementValid(candidate, placedChunks, selectedChunkIndex)) {
                            pushMapUndo(mapUndoStack, placedChunks, chunkGeometries);
                            placedChunks[selectedChunkIndex].layer++;
                            chunkToolMessage = to!string(TextFormat("Chunk %d moved to layer %d.", selectedChunkIndex + 1, placedChunks[selectedChunkIndex].layer));
                        } else {
                            chunkToolMessage = "Layer change blocked: overlap on target layer.";
                        }
                        PlaySound(clickSound);
                    }
                } else {
                    GuiLabel(Rectangle(inspectorRect.x + 16.0f, inspectorRect.y + 392.0f, inspectorRect.width - 32.0f, 24.0f), "Selected Chunk: none");
                }
                }
            } else if (editingChunkIndex >= 0 && editingChunkIndex < cast(int)placedChunks.length) {
                chunkEditorCamera.offset = Vector2(canvasRect.x + canvasRect.width * 0.5f, canvasRect.y + canvasRect.height * 0.5f);
                const chunkEditorLayout = getGridLayout(canvasRect, chunkEditorCamera);
                const editingChunk = placedChunks[editingChunkIndex];
                bool shouldReturnToMap = false;
                drawChunkEditorCanvas(
                    canvasRect,
                    chunkEditorLayout,
                    placedChunks,
                    chunkGeometries,
                    ditherImage,
                    editingChunkIndex,
                    editingChunk,
                    chunkGeometries[editingChunkIndex],
                    selectedPointIndices,
                    selectedFaceIndices,
                    selectedWallIndices,
                    selectedEntityIndices,
                    selectedObjectIndices,
                    isBoxSelecting,
                    getNormalizedRectangleFromPoints(boxSelectStartWorld, boxSelectEndWorld),
                    showGrid,
                    chunkEditorTool
                );

                const previewCamera = getChunkPreviewCamera(chunkPreviewBounds, chunkPreviewYaw, chunkPreviewPitch, chunkPreviewDistance);
                renderChunkPreview3D(chunkPreviewTexture, previewCamera, placedChunks, chunkGeometries, editingChunkIndex, chunkPreviewBounds, ditherImage);
                GuiPanel(chunkPreviewPanelRect, "3D Preview");
                DrawTexturePro(
                    chunkPreviewTexture.texture,
                    Rectangle(0.0f, 0.0f, chunkPreviewTextureWidth, -chunkPreviewTextureHeight),
                    chunkPreviewContentRect,
                    Vector2.zero,
                    0.0f,
                    Colors.WHITE
                );
                DrawRectangleLinesEx(chunkPreviewContentRect, 1.0f, Fade(Colors.DARKGRAY, 0.65f));

                if (showInspector) {
                    GuiPanel(inspectorRect, "Chunk Editor");
                    GuiLabel(Rectangle(inspectorRect.x + 16.0f, inspectorRect.y + 42.0f, inspectorRect.width - 32.0f, 24.0f), TextFormat("Chunk %d", editingChunkIndex + 1));

                    // 2x2 tool button grid
                    const placePointToolBounds  = Rectangle(inspectorRect.x + 16.0f,  inspectorRect.y + 68.0f,  116.0f, 28.0f);
                    const selectToolBounds      = Rectangle(inspectorRect.x + 140.0f, inspectorRect.y + 68.0f,  116.0f, 28.0f);
                    const placeEntityToolBounds = Rectangle(inspectorRect.x + 16.0f,  inspectorRect.y + 102.0f, 116.0f, 28.0f);
                    const placeObjectToolBounds = Rectangle(inspectorRect.x + 140.0f, inspectorRect.y + 102.0f, 116.0f, 28.0f);

                    if (GuiButton(placePointToolBounds, "Point")) {
                        setChunkEditorTool(chunkEditorTool, ChunkEditorTool.placePoint, chunkEditorMessage, clickSound);
                    }
                    if (GuiButton(selectToolBounds, "Select")) {
                        setChunkEditorTool(chunkEditorTool, ChunkEditorTool.selectPoint, chunkEditorMessage, clickSound);
                    }
                    if (GuiButton(placeEntityToolBounds, "Entity")) {
                        setChunkEditorTool(chunkEditorTool, ChunkEditorTool.placeEntity, chunkEditorMessage, clickSound);
                    }
                    if (GuiButton(placeObjectToolBounds, "Object")) {
                        setChunkEditorTool(chunkEditorTool, ChunkEditorTool.placeObject, chunkEditorMessage, clickSound);
                    }

                    if (chunkEditorTool == ChunkEditorTool.placePoint) {
                        drawActiveToolHighlight(placePointToolBounds);
                    } else if (chunkEditorTool == ChunkEditorTool.selectPoint) {
                        drawActiveToolHighlight(selectToolBounds);
                    } else if (chunkEditorTool == ChunkEditorTool.placeEntity) {
                        drawActiveToolHighlight(placeEntityToolBounds);
                    } else {
                        drawActiveToolHighlight(placeObjectToolBounds);
                    }

                    // Scrollable content area below tool buttons
                    const contentAreaTop = inspectorRect.y + 136.0f;
                    const fixedBottomHeight = 104.0f; // message (2 lines) + bounds + shortcuts
                    const contentAreaHeight = inspectorRect.height - 136.0f - fixedBottomHeight;
                    const contentAreaRect = Rectangle(inspectorRect.x, contentAreaTop, inspectorRect.width, contentAreaHeight);

                    // Handle scroll wheel when mouse is over inspector
                    const mousePos = GetMousePosition();
                    if (CheckCollisionPointRec(mousePos, inspectorRect)) {
                        const wheel = GetMouseWheelMove();
                        if (wheel != 0.0f) {
                            chunkInspectorScrollY -= wheel * 24.0f;
                            if (chunkInspectorScrollY < 0.0f) chunkInspectorScrollY = 0.0f;
                        }
                    }

                    // Helper: offset y by scroll within content area
                    float iy(float relY) {
                        return contentAreaTop + relY - chunkInspectorScrollY;
                    }

                    BeginScissorMode(cast(int)contentAreaRect.x, cast(int)contentAreaRect.y, cast(int)contentAreaRect.width, cast(int)contentAreaRect.height);

                    if (chunkEditorTool == ChunkEditorTool.placeEntity) {
                        GuiLabel(Rectangle(inspectorRect.x + 16.0f, iy(0.0f), 100.0f, 24.0f), "Entity Type:");
                        int entityTypeValue = cast(int)currentEntityType;
                        if (GuiButton(Rectangle(inspectorRect.x + 108.0f, iy(-2.0f), 24.0f, 24.0f), "<")) {
                            if (entityTypeValue > 0) {
                                currentEntityType = cast(EntityType)(entityTypeValue - 1);
                                PlaySound(clickSound);
                            }
                        }
                        GuiLabel(Rectangle(inspectorRect.x + 136.0f, iy(0.0f), 68.0f, 24.0f), getEntityTypeName(currentEntityType).ptr);
                        if (GuiButton(Rectangle(inspectorRect.x + 208.0f, iy(-2.0f), 24.0f, 24.0f), ">")) {
                            if (entityTypeValue < cast(int)EntityType.max) {
                                currentEntityType = cast(EntityType)(entityTypeValue + 1);
                                PlaySound(clickSound);
                            }
                        }

                        GuiLabel(Rectangle(inspectorRect.x + 16.0f, iy(28.0f), 100.0f, 24.0f), TextFormat("Rotation: %.0f", currentEntityRotationY));
                        if (GuiButton(Rectangle(inspectorRect.x + 108.0f, iy(26.0f), 24.0f, 24.0f), "<")) {
                            currentEntityRotationY -= 15.0f;
                            if (currentEntityRotationY < 0.0f) currentEntityRotationY += 360.0f;
                            PlaySound(clickSound);
                        }
                        if (GuiButton(Rectangle(inspectorRect.x + 136.0f, iy(26.0f), 48.0f, 24.0f), "Reset")) {
                            currentEntityRotationY = 0.0f;
                            PlaySound(clickSound);
                        }
                        if (GuiButton(Rectangle(inspectorRect.x + 188.0f, iy(26.0f), 24.0f, 24.0f), ">")) {
                            currentEntityRotationY += 15.0f;
                            if (currentEntityRotationY >= 360.0f) currentEntityRotationY -= 360.0f;
                            PlaySound(clickSound);
                        }
                    }

                    if (chunkEditorTool == ChunkEditorTool.placeObject) {
                        GuiLabel(Rectangle(inspectorRect.x + 16.0f, iy(0.0f), 100.0f, 24.0f), "Object Type:");
                        int objectTypeValue = cast(int)currentObjectType;
                        if (GuiButton(Rectangle(inspectorRect.x + 108.0f, iy(-2.0f), 24.0f, 24.0f), "<")) {
                            if (objectTypeValue > 0) {
                                currentObjectType = cast(ObjectType)(objectTypeValue - 1);
                                PlaySound(clickSound);
                            }
                        }
                        GuiLabel(Rectangle(inspectorRect.x + 136.0f, iy(0.0f), 68.0f, 24.0f), getObjectTypeName(currentObjectType).ptr);
                        if (GuiButton(Rectangle(inspectorRect.x + 208.0f, iy(-2.0f), 24.0f, 24.0f), ">")) {
                            if (objectTypeValue < cast(int)ObjectType.max) {
                                currentObjectType = cast(ObjectType)(objectTypeValue + 1);
                                PlaySound(clickSound);
                            }
                        }

                        GuiLabel(Rectangle(inspectorRect.x + 16.0f, iy(28.0f), 100.0f, 24.0f), TextFormat("Height: %.1f", currentObjectHeight));
                        if (GuiButton(Rectangle(inspectorRect.x + 108.0f, iy(26.0f), 24.0f, 24.0f), "-")) {
                            currentObjectHeight -= 1.0f;
                            PlaySound(clickSound);
                        }
                        if (GuiButton(Rectangle(inspectorRect.x + 136.0f, iy(26.0f), 48.0f, 24.0f), "Reset")) {
                            currentObjectHeight = 0.0f;
                            PlaySound(clickSound);
                        }
                        if (GuiButton(Rectangle(inspectorRect.x + 188.0f, iy(26.0f), 24.0f, 24.0f), "+")) {
                            currentObjectHeight += 1.0f;
                            PlaySound(clickSound);
                        }

                        GuiLabel(Rectangle(inspectorRect.x + 16.0f, iy(56.0f), 100.0f, 24.0f), TextFormat("Rotation: %.0f", currentObjectRotationY));
                        if (GuiButton(Rectangle(inspectorRect.x + 108.0f, iy(54.0f), 24.0f, 24.0f), "<")) {
                            currentObjectRotationY -= 15.0f;
                            if (currentObjectRotationY < 0.0f) currentObjectRotationY += 360.0f;
                            PlaySound(clickSound);
                        }
                        if (GuiButton(Rectangle(inspectorRect.x + 136.0f, iy(54.0f), 48.0f, 24.0f), "Reset")) {
                            currentObjectRotationY = 0.0f;
                            PlaySound(clickSound);
                        }
                        if (GuiButton(Rectangle(inspectorRect.x + 188.0f, iy(54.0f), 24.0f, 24.0f), ">")) {
                            currentObjectRotationY += 15.0f;
                            if (currentObjectRotationY >= 360.0f) currentObjectRotationY -= 360.0f;
                            PlaySound(clickSound);
                        }
                    }

                    if (GuiButton(Rectangle(inspectorRect.x + 16.0f, iy(84.0f), 116.0f, 28.0f), "Create Face")) {
                        pushChunkUndo(chunkUndoStack, chunkGeometries[editingChunkIndex]);
                        createSelectedFace(
                            chunkGeometries[editingChunkIndex],
                            selectedPointIndices,
                            selectedFaceIndices,
                            chunkEditorMessage,
                            connectSound,
                            touchSound
                        );
                    }

                    if (GuiButton(Rectangle(inspectorRect.x + 140.0f, iy(84.0f), 116.0f, 28.0f), "Delete Face")) {
                        pushChunkUndo(chunkUndoStack, chunkGeometries[editingChunkIndex]);
                        deleteSelectedFaces(
                            chunkGeometries[editingChunkIndex],
                            selectedFaceIndices,
                            chunkEditorMessage,
                            deleteSound,
                            touchSound
                        );
                    }

                    if (GuiButton(Rectangle(inspectorRect.x + 16.0f, iy(120.0f), 116.0f, 28.0f), "Create Wall")) {
                        pushChunkUndo(chunkUndoStack, chunkGeometries[editingChunkIndex]);
                        createSelectedWall(
                            chunkGeometries[editingChunkIndex],
                            selectedPointIndices,
                            selectedFaceIndices,
                            selectedWallIndices,
                            chunkEditorMessage,
                            connectSound,
                            touchSound
                        );
                    }

                    if (GuiButton(Rectangle(inspectorRect.x + 140.0f, iy(120.0f), 116.0f, 28.0f), "Delete Wall")) {
                        pushChunkUndo(chunkUndoStack, chunkGeometries[editingChunkIndex]);
                        deleteSelectedWalls(
                            chunkGeometries[editingChunkIndex],
                            selectedWallIndices,
                            chunkEditorMessage,
                            deleteSound,
                            touchSound
                        );
                    }

                    if (GuiButton(Rectangle(inspectorRect.x + 16.0f, iy(156.0f), 116.0f, 28.0f), "Delete Point")) {
                        deleteSelectedPoints(
                            chunkGeometries[editingChunkIndex],
                            selectedPointIndices,
                            selectedFaceIndices,
                            selectedWallIndices,
                            selectedEntityIndices,
                            selectedObjectIndices,
                            chunkEditorMessage,
                            deleteSound,
                            touchSound
                        );
                    }

                    if (GuiButton(Rectangle(inspectorRect.x + 140.0f, iy(156.0f), 116.0f, 28.0f), "Back to Map")) {
                        shouldReturnToMap = true;
                    }

                    if (GuiButton(Rectangle(inspectorRect.x + 16.0f, iy(192.0f), 116.0f, 28.0f), "Delete Entity")) {
                        pushChunkUndo(chunkUndoStack, chunkGeometries[editingChunkIndex]);
                        deleteSelectedEntities(
                            chunkGeometries[editingChunkIndex],
                            selectedEntityIndices,
                            chunkEditorMessage,
                            deleteSound,
                            touchSound
                        );
                    }

                    if (GuiButton(Rectangle(inspectorRect.x + 140.0f, iy(192.0f), 116.0f, 28.0f), "Delete Object")) {
                        pushChunkUndo(chunkUndoStack, chunkGeometries[editingChunkIndex]);
                        deleteSelectedObjects(
                            chunkGeometries[editingChunkIndex],
                            selectedObjectIndices,
                            chunkEditorMessage,
                            deleteSound,
                            touchSound
                        );
                    }

                    GuiLabel(Rectangle(inspectorRect.x + 16.0f, iy(228.0f), inspectorRect.width - 32.0f, 24.0f), TextFormat("Bounds: %d x %d   Zoom: %d%%", editingChunk.width * cast(int)mapGridCellSize, editingChunk.height * cast(int)mapGridCellSize, cast(int)(chunkEditorCamera.zoom * 100.0f)));

                    if (selectedFaceIndices.length != 1) {
                        faceFloorEditMode = false;
                        faceCeilingEditMode = false;
                    }

                    if (selectedFaceIndices.length <= 1) {
                        batchFaceFloorEditMode = false;
                        batchFaceCeilingEditMode = false;
                    }

                    if (selectedFaceIndices.length > 0) {
                        bool allAutoWallsEnabled = true;
                        bool anyAutoWallsEnabled = false;
                        bool allSameYEnabled = true;
                        bool anySameYEnabled = false;

                        foreach (selectedFaceIndex; selectedFaceIndices) {
                            if (selectedFaceIndex < 0 || selectedFaceIndex >= cast(int)chunkGeometries[editingChunkIndex].faces.length) {
                                continue;
                            }

                            const face = chunkGeometries[editingChunkIndex].faces[selectedFaceIndex];
                            if (face.autoWallFromHeightDifference) anyAutoWallsEnabled = true;
                            else allAutoWallsEnabled = false;

                            if (face.sameFloorAndCeiling) anySameYEnabled = true;
                            else allSameYEnabled = false;
                        }

                        const autoWallsLabel = allAutoWallsEnabled
                            ? "Auto Walls: On"
                            : (anyAutoWallsEnabled ? "Auto Walls: Mixed" : "Auto Walls: Off");
                        const sameYLabel = allSameYEnabled
                            ? "Same Y: On"
                            : (anySameYEnabled ? "Same Y: Mixed" : "Same Y: Off");

                        if (GuiButton(Rectangle(inspectorRect.x + 16.0f, iy(264.0f), 116.0f, 28.0f), autoWallsLabel.ptr)) {
                            pushChunkUndo(chunkUndoStack, chunkGeometries[editingChunkIndex]);
                            const nextAutoWallsState = !allAutoWallsEnabled;
                            foreach (selectedFaceIndex; selectedFaceIndices) {
                                if (selectedFaceIndex >= 0 && selectedFaceIndex < cast(int)chunkGeometries[editingChunkIndex].faces.length) {
                                    chunkGeometries[editingChunkIndex].faces[selectedFaceIndex].autoWallFromHeightDifference = nextAutoWallsState;
                                }
                            }
                            chunkEditorMessage = nextAutoWallsState
                                ? "Selected sectors now auto-generate walls from height differences."
                                : "Selected sectors no longer auto-generate height-difference walls.";
                            PlaySound(applySound);
                        }

                        if (GuiButton(Rectangle(inspectorRect.x + 140.0f, iy(264.0f), 116.0f, 28.0f), sameYLabel.ptr)) {
                            pushChunkUndo(chunkUndoStack, chunkGeometries[editingChunkIndex]);
                            const nextSameYState = !allSameYEnabled;
                            foreach (selectedFaceIndex; selectedFaceIndices) {
                                if (selectedFaceIndex >= 0 && selectedFaceIndex < cast(int)chunkGeometries[editingChunkIndex].faces.length) {
                                    auto face = &chunkGeometries[editingChunkIndex].faces[selectedFaceIndex];
                                    face.sameFloorAndCeiling = nextSameYState;
                                    if (nextSameYState) {
                                        face.ceilingHeight = face.floorHeight;
                                    }
                                }
                            }
                            chunkEditorMessage = nextSameYState
                                ? "Selected sectors now lock ceiling to floor."
                                : "Selected sectors can now use different floor and ceiling values.";
                            PlaySound(clickSound);
                        }
                    }

                    if (selectedFaceIndices.length > 1) {
                        GuiLabel(Rectangle(inspectorRect.x + 16.0f, iy(300.0f), inspectorRect.width - 32.0f, 24.0f), TextFormat("Apply Height To %d Faces", cast(int)selectedFaceIndices.length));
                        GuiLabel(Rectangle(inspectorRect.x + 16.0f, iy(324.0f), 42.0f, 24.0f), "Floor");
                        if (GuiValueBox(Rectangle(inspectorRect.x + 58.0f, iy(322.0f), 56.0f, 24.0f), null, &batchFaceFloorValue, -512, 1024, batchFaceFloorEditMode) == 1) {
                            batchFaceFloorEditMode = !batchFaceFloorEditMode;
                        }
                        if (GuiButton(Rectangle(inspectorRect.x + 118.0f, iy(322.0f), 24.0f, 24.0f), "-")) {
                            batchFaceFloorValue--;
                            PlaySound(clickSound);
                        }
                        if (GuiButton(Rectangle(inspectorRect.x + 146.0f, iy(322.0f), 24.0f, 24.0f), "+")) {
                            batchFaceFloorValue++;
                            PlaySound(clickSound);
                        }
                        if (GuiButton(Rectangle(inspectorRect.x + 176.0f, iy(322.0f), 68.0f, 24.0f), "Apply")) {
                            pushChunkUndo(chunkUndoStack, chunkGeometries[editingChunkIndex]);
                            const clampedFloorValue = clampInt(batchFaceFloorValue, -512, 1024);
                            foreach (selectedFaceIndex; selectedFaceIndices) {
                                if (selectedFaceIndex >= 0 && selectedFaceIndex < cast(int)chunkGeometries[editingChunkIndex].faces.length) {
                                    auto face = &chunkGeometries[editingChunkIndex].faces[selectedFaceIndex];
                                    face.floorHeight = clampedFloorValue;
                                    if (face.sameFloorAndCeiling) {
                                        face.ceilingHeight = clampedFloorValue;
                                    } else if (face.ceilingHeight < face.floorHeight) {
                                        face.ceilingHeight = face.floorHeight;
                                    }
                                }
                            }
                            batchFaceFloorValue = clampedFloorValue;
                            chunkEditorMessage = "Applied floor height to selected faces.";
                            PlaySound(clickSound);
                        }

                        GuiLabel(Rectangle(inspectorRect.x + 16.0f, iy(352.0f), 42.0f, 24.0f), "Ceil");
                        if (GuiValueBox(Rectangle(inspectorRect.x + 58.0f, iy(350.0f), 56.0f, 24.0f), null, &batchFaceCeilingValue, -512, 1024, batchFaceCeilingEditMode) == 1) {
                            batchFaceCeilingEditMode = !batchFaceCeilingEditMode;
                        }
                        if (GuiButton(Rectangle(inspectorRect.x + 118.0f, iy(350.0f), 24.0f, 24.0f), "-")) {
                            batchFaceCeilingValue--;
                            PlaySound(clickSound);
                        }
                        if (GuiButton(Rectangle(inspectorRect.x + 146.0f, iy(350.0f), 24.0f, 24.0f), "+")) {
                            batchFaceCeilingValue++;
                            PlaySound(clickSound);
                        }
                        if (GuiButton(Rectangle(inspectorRect.x + 176.0f, iy(350.0f), 68.0f, 24.0f), "Apply")) {
                            pushChunkUndo(chunkUndoStack, chunkGeometries[editingChunkIndex]);
                            const clampedCeilingValue = clampInt(batchFaceCeilingValue, -512, 1024);
                            foreach (selectedFaceIndex; selectedFaceIndices) {
                                if (selectedFaceIndex >= 0 && selectedFaceIndex < cast(int)chunkGeometries[editingChunkIndex].faces.length) {
                                    auto face = &chunkGeometries[editingChunkIndex].faces[selectedFaceIndex];
                                    if (face.sameFloorAndCeiling) {
                                        face.floorHeight = clampedCeilingValue;
                                        face.ceilingHeight = clampedCeilingValue;
                                    } else {
                                        face.ceilingHeight = clampedCeilingValue >= face.floorHeight ? clampedCeilingValue : face.floorHeight;
                                    }
                                }
                            }
                            batchFaceCeilingValue = clampedCeilingValue;
                            chunkEditorMessage = "Applied ceiling height to selected faces.";
                            PlaySound(clickSound);
                        }
                    }

                    if (selectedFaceIndices.length == 1) {
                        const selectedFaceIndex = selectedFaceIndices[0];
                        if (selectedFaceIndex >= 0 && selectedFaceIndex < cast(int)chunkGeometries[editingChunkIndex].faces.length) {
                            auto face = &chunkGeometries[editingChunkIndex].faces[selectedFaceIndex];
                            GuiLabel(Rectangle(inspectorRect.x + 16.0f, iy(300.0f), inspectorRect.width - 32.0f, 24.0f), TextFormat("Face %d", selectedFaceIndex + 1));
                            GuiLabel(Rectangle(inspectorRect.x + 16.0f, iy(324.0f), 42.0f, 24.0f), "Floor");

                            if (!faceFloorEditMode) {
                                faceFloorInputValue = face.floorHeight;
                            }
                            if (GuiValueBox(Rectangle(inspectorRect.x + 58.0f, iy(322.0f), 56.0f, 24.0f), null, &faceFloorInputValue, -512, 1024, faceFloorEditMode) == 1) {
                                faceFloorEditMode = !faceFloorEditMode;
                                if (!faceFloorEditMode) {
                                    pushChunkUndo(chunkUndoStack, chunkGeometries[editingChunkIndex]);
                                    face.floorHeight = clampInt(faceFloorInputValue, -512, 1024);
                                    if (face.sameFloorAndCeiling) {
                                        face.ceilingHeight = face.floorHeight;
                                    } else if (face.ceilingHeight < face.floorHeight) {
                                        face.ceilingHeight = face.floorHeight;
                                    }
                                    PlaySound(clickSound);
                                }
                            }
                            if (GuiButton(Rectangle(inspectorRect.x + 118.0f, iy(322.0f), 24.0f, 24.0f), "-")) {
                                pushChunkUndo(chunkUndoStack, chunkGeometries[editingChunkIndex]);
                                face.floorHeight--;
                                faceFloorInputValue = face.floorHeight;
                                if (face.sameFloorAndCeiling) {
                                    face.ceilingHeight = face.floorHeight;
                                    faceCeilingInputValue = face.ceilingHeight;
                                } else if (face.ceilingHeight < face.floorHeight) {
                                    face.ceilingHeight = face.floorHeight;
                                    faceCeilingInputValue = face.ceilingHeight;
                                }
                                PlaySound(clickSound);
                            }
                            if (GuiButton(Rectangle(inspectorRect.x + 146.0f, iy(322.0f), 24.0f, 24.0f), "+")) {
                                pushChunkUndo(chunkUndoStack, chunkGeometries[editingChunkIndex]);
                                face.floorHeight++;
                                faceFloorInputValue = face.floorHeight;
                                if (face.sameFloorAndCeiling) {
                                    face.ceilingHeight = face.floorHeight;
                                    faceCeilingInputValue = face.ceilingHeight;
                                } else if (face.ceilingHeight < face.floorHeight) {
                                    face.ceilingHeight = face.floorHeight;
                                    faceCeilingInputValue = face.ceilingHeight;
                                }
                                PlaySound(clickSound);
                            }

                            GuiLabel(Rectangle(inspectorRect.x + 16.0f, iy(352.0f), 42.0f, 24.0f), "Ceil");
                            if (!faceCeilingEditMode) {
                                faceCeilingInputValue = face.ceilingHeight;
                            }
                            if (face.sameFloorAndCeiling) GuiDisable();
                            if (GuiValueBox(Rectangle(inspectorRect.x + 58.0f, iy(350.0f), 56.0f, 24.0f), null, &faceCeilingInputValue, -512, 1024, faceCeilingEditMode) == 1) {
                                faceCeilingEditMode = !faceCeilingEditMode;
                                if (!faceCeilingEditMode && !face.sameFloorAndCeiling) {
                                    pushChunkUndo(chunkUndoStack, chunkGeometries[editingChunkIndex]);
                                    const nextCeilingValue = clampInt(faceCeilingInputValue, -512, 1024);
                                    face.ceilingHeight = nextCeilingValue >= face.floorHeight ? nextCeilingValue : face.floorHeight;
                                    faceCeilingInputValue = face.ceilingHeight;
                                    PlaySound(clickSound);
                                }
                            }
                            const decreaseCeiling = GuiButton(Rectangle(inspectorRect.x + 118.0f, iy(350.0f), 24.0f, 24.0f), "-");
                            const increaseCeiling = GuiButton(Rectangle(inspectorRect.x + 146.0f, iy(350.0f), 24.0f, 24.0f), "+");
                            if (face.sameFloorAndCeiling) GuiEnable();

                            if (!face.sameFloorAndCeiling) {
                                if (decreaseCeiling) {
                                    if (face.ceilingHeight > face.floorHeight) {
                                        pushChunkUndo(chunkUndoStack, chunkGeometries[editingChunkIndex]);
                                        face.ceilingHeight--;
                                        faceCeilingInputValue = face.ceilingHeight;
                                        PlaySound(clickSound);
                                    } else {
                                        PlaySound(touchSound);
                                    }
                                }
                                if (increaseCeiling) {
                                    pushChunkUndo(chunkUndoStack, chunkGeometries[editingChunkIndex]);
                                    face.ceilingHeight++;
                                    faceCeilingInputValue = face.ceilingHeight;
                                    PlaySound(clickSound);
                                }
                            }
                            GuiLabel(Rectangle(inspectorRect.x + 16.0f, iy(380.0f), 96.0f, 24.0f), TextFormat("Palette: %d", face.paletteIndex));
                            if (GuiButton(Rectangle(inspectorRect.x + 114.0f, iy(378.0f), 24.0f, 24.0f), "-")) {
                                if (face.paletteIndex > 0) {
                                    pushChunkUndo(chunkUndoStack, chunkGeometries[editingChunkIndex]);
                                    face.paletteIndex--;
                                    PlaySound(clickSound);
                                } else {
                                    PlaySound(touchSound);
                                }
                            }
                            if (GuiButton(Rectangle(inspectorRect.x + 144.0f, iy(378.0f), 24.0f, 24.0f), "+")) {
                                if (face.paletteIndex < paletteCount - 1) {
                                    pushChunkUndo(chunkUndoStack, chunkGeometries[editingChunkIndex]);
                                    face.paletteIndex++;
                                    PlaySound(clickSound);
                                } else {
                                    PlaySound(touchSound);
                                }
                            }
                        }
                    }

                    if (selectedWallIndices.length == 1) {
                        const selectedWallIndex = selectedWallIndices[0];
                        if (selectedWallIndex >= 0 && selectedWallIndex < cast(int)chunkGeometries[editingChunkIndex].walls.length) {
                            auto wall = &chunkGeometries[editingChunkIndex].walls[selectedWallIndex];
                            GuiLabel(Rectangle(inspectorRect.x + 16.0f, iy(300.0f), inspectorRect.width - 32.0f, 24.0f), TextFormat("Wall %d: %d -> %d", selectedWallIndex + 1, wall.startPointIndex + 1, wall.endPointIndex + 1));
                            GuiLabel(Rectangle(inspectorRect.x + 16.0f, iy(324.0f), 72.0f, 24.0f), TextFormat("Floor: %d", wall.floorHeight));
                            if (GuiButton(Rectangle(inspectorRect.x + 94.0f, iy(322.0f), 24.0f, 24.0f), "-")) {
                                wall.floorHeight--;
                                PlaySound(clickSound);
                            }
                            if (GuiButton(Rectangle(inspectorRect.x + 124.0f, iy(322.0f), 24.0f, 24.0f), "+")) {
                                wall.floorHeight++;
                                PlaySound(clickSound);
                            }
                            GuiLabel(Rectangle(inspectorRect.x + 156.0f, iy(324.0f), 80.0f, 24.0f), TextFormat("Ceil: %d", wall.ceilingHeight));
                            if (GuiButton(Rectangle(inspectorRect.x + 220.0f, iy(322.0f), 24.0f, 24.0f), "-")) {
                                wall.ceilingHeight = wall.ceilingHeight > wall.floorHeight + 1 ? wall.ceilingHeight - 1 : wall.ceilingHeight;
                                PlaySound(clickSound);
                            }
                            if (GuiButton(Rectangle(inspectorRect.x + 250.0f, iy(322.0f), 24.0f, 24.0f), "+")) {
                                wall.ceilingHeight++;
                                PlaySound(clickSound);
                            }
                            GuiLabel(Rectangle(inspectorRect.x + 16.0f, iy(352.0f), 96.0f, 24.0f), TextFormat("Palette: %d", wall.paletteIndex));
                            if (GuiButton(Rectangle(inspectorRect.x + 114.0f, iy(350.0f), 24.0f, 24.0f), "-")) {
                                if (wall.paletteIndex > 0) {
                                    wall.paletteIndex--;
                                    PlaySound(clickSound);
                                } else {
                                    PlaySound(touchSound);
                                }
                            }
                            if (GuiButton(Rectangle(inspectorRect.x + 144.0f, iy(350.0f), 24.0f, 24.0f), "+")) {
                                if (wall.paletteIndex < paletteCount - 1) {
                                    wall.paletteIndex++;
                                    PlaySound(clickSound);
                                } else {
                                    PlaySound(touchSound);
                                }
                            }
                        }
                    }

                    if (selectedEntityIndices.length == 1) {
                        const selectedEntityIndex = selectedEntityIndices[0];
                        if (selectedEntityIndex >= 0 && selectedEntityIndex < cast(int)chunkGeometries[editingChunkIndex].entities.length) {
                            auto entity = &chunkGeometries[editingChunkIndex].entities[selectedEntityIndex];
                            GuiLabel(Rectangle(inspectorRect.x + 16.0f, iy(262.0f), inspectorRect.width - 32.0f, 24.0f), TextFormat("Entity %d: %s", selectedEntityIndex + 1, getEntityTypeName(entity.type).ptr));

                            GuiLabel(Rectangle(inspectorRect.x + 16.0f, iy(286.0f), 120.0f, 24.0f), TextFormat("Position: %.1f, %.1f", entity.x, entity.z));

                            GuiLabel(Rectangle(inspectorRect.x + 16.0f, iy(310.0f), 100.0f, 24.0f), "Type:");
                            int entityTypeValue = cast(int)entity.type;
                            if (GuiButton(Rectangle(inspectorRect.x + 56.0f, iy(308.0f), 24.0f, 24.0f), "<")) {
                                if (entityTypeValue > 0) {
                                    entity.type = cast(EntityType)(entityTypeValue - 1);
                                    PlaySound(clickSound);
                                }
                            }
                            GuiLabel(Rectangle(inspectorRect.x + 84.0f, iy(310.0f), 100.0f, 24.0f), getEntityTypeName(entity.type).ptr);
                            if (GuiButton(Rectangle(inspectorRect.x + 188.0f, iy(308.0f), 24.0f, 24.0f), ">")) {
                                if (entityTypeValue < cast(int)EntityType.max) {
                                    entity.type = cast(EntityType)(entityTypeValue + 1);
                                    PlaySound(clickSound);
                                }
                            }

                            GuiLabel(Rectangle(inspectorRect.x + 16.0f, iy(334.0f), 100.0f, 24.0f), TextFormat("Rotation: %.0f", entity.rotationY));
                            if (GuiButton(Rectangle(inspectorRect.x + 108.0f, iy(332.0f), 24.0f, 24.0f), "-")) {
                                entity.rotationY -= 15.0f;
                                if (entity.rotationY < 0.0f) entity.rotationY += 360.0f;
                                PlaySound(clickSound);
                            }
                            if (GuiButton(Rectangle(inspectorRect.x + 136.0f, iy(332.0f), 48.0f, 24.0f), "Reset")) {
                                entity.rotationY = 0.0f;
                                PlaySound(clickSound);
                            }
                            if (GuiButton(Rectangle(inspectorRect.x + 188.0f, iy(332.0f), 24.0f, 24.0f), ">")) {
                                entity.rotationY += 15.0f;
                                if (entity.rotationY >= 360.0f) entity.rotationY -= 360.0f;
                                PlaySound(clickSound);
                            }
                        }
                    }

                    if (selectedObjectIndices.length > 1) {
                        GuiLabel(Rectangle(inspectorRect.x + 16.0f, iy(262.0f), inspectorRect.width - 32.0f, 24.0f), TextFormat("Apply To %d Objects", cast(int)selectedObjectIndices.length));
                        GuiLabel(Rectangle(inspectorRect.x + 16.0f, iy(286.0f), 100.0f, 24.0f), "Height:");
                        if (GuiButton(Rectangle(inspectorRect.x + 108.0f, iy(284.0f), 24.0f, 24.0f), "-")) {
                            foreach (idx; selectedObjectIndices) {
                                if (idx >= 0 && idx < cast(int)chunkGeometries[editingChunkIndex].objects.length)
                                    chunkGeometries[editingChunkIndex].objects[idx].y -= 1.0f;
                            }
                            PlaySound(clickSound);
                        }
                        if (GuiButton(Rectangle(inspectorRect.x + 136.0f, iy(284.0f), 48.0f, 24.0f), "Reset")) {
                            foreach (idx; selectedObjectIndices) {
                                if (idx >= 0 && idx < cast(int)chunkGeometries[editingChunkIndex].objects.length)
                                    chunkGeometries[editingChunkIndex].objects[idx].y = 0.0f;
                            }
                            PlaySound(clickSound);
                        }
                        if (GuiButton(Rectangle(inspectorRect.x + 188.0f, iy(284.0f), 24.0f, 24.0f), "+")) {
                            foreach (idx; selectedObjectIndices) {
                                if (idx >= 0 && idx < cast(int)chunkGeometries[editingChunkIndex].objects.length)
                                    chunkGeometries[editingChunkIndex].objects[idx].y += 1.0f;
                            }
                            PlaySound(clickSound);
                        }
                        GuiLabel(Rectangle(inspectorRect.x + 16.0f, iy(314.0f), 100.0f, 24.0f), "Rotation:");
                        if (GuiButton(Rectangle(inspectorRect.x + 108.0f, iy(312.0f), 24.0f, 24.0f), "<")) {
                            foreach (idx; selectedObjectIndices) {
                                if (idx >= 0 && idx < cast(int)chunkGeometries[editingChunkIndex].objects.length) {
                                    chunkGeometries[editingChunkIndex].objects[idx].rotationY -= 15.0f;
                                    if (chunkGeometries[editingChunkIndex].objects[idx].rotationY < 0.0f)
                                        chunkGeometries[editingChunkIndex].objects[idx].rotationY += 360.0f;
                                }
                            }
                            PlaySound(clickSound);
                        }
                        if (GuiButton(Rectangle(inspectorRect.x + 136.0f, iy(312.0f), 48.0f, 24.0f), "Reset")) {
                            foreach (idx; selectedObjectIndices) {
                                if (idx >= 0 && idx < cast(int)chunkGeometries[editingChunkIndex].objects.length)
                                    chunkGeometries[editingChunkIndex].objects[idx].rotationY = 0.0f;
                            }
                            PlaySound(clickSound);
                        }
                        if (GuiButton(Rectangle(inspectorRect.x + 188.0f, iy(312.0f), 24.0f, 24.0f), ">")) {
                            foreach (idx; selectedObjectIndices) {
                                if (idx >= 0 && idx < cast(int)chunkGeometries[editingChunkIndex].objects.length) {
                                    chunkGeometries[editingChunkIndex].objects[idx].rotationY += 15.0f;
                                    if (chunkGeometries[editingChunkIndex].objects[idx].rotationY >= 360.0f)
                                        chunkGeometries[editingChunkIndex].objects[idx].rotationY -= 360.0f;
                                }
                            }
                            PlaySound(clickSound);
                        }
                    }

                    if (selectedObjectIndices.length == 1) {
                        const selectedObjectIndex = selectedObjectIndices[0];
                        if (selectedObjectIndex >= 0 && selectedObjectIndex < cast(int)chunkGeometries[editingChunkIndex].objects.length) {
                            auto obj = &chunkGeometries[editingChunkIndex].objects[selectedObjectIndex];
                            GuiLabel(Rectangle(inspectorRect.x + 16.0f, iy(262.0f), inspectorRect.width - 32.0f, 24.0f), TextFormat("Object %d: %s", selectedObjectIndex + 1, getObjectTypeName(obj.type).ptr));

                            GuiLabel(Rectangle(inspectorRect.x + 16.0f, iy(286.0f), 156.0f, 24.0f), TextFormat("Pos: %.1f, %.1f, %.1f", obj.x, obj.y, obj.z));

                            GuiLabel(Rectangle(inspectorRect.x + 16.0f, iy(310.0f), 100.0f, 24.0f), "Type:");
                            int objectTypeValue = cast(int)obj.type;
                            if (GuiButton(Rectangle(inspectorRect.x + 56.0f, iy(308.0f), 24.0f, 24.0f), "<")) {
                                if (objectTypeValue > 0) {
                                    obj.type = cast(ObjectType)(objectTypeValue - 1);
                                    PlaySound(clickSound);
                                }
                            }
                            GuiLabel(Rectangle(inspectorRect.x + 84.0f, iy(310.0f), 100.0f, 24.0f), getObjectTypeName(obj.type).ptr);
                            if (GuiButton(Rectangle(inspectorRect.x + 188.0f, iy(308.0f), 24.0f, 24.0f), ">")) {
                                if (objectTypeValue < cast(int)ObjectType.max) {
                                    obj.type = cast(ObjectType)(objectTypeValue + 1);
                                    PlaySound(clickSound);
                                }
                            }

                            GuiLabel(Rectangle(inspectorRect.x + 16.0f, iy(334.0f), 100.0f, 24.0f), TextFormat("Height: %.1f", obj.y));
                            if (GuiButton(Rectangle(inspectorRect.x + 108.0f, iy(332.0f), 24.0f, 24.0f), "-")) {
                                obj.y -= 1.0f;
                                PlaySound(clickSound);
                            }
                            if (GuiButton(Rectangle(inspectorRect.x + 136.0f, iy(332.0f), 48.0f, 24.0f), "Reset")) {
                                obj.y = 0.0f;
                                PlaySound(clickSound);
                            }
                            if (GuiButton(Rectangle(inspectorRect.x + 188.0f, iy(332.0f), 24.0f, 24.0f), "+")) {
                                obj.y += 1.0f;
                                PlaySound(clickSound);
                            }

                            GuiLabel(Rectangle(inspectorRect.x + 16.0f, iy(358.0f), 100.0f, 24.0f), TextFormat("Rotation: %.0f", obj.rotationY));
                            if (GuiButton(Rectangle(inspectorRect.x + 108.0f, iy(356.0f), 24.0f, 24.0f), "-")) {
                                obj.rotationY -= 15.0f;
                                if (obj.rotationY < 0.0f) obj.rotationY += 360.0f;
                                PlaySound(clickSound);
                            }
                            if (GuiButton(Rectangle(inspectorRect.x + 136.0f, iy(356.0f), 48.0f, 24.0f), "Reset")) {
                                obj.rotationY = 0.0f;
                                PlaySound(clickSound);
                            }
                            if (GuiButton(Rectangle(inspectorRect.x + 188.0f, iy(356.0f), 24.0f, 24.0f), "+")) {
                                obj.rotationY += 15.0f;
                                if (obj.rotationY >= 360.0f) obj.rotationY -= 360.0f;
                                PlaySound(clickSound);
                            }
                        }
                    }

                    EndScissorMode();

                    // Fixed bottom section (not scrolled)
                    const fixedBottomY = inspectorRect.y + inspectorRect.height - fixedBottomHeight;
                    DrawLine(cast(int)inspectorRect.x, cast(int)(fixedBottomY - 1), cast(int)(inspectorRect.x + inspectorRect.width), cast(int)(fixedBottomY - 1), Fade(Colors.DARKGRAY, 0.8f));
                    drawWrappedLabel(Rectangle(inspectorRect.x + 16.0f, fixedBottomY + 4.0f, inspectorRect.width - 32.0f, 40.0f), chunkEditorMessage);
                    GuiLabel(Rectangle(inspectorRect.x + 16.0f, fixedBottomY + 44.0f, inspectorRect.width - 32.0f, 24.0f), TextFormat("P:%d  F:%d  W:%d  E:%d  O:%d", cast(int)chunkGeometries[editingChunkIndex].points.length, cast(int)chunkGeometries[editingChunkIndex].faces.length, cast(int)chunkGeometries[editingChunkIndex].walls.length, cast(int)chunkGeometries[editingChunkIndex].entities.length, cast(int)chunkGeometries[editingChunkIndex].objects.length));
                    GuiLabel(Rectangle(inspectorRect.x + 16.0f, fixedBottomY + 68.0f, inspectorRect.width - 32.0f, 24.0f), TextFormat("Sel P:%d  F:%d  W:%d  E:%d  O:%d", cast(int)selectedPointIndices.length, cast(int)selectedFaceIndices.length, cast(int)selectedWallIndices.length, cast(int)selectedEntityIndices.length, cast(int)selectedObjectIndices.length));

                    if (shouldReturnToMap) {
                        returnToMapFromChunkEditor(
                            appScreen,
                            selectedChunkIndex,
                            editingChunkIndex,
                            selectedPointIndices,
                            selectedFaceIndices,
                            selectedWallIndices,
                            selectedEntityIndices,
                            selectedObjectIndices,
                            isBoxSelecting,
                            chunkEditorMessage,
                            chunkToolMessage,
                            clickSound
                        );
                    }
                }
            }
        } else {
            const selectionWindow = Rectangle(
                cast(float)(GetScreenWidth() / 2) - 220.0f,
                cast(float)(GetScreenHeight() / 2) - 110.0f,
                440.0f,
                220.0f
            );
            GuiPanel(selectionWindow, "Choose a Map Action");
            GuiLabel(
                Rectangle(selectionWindow.x + 20.0f, selectionWindow.y + 42.0f, selectionWindow.width - 40.0f, 24.0f),
                "Start a fresh map or load an existing one."
            );
            GuiLabel(
                Rectangle(selectionWindow.x + 20.0f, selectionWindow.y + 68.0f, selectionWindow.width - 40.0f, 24.0f),
                "A grid canvas will appear once a map is active."
            );
            GuiLabel(
                Rectangle(selectionWindow.x + 20.0f, selectionWindow.y + 94.0f, selectionWindow.width - 40.0f, 24.0f),
                "Create or open a map to unlock Project, Map, and Chunk tools."
            );

            const buttonY = selectionWindow.y + 142.0f;
            const buttonWidth = (selectionWindow.width - 60.0f) / 2.0f;

            if (GuiButton(
                Rectangle(selectionWindow.x + 20.0f, buttonY, buttonWidth, 40.0f),
                "New Map"
            )) {
                selectedMapPath = "A new map session will start here";
                hasActiveMap = true;
                appScreen = AppScreen.map;
                placedChunks.length = 0;
                chunkGeometries.length = 0;
                selectedChunkIndex = -1;
                editingChunkIndex = -1;
                PlaySound(connectSound);
            }

            if (GuiButton(
                Rectangle(selectionWindow.x + 40.0f + buttonWidth, buttonY, buttonWidth, 40.0f),
                "Open Map"
            )) {
                pendingOpenMapDialog = true;
                PlaySound(clickSound);
            }
        }

        if (selectedToolbarIndex >= 0) {
            const menuOptions = getMenuOptions(selectedToolbarIndex);
            const menuRect = getToolbarMenuRect(selectedToolbarButtonRect, menuOptions.length);

            GuiPanel(menuRect, null);

            foreach (optionIndex, optionLabel; menuOptions) {
                const optionRect = Rectangle(
                    menuRect.x + 10.0f,
                    menuRect.y + 10.0f + optionIndex * 34.0f,
                    menuRect.width - 20.0f,
                    28.0f
                );
                const optionEnabled = isMenuOptionEnabled(selectedToolbarIndex, cast(int)optionIndex, hasActiveMap);

                if (!optionEnabled) GuiDisable();
                const clicked = GuiButton(optionRect, optionLabel.ptr);
                if (!optionEnabled) GuiEnable();

                if (clicked && optionEnabled) {
                    applyToolbarAction(
                        selectedToolbarIndex,
                        cast(int)optionIndex,
                        selectedMapPath,
                        hasActiveMap,
                        appScreen,
                        editingChunkIndex,
                        pendingOpenMapDialog,
                        showGrid,
                        showInspector,
                        showChunkBounds,
                        placedChunks,
                        chunkGeometries,
                        shouldExit,
                        mapCamera,
                        chunkEditorCamera,
                        selectedPointIndices,
                        selectedFaceIndices,
                        selectedWallIndices,
                        selectedEntityIndices,
                        selectedObjectIndices,
                        chunkToolMessage,
                        chunkEditorMessage,
                        showAboutDialog,
                        showShortcutsDialog,
                        pendingSaveMapDialog
                    );
                    PlaySound(clickSound);
                    if (!shouldExit) {
                        selectedToolbarIndex = -1;
                    }
                }
            }
        }

        if (showAboutDialog) {
            const dialogWidth = 480.0f;
            const dialogHeight = 300.0f;
            const dialogX = (GetScreenWidth() - dialogWidth) * 0.5f;
            const dialogY = (GetScreenHeight() - dialogHeight) * 0.5f;
            const dialogRect = Rectangle(dialogX, dialogY, dialogWidth, dialogHeight);

            DrawRectangle(0, 0, GetScreenWidth(), GetScreenHeight(), Color(0, 0, 0, 180));
            GuiPanel(dialogRect, "About Leafway");

            float textY = dialogY + 40.0f;
            const textX = dialogX + 20.0f;
            const textWidth = dialogWidth - 40.0f;

            DrawText("Leafway Editor", cast(int)textX, cast(int)textY, 24, Colors.WHITE);
            textY += 40.0f;

            DrawText("Version: 0.1.0 (Prototype)", cast(int)textX, cast(int)textY, 16, Colors.LIGHTGRAY);
            textY += 30.0f;

            DrawText("A simple 3D DOOM-style map maker for Playdate", cast(int)textX, cast(int)textY, 14, Colors.LIGHTGRAY);
            textY += 25.0f;
            DrawText("made with raylib in D.", cast(int)textX, cast(int)textY, 14, Colors.LIGHTGRAY);
            textY += 35.0f;

            DrawText("Created by Dylan (2025)", cast(int)textX, cast(int)textY, 14, Colors.LIGHTGRAY);
            textY += 35.0f;

            if (GuiButton(Rectangle(dialogX + dialogWidth - 100.0f, dialogY + dialogHeight - 50.0f, 80.0f, 35.0f), "Close")) {
                showAboutDialog = false;
                PlaySound(clickSound);
            }
        }

        if (showShortcutsDialog) {
            const dialogWidth = 520.0f;
            const dialogHeight = 440.0f;
            const dialogX = (GetScreenWidth() - dialogWidth) * 0.5f;
            const dialogY = (GetScreenHeight() - dialogHeight) * 0.5f;
            const dialogRect = Rectangle(dialogX, dialogY, dialogWidth, dialogHeight);

            DrawRectangle(0, 0, GetScreenWidth(), GetScreenHeight(), Color(0, 0, 0, 180));
            GuiPanel(dialogRect, "Keyboard Shortcuts");

            float textY = dialogY + 40.0f;
            const textX = dialogX + 20.0f;
            const colWidth = 250.0f;

            DrawText("Map Screen:", cast(int)textX, cast(int)textY, 16, Colors.WHITE);
            textY += 25.0f;

            DrawText("D", cast(int)textX, cast(int)textY, 14, Colors.LIGHTGRAY);
            DrawText("Draw/Place Chunk", cast(int)(textX + 120.0f), cast(int)textY, 14, Colors.LIGHTGRAY);
            textY += 20.0f;

            DrawText("M", cast(int)textX, cast(int)textY, 14, Colors.LIGHTGRAY);
            DrawText("Move Chunk", cast(int)(textX + 120.0f), cast(int)textY, 14, Colors.LIGHTGRAY);
            textY += 20.0f;

            DrawText("E", cast(int)textX, cast(int)textY, 14, Colors.LIGHTGRAY);
            DrawText("Edit Chunk", cast(int)(textX + 120.0f), cast(int)textY, 14, Colors.LIGHTGRAY);
            textY += 20.0f;

            DrawText("Delete/Backspace", cast(int)textX, cast(int)textY, 14, Colors.LIGHTGRAY);
            DrawText("Delete Chunk", cast(int)(textX + 120.0f), cast(int)textY, 14, Colors.LIGHTGRAY);
            textY += 20.0f;

            DrawText("Escape", cast(int)textX, cast(int)textY, 14, Colors.LIGHTGRAY);
            DrawText("Clear Selection", cast(int)(textX + 120.0f), cast(int)textY, 14, Colors.LIGHTGRAY);
            textY += 30.0f;

            DrawText("Chunk Editor:", cast(int)textX, cast(int)textY, 16, Colors.WHITE);
            textY += 25.0f;

            DrawText("1", cast(int)textX, cast(int)textY, 14, Colors.LIGHTGRAY);
            DrawText("Place Point Mode", cast(int)(textX + 120.0f), cast(int)textY, 14, Colors.LIGHTGRAY);
            textY += 20.0f;

            DrawText("2", cast(int)textX, cast(int)textY, 14, Colors.LIGHTGRAY);
            DrawText("Select Mode", cast(int)(textX + 120.0f), cast(int)textY, 14, Colors.LIGHTGRAY);
            textY += 20.0f;

            DrawText("Tab", cast(int)textX, cast(int)textY, 14, Colors.LIGHTGRAY);
            DrawText("Toggle Mode", cast(int)(textX + 120.0f), cast(int)textY, 14, Colors.LIGHTGRAY);
            textY += 20.0f;

            DrawText("F", cast(int)textX, cast(int)textY, 14, Colors.LIGHTGRAY);
            DrawText("Create Face", cast(int)(textX + 120.0f), cast(int)textY, 14, Colors.LIGHTGRAY);
            textY += 20.0f;

            DrawText("W", cast(int)textX, cast(int)textY, 14, Colors.LIGHTGRAY);
            DrawText("Create Wall", cast(int)(textX + 120.0f), cast(int)textY, 14, Colors.LIGHTGRAY);
            textY += 20.0f;

            DrawText("Delete/Backspace", cast(int)textX, cast(int)textY, 14, Colors.LIGHTGRAY);
            DrawText("Delete Selection", cast(int)(textX + 120.0f), cast(int)textY, 14, Colors.LIGHTGRAY);
            textY += 20.0f;

            DrawText("Ctrl+A", cast(int)textX, cast(int)textY, 14, Colors.LIGHTGRAY);
            DrawText("Select All Points", cast(int)(textX + 120.0f), cast(int)textY, 14, Colors.LIGHTGRAY);
            textY += 20.0f;

            DrawText("Escape", cast(int)textX, cast(int)textY, 14, Colors.LIGHTGRAY);
            DrawText("Clear/Exit", cast(int)(textX + 120.0f), cast(int)textY, 14, Colors.LIGHTGRAY);
            textY += 20.0f;

            if (GuiButton(Rectangle(dialogX + dialogWidth - 100.0f, dialogY + dialogHeight - 50.0f, 80.0f, 35.0f), "Close")) {
                showShortcutsDialog = false;
                PlaySound(clickSound);
            }
        }

    }

    StopMusicStream(oceanMusic);
    UnloadMusicStream(oceanMusic);
    UnloadSound(connectSound);
    UnloadSound(applySound);
    UnloadSound(touchSound);
    UnloadSound(deleteSound);
    UnloadSound(moveSound);
    UnloadSound(placeSound);
    UnloadSound(clickSound);
    UnloadRenderTexture(chunkPreviewTexture);
    UnloadImage(ditherImage);
    UnloadTexture(waterTexture);
    CloseAudioDevice();
    CloseWindow();
    return 0;
}
