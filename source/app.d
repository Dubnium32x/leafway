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
import std.process : execute;
import core.stdc.math : fmod, floor, atan2;
import std.file;
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

struct ToolbarItem {
    string label;
}

struct GridCell {
    int column;
    int row;
}

struct MapChunk {
    int column;
    int row;
    int width;
    int height;
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
}

struct ChunkGeometry {
    ChunkPoint[] points;
    ChunkFace[] faces;
}

struct GridLayout {
    Rectangle canvasRect;
    Camera2D camera;
    float cellSize;
}

private int clampInt(int value, int minimum, int maximum)
{
    if (value < minimum) return minimum;
    if (value > maximum) return maximum;
    return value;
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

        if (chunksOverlap(candidate, chunk)) {
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
}

private void removeFaceAt(ref ChunkGeometry geometry, int faceIndex)
{
    geometry.faces = geometry.faces[0 .. faceIndex] ~ geometry.faces[faceIndex + 1 .. $];
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
    ChunkFace candidateFace = ChunkFace(orderedPointIndices.dup, 0, 16, 0);
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

private void drawMapCanvas(
    Rectangle canvasRect,
    GridLayout gridLayout,
    MapChunk[] placedChunks,
    ChunkGeometry[] chunkGeometries,
    int selectedChunkIndex,
    bool showGrid,
    bool showChunkBounds,
    bool isDraggingChunk,
    MapChunk previewChunk,
    bool previewPlacementValid,
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
        DrawRectangleRec(chunkRect, Fade(Colors.DARKBLUE, isSelected ? 0.60f : 0.42f));

        if (index < chunkGeometries.length) {
            const chunkOffset = Vector2(chunkRect.x, chunkRect.y);
            foreach (faceIndex, face; chunkGeometries[index].faces) {
                const faceFill = isSelected
                    ? Fade(Colors.GOLD, 0.18f)
                    : Fade(Colors.SKYBLUE, 0.16f);
                drawFilledFace(chunkGeometries[index], face, faceFill, chunkOffset);

                const polygonPoints = getFacePolygonPoints(chunkGeometries[index], face, chunkOffset);
                for (int pointIndex = 0; pointIndex < cast(int)polygonPoints.length; pointIndex++) {
                    const nextPointIndex = (pointIndex + 1) % cast(int)polygonPoints.length;
                    DrawLineV(polygonPoints[pointIndex], polygonPoints[nextPointIndex], Fade(Colors.WHITE, 0.45f));
                }
            }
        }

        DrawRectangleLinesEx(
            chunkRect,
            isSelected ? 3.0f : (showChunkBounds ? 2.5f : 1.5f),
            isSelected ? Fade(Colors.GOLD, 0.95f) : Fade(Colors.WHITE, 0.85f)
        );
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
    int editingChunkIndex,
    MapChunk chunk,
    ChunkGeometry geometry,
    int[] selectedPointIndices,
    int[] selectedFaceIndices,
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
                drawFilledFace(chunkGeometries[index], face, Fade(Colors.SKYBLUE, 0.10f), chunkOffset);

                const polygonPoints = getFacePolygonPoints(chunkGeometries[index], face, chunkOffset);
                for (int pointIndex = 0; pointIndex < cast(int)polygonPoints.length; pointIndex++) {
                    const nextPointIndex = (pointIndex + 1) % cast(int)polygonPoints.length;
                    DrawLineV(polygonPoints[pointIndex], polygonPoints[nextPointIndex], Fade(Colors.RAYWHITE, 0.18f));
                }
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
        const fillColor = isSelected ? Fade(Colors.GOLD, 0.28f) : Fade(Colors.SKYBLUE, 0.18f);

        drawFilledFace(geometry, face, fillColor);

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

    foreach (pointIndex, point; geometry.points) {
        const pointPosition = getChunkPointPosition(point);
        const isSelected = selectedPointIndicesContain(selectedPointIndices, cast(int)pointIndex);
        DrawCircleV(pointPosition, (isSelected ? 4.0f : 3.0f) / gridLayout.camera.zoom, isSelected ? Fade(Colors.GOLD, 0.98f) : Fade(Colors.LIME, 0.92f));
    }

    if (editorTool == ChunkEditorTool.placePoint) {
        DrawCircleV(Vector2.zero, 2.5f / gridLayout.camera.zoom, Fade(Colors.SKYBLUE, 0.95f));
    }
}

private string[] getMenuOptions(int toolbarIndex)
{
    switch (toolbarIndex) {
    case 0:
        return ["New Map", "Open Map", "Save Snapshot", "Quit"];
    case 1:
        return ["Undo", "Redo", "Duplicate Chunk", "Delete Selection"];
    case 2:
        return ["Toggle Grid", "Toggle Inspector", "Toggle Chunk Bounds", "Reset Layout"];
    case 3:
        return ["Project Settings", "Validate Project", "Build Chunks"];
    case 4:
        return ["Resize Map", "Fill With Water", "Center Camera"];
    case 5:
        return ["New Chunk", "Duplicate Chunk", "Bake Lighting"];
    case 6:
        return ["Controls", "Documentation", "About Leafway"];
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
        return optionIndex == 0 || optionIndex == 1 || optionIndex == 3;
    case 2:
        return true;
    case 6:
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
            selectedMapPath = "leafway_snapshot_preview.png";
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
            break;
        case 1:
            break;
        case 2:
            break;
        default:
            break;
        }
        break;
    case 5:
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
    case 6:
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

private string openMapFileDialog()
{
    version (linux) {
        const result = execute([
            "zenity",
            "--file-selection",
            "--title=Open Map",
            "--filename=./",
            "--file-filter=Leafway Maps | *.leafway *.json *.map",
            "--file-filter=All Files | *"
        ]);

        if (result.status != 0) {
            return "";
        }

        return result.output.strip().idup;
    } else {
        return "";
    }
}

int main()
{
    SetExitKey(0); // Disable default exit key (ESC) to handle it manually in the menu
    SetConfigFlags(ConfigFlags.FLAG_WINDOW_RESIZABLE | ConfigFlags.FLAG_VSYNC_HINT);
    InitWindow(1280, 720, "Leafway Editor - Prototype");
    SetWindowMinSize(960, 540);
    SetTargetFPS(60);

    InitAudioDevice();

    Texture2D waterTexture = LoadTexture("resources/image/water.png");
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
    SetSoundVolume(clickSound, 0.55f);
    SetSoundVolume(placeSound, 0.55f);
    SetSoundVolume(moveSound, 0.55f);
    SetSoundVolume(deleteSound, 0.55f);
    SetSoundVolume(touchSound, 0.45f);
    SetSoundVolume(connectSound, 0.55f);

    ToolbarItem[] toolbarItems = [
        ToolbarItem("File"),
        ToolbarItem("Edit"),
        ToolbarItem("View"),
        ToolbarItem("Project"),
        ToolbarItem("Map"),
        ToolbarItem("Chunk"),
        ToolbarItem("Help")
    ];

    int selectedToolbarIndex = -1;
    Vector2 waterOffset = Vector2.zero;
    string selectedMapPath = "No map selected";
    bool hasActiveMap = false;
    AppScreen appScreen = AppScreen.map;
    bool pendingOpenMapDialog = false;
    bool showGrid = true;
    bool showInspector = true;
    bool showChunkBounds = false;
    MapChunk[] placedChunks;
    ChunkGeometry[] chunkGeometries;
    Camera2D mapCamera = Camera2D(Vector2.zero, Vector2.zero, 0.0f, 1.0f);
    Camera2D chunkEditorCamera = Camera2D(Vector2.zero, Vector2.zero, 0.0f, 2.0f);
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
    string chunkToolMessage = "Draw mode: drag on the canvas to create a new chunk.";
    ChunkEditorTool chunkEditorTool = ChunkEditorTool.placePoint;
    int[] selectedPointIndices;
    int[] selectedFaceIndices;
    string chunkEditorMessage = "Point mode: click to place snapped points inside the chunk bounds.";
    bool shouldExit = false;

    while (!WindowShouldClose() && !shouldExit) {
        const frameTime = GetFrameTime();
        const canvasRect = getMapCanvasRect(showInspector);
        const inspectorRect = getInspectorRect();
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
                selectedMapPath = chosenMap;
                hasActiveMap = true;
                appScreen = AppScreen.map;
                placedChunks.length = 0;
                chunkGeometries.length = 0;
                selectedChunkIndex = -1;
                editingChunkIndex = -1;
                PlaySound(connectSound);
            }
        }

        if (hasActiveMap && selectedToolbarIndex < 0 && appScreen == AppScreen.map) {
            const mouseInsideCanvas = CheckCollisionPointRec(mousePosition, canvasRect);
            const wheelMove = mouseInsideCanvas ? GetMouseWheelMove() : 0.0f;

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
                    previewPlacementValid = isChunkPlacementValid(previewChunk, placedChunks);
                    break;
                case ChunkTool.move:
                    if (clickedChunkIndex >= 0) {
                        selectedChunkIndex = clickedChunkIndex;
                        interactionStartChunk = placedChunks[selectedChunkIndex];
                        dragCellOffset = GridCell(clickedCell.column - interactionStartChunk.column, clickedCell.row - interactionStartChunk.row);
                        previewChunk = interactionStartChunk;
                        previewPlacementValid = true;
                        isDraggingChunk = true;
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
                        placedChunks = placedChunks[0 .. clickedChunkIndex] ~ placedChunks[clickedChunkIndex + 1 .. $];
                        chunkGeometries = chunkGeometries[0 .. clickedChunkIndex] ~ chunkGeometries[clickedChunkIndex + 1 .. $];
                        if (selectedChunkIndex == clickedChunkIndex) {
                            selectedChunkIndex = -1;
                        } else if (selectedChunkIndex > clickedChunkIndex) {
                            selectedChunkIndex--;
                        }
                        chunkToolMessage = "Chunk deleted.";
                        PlaySound(deleteSound);
                    } else {
                        PlaySound(touchSound);
                    }
                    break;
                case ChunkTool.edit:
                    if (clickedChunkIndex >= 0) {
                        selectedChunkIndex = clickedChunkIndex;
                        editingChunkIndex = clickedChunkIndex;
                        appScreen = AppScreen.chunkEditor;
                        selectedPointIndices.length = 0;
                        selectedFaceIndices.length = 0;
                        chunkEditorTool = ChunkEditorTool.placePoint;
                        chunkEditorMessage = to!string(TextFormat("Editing chunk %d. Place or select points to build faces.", clickedChunkIndex + 1));
                        const editChunk = placedChunks[editingChunkIndex];
                        chunkEditorCamera.target = Vector2(editChunk.width * mapGridCellSize * 0.5f, editChunk.height * mapGridCellSize * 0.5f);
                        chunkEditorCamera.zoom = 2.0f;
                        PlaySound(connectSound);
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
                            placedChunks ~= previewChunk;
                            chunkGeometries ~= ChunkGeometry.init;
                            selectedChunkIndex = cast(int)placedChunks.length - 1;
                            chunkToolMessage = to!string(TextFormat("Chunk %d created.", selectedChunkIndex + 1));
                            PlaySound(placeSound);
                        } else {
                            chunkToolMessage = "Chunks cannot overlap.";
                            PlaySound(touchSound);
                        }
                        break;
                    case ChunkTool.move:
                        if (selectedChunkIndex >= 0 && previewPlacementValid) {
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
            const mouseInsideCanvas = CheckCollisionPointRec(mousePosition, canvasRect);
            const wheelMove = mouseInsideCanvas ? GetMouseWheelMove() : 0.0f;

            if (wheelMove != 0.0f) {
                chunkEditorCamera.zoom += wheelMove * 0.125f;
                if (chunkEditorCamera.zoom < 0.5f) chunkEditorCamera.zoom = 0.5f;
                if (chunkEditorCamera.zoom > 6.0f) chunkEditorCamera.zoom = 6.0f;
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

            if (IsMouseButtonPressed(MouseButton.MOUSE_BUTTON_LEFT) && mouseInsideCanvas && !isPanningCanvas) {
                const worldPosition = GetScreenToWorld2D(mousePosition, chunkEditorLayout.camera);
                const editChunk = placedChunks[editingChunkIndex];

                if (chunkEditorTool == ChunkEditorTool.placePoint) {
                    const point = getChunkPointAtWorldPosition(worldPosition, editChunk);
                    if (!chunkGeometryHasPoint(chunkGeometries[editingChunkIndex], point)) {
                        chunkGeometries[editingChunkIndex].points ~= point;
                        selectedPointIndices = [cast(int)chunkGeometries[editingChunkIndex].points.length - 1];
                        selectedFaceIndices.length = 0;
                        chunkEditorMessage = to!string(TextFormat("Placed point at %d, %d.", point.x, point.z));
                        PlaySound(placeSound);
                    } else {
                        chunkEditorMessage = "A point already exists at that snapped location.";
                        PlaySound(touchSound);
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
                        chunkEditorMessage = to!string(TextFormat("Selected %d point(s).", cast(int)selectedPointIndices.length));
                        PlaySound(clickSound);
                    } else {
                        const faceIndex = findFaceAtWorldPosition(chunkGeometries[editingChunkIndex], worldPosition, 14.0f / chunkEditorCamera.zoom);
                        if (faceIndex >= 0) {
                            if (selectedFaceIndicesContain(selectedFaceIndices, faceIndex)) {
                                selectedFaceIndices = selectedFaceIndices.filter!(index => index != faceIndex).array;
                            } else {
                                selectedFaceIndices ~= faceIndex;
                            }
                            selectedPointIndices.length = 0;
                            chunkEditorMessage = to!string(TextFormat("Selected %d face(s).", cast(int)selectedFaceIndices.length));
                            PlaySound(clickSound);
                        } else {
                            selectedPointIndices.length = 0;
                            selectedFaceIndices.length = 0;
                            chunkEditorMessage = "Selection cleared.";
                            PlaySound(touchSound);
                        }
                    }
                }
            }
        } else {
            isDraggingChunk = false;
            isPanningCanvas = false;
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

        Rectangle[] toolbarButtonRects;
        float nextButtonX = toolbarPadding;
        foreach (index, item; toolbarItems) {
            const buttonWidth = cast(float)MeasureText(item.label.ptr, 20) + 28.0f;
            Rectangle bounds = Rectangle(nextButtonX, toolbarPadding, buttonWidth, toolbarHeight - toolbarPadding * 2.0f);
            toolbarButtonRects ~= bounds;
            const toolbarEnabled = isToolbarEnabled(cast(int)index, hasActiveMap);

            if (!toolbarEnabled) GuiDisable();
            const clicked = GuiButton(bounds, item.label.ptr);
            if (!toolbarEnabled) GuiEnable();

            if (clicked && toolbarEnabled) {
                selectedToolbarIndex = selectedToolbarIndex == cast(int)index
                    ? -1
                    : cast(int)index;
                PlaySound(clickSound);
            }

            nextButtonX += buttonWidth + toolbarPadding;
        }

        if (hasActiveMap) {
            if (appScreen == AppScreen.map) {
                drawMapCanvas(canvasRect, gridLayout, placedChunks, chunkGeometries, selectedChunkIndex, showGrid, showChunkBounds, isDraggingChunk, previewChunk, previewPlacementValid);

                if (showInspector) {
                GuiPanel(inspectorRect, "Map Canvas");
                GuiLabel(Rectangle(inspectorRect.x + 16.0f, inspectorRect.y + 42.0f, inspectorRect.width - 32.0f, 24.0f), "Chunk Tools");

                if (GuiButton(Rectangle(inspectorRect.x + 16.0f, inspectorRect.y + 68.0f, 74.0f, 28.0f), "Draw")) {
                    activeChunkTool = ChunkTool.draw;
                    chunkToolMessage = "Draw mode: drag on the canvas to create a new chunk.";
                    PlaySound(clickSound);
                }
                if (GuiButton(Rectangle(inspectorRect.x + 98.0f, inspectorRect.y + 68.0f, 74.0f, 28.0f), "Move")) {
                    activeChunkTool = ChunkTool.move;
                    chunkToolMessage = "Move mode: drag a chunk to reposition it.";
                    PlaySound(clickSound);
                }
                GuiDisable();
                GuiButton(Rectangle(inspectorRect.x + 180.0f, inspectorRect.y + 68.0f, 74.0f, 28.0f), "Resize");
                GuiEnable();
                if (GuiButton(Rectangle(inspectorRect.x + 16.0f, inspectorRect.y + 104.0f, 114.0f, 28.0f), "Delete")) {
                    activeChunkTool = ChunkTool.deleteChunk;
                    chunkToolMessage = "Delete mode: click a chunk to remove it.";
                    PlaySound(clickSound);
                }
                if (GuiButton(Rectangle(inspectorRect.x + 140.0f, inspectorRect.y + 104.0f, 114.0f, 28.0f), "Enter Edit")) {
                    activeChunkTool = ChunkTool.edit;
                    chunkToolMessage = "Edit mode: click a chunk to inspect it.";
                    PlaySound(clickSound);
                }

                GuiLabel(Rectangle(inspectorRect.x + 16.0f, inspectorRect.y + 144.0f, inspectorRect.width - 32.0f, 40.0f), chunkToolMessage.ptr);
                GuiLabel(Rectangle(inspectorRect.x + 16.0f, inspectorRect.y + 190.0f, inspectorRect.width - 32.0f, 24.0f), TextFormat("Snap Size: %d px", cast(int)gridLayout.cellSize));
                GuiLabel(Rectangle(inspectorRect.x + 16.0f, inspectorRect.y + 216.0f, inspectorRect.width - 32.0f, 24.0f), TextFormat("Chunks: %d", cast(int)placedChunks.length));
                GuiLabel(Rectangle(inspectorRect.x + 16.0f, inspectorRect.y + 242.0f, inspectorRect.width - 32.0f, 24.0f), TextFormat("Zoom: %d%%", cast(int)(mapCamera.zoom * 100.0f)));
                GuiLabel(Rectangle(inspectorRect.x + 16.0f, inspectorRect.y + 268.0f, inspectorRect.width - 32.0f, 24.0f), TextFormat("Camera: %d, %d", cast(int)mapCamera.target.x, cast(int)mapCamera.target.y));
                GuiLabel(Rectangle(inspectorRect.x + 16.0f, inspectorRect.y + 300.0f, inspectorRect.width - 32.0f, 24.0f), "Current Map:");
                GuiLabel(Rectangle(inspectorRect.x + 16.0f, inspectorRect.y + 326.0f, inspectorRect.width - 32.0f, 40.0f), selectedMapPath.ptr);

                if (selectedChunkIndex >= 0 && selectedChunkIndex < cast(int)placedChunks.length) {
                    const selectedChunk = placedChunks[selectedChunkIndex];
                    GuiLabel(Rectangle(inspectorRect.x + 16.0f, inspectorRect.y + 376.0f, inspectorRect.width - 32.0f, 24.0f), TextFormat("Selected Chunk: %d", selectedChunkIndex + 1));
                    GuiLabel(Rectangle(inspectorRect.x + 16.0f, inspectorRect.y + 402.0f, inspectorRect.width - 32.0f, 24.0f), TextFormat("Origin: %d, %d", selectedChunk.column, selectedChunk.row));
                    GuiLabel(Rectangle(inspectorRect.x + 16.0f, inspectorRect.y + 428.0f, inspectorRect.width - 32.0f, 24.0f), TextFormat("Size: %d x %d", selectedChunk.width, selectedChunk.height));
                } else {
                    GuiLabel(Rectangle(inspectorRect.x + 16.0f, inspectorRect.y + 376.0f, inspectorRect.width - 32.0f, 24.0f), "Selected Chunk: none");
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
                    editingChunkIndex,
                    editingChunk,
                    chunkGeometries[editingChunkIndex],
                    selectedPointIndices,
                    selectedFaceIndices,
                    showGrid,
                    chunkEditorTool
                );

                if (showInspector) {
                    GuiPanel(inspectorRect, "Chunk Editor");
                    GuiLabel(Rectangle(inspectorRect.x + 16.0f, inspectorRect.y + 42.0f, inspectorRect.width - 32.0f, 24.0f), TextFormat("Chunk %d", editingChunkIndex + 1));

                    if (GuiButton(Rectangle(inspectorRect.x + 16.0f, inspectorRect.y + 68.0f, 116.0f, 28.0f), "Place Point")) {
                        chunkEditorTool = ChunkEditorTool.placePoint;
                        chunkEditorMessage = "Point mode: click to place snapped points inside the chunk bounds.";
                        PlaySound(clickSound);
                    }
                    if (GuiButton(Rectangle(inspectorRect.x + 140.0f, inspectorRect.y + 68.0f, 116.0f, 28.0f), "Select")) {
                        chunkEditorTool = ChunkEditorTool.selectPoint;
                        chunkEditorMessage = "Select mode: click points or face centers.";
                        PlaySound(clickSound);
                    }

                    if (GuiButton(Rectangle(inspectorRect.x + 16.0f, inspectorRect.y + 104.0f, 116.0f, 28.0f), "Create Face")) {
                        if (selectedPointIndices.length >= 3) {
                            const orderedPointIndices = sortFacePointIndices(chunkGeometries[editingChunkIndex], selectedPointIndices);
                            if (faceOverlapsExistingFaces(chunkGeometries[editingChunkIndex], orderedPointIndices)) {
                                chunkEditorMessage = "Face is invalid: it overlaps another face or crosses itself.";
                                PlaySound(touchSound);
                            } else {
                                chunkGeometries[editingChunkIndex].faces ~= ChunkFace(orderedPointIndices.dup, 0, 16, 0);
                                selectedFaceIndices = [cast(int)chunkGeometries[editingChunkIndex].faces.length - 1];
                                selectedPointIndices.length = 0;
                                chunkEditorMessage = to!string(TextFormat("Created face %d.", selectedFaceIndices[0] + 1));
                                PlaySound(connectSound);
                            }
                        } else {
                            chunkEditorMessage = "Select at least 3 points to create a face.";
                            PlaySound(touchSound);
                        }
                    }

                    if (GuiButton(Rectangle(inspectorRect.x + 140.0f, inspectorRect.y + 104.0f, 116.0f, 28.0f), "Delete Face")) {
                        if (selectedFaceIndices.length > 0) {
                            auto faceIndicesToDelete = selectedFaceIndices.dup;
                            faceIndicesToDelete.sort!((a, b) => a > b);
                            foreach (faceIndex; faceIndicesToDelete) {
                                if (faceIndex >= 0 && faceIndex < cast(int)chunkGeometries[editingChunkIndex].faces.length) {
                                    removeFaceAt(chunkGeometries[editingChunkIndex], faceIndex);
                                }
                            }
                            chunkEditorMessage = to!string(TextFormat("Deleted %d face(s).", cast(int)faceIndicesToDelete.length));
                            selectedFaceIndices.length = 0;
                            PlaySound(deleteSound);
                        } else {
                            chunkEditorMessage = "Select one or more faces to delete.";
                            PlaySound(touchSound);
                        }
                    }

                    if (GuiButton(Rectangle(inspectorRect.x + 16.0f, inspectorRect.y + 140.0f, 116.0f, 28.0f), "Delete Point")) {
                        if (selectedPointIndices.length > 0) {
                            if (selectedPointsUsedByUnselectedFaces(chunkGeometries[editingChunkIndex], selectedPointIndices, selectedFaceIndices)) {
                                chunkEditorMessage = "Delete linked faces first, or select those faces too.";
                                PlaySound(touchSound);
                            } else {
                                auto pointIndicesToDelete = selectedPointIndices.dup;
                                pointIndicesToDelete.sort!((a, b) => a > b);
                                foreach (pointIndex; pointIndicesToDelete) {
                                    if (pointIndex >= 0 && pointIndex < cast(int)chunkGeometries[editingChunkIndex].points.length) {
                                        removePointAt(chunkGeometries[editingChunkIndex], pointIndex);
                                    }
                                }
                                selectedPointIndices.length = 0;
                                selectedFaceIndices.length = 0;
                                chunkEditorMessage = to!string(TextFormat("Deleted %d point(s).", cast(int)pointIndicesToDelete.length));
                                PlaySound(deleteSound);
                            }
                        } else {
                            chunkEditorMessage = "Select one or more points to delete.";
                            PlaySound(touchSound);
                        }
                    }

                    if (GuiButton(Rectangle(inspectorRect.x + 140.0f, inspectorRect.y + 140.0f, 116.0f, 28.0f), "Back to Map")) {
                        shouldReturnToMap = true;
                    }

                    GuiLabel(Rectangle(inspectorRect.x + 16.0f, inspectorRect.y + 178.0f, inspectorRect.width - 32.0f, 64.0f), chunkEditorMessage.ptr);
                    GuiLabel(Rectangle(inspectorRect.x + 16.0f, inspectorRect.y + 248.0f, inspectorRect.width - 32.0f, 24.0f), TextFormat("Bounds: %d x %d", editingChunk.width * cast(int)mapGridCellSize, editingChunk.height * cast(int)mapGridCellSize));
                    GuiLabel(Rectangle(inspectorRect.x + 16.0f, inspectorRect.y + 274.0f, inspectorRect.width - 32.0f, 24.0f), TextFormat("Points: %d", cast(int)chunkGeometries[editingChunkIndex].points.length));
                    GuiLabel(Rectangle(inspectorRect.x + 16.0f, inspectorRect.y + 300.0f, inspectorRect.width - 32.0f, 24.0f), TextFormat("Faces: %d", cast(int)chunkGeometries[editingChunkIndex].faces.length));
                    GuiLabel(Rectangle(inspectorRect.x + 16.0f, inspectorRect.y + 326.0f, inspectorRect.width - 32.0f, 24.0f), TextFormat("Zoom: %d%%", cast(int)(chunkEditorCamera.zoom * 100.0f)));
                    GuiLabel(Rectangle(inspectorRect.x + 16.0f, inspectorRect.y + 352.0f, inspectorRect.width - 32.0f, 24.0f), chunkEditorTool == ChunkEditorTool.placePoint ? "Tool: Place Point" : "Tool: Select");
                    GuiLabel(Rectangle(inspectorRect.x + 16.0f, inspectorRect.y + 388.0f, inspectorRect.width - 32.0f, 24.0f), TextFormat("Selected Points: %d", cast(int)selectedPointIndices.length));
                    GuiLabel(Rectangle(inspectorRect.x + 16.0f, inspectorRect.y + 414.0f, inspectorRect.width - 32.0f, 24.0f), TextFormat("Selected Faces: %d", cast(int)selectedFaceIndices.length));
                    GuiLabel(Rectangle(inspectorRect.x + 16.0f, inspectorRect.y + 440.0f, inspectorRect.width - 32.0f, 24.0f), "Faces are built from selected points in click order.");

                    if (shouldReturnToMap) {
                        appScreen = AppScreen.map;
                        selectedChunkIndex = editingChunkIndex;
                        selectedPointIndices.length = 0;
                        selectedFaceIndices.length = 0;
                        editingChunkIndex = -1;
                        chunkEditorMessage = "Returned to the map canvas.";
                        chunkToolMessage = "Edit mode: click a chunk to inspect it.";
                        PlaySound(clickSound);
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

        if (selectedToolbarIndex >= 0 && selectedToolbarIndex < cast(int)toolbarButtonRects.length) {
            const menuOptions = getMenuOptions(selectedToolbarIndex);
            const menuRect = getToolbarMenuRect(toolbarButtonRects[selectedToolbarIndex], menuOptions.length);

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
                        shouldExit
                    );
                    PlaySound(clickSound);
                    if (!shouldExit) {
                        selectedToolbarIndex = -1;
                    }
                }
            }
        }

    }

    StopMusicStream(oceanMusic);
    UnloadMusicStream(oceanMusic);
    UnloadSound(connectSound);
    UnloadSound(touchSound);
    UnloadSound(deleteSound);
    UnloadSound(moveSound);
    UnloadSound(placeSound);
    UnloadSound(clickSound);
    UnloadTexture(waterTexture);
    CloseAudioDevice();
    CloseWindow();
    return 0;
}
