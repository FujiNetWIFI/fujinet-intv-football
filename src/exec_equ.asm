; EXEC ROM entry points and RAM locations used by the netcode patch.
; Derived from build/exec.dis (dis1600 of the console EXEC) -- see
; spikes/NOTES.md for the analysis behind each.

X_MUSIC_TICK    EQU     $1A71   ; music note-timer routine (timer entry 0)
X_RAND1         EQU     $167D   ; LFSR random, state at EXEC_RNG
X_RAND2         EQU     $169E

EXEC_RNG        EQU     $035E   ; 16-bit LFSR state (System RAM)
EXEC_ISR_DEF    EQU     $1126   ; the EXEC's default game-time ISR (what
                                ;  $0100/$0101 hold at every tick boundary)

; EXEC decoded per-controller input bytes, rewritten by the controller scan
; each main-loop pass.  Auto Racing never polls these -- its input arrives
; exclusively through the $035D event dispatch (see spikes/NOTES.md, M2) --
; but the lockstep capture reads them, and the game pre-latches the RAW
; cells at the top of its tick to force the scan's held path.
EXEC_IN_L       EQU     $011F   ; left controller decoded input
EXEC_IN_R       EQU     $0120   ; right controller decoded input
EXEC_KP_L       EQU     $0121   ; left controller keypad event cell
EXEC_KP_R       EQU     $0122
EXEC_HTBL       EQU     $035D   ; input-handler table pointer (game-managed)
EXEC_RAW_L      EQU     $0123   ; left controller raw (inverted port) value
EXEC_RAW_R      EQU     $0124

; Original game entry points we re-dispatch from the master tick.
AR_TICK_FAST    EQU     $511E   ; game tick (was timer entry 1, interval 1)
AR_TICK_SLOW    EQU     $51B7   ; race clock (was timer entry 2, interval 15)
AR_START        EQU     $5037   ; original start-of-game vector target

; Game phase cell.  $11 = course select, $0D = car select (transitions by
; XOR), 0 = racing (set at $522E when race init completes).  Menu phases are
; odd; bit 7*256 suppresses the input handlers.  There is no ball-dead
; analogue in a continuous race -- the resync gate value is chosen at M8.
AR_PHASE        EQU     $015D
