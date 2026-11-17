package main

game_collect_actions :: proc(game: ^Game) {
	clear(&game.turns)
	for team in game.teams {
		for &mouse in team.mice {
			if mouse.state != .Alive { continue }
			mouse_reset(&mouse)
			mouse_sync_map_observations(&mouse, &game.arena)
			action, fault := mouse_run(&mouse)
			append(&game.turns, Mouse_Turn{
				mouse_id = mouse.id,
				action = action,
				fault = fault,
			})
		}
	}
}

game_kill_mouse :: proc(game: ^Game, mouse: ^Mouse) {
	if mouse == nil || mouse.state == .Dead { return }
	mouse.state = .Dead
	mouse.action = nil
	if mouse.has_cheese {
		arena_drop_cheese(&game.arena, mouse.pos)
		mouse.has_cheese = false
	}
}

game_resolve_faults :: proc(game: ^Game) {
	for turn in game.turns {
		if turn.fault == .None { continue }
		mouse := game_find_mouse(game, turn.mouse_id)
		if mouse == nil || mouse.state != .Alive { continue }
		mouse.fault = turn.fault
		game_kill_mouse(game, mouse)
	}
}

mouse_move_destination :: proc(position: Coordinate, direction: Direction) -> Coordinate {
	destination := position
	switch direction {
	case .North: destination.y -= 1
	case .East: destination.x += 1
	case .South: destination.y += 1
	case .West: destination.x -= 1
	}
	return destination
}

game_resolve_combat :: proc(game: ^Game) {
	occupants: [ARENA_WIDTH * ARENA_HEIGHT]^Mouse
	victims: [ARENA_WIDTH * ARENA_HEIGHT]bool
	for team in game.teams {
		for &mouse in team.mice {
			if mouse.state != .Alive || !coordinate_in_bounds(mouse.pos) { continue }
			occupants[mouse.pos.y * ARENA_WIDTH + mouse.pos.x] = &mouse
		}
	}

	for turn in game.turns {
		if turn.fault != .None { continue }
		_, is_attack := turn.action.(Attack_Action)
		if !is_attack { continue }
		attacker := game_find_mouse(game, turn.mouse_id)
		if attacker == nil || attacker.state != .Alive || !coordinate_in_bounds(attacker.pos) {
			continue
		}
		target := mouse_move_destination(attacker.pos, attacker.facing)
		if !coordinate_in_bounds(target) { continue }
		index := target.y * ARENA_WIDTH + target.x
		if game.arena.tiles[index] == .Wall { continue }
		victim := occupants[index]
		if victim != nil && victim.team != attacker.team {
			victims[index] = true
		}
	}

	for killed, index in victims {
		if killed { game_kill_mouse(game, occupants[index]) }
	}
}

game_resolve_movement :: proc(game: ^Game) {
	occupied: [ARENA_WIDTH * ARENA_HEIGHT]bool
	claims: [ARENA_WIDTH * ARENA_HEIGHT]int
	for team in game.teams {
		for &mouse in team.mice {
			if mouse.state != .Alive || !coordinate_in_bounds(mouse.pos) { continue }
			occupied[mouse.pos.y * ARENA_WIDTH + mouse.pos.x] = true
		}
	}

	Move_Candidate :: struct {
		mouse: ^Mouse,
		destination: Coordinate,
	}
	candidates: [dynamic]Move_Candidate
	defer delete(candidates)

	for turn in game.turns {
		if turn.fault != .None { continue }
		action, is_move := turn.action.(Move_Action)
		if !is_move { continue }
		mouse := game_find_mouse(game, turn.mouse_id)
		if mouse == nil || mouse.state != .Alive { continue }
		mouse.facing = action.direction
		destination := mouse_move_destination(mouse.pos, action.direction)
		if !coordinate_in_bounds(destination) { continue }
		index := destination.y * ARENA_WIDTH + destination.x
		if game.arena.tiles[index] == .Wall || occupied[index] { continue }
		claims[index] += 1
		append(&candidates, Move_Candidate{mouse, destination})
	}

	for candidate in candidates {
		index := candidate.destination.y * ARENA_WIDTH + candidate.destination.x
		if claims[index] == 1 {
			candidate.mouse.pos = candidate.destination
		}
	}
}

game_collect_cheese :: proc(game: ^Game) {
	for team in game.teams {
		for &mouse in team.mice {
			if mouse.state != .Alive || mouse.has_cheese || !coordinate_in_bounds(mouse.pos) {
				continue
			}
			index := mouse.pos.y * ARENA_WIDTH + mouse.pos.x
			if game.arena.tiles[index] == .Wall { continue }
			mouse.has_cheese = arena_take_cheese(&game.arena, mouse.pos)
		}
	}
}

game_deposit_cheese :: proc(game: ^Game) {
	for team in game.teams {
		for &mouse in team.mice {
			if mouse.state != .Alive || !mouse.has_cheese || !coordinate_in_bounds(mouse.pos) {
				continue
			}
			tile := game.arena.tiles[mouse.pos.y * ARENA_WIDTH + mouse.pos.x]
			friendly := (mouse.team == .One && tile == .Altar_Team_1) ||
			            (mouse.team == .Two && tile == .Altar_Team_2)
			if friendly {
				mouse.has_cheese = false
				game.teams[mouse.team].score += 1
			}
		}
	}
}
