package main

import "core:fmt"
import "core:math/rand"

import lc3 "vendor/liblc3"

TRAP_VECTOR_MOVE   :: 0x30
TRAP_VECTOR_ATTACK :: 0x31
TRAP_VECTOR_SQUEAK :: 0x32
TRAP_VECTOR_RANDOM :: 0x33

VM_OBSERVATION      :: 0xE000
VM_OBS_MOUSE_ID     :: VM_OBSERVATION + 0
VM_OBS_POS_X        :: VM_OBSERVATION + 1
VM_OBS_POS_Y        :: VM_OBSERVATION + 2
VM_OBS_CHEESE_STATE :: VM_OBSERVATION + 3
VM_OBS_MAP_STATE    :: VM_OBSERVATION + 4

MOUSE_VISION_RADIUS :: 2
MOUSE_VISION_WIDTH  :: MOUSE_VISION_RADIUS * 2 + 1
MOUSE_VISION_CELLS  :: MOUSE_VISION_WIDTH * MOUSE_VISION_WIDTH

Observed_Altar :: enum u16 {
	None     = 0,
	Friendly = 1,
	Enemy    = 2,
}

Observed_Tile :: bit_field u16 {
	blocked:         bool           | 1,
	mouse_present:   bool           | 1,
	enemy_mouse:     bool           | 1,
	mouse_direction: u16            | 2,
	cheese_timer:    i16            | 4,
	altar:           Observed_Altar | 2,
	reserved:        u16            | 5,
}

MAX_INSTRUCTIONS :: 10_000

Direction :: enum {
	North,
	East,
	South,
	West,
}

Move_Action :: struct {
	direction: Direction,
}

Attack_Action :: struct {}

Squeak_Action :: struct {
	message: u16,
}

Mouse_Action :: union {
	Move_Action,
	Attack_Action,
	Squeak_Action,
}

Mouse_Error :: enum {
	None,
	Invalid_Direction,
	Unsupported_Trap,
	Unsupported_Instruction,
	Reserved_Instruction,
}

Mouse_State :: enum {
	Alive,
	Dead,
}

Mouse_ID :: distinct u16
INVALID_MOUSE_ID :: Mouse_ID(0)

Mouse :: struct {
	id:         Mouse_ID,
	state:      Mouse_State,
	pos:        Coordinate,
	facing:     Direction,
	team:       Team,
	vm:         lc3.LC3,
	action:     Mouse_Action,
	has_cheese: bool,

	// Traps don't return errors
	fault: Mouse_Error,
}

@(require_results)
mouse_init :: proc(mouse: ^Mouse, buffer: []u8) -> bool {
	if len(buffer) < 4 || len(buffer) % 2 != 0 { return false }
	origin := int(buffer[0]) << 8 | int(buffer[1])
	end := origin + (len(buffer) - 2) / 2
	observation_end := VM_OBS_MAP_STATE + MOUSE_VISION_CELLS
	if end > lc3.MEMORY_SIZE ||
	   (origin < observation_end && end > VM_OBSERVATION) {
		return false
	}

	lc3.init(&mouse.vm)
	mouse.action = nil
	mouse.fault = .None

	if !lc3.load_from_buffer(&mouse.vm, buffer) {
		lc3.destroy(&mouse.vm)
		mouse.vm = {}
		return false
	}

	register_trap_move(mouse)
	register_trap_attack(mouse)
	register_trap_squeak(mouse)
	register_trap_random(mouse)
	mouse_sync_observations(mouse)

	return true
}

mouse_reset :: proc(mouse: ^Mouse){
	lc3.reset(&mouse.vm)

	mouse.action = nil
	mouse.fault = .None
	mouse_sync_observations(mouse)
}

mouse_destroy :: proc(mouse: ^Mouse){
	lc3.destroy(&mouse.vm)
}

@(require_results)
mouse_run :: proc(mouse: ^Mouse) -> (action: Mouse_Action, err: Mouse_Error) {
	fmt.assertf(mouse != nil, "mouse_run requires a non-nil mouse")
	fmt.assertf(!mouse.vm.halted, "mouse_run called with a halted VM; call mouse_reset before running it again")

	mouse_sync_observations(mouse)
	mouse.action = nil
	mouse.fault = .None

	for _ in 0..<MAX_INSTRUCTIONS {
		vm_error := lc3.step(&mouse.vm)

		// Map VM Errors To Custom Errors
		switch vm_error {
		case .None:
		case .Halted:
			return nil, .None
		case .Unsupported_Trap:
			return nil, .Unsupported_Trap
		case .Unsupported_Instruction:
			return nil, .Unsupported_Instruction
		case .Reserved_Instruction:
			return nil, .Reserved_Instruction
		}

		if mouse.fault != .None {
			return nil, mouse.fault
		}
		if mouse.action != nil {
			return mouse.action, .None
		}
		if mouse.vm.halted {
			return nil, .None
		}
	}

	return nil, .None
}

mouse_sync_observations :: proc(mouse: ^Mouse) {
	lc3.memset(&mouse.vm, VM_OBS_MOUSE_ID, u16(mouse.id))
	lc3.memset(&mouse.vm, VM_OBS_POS_X, u16(mouse.pos.x))
	lc3.memset(&mouse.vm, VM_OBS_POS_Y, u16(mouse.pos.y))
	lc3.memset(&mouse.vm, VM_OBS_CHEESE_STATE, u16(mouse.has_cheese))
}

mouse_sync_map_observations :: proc(mouse: ^Mouse, game: ^Game) {
	arena := &game.arena

	for row in 0..<MOUSE_VISION_WIDTH {
		for column in 0..<MOUSE_VISION_WIDTH {
			position := Coordinate{
				x = mouse.pos.x + column - MOUSE_VISION_RADIUS,
				y = mouse.pos.y + row - MOUSE_VISION_RADIUS,
			}
			observed := Observed_Tile{blocked = true, cheese_timer = -1}

			if coordinate_in_bounds(position) {
				tile := arena.tiles[position.y * ARENA_WIDTH + position.x]
				observed.blocked = tile == .Wall

				switch tile {
				case .Floor, .Wall:
				case .Altar_Team_1, .Altar_Team_2:
					friendly := (tile == .Altar_Team_1 && mouse.team == .One) ||
					            (tile == .Altar_Team_2 && mouse.team == .Two)
					observed.altar = .Friendly if friendly else .Enemy
				}

				if !observed.blocked {
					if arena_has_cheese(arena, position) {
						observed.cheese_timer = 0
					} else {
						for spawner in arena.cheese_spawners {
							if spawner.pos != position { continue }
							observed.cheese_timer = i16(clamp(spawner.delay, 0, 7))
							break
						}
					}

					for team in game.teams {
						for occupant in team.mice {
							if occupant.state != .Alive || occupant.pos != position { continue }
							observed.mouse_present = true
							observed.enemy_mouse   = occupant.team != mouse.team
							switch occupant.facing {
							case .North: observed.mouse_direction = 0
							case .East:  observed.mouse_direction = 1
							case .South: observed.mouse_direction = 2
							case .West:  observed.mouse_direction = 3
							}
						}
					}
				}
			}

			index := row * MOUSE_VISION_WIDTH + column
			lc3.memset(&mouse.vm, u16(VM_OBS_MAP_STATE + index), transmute(u16)observed)
		}
	}
}

@(private="file")
register_trap_move :: proc(mouse: ^Mouse){
	lc3.register_trap(
		&mouse.vm,
		TRAP_VECTOR_MOVE,
		trap_move_callback,
		mouse,
	)

	trap_move_callback :: proc(vm: ^lc3.LC3, user_data: rawptr){
		mouse := (^Mouse)(user_data)

		switch vm.registers[0] {
		case 0x0:
			mouse.action = Move_Action{direction = .North}
		case 0x1:
			mouse.action = Move_Action{direction = .West}
		case 0x2:
			mouse.action = Move_Action{direction = .South}
		case 0x3:
			mouse.action = Move_Action{direction = .East}
		case:
			mouse.fault = .Invalid_Direction
		}
	}
}

@(private="file")
register_trap_attack :: proc(mouse: ^Mouse){
	lc3.register_trap(
		&mouse.vm,
		TRAP_VECTOR_ATTACK,
		trap_attack_callback,
		mouse,
	)

	trap_attack_callback :: proc(vm: ^lc3.LC3, user_data: rawptr){
		mouse := (^Mouse)(user_data)

		mouse.action = Attack_Action{}
	}
}

@(private="file")
register_trap_squeak :: proc(mouse: ^Mouse){
	lc3.register_trap(
		&mouse.vm,
		TRAP_VECTOR_SQUEAK,
		trap_squeak_callback,
		mouse,
	)

	trap_squeak_callback :: proc(vm: ^lc3.LC3, user_data: rawptr){
		mouse := (^Mouse)(user_data)

		mouse.action = Squeak_Action{message = vm.registers[0]}
	}
}

@(private="file")
register_trap_random :: proc(mouse: ^Mouse){
	lc3.register_trap(
		&mouse.vm,
		TRAP_VECTOR_MOVE,
		trap_random_callback,
		mouse,
	)

	trap_random_callback :: proc(vm: ^lc3.LC3, user_data: rawptr){
		mouse := (^Mouse)(user_data)
		mouse.vm.registers[0x0] = u16(rand.uint32())
	}
}
