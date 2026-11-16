package main

import "core:os"
import "core:strings"

Team :: enum {
	One,
	Two
}

Game :: struct {
	arena: Arena
}

game_load_map :: proc(game: ^Game, file_path: string) -> bool {
	data, err := os.read_entire_file_from_path(file_path, context.allocator)
	if err != nil {
		return false
	}
	defer delete(data, context.allocator)

	has_altar := false
	iterator := string(data)
	for line in strings.split_lines_iterator(&iterator) {
		fields := strings.fields(line)
		defer delete(fields)

		if len(fields) < 2 {
			return false
		}

		switch (fields[0]) {
		case "SYMMETRY":
			if (fields[1] == "HORIZONTAL") {
				game.arena.symmetry = .Horizontal
			} else if (fields[1] == "VERTICAL") {
				game.arena.symmetry = .Vertical
			} else {
				// TODO: Return Better Error
				return false
			}
		case "ALTAR":
			if has_altar { return false }
			altar_coord, altar_coord_ok := parse_coordinate(fields[1])
			if !altar_coord_ok {return false}

			if altar_coord.y >= ARENA_HEIGHT - 1 || altar_coord.x >= ARENA_WIDTH - 1{
				return false
			}
			
			altar_coords := [4]int{
				altar_coord.y * ARENA_WIDTH + altar_coord.x,
				(altar_coord.y + 1) * ARENA_WIDTH + altar_coord.x,
				altar_coord.y * ARENA_WIDTH + (altar_coord.x + 1),
				(altar_coord.y + 1) * ARENA_WIDTH + (altar_coord.x + 1),
			}

			for coord in altar_coords {
				if game.arena.tiles[coord] != .Floor {
					return false
				}

				game.arena.tiles[coord] = .Altar_Team_1
			}
			has_altar = true
		case "WALL":
			wall_coord, wall_coord_ok := parse_coordinate(fields[1])
			if !wall_coord_ok { return false }
			
			arena_coord := wall_coord.y * ARENA_WIDTH + wall_coord.x
			if game.arena.tiles[arena_coord] != .Floor {
				return false
			}

			game.arena.tiles[arena_coord] = .Wall
		case:
			return false
		}

	}

	if !has_altar { return false; }

	arena_reflect(&game.arena)

	return true
}
