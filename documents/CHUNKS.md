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
f y0 y1 (yMin and yMax are used for rendering the sectors)

s x z
s x z 
s x z
p 12
f y0 y1 (yMin and yMax are used for rendering the sectors)

w x z
w x z   
p 4
. . . continue til the end of the walls
f y0 y1 (yMin and yMax are used for rendering the walls)

w x z
w x z   
p 8
. . . continue til the end of the walls
f y0 y1 (yMin and yMax are used for rendering the walls)

o x y z i (contains the position and the data index of the object)
. . . continue til the end of the objects
e x z i (contains the position and the data index of the entity)
e x z i (contains the position and the data index of the entity)
. . . continue til the end of the entities
ok
```
This is a lot to break down, so let's go through it step by step.

## Chunk Init
The first line of the chunk data in the `.leaf` file is the chunk init. This line starts with an `i` and is followed by the maximum amount of points in the chunk. This is used to determine how many points are in the chunk and how much memory to allocate for them.

# Palette
Palettes, represented by a `p` followed by the palette index, are used to define the colors of the sector or walls, which is used for rendering the map. The palette index is used to determine which palette to use for rendering the sector or wall, and it can be used to create different visual styles for the map. The palette index does not affect the collision detection or the position of objects in the map, so it is only used for rendering purposes.

## Sector Walls
The sector walls's `f` stores both the minimum and maximum "floor" and "ceiling" heights of the sector. This is used for rendering the sectors in the map, but it does not affect the collision detection or the position of objects in the map. The sector walls are used to define the shape of the sectors in the map, and they are double sided, meaning that they can be seen from both sides.

## Chunk Bounds
The chunk bounds are on the second line and are represented by a `c` followed by the minimum and maximum x and z coordinates of the chunk. This is used to determine if a point, wall, or object is within the chunk. When considering the limitations of the y axis, no boundaries are necessary, because the y axis is only used for rendering and does not affect the chunk's content.

## Points
The next number of lines after the chunk bounds are the points. Each sector point is represented by an `s` followed by the x and z coordinates of the point. These points are used to define the shape of the sectors in the map.

## Walls
Walls are the same as sectors, except these are double sided and are represented by a `w` followed by the x and z coordinates of the wall. These walls are used to define the shape of the walls in the map. The `f` after the walls is used to define the minimum and maximum heights of the walls, which is used for rendering the walls in the map.

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
The faces of the map would work similarly to the walls, but they would be used for rendering height differences in the map. Similiar to DOOM, the faces would be defined by the points in the chunk and would be used to create the visual appearance of the map. However, they would not affect the collision detection or the position of objects in the map, so they would not be included in the chunk data.