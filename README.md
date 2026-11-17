# LC3 BattleCode 2026

LC3 BattleCode is a programming game where two teams of mice compete in a 16×16 arena. You write an LC-3 program to control your team. Your mice can explore, collect cheese, return it to their altar for points, and attack opposing mice.

The simulator runs the match locally. You can record a replay and open it in the browser viewer to see what happened.

## How the game works

Each team supplies one compiled LC-3 object file (`.obj`). Every mouse on that team runs its own copy of the program, with its own registers and memory. Mice do not share VM memory.

Time advances in **ticks**. During each tick, every living mouse reads its observations and chooses one action: move, attack, or wait. The simulator then resolves the actions and updates the arena.

There are two ways to win:

* **Eliminate the other team.** If all opposing mice die, your team wins regardless of score. If both teams are eliminated together, the match is a draw.
* **Have the higher score after 10,000 ticks.** Each cheese deposited at your team's altar is worth one point. Equal scores at the limit produce a draw.

## Getting started

### Requirements

You need [Odin](https://odin-lang.org/) to build and run the simulator. To write your own bots, you also need an LC-3 assembler that produces binary `.obj` files. The examples use **elk**.

The repository includes a `devenv.nix` configuration that enables Odin if you use devenv.

From the repository root, initialize the bundled LC-3 library:

```sh
git submodule update --init --recursive
```

### Run the included match

The example programs are already compiled, so you can try a match without an assembler:

```sh
odin run . -- run examples/showcase.map examples/team1.obj examples/team2.obj
```

The terminal prints the input files, final scores, surviving mouse counts, and match result.

### Record and watch a match

```sh
odin run . -- run examples/showcase.map examples/team1.obj examples/team2.obj --replay match.jsonl
```

The replay file must **not already exist**, and its parent directory must exist. Choose a new filename for each recording.

Open [`viewer/index.html`](viewer/index.html) in your browser and select `match.jsonl`. You can play or pause the match, step through ticks, scrub the timeline, and select mice to inspect their state and actions. No server or package installation is required.

To try playback without running a match, open the included [`examples/showcase.replay.jsonl`](examples/showcase.replay.jsonl).

The viewer shows the whole arena. Your bot only receives the observations described below, not everything visible in the replay.

### Build a standalone executable

```sh
odin build . -out:lc3bc
./lc3bc run examples/showcase.map examples/team1.obj examples/team2.obj
./lc3bc help
```

On Windows, use an appropriate executable name, such as `lc3bc.exe`.

## Writing a bot

Write an LC-3 assembly program, assemble it into an object file, then pass that file as one team's program:

```sh
elk my_bot.asm --assemble --output my_bot.obj --relaxed
odin run . -- run examples/showcase.map my_bot.obj examples/team2.obj --replay my-match.jsonl
```

With elk, `--assemble` produces the object file without trying to run it in elk's emulator. `--relaxed` suppresses warnings about the game's custom trap vectors. These traps must run inside the BattleCode simulator.

See [`examples/README.md`](examples/README.md) for instructions on rebuilding the included bots.

### What resets each tick?

At the beginning of each turn:

* Registers R0 through R7 are cleared to zero.
* The program counter returns to the program's origin address.
* Condition codes reset to negative, and the VM is no longer halted.
* Observation memory is refreshed with the mouse's current state and surroundings.

**Program memory persists between ticks.** Store counters, routes, and other lasting state in memory, not registers. Each mouse has its own persistent memory, even when multiple mice run the same program.

Each mouse can execute up to **10,000 instructions per tick**. Reaching that limit without requesting an action counts as waiting. Execution faults, such as an unsupported trap or an invalid movement direction, kill the mouse.

### A minimal bot

This program reads the mouse's X coordinate and moves toward the center of the arena:

```asm
.ORIG x3000
    LDI R0, OBS_X       ; Read X from observation address xE001.
    ADD R1, R0, #-8
    BRn GO_EAST         ; X < 8: move east.

    AND R0, R0, #0
    ADD R0, R0, #1      ; Direction 1 is west.
    TRAP x30

GO_EAST
    AND R0, R0, #0
    ADD R0, R0, #3      ; Direction 3 is east.
    TRAP x30

OBS_X .FILL xE001
.END
```

Requesting an action ends the turn immediately. Execution starts again at `x3000` next tick; it does not resume after the trap. This is a movement example, not a complete strategy: it does not avoid collisions or collect cheese deliberately.

## Traps and actions

A **trap** is how your LC-3 program asks the simulator to do something. Set any required registers, then execute the corresponding `TRAP` instruction.

Your mouse can request only **one action per tick**. A move or attack trap ends execution for that turn immediately. A request is not a guarantee of success: movement may be blocked and attacks may miss.

### Move: `TRAP x30`

Put the direction in **R0** before calling the trap:

| R0 | Direction | Coordinate change |
| --- | --- | --- |
| `0` | North | Y decreases by 1 |
| `1` | West | X decreases by 1 |
| `2` | South | Y increases by 1 |
| `3` | East | X increases by 1 |

For example, move east:

```asm
AND R0, R0, #0
ADD R0, R0, #3
TRAP x30
```

A move attempts to advance one cell. It also changes the mouse's facing direction, **even if movement is blocked**. Any R0 value other than 0, 1, 2, or 3 causes a fault and kills the mouse.

### Attack: `TRAP x31`

```asm
TRAP x31
```

Attack the single adjacent cell in the mouse's current facing direction. No input register is required. R0 does not select the attack direction.

One hit kills an enemy mouse. Friendly fire is disabled, and attacking an empty cell has no effect. There is no separate turn action: use a movement request to change facing, then attack on a later tick.

Mice initially face toward the opposing half of the arena: east or west on a vertically mirrored map, south or north on a horizontally mirrored map.

### Wait: `HALT`

```asm
HALT
```

`HALT` (`TRAP x25`) ends the turn without moving or attacking. It does **not** remove the mouse from the match. The program starts again next tick.

Waiting mice can still automatically collect or deposit cheese at their current position.

## Observation memory

The simulator writes observations into reserved LC-3 memory before your mouse runs. Read these words to learn about that mouse and its surroundings.

Addresses beginning with `x` are hexadecimal. Each address below holds one **16-bit word**, not a byte.

### Mouse information

| Address | Meaning |
| --- | --- |
| `xE000` | Mouse ID: a stable, nonzero identifier unique within this match |
| `xE001` | Current X coordinate, from 0 to 15 |
| `xE002` | Current Y coordinate, from 0 to 15 |
| `xE003` | Carrying cheese: `0` for no, `1` for yes |
| `xE004` through `xE01C` | The 25 cells of the local map observation |

Coordinates start at `(0,0)` in the top left. X increases to the right, and Y increases downward. Directions and coordinates are absolute; the view does not rotate with your mouse or team.

For example, use `LDI` with a stored address to read whether the mouse carries cheese:

```asm
LDI R0, CHEESE_ADDR     ; R0 becomes 0 or 1.
; Continue your decision logic here.

CHEESE_ADDR .FILL xE003
```

`LD` would load the address `xE003` itself; `LDI` follows that address to read the observation word.

### Local map view

Each mouse sees a **5×5 square** centered on its current cell, extending two cells in every direction. Walls do not block this view.

The words are stored row by row, from the top left to the bottom right:

```text
             West                 East
North     xE004 xE005 xE006 xE007 xE008
          xE009 xE00A xE00B xE00C xE00D
          xE00E xE00F xE010 xE011 xE012
          xE013 xE014 xE015 xE016 xE017
South     xE018 xE019 xE01A xE01B xE01C
```

`xE010` is the mouse's own cell, at index 12 in the 25-word view. Its immediate neighbors are:

| Neighbor | Address |
| --- | --- |
| North | `xE00B` |
| West | `xE00F` |
| South | `xE015` |
| East | `xE011` |

For a relative offset `(dx,dy)`, where each offset is between −2 and 2, the address is:

```text
xE004 + (dy + 2) * 5 + (dx + 2)
```

Each cell contains one of these values:

| Value | Meaning |
| --- | --- |
| `0` | Floor |
| `1` | Wall |
| `2` | Cheese present |
| `3` | Your team's altar |
| `4` | The opposing team's altar |
| `5` | Outside the arena |

**Other mice are not encoded in the observation grid.** A floor observation does not guarantee that a cell is unoccupied. The grid also does not report cheese quantities or spawner countdowns. If cheese is present, its value takes priority over the underlying altar terrain.

### Reserved addresses

Keep your program image and persistent data outside **`xE000` through `xE01C`, inclusive**. The loader rejects object files whose loaded image overlaps this region.

Your program can write to these words while running, but doing so does not change the real mouse or arena. The simulator replaces them with fresh observations on the next tick.

Object files must contain a big-endian origin word followed by at least one complete program word. The loaded image must fit within LC-3 memory. A normal LC-3 assembler produces this format for you.

## Game rules

### Movement

Movement fails if the destination is outside the arena, is a wall, or is occupied by a living mouse at the start of the movement phase.

If multiple mice try to enter the same empty cell, all of those moves fail. Mice cannot swap positions or follow another mouse into a cell it vacates during that phase. Dead mice do not block movement.

### Combat

All attacks resolve before movement, using the mice's positions and facing directions from before movement. A mouse cannot escape a hit by requesting a move during the same tick.

Attacks resolve simultaneously, so two adjacent enemies facing each other can kill one another in the same tick. Mice killed by execution faults are removed before attacks resolve.

### Cheese and scoring

A mouse carries at most one piece of cheese. Pickup and deposit are automatic; no trap is required.

After movement, an empty-handed mouse picks up cheese at its position. Dropped cheese is collected before cheese from a spawner. Collecting a spawner's cheese starts a five-tick respawn timer.

A mouse carrying cheese on any tile of its own 2×2 altar deposits it and earns **one point** for its team. A mouse that dies drops its carried cheese at its position, where another mouse can collect it.

### Tick order

The simulator processes each tick in this order:

1. Advance cheese spawner timers.
2. Refresh observations and collect an action from each living mouse.
3. Kill mice whose programs faulted.
4. Resolve attacks simultaneously and apply deaths.
5. Resolve movement for surviving mice.
6. Collect cheese, then deposit carried cheese at friendly altars.
7. Advance the tick counter and check whether the match has ended.

All mice choose actions before any attack or movement is applied. Running earlier in the collection loop does not let a mouse move before another mouse observes the world.

## Creating a map

Maps are plain text files. Define one half of the arena, and the simulator mirrors it to create the other team's half.

```text
# Describe the left half of a vertically mirrored arena.
SYMMETRY VERTICAL
ALTAR 1,1
MOUSE 3,3
CHEESE 4,3 0
WALL 2,5
```

| Declaration | Meaning |
| --- | --- |
| `SYMMETRY VERTICAL` | Mirror the left half onto the right half |
| `SYMMETRY HORIZONTAL` | Mirror the top half onto the bottom half |
| `ALTAR x,y` | Place the top left corner of your team's 2×2 altar |
| `MOUSE x,y` | Add a mouse spawn and a corresponding mirrored opponent |
| `CHEESE x,y delay` | Add a cheese spawner with a nonnegative initial delay in ticks |
| `WALL x,y` | Place a wall |

A cheese delay of `0` means cheese is present at the start. After collection, subsequent respawns take five ticks.

### Map requirements

* Include exactly one `SYMMETRY`, exactly one source `ALTAR`, and at least one `MOUSE`.
* Use coordinates from 0 to 15, written as `x,y` without spaces around the comma.
* For vertical symmetry, place everything in the left half: `x < 8`.
* For horizontal symmetry, place everything in the top half: `y < 8`.
* Keep the altar's entire 2×2 footprint inside the source half.
* Place mice on distinct floor cells. Cheese spawners must also be on floor, but may share a cell with a mouse spawn.
* Do not overlap walls and altars or repeat a cheese spawner position.

Declarations can appear in any order. Blank lines and comments beginning with `#` are allowed, including comments at the end of a declaration.

## Command reference

```text
lc3bc run <map_path> <team1_path> <team2_path> [--replay <new_file.jsonl>]
lc3bc help
```

The team paths must point to compiled `.obj` files, not assembly source. The first program controls the source half of the map; the second controls the mirrored half. Both teams may use the same program file.

| Exit code | Meaning |
| --- | --- |
| `0` | Match completed, including a draw, or help was displayed |
| `1` | Map loading, program loading, or replay output failed |
| `2` | Invalid command or arguments |

The exit code reports whether the command succeeded, **not which team won**. Read the terminal result or final replay frame for the outcome.

## Troubleshooting

**The simulator cannot find the LC-3 library.** Run `git submodule update --init --recursive` from the repository root.

**My program is rejected.** Check that you supplied a binary `.obj` file with at least one program word, that it fits in memory, and that its loaded image does not overlap `xE000` through `xE01C`.

**My mouse dies immediately.** Check for unsupported instructions or traps, and verify that R0 is between 0 and 3 when calling `TRAP x30`. Use the replay viewer to inspect the recorded fault.

**My program keeps starting over.** That is expected. Store progress in memory because registers and the program counter reset every tick.

**My mouse sees floor but cannot move there.** Another mouse may occupy the cell, or multiple mice may be trying to enter it. Mouse occupancy is not included in the observation grid.

**Replay recording fails.** Choose a filename that does not already exist and make sure its parent directory exists and is writable.

For more playback controls and the recording format, see the [replay guide](docs/replay.md).
