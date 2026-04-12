# Leafway
#### Plan

## Overview
Leafway is a 3D map creator that is designed for use for 3D levels on the Playdate. The goal of Leafway is to provide a simple an intuitive interface for creating simple 3D maps that the Playdate can handle. The maps created with Leafway will be used for a variety of purposes, including games, demos, and other interactive experiences on the Playdate.

This program in particular is focused on making maps for "Green Leaf Fishing," a 3D fishing game on the Playdate. The maps created with Leafway will be used as the fishing locations in the game, and will be designed to provide a variety of fishing experiences for the player.

## Map Format
You can look at the [chunk documentation](./CHUNKS.md) for more information on the map format, but in short, the map data will be stored in a custom `.leaf` file that contains information on the points, walls, objects, and entities in the map. The map data is designed to be simple and easy to read, while also providing enough information to create complex and interesting maps for the Playdate.

### How can we make these maps?
Good question. Basically what needs to happen is that the user will be given a blank canvas, alongwith a grid of chunks. The user can start from one chunk and start placing points, walls, and objects in the chunk. The user can then move on to the next chunk and continue placing points, walls, and objects until they have created a complete map. The user can also go back and edit previous chunks if they want to make changes to the map.

## Map Editor
The map editor will be a simple and intuitive interface that allows the user to easily place points, and raise faces or sectors to create the map. The user will be able to select different tools for placing points, walls, and objects, and will be able to easily switch between chunks to continue building their map. The map editor will also provide a variety of options for customizing the appearance of the map, such as changing the colors of the points, walls, and objects, and adjusting the lighting and shading of the map.

## Coloring 
Since the Playdate has a black and white screen, the maps created with leafway will be designed to be as such. However, the map editor will provide options for "coloring", which will be in forms of dithering, patterns, and other techniques that can be used to create the illusion of color on the Playdate's screen. The user will be able to choose from a variety of different patterns and dithering techniques to create the desired look for their map, and will be able to easily switch between different patterns and techniques to see how they affect the appearance of the map.

