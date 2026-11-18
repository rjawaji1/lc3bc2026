# Replay recordings

Record a match with:

```sh
odin run . -- run arena.map team1.obj team2.obj --replay match.jsonl
```

Replay files are plain JSON Lines. An existing output file is overwritten. Open `viewer/index.html`, choose **Open replay**, and select the recording. Use the playback controls or timeline to navigate ticks, then select a mouse to inspect it.

## LC-3 snapshots

Every new recording includes R0–R7, PC, and CC for every mouse in every frame. No debugging flag, halted flag, or VM memory dump is used.

The JSON format remains version 1 with additive fields. New headers set `vm_snapshots` to `true`. The viewer also accepts older headers where it is absent or false.

Each mouse has a `vm` object:

```json
{
  "registers": [1, 0, 0, 0, 0, 0, 0, 12290],
  "pc": 12290,
  "cc": 1
}
```

- `registers` contains exactly eight unsigned 16-bit numbers, ordered R0 through R7.
- PC is also an unsigned 16-bit number. All are serialized as JSON integers.
- `cc` is a `u16` with value `4` (N), `2` (Z), or `1` (P).
- The viewer displays these numbers as hexadecimal words, such as `x3002`.
- Older recordings may omit `vm` or set it to `null`. A header with `vm_snapshots: true` requires a valid snapshot for every mouse.

Snapshots describe the VM after the mouse finishes executing for the tick, before the next reset. The frame's arena state is recorded after movement and other game updates, but those phases do not execute additional LC-3 instructions. Tick 0 contains initialized VM state. Dead mice retain their last execution state.

The recorded PC is the current VM program counter, not a separately captured faulting-instruction address. These are per-tick snapshots, not an instruction trace.

## JSON Lines structure

The first record is a header containing the version, arena dimensions, terrain, team names, map name, tick limit, and snapshot flag. Every subsequent record is a frame containing the tick, result, scores, mice, cheese spawners, dropped cheese, and requested actions.

Frames start at tick 0 and advance consecutively. Each line is an independent JSON object. The viewer supports partial recordings, but requires a header and at least one frame. The viewer's file-size limit is 128 MiB.
