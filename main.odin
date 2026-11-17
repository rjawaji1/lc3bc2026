package main

import "core:fmt"
import "core:os"

HELP_TEXT :: #load("help.txt", string)

command_print_help :: proc(){
	fmt.print(HELP_TEXT)
}


command_run :: proc(map_path, team1_path, team2_path: string) -> bool {
	game: Game
	defer game_destroy(&game)
	if !game_init(&game, map_path, team1_path, team2_path) {
		return false
	}

	fmt.printf("Team 1: %s\nTeam 2: %s\nMap: %s\n", team1_path, team2_path, map_path)
	for game.result == .Undecided {
		game_step(&game)
	}

	fmt.printf("\nMatch finished after %d ticks.\n", game.tick)
	switch game.end_reason {
	case .Elimination:
		fmt.println("Reason: team elimination.")
	case .Tick_Limit:
		fmt.println("Reason: tick limit reached; result decided by score.")
	case .None:
	}
	fmt.printf("Team 1: score %d, %d mice alive\n", game.teams[.One].score, game_living_mice(&game, .One))
	fmt.printf("Team 2: score %d, %d mice alive\n", game.teams[.Two].score, game_living_mice(&game, .Two))
	switch game.result {
	case .Team_One_Won:
		fmt.println("Winner: Team 1\nLoser: Team 2")
	case .Team_Two_Won:
		fmt.println("Winner: Team 2\nLoser: Team 1")
	case .Draw:
		fmt.println("Draw: neither team won or lost.")
	case .Undecided:
	}
	return true
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
			fmt.eprintln("Error: run requires 3 file paths")
			command_print_help()
			os.exit(2)
		}
		
		if !command_run(args[1], args[2], args[3]) {
			os.exit(1)
		}

	case:
		fmt.eprintf("Unknown command: %s\n", args[0])
		command_print_help()
		os.exit(2)
	}
}
