# Leafway
#### Chunk Explaination

We plan on putting the content of map data into a `.leaf` file. This is a custom made file that will provide information on how many walls, points, and sectors are in the map. Here's a brief example:
```
i [MAX_POINTS] (this is the sector wall and object point amount)
c chunkMinX chunkMinZ chunkMaxX chunkMaxZ
s x z
s x z 
s x z
p 0
. . . continue til the end of the points
f y0 y1 (y0 and y1 are the floor and ceiling values for the sector)

s x z
s x z 
s x z
p 12
f y0 y1 (y0 and y1 are the floor and ceiling values for the sector)

w x z
w x z   
p 4
. . . continue til the end of the walls
f y0 y1 (y0 and y1 are the floor and ceiling values for the wall)

w x z
w x z   
p 8
. . . continue til the end of the walls
f y0 y1 (y0 and y1 are the floor and ceiling values for the wall)

o x y z rx ry rz sx sy sz i (contains the position, rotation, scale, and the data index of the object)
. . . continue til the end of the objects   
e x z rx ry rz sx sy sz i (contains the position, rotation, scale, and the data index of the entity)
e x z rx ry rz sx sy sz i (contains the position, rotation, scale, and the data index of the entity)
. . . continue til the end of the entities
ok
```
This is a lot to break down, so let's go through it step by step.

## Chunk Init
The first line of the chunk data in the `.leaf` file is the chunk init. This line starts with an `i` and is followed by the maximum amount of points in the chunk. This is used to determine how many points are in the chunk and how much memory to allocate for them.

# Palette
Palettes, represented by a `p` followed by the palette index, are used to define the colors of the sector or walls, which is used for rendering the map. The palette index is used to determine which palette to use for rendering the sector or wall, and it can be used to create different visual styles for the map. The palette index does not affect the collision detection or the position of objects in the map, so it is only used for rendering purposes.

## Sector Heights
Each sector uses `f y0 y1` to store its floor and ceiling values. In editor terms this is the height range for the sector or face. This is used for rendering the sector in the map, but it does not affect the position of objects in the map.

## Chunk Bounds
The chunk bounds are on the second line and are represented by a `c` followed by the minimum and maximum x and z coordinates of the chunk. This is used to determine if a point, wall, or object is within the chunk. When considering the limitations of the y axis, no boundaries are necessary, because the y axis is only used for rendering and does not affect the chunk's content.

## Points
The next number of lines after the chunk bounds are the points. Each sector point is represented by an `s` followed by the x and z coordinates of the point. These points are used to define the shape of the sectors in the map.

## Walls
Walls are represented by a `w` followed by the x and z coordinates of the wall. Like sectors, walls also use `f y0 y1` to define their floor and ceiling values. In other words, both sectors and walls carry a height range, but they are different primitives in the editor and in the map format.

## Objects
Objects are represented by an `o` followed by the x, y, and z coordinates of the object, as well as the data index of the object. These objects are used to define the position and type of objects in the map.

### Rules with Objects
Objects and the map itself are separate, meaning that slopes are doable with objects. However, its probably not advised to collide on top of objects, because they are not part of the map and can cause issues with collision detection. Objects are also not used for rendering, so they will not affect the visual appearance of the map. They are only used for defining the position and type of objects in the map, so they should be used for things like enemies, items, and other interactive objects in the map.

## Entity
The entity is represented by an `e` and is used to define the position and type of entities in the map. Entities are used to define the position and type of enemies, items, and other interactive objects in the map.

## End of Chunk
The end of the chunk data is represented by an `ok`. This is used to indicate that the chunk data has been fully read and that the chunk can be processed. An "OK" is used instead of an "END" because it is shorter and easier to read.

## Why not include slopes?
They are not necessary for the chunk data because they do not affect the chunk's content. Slopes are only used for rendering and do not affect the position of points, walls, or objects in the chunk. Therefore, they are not included in the chunk data.

It's also worth noting that the chunk data takes inspiration from the original DOOM map format, which also did not include slopes in the map data. This is because slopes can be calculated based on the points and walls in the chunk, and including them in the chunk data would be redundant.

## Faces
In the editor, faces are the sector-style polygons built from chunk points. They carry the same `y0/y1` idea as sectors: a floor value and a ceiling value. Walls also carry `y0/y1`, but they are edge primitives instead of area primitives.

# Update
## The .lm File
```
lm [MAP_NAME]
[CHUNK_AMOUNT]
chunk chunkMinX chunkMinZ chunkMaxX chunkMaxZ
i [MAX_POINTS] (this is the sector wall and object point amount)
s x z
s x z
s x z
p 12
f y0 y1 (y0 and y1 are the floor and ceiling values for the sector)

s x z
s x z
s x z
p 12
f y0 y1 (y0 and y1 are the floor and ceiling values for the sector)

w x z
w x z
p 4
f y0 y1 (y0 and y1 are the floor and ceiling values for the wall)

w x z
w x z
p 8
f y0 y1 (y0 and y1 are the floor and ceiling values for the wall)

o x y z rx ry rz sx sy sz i (contains the position, rotation, scale, and the data index of the object)
o x y z rx ry rz sx sy sz i (contains the position, rotation, scale, and the data index of the object)
. . . continue til the end of the objects
e x z rx ry rz sx sy sz i (contains the position, rotation, scale, and the data index of the entity)
e x z rx ry rz sx sy sz i (contains the position, rotation, scale, and the data index of the entity)
. . . continue til the end of the entities
ok
chunk chunkMinX chunkMinZ chunkMaxX chunkMaxZ
i [MAX_POINTS] (this is the sector wall and object point amount)
s x z
s x z
s x z
p 12
f y0 y1 (y0 and y1 are the floor and ceiling values for the sector)

w x z
w x z
p 4
f y0 y1 (y0 and y1 are the floor and ceiling values for the wall)

w x z
w x z
p 8
f y0 y1 (y0 and y1 are the floor and ceiling values for the wall)

o x y z rx ry rz sx sy sz i (contains the position, rotation, scale, and the data index of the object)
o x y z rx ry rz sx sy sz i (contains the position, rotation, scale, and the data index of the object)
. . . continue til the end of the objects
e x z rx ry rz sx sy sz i (contains the position, rotation, scale, and the data index of the entity)
e x z rx ry rz sx sy sz i (contains the position, rotation, scale, and the data index of the entity)
. . . continue til the end of the entities
ok
```

This new file type pretty much replaces the old `.leaf` file. The main difference is that all chunks are stored in a single file rather than each file being a separate chunk. This makes it easier to manage and load the map data, as well as reducing the number of files needed for a map. The `.lm` file also includes the map name and the amount of chunks in the map, which can be used for loading and managing the map data.