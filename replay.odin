package main

import "core:encoding/json"
import "core:os"

REPLAY_VERSION :: 1

Replay_Header :: struct {
	kind: string,
	version: int,
	width, height: int,
	max_ticks: int,
	vm_snapshots: bool,
	map_name: string,
	team_names: [2]string,
	tiles: [ARENA_WIDTH * ARENA_HEIGHT]u8,
}

Replay_VM :: struct {
	registers: [8]u16,
	pc:        u16,
	cc:        u16,
}

Replay_Mouse :: struct {
	id: u16,
	team: int,
	x, y: int,
	facing: Direction,
	alive, has_cheese: bool,
	fault: Mouse_Error,
	vm: Replay_VM,
}

Replay_Spawner :: struct {
	x, y, delay: int,
	present: bool,
}

Replay_Drop :: struct {
	x, y: int,
	count: uint,
}

Replay_Turn :: struct {
	mouse_id: u16,
	action: string,
	direction: Direction,
	message: u16,
	fault: Mouse_Error,
}

Replay_Frame :: struct {
	kind: string,
	tick: int,
	scores: [2]uint,
	result: Game_Result,
	end_reason: Game_End_Reason,
	mice: [dynamic]Replay_Mouse,
	spawners: [dynamic]Replay_Spawner,
	dropped_cheese: [dynamic]Replay_Drop,
	turns: [dynamic]Replay_Turn,
}

replay_write_all :: proc(file: ^os.File, data: []u8) -> bool {
	remaining := data
	for len(remaining) > 0 {
		written, err := os.write(file, remaining)
		if err != nil || written <= 0 { return false }
		remaining = remaining[written:]
	}
	return true
}

replay_write_record :: proc(file: ^os.File, value: any) -> bool {
	data, err := json.marshal(value, {use_enum_names = true})
	if err != nil { return false }
	defer delete(data)
	return replay_write_all(file, data) && replay_write_all(file, []u8{'\n'})
}

replay_display_name :: proc(path: string) -> string {
	start := 0
	for character, index in path {
		if character == '/' || character == '\\' { start = index + 1 }
	}
	return path[start:]
}

replay_write_header :: proc(file: ^os.File, game: ^Game, map_name, team1_name, team2_name: string) -> bool {
	header := Replay_Header{
		kind = "header",
		version = REPLAY_VERSION,
		width = ARENA_WIDTH,
		height = ARENA_HEIGHT,
		max_ticks = MAX_GAME_STEPS,
		vm_snapshots = true,
		map_name = replay_display_name(map_name),
		team_names = {replay_display_name(team1_name), replay_display_name(team2_name)},
	}
	for tile, i in game.arena.tiles { header.tiles[i] = u8(tile) }
	return replay_write_record(file, header)
}

replay_capture_frame :: proc(game: ^Game) -> Replay_Frame {
	frame := Replay_Frame{
		kind = "frame",
		tick = game.tick,
		scores = {game.teams[.One].score, game.teams[.Two].score},
		result = game.result,
		end_reason = game.end_reason,
	}
	for team in game.teams {
		for &mouse in team.mice {
			append(&frame.mice, Replay_Mouse{
				id = u16(mouse.id), team = int(mouse.team) + 1,
				x = mouse.pos.x, y = mouse.pos.y, facing = mouse.facing,
				alive = mouse.state == .Alive, has_cheese = mouse.has_cheese,
				fault = mouse.fault,
				vm = Replay_VM{
					registers = mouse.vm.registers,
					pc        = mouse.vm.pc,
					cc        = u16(mouse.vm.cc),
				},
			})
		}
	}
	for spawner in game.arena.cheese_spawners {
		append(&frame.spawners, Replay_Spawner{
			x = spawner.pos.x, y = spawner.pos.y,
			delay = spawner.delay, present = spawner.present,
		})
	}
	for count, index in game.arena.dropped_cheese {
		if count == 0 { continue }
		append(&frame.dropped_cheese, Replay_Drop{
			x = index % ARENA_WIDTH, y = index / ARENA_WIDTH, count = count,
		})
	}
	for turn in game.turns {
		record := Replay_Turn{mouse_id = u16(turn.mouse_id), action = "wait", fault = turn.fault}
		switch action in turn.action {
		case Move_Action:
			record.action = "move"
			record.direction = action.direction
		case Attack_Action:
			record.action = "attack"
		case Squeak_Action:
			record.action = "squeak"
			record.message = action.message
		case:
		}
		append(&frame.turns, record)
	}
	return frame
}

replay_destroy_frame :: proc(frame: ^Replay_Frame) {
	delete(frame.mice)
	delete(frame.spawners)
	delete(frame.dropped_cheese)
	delete(frame.turns)
}

replay_write_frame :: proc(file: ^os.File, game: ^Game) -> bool {
	frame := replay_capture_frame(game)
	defer replay_destroy_frame(&frame)
	return replay_write_record(file, frame)
}
