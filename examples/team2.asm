; Scripted showcase bot for team 2.
; Registers reset every tick, but the Step counter in VM memory persists.
; The host stops execution after one move or attack request.
; Action codes: 0 north, 1 east, 2 south, 3 west, 4 attack, 5 wait.
; Assemble with the aliases documented in examples/README.md.

.ORIG x3000

    ; Clamp the index to the final action so the bot never reads past Actions.
    ld r1, Step
    add r2, r1, #-10
    brnz Choose
    and r1, r1, #0
    add r1, r1, #10

Choose
    ; Read this tick's action and advance the persistent counter.
    lea r2, Actions
    add r2, r2, r1
    ldr r0, r2, #0
    add r1, r1, #1
    st r1, Step

    ; Movement uses r0 directly. Attack and wait are table-only action codes.
    add r2, r0, #-4
    brz DoAttack
    add r2, r0, #-5
    brz DoWait
    move                    ; Game trap x30: request movement using r0.

DoAttack
    attack                  ; Game trap x31: attack in the current facing.

DoWait
    halt                    ; End this turn without requesting an action.

Step
    .FILL #0

Actions
    .FILL #3                ; Tick 1: west onto cheese at (11,3).
    .FILL #1                ; Tick 2: east to (12,3), carrying cheese.
    .FILL #1                ; Tick 3: east to (13,3).
    .FILL #0                ; Tick 4: north onto the altar; deposit cheese.
    .FILL #2                ; Tick 5: south to (13,3).
    .FILL #3                ; Tick 6: west to (12,3).
    .FILL #3                ; Tick 7: west onto respawned cheese at (11,3).
    .FILL #3                ; Tick 8: west to (10,3).
    .FILL #3                ; Tick 9: west to (9,3).
    .FILL #3                ; Tick 10: west to (8,3), facing team 1.
    .FILL #5                ; Tick 11 onward: wait; team 1 attacks and wins.

.END
