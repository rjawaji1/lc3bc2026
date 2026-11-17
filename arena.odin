package main

import "core:strconv"
import "core:strings"

ARENA_WIDTH :: 16
ARENA_HEIGHT :: 16

CHEESE_SPAWN_TICKS :: 5

Tile :: enum {
	Floor,
	Wall,
	Altar_Team_1,
	Altar_Team_2,
}

Symmetry :: enum {
	Horizontal,
	Vertical,
}

Cheese_Spawn :: struct {
	delay:   int,
	present: bool,
	pos:     Coordinate
}

Arena :: struct {
	tiles:    [ARENA_HEIGHT * ARENA_WIDTH]Tile,
	cheese_spawners: [dynamic]Cheese_Spawn,
	dropped_cheese: [ARENA_HEIGHT * ARENA_WIDTH]uint,
	symmetry: Symmetry,
}

Coordinate :: struct {
	x: int,
	y: int,
}

coordinate_in_bounds :: proc(position: Coordinate) -> bool {
	return position.x >= 0 && position.x < ARENA_WIDTH &&
	       position.y >= 0 && position.y < ARENA_HEIGHT
}

coordinate_in_source_half :: proc(position: Coordinate, symmetry: Symmetry) -> bool {
	if !coordinate_in_bounds(position) { return false }
	if symmetry == .Vertical { return position.x < ARENA_WIDTH / 2 }
	return position.y < ARENA_HEIGHT / 2
}

arena_has_cheese :: proc(arena: ^Arena, position: Coordinate) -> bool {
	if !coordinate_in_bounds(position) { return false }
	if arena.dropped_cheese[position.y * ARENA_WIDTH + position.x] > 0 {
		return true
	}
	for spawner in arena.cheese_spawners {
		if spawner.pos == position && spawner.present { return true }
	}
	return false
}

arena_take_cheese :: proc(arena: ^Arena, position: Coordinate) -> bool {
	if !coordinate_in_bounds(position) { return false }
	index := position.y * ARENA_WIDTH + position.x
	if arena.dropped_cheese[index] > 0 {
		arena.dropped_cheese[index] -= 1
		return true
	}
	for &spawner in arena.cheese_spawners {
		if spawner.pos == position && spawner.present {
			spawner.present = false
			spawner.delay = CHEESE_SPAWN_TICKS
			return true
		}
	}
	return false
}

arena_drop_cheese :: proc(arena: ^Arena, position: Coordinate) {
	if !coordinate_in_bounds(position) { return }
	for &spawner in arena.cheese_spawners {
		if spawner.pos == position && !spawner.present {
			spawner.present = true
			return
		}
	}
	arena.dropped_cheese[position.y * ARENA_WIDTH + position.x] += 1
}

arena_destroy :: proc(arena: ^Arena){
	delete(arena.cheese_spawners)
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

	source_count := len(arena.cheese_spawners)
	for i in 0..<source_count {
		spawner := arena.cheese_spawners[i]
		switch arena.symmetry {
		case .Vertical:
			spawner.pos.x = ARENA_WIDTH - 1 - spawner.pos.x
		case .Horizontal:
			spawner.pos.y = ARENA_HEIGHT - 1 - spawner.pos.y
		}
		append(&arena.cheese_spawners, spawner)
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
