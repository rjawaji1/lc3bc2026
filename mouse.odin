package main

import "core:fmt"
import lc3 "vendor/liblc3"

TRAP_VECTOR_MOVE   :: 0x30
TRAP_VECTOR_ATTACK :: 0x31
TRAP_VECTOR_SQUEAK :: 0x32

MAX_INSTRUCTIONS :: 10_000

Direction :: enum {
	North,
	East,
	South,
	West
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

Mouse :: struct {
	pos:    Coordinate,
	facing: Direction,
	team:   Team,
	vm:     lc3.LC3,
	action: Mouse_Action,

	// Traps don't return errors
	fault: Mouse_Error
}

@(require_results)
mouse_init :: proc(mouse: ^Mouse, buffer: []u8) -> bool {
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

	return true
}

mouse_reset :: proc(mouse: ^Mouse){
	lc3.reset(&mouse.vm)

	mouse.action = nil
	mouse.fault = .None
}

mouse_destroy :: proc(mouse: ^Mouse){
	lc3.destroy(&mouse.vm)
}

@(require_results)
mouse_run :: proc(mouse: ^Mouse) -> (action: Mouse_Action, err: Mouse_Error) {
	fmt.assertf(mouse != nil, "mouse_run requires a non-nil mouse")
	fmt.assertf(!mouse.vm.halted, "mouse_run called with a halted VM; call mouse_reset before running it again")

	mouse.action = nil
	mouse.fault = .None

	for i in 0..<MAX_INSTRUCTIONS {
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


@(private="file")
register_trap_move :: proc(mouse: ^Mouse){
	lc3.register_trap(
		&mouse.vm,
		TRAP_VECTOR_MOVE,
		trap_move_callback,
		mouse
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
		mouse
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
		mouse
	)

	trap_squeak_callback :: proc(vm: ^lc3.LC3, user_data: rawptr){
		mouse := (^Mouse)(user_data)

		mouse.action = Squeak_Action{message = vm.registers[0]}
	}
}

