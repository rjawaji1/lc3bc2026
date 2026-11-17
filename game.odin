package main

import "core:strconv"
import "core:fmt"
import "core:os"
import "core:strings"

import lc3 "vendor/liblc3"

MAX_GAME_STEPS :: 10_000

Team :: enum {
	One,
	Two,
}

Team_State :: struct {
	mice: [dynamic]Mouse,
	score: uint,
}

Game :: struct {
	arena: Arena,
	teams: [Team]Team_State,
}

game_init :: proc(
	game: ^Game,
	map_filepath: string,
	team1_filepath: string,
	team2_filepath: string,
){
	if !game_load_map(game, map_filepath) {
		return
	}

	team1_code, team1_load_err := os.read_entire_file_from_path(team1_filepath, context.allocator)
	if team1_load_err != nil {
		fmt.print("Unable to load Team 1 Code")
	}
	defer delete(team1_code)

	team2_code, team2_load_err := os.read_entire_file_from_path(team2_filepath, context.allocator)
	if team2_load_err != nil {
		fmt.print("Unable to load Team 1 Code")
	}
	defer delete(team2_code)

	for &mouse in game.teams[.One].mice {
		ok := mouse_init(&mouse, team1_code)
		if !ok {
			// TODO: Better Error Handling
			return
		}
	}

	for &mouse in game.teams[.Two].mice {
		ok := mouse_init(&mouse, team2_code)
		if !ok {
			// TODO: Better Error Handling
			return
		}
	}
}

game_step :: proc(game: ^Game){
	// Reset Mice
	for team in game.teams {
		for &mouse in team.mice {
			mouse_reset(&mouse)
		}
	}

	// Step Through
	for team in game.teams {
		for &mouse in team.mice {
			action, run_err := mouse_run(&mouse)
			if run_err != .None {
				// Kill Mouse
			}
		}
	}

	// Process Mice Actions
	
	// Collect Cheese

	// Count Down Cheese timers
	for &cheese_spawner in game.arena.cheese_spawners {
		if cheese_spawner.present { continue }

		if cheese_spawner.delay > 0 {
			cheese_spawner.delay -= 1
		}

		if cheese_spawner.delay == 0 {
			cheese_spawner.delay = CHEESE_SPAWN_TICKS
			cheese_spawner.present = true
		}
	}

	// Sync Mouse Map State
}

game_destroy :: proc(game: ^Game){
	for team in game.teams {
		for &mouse in team.mice {
			lc3.destroy(&mouse.vm)
		}
		delete(team.mice)
	}

	arena_destroy(&game.arena)
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

		case "MOUSE":
			mouse_coord, mouse_coord_ok := parse_coordinate(fields[1])
			if !mouse_coord_ok { return false }

			mouse: Mouse
			mouse.pos = mouse_coord
			mouse.team = .One

			append(&game.teams[.One].mice, mouse)

		case "CHEESE":
			cheese_coords, cheese_coord_ok := parse_coordinate(fields[1])
			if !cheese_coord_ok { return false; }

			cheese_spawn_timer, cheese_spawn_timer_ok := strconv.parse_int(fields[2])
			if !cheese_spawn_timer_ok || cheese_spawn_timer < 0 { return false; }


		case:
			return false
		}

	}

	if !has_altar { return false }

	game_reflect(game)

	return true
}

game_reflect :: proc(game: ^Game) {
	arena_reflect(&game.arena)

	for mouse in game.teams[.One].mice {
		mouse_2: Mouse
		mouse_2.team = .Two
		mouse_2.pos = mouse.pos

		switch game.arena.symmetry {
		case .Vertical:
			mouse_2.pos.x = ARENA_WIDTH - 1 - mouse.pos.x
		case .Horizontal:
			mouse_2.pos.y = ARENA_HEIGHT - 1 - mouse.pos.y
		}

		append(&game.teams[.Two].mice, mouse_2)
	}
}
