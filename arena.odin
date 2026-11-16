package main

import "core:strconv"
import "core:strings"

ARENA_WIDTH :: 16
ARENA_HEIGHT :: 16

Tile :: enum {
	Floor,
	Wall,
	Altar_Team_1,
	Altar_Team_2
}

Symmetry :: enum {
	Horizontal,
	Vertical,
}

Arena :: struct {
	tiles:    [ARENA_HEIGHT * ARENA_WIDTH]Tile,
	symmetry: Symmetry,
}

Coordinate :: struct {
	x: int,
	y: int,
}


arena_reflect :: proc(arena: ^Arena){
	switch arena.symmetry {
	case .Vertical:
		for y in 0..<ARENA_HEIGHT {
			for x in 0..<(ARENA_WIDTH / 2) {
				source := y * ARENA_WIDTH + x
				target := y * ARENA_WIDTH + (ARENA_WIDTH - 1 - x)

				arena.tiles[target] = arena.tiles[source] if arena.tiles[source] != .Altar_Team_1 else .Altar_Team_2
			}
		}
	case .Horizontal:
		for y in 0..<(ARENA_HEIGHT / 2) {
			for x in 0..<ARENA_WIDTH {
				source := y * ARENA_WIDTH + x
				target := (ARENA_HEIGHT - 1 - y) * ARENA_WIDTH + x

				arena.tiles[target] = arena.tiles[source] if arena.tiles[source] != .Altar_Team_1 else .Altar_Team_2
			}
		}
	}
}

parse_coordinate :: proc(str_coord: string) -> (Coordinate, bool) {
	coord := strings.split(str_coord, ",")
	defer delete(coord)

	if len(coord) != 2 {
		return {}, false
	}

	coord_x, coord_x_ok := strconv.parse_int(coord[0])
	if !coord_x_ok || coord_x < 0 || coord_x >= ARENA_WIDTH {
		return {}, false
	}

	coord_y, coord_y_ok := strconv.parse_int(coord[1])
	if !coord_y_ok || coord_y < 0 || coord_y >= ARENA_HEIGHT {
		return {}, false
	}

	return {x = coord_x, y = coord_y}, true
}
