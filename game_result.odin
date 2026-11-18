package main

game_living_mice :: proc(game: ^Game, team: Team) -> int {
	count := 0

	for &mouse in game.teams[team].mice {
		if mouse.state == .Alive { count += 1 }
	}

	return count
}

game_update_result :: proc(game: ^Game) {
	if game.result != .Undecided { return }

	one := game_living_mice(game, .One)
	two := game_living_mice(game, .Two)

	if one == 0 || two == 0 {
		game.end_reason = .Elimination

		if one == 0 && two == 0 {
			game.result = .Draw
		} else if one == 0 {
			game.result = .Team_Two_Won
		} else {
			game.result = .Team_One_Won
		}

		return
	}

	if game.tick >= MAX_GAME_STEPS {
		game.end_reason = .Tick_Limit

		one_score := game.teams[.One].score
		two_score := game.teams[.Two].score

		if one_score > two_score {
			game.result = .Team_One_Won
		} else if two_score > one_score {
			game.result = .Team_Two_Won
		} else {
			game.result = .Draw
		}
	}
}
