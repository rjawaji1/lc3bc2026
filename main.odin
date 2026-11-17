package main

import "core:fmt"
import "core:os"

HELP_TEXT :: #load("help.txt", string)

command_print_help :: proc(){
	fmt.print(HELP_TEXT)
}



main :: proc() {
	args := os.args[1:]

	if len(args) == 0 {
		command_print_help()
		return
	}

	switch args[0]{
	case "help", "--help", "-h":
		command_print_help()

	case "run":
		if len(args) != 4 {
			fmt.println("Error: run requires 3 file paths")
			command_print_help()
			return
		}
		
		game: Game
		game_init(&game, args[1], args[2], args[3])
		defer game_destroy(&game)

	case:
		fmt.printf("Unknown command:", args[0])
		command_print_help()
	}
}
