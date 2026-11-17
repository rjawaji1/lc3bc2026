package main

import "core:strconv"
import "core:fmt"
import "core:os"
import "core:strings"

MAX_GAME_STEPS :: 10_000

Team :: enum {
	One,
	Two,
}

Team_State :: struct {
	mice: [dynamic]Mouse,
	score: uint,
}

Mouse_Turn :: struct {
	mouse_id: Mouse_ID,
	action: Mouse_Action,
	fault: Mouse_Error,
}

Game_Result :: enum {
	Undecided,
	Team_One_Won,
	Team_Two_Won,
	Draw,
}

Game_End_Reason :: enum {
	None,
	Elimination,
	Tick_Limit,
}

Game :: struct {
	arena: Arena,
	teams: [Team]Team_State,
	last_mouse_id: Mouse_ID,
	turns: [dynamic]Mouse_Turn,
	tick: int,
	result: Game_Result,
	end_reason: Game_End_Reason,
}

@(private="file")
game_allocate_mouse_id :: proc(game: ^Game) -> Mouse_ID {
	fmt.assertf(game.last_mouse_id < Mouse_ID(0xffff), "Mouse IDs exhausted")
	game.last_mouse_id += 1
	return game.last_mouse_id
}

game_find_mouse :: proc(game: ^Game, id: Mouse_ID) -> ^Mouse {
	if id == INVALID_MOUSE_ID {
		return nil
	}

	for team in game.teams {
		for &mouse in team.mice {
			if mouse.id == id {
				return &mouse
			}
		}
	}
	return nil
}

game_init :: proc(
	game: ^Game,
	map_filepath: string,
	team1_filepath: string,
	team2_filepath: string,
) -> bool {
	if !game_load_map(game, map_filepath) {
		fmt.eprintf("Unable to load map: %s\n", map_filepath)
		return false
	}
	if len(game.teams[.One].mice) == 0 || len(game.teams[.Two].mice) == 0 {
		fmt.eprintln("Map must contain at least one mouse per team")
		return false
	}

	team1_code, team1_load_err := os.read_entire_file_from_path(team1_filepath, context.allocator)
	if team1_load_err != nil {
		fmt.eprintf("Unable to read Team 1 program: %s\n", team1_filepath)
		return false
	}
	defer delete(team1_code)

	team2_code, team2_load_err := os.read_entire_file_from_path(team2_filepath, context.allocator)
	if team2_load_err != nil {
		fmt.eprintf("Unable to read Team 2 program: %s\n", team2_filepath)
		return false
	}
	defer delete(team2_code)

	for &mouse in game.teams[.One].mice {
		ok := mouse_init(&mouse, team1_code)
		if !ok {
			fmt.eprintf("Invalid Team 1 LC-3 program: %s\n", team1_filepath)
			return false
		}
		mouse_sync_map_observations(&mouse, &game.arena)
	}

	for &mouse in game.teams[.Two].mice {
		ok := mouse_init(&mouse, team2_code)
		if !ok {
			fmt.eprintf("Invalid Team 2 LC-3 program: %s\n", team2_filepath)
			return false
		}
		mouse_sync_map_observations(&mouse, &game.arena)
	}
	return true
}

game_step :: proc(game: ^Game){
	game_update_result(game)
	if game.result != .Undecided { return }

	game_tick_cheese(game)
	game_collect_actions(game)
	game_resolve_faults(game)
	game_resolve_combat(game)
	game_resolve_movement(game)
	game_collect_cheese(game)
	game_deposit_cheese(game)

	game.tick += 1
	game_update_result(game)
}

game_tick_cheese :: proc(game: ^Game) {
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

}

game_destroy :: proc(game: ^Game){
	for team in game.teams {
		for &mouse in team.mice {
			mouse_destroy(&mouse)
		}
		delete(team.mice)
	}

	delete(game.turns)
	arena_destroy(&game.arena)
	game^ = {}
}

@(private="file")
game_map_error :: proc(line: int, message: string) -> bool {
	if line > 0 {
		fmt.eprintf("Map line %d: %s\n", line, message)
	} else {
		fmt.eprintf("Invalid map: %s\n", message)
	}
	return false
}

game_load_map :: proc(game: ^Game, file_path: string) -> bool {
	data, err := os.read_entire_file_from_path(file_path, context.allocator)
	if err != nil { return false }
	defer delete(data)

	has_symmetry := false
	has_altar := false
	line_number := 0
	iterator := string(data)
	for raw_line in strings.split_lines_iterator(&iterator) {
		line_number += 1
		line := raw_line
		if comment := strings.index_byte(line, '#'); comment >= 0 {
			line = line[:comment]
		}
		fields := strings.fields(line)
		defer delete(fields)
		if len(fields) == 0 { continue }

		expected := 2
		if fields[0] == "CHEESE" { expected = 3 }
		if len(fields) != expected {
			return game_map_error(line_number, "wrong number of arguments")
		}

		switch fields[0] {
		case "SYMMETRY":
			if has_symmetry {
				return game_map_error(line_number, "duplicate SYMMETRY declaration")
			}
			switch fields[1] {
			case "HORIZONTAL": game.arena.symmetry = .Horizontal
			case "VERTICAL": game.arena.symmetry = .Vertical
			case: return game_map_error(line_number, "expected HORIZONTAL or VERTICAL")
			}
			has_symmetry = true

		case "ALTAR":
			if has_altar { return game_map_error(line_number, "only one source altar is allowed") }
			position, ok := parse_coordinate(fields[1])
			if !ok || position.x >= ARENA_WIDTH-1 || position.y >= ARENA_HEIGHT-1 {
				return game_map_error(line_number, "altar must fit a 2x2 square inside the map")
			}
			for y in position.y..<position.y+2 {
				for x in position.x..<position.x+2 {
					index := y * ARENA_WIDTH + x
					if game.arena.tiles[index] != .Floor {
						return game_map_error(line_number, "altar overlaps terrain")
					}
					game.arena.tiles[index] = .Altar_Team_1
				}
			}
			has_altar = true

		case "WALL":
			position, ok := parse_coordinate(fields[1])
			if !ok { return game_map_error(line_number, "invalid wall coordinate") }
			index := position.y * ARENA_WIDTH + position.x
			if game.arena.tiles[index] != .Floor {
				return game_map_error(line_number, "wall overlaps terrain")
			}
			game.arena.tiles[index] = .Wall

		case "MOUSE":
			position, ok := parse_coordinate(fields[1])
			if !ok { return game_map_error(line_number, "invalid mouse coordinate") }
			if len(game.teams[.One].mice) >= ARENA_WIDTH * ARENA_HEIGHT / 2 {
				return game_map_error(line_number, "too many source mice")
			}
			mouse := Mouse{
				id = game_allocate_mouse_id(game),
				pos = position,
				team = .One,
			}
			append(&game.teams[.One].mice, mouse)

		case "CHEESE":
			position, ok := parse_coordinate(fields[1])
			if !ok { return game_map_error(line_number, "invalid cheese coordinate") }
			delay, delay_ok := strconv.parse_int(fields[2])
			if !delay_ok || delay < 0 {
				return game_map_error(line_number, "cheese delay must be a nonnegative integer")
			}
			for spawner in game.arena.cheese_spawners {
				if spawner.pos == position {
					return game_map_error(line_number, "duplicate cheese spawner")
				}
			}
			append(&game.arena.cheese_spawners, Cheese_Spawn{
				pos = position,
				delay = delay,
				present = delay == 0,
			})

		case:
			return game_map_error(line_number, "unknown map keyword")
		}
	}

	if !has_symmetry { return game_map_error(0, "missing SYMMETRY") }
	if !has_altar { return game_map_error(0, "missing ALTAR") }
	if len(game.teams[.One].mice) == 0 { return game_map_error(0, "missing MOUSE") }

	for tile, index in game.arena.tiles {
		if tile == .Floor { continue }
		position := Coordinate{index % ARENA_WIDTH, index / ARENA_WIDTH}
		if !coordinate_in_source_half(position, game.arena.symmetry) {
			return game_map_error(0, "terrain and the full altar must be in the source half")
		}
	}

	occupied: [ARENA_WIDTH * ARENA_HEIGHT]bool
	for &mouse in game.teams[.One].mice {
		index := mouse.pos.y * ARENA_WIDTH + mouse.pos.x
		if !coordinate_in_source_half(mouse.pos, game.arena.symmetry) ||
		   game.arena.tiles[index] != .Floor || occupied[index] {
			return game_map_error(0, "mice must occupy distinct floor cells in the source half")
		}
		occupied[index] = true
	}
	for spawner in game.arena.cheese_spawners {
		index := spawner.pos.y * ARENA_WIDTH + spawner.pos.x
		if !coordinate_in_source_half(spawner.pos, game.arena.symmetry) ||
		   game.arena.tiles[index] != .Floor {
			return game_map_error(0, "cheese spawners must occupy floor cells in the source half")
		}
	}

	game_reflect(game)
	return true
}

game_reflect :: proc(game: ^Game) {
	arena_reflect(&game.arena)

	for &mouse in game.teams[.One].mice {
		mouse.facing = .East if game.arena.symmetry == .Vertical else .South
		mouse_2: Mouse
		mouse_2.id = game_allocate_mouse_id(game)
		mouse_2.team = .Two
		mouse_2.facing = .West if game.arena.symmetry == .Vertical else .North
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
