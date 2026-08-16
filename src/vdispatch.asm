; Virtual input-event dispatch engine.
;
; Auto Racing's input reaches game state exclusively through the EXEC scan's
; $035D handler dispatch (spikes/NOTES.md, M2): there is no polled cell to
; shadow.  Interception therefore means nulling $035D during the real scan
; and replaying both pads' events in sim space through the live handlers.
; That machinery lived inside Baseball's lockstep.asm; here it is shared by
; the local spikes (lag/det/replay -- SPIKE_VIRT builds, driven from
; MASTER_TICK) and by the lockstep engine (driven from LS_PASS), so it gets
; its own file.  LS_* names are kept verbatim from the Baseball engine.

; ---------------------------------------------------------------------------
; VIRT_CAPTURE -- fill the per-tick input rings for tick T+d (d = DELAY_EN).
; Side 0 = left pad -> LOC_* rings, side 1 = right pad -> RMT_* rings (in
; local modes NET_ROLE is 0, so LS_VDISPATCH maps them back the same way).
; Sources: live EXEC cells, or the deterministic fuzz PRNG (SPIKE_SCRIPT),
; or the recorded table (SPIKE_REPLAY).
; ---------------------------------------------------------------------------
VIRT_CAPTURE:
        PSHR    R5
        MVI     TICK_HI, R1
        SWAP    R1,     1
        ADD     TICK_LO, R1
        ADD     DELAY_EN, R1            ; R1 = T + d
    IF SPIKE_REPLAY <> 0
        ; rings fed from the recorded stream, 4 cells per tick; idle once
        ; the table is exhausted
        MOVR    R1,     R2
        ANDI    #$FF,   R1              ; ring slot
        CMPI    #REPLAY_LEN, R2
        BLT     @@vr_tbl
        MVII    #$40,   R0              ; idle decoded, no keypad
        JSR     R5,     @@vr_put_dec
        CLRR    R0
        JSR     R5,     @@vr_put_kp
        PULR    R7
@@vr_tbl:
        SLL     R2,     2
        ADDI    #REPLAY_TBL, R2
        MOVR    R2,     R4
        MVI@    R4,     R0              ; L decoded
        MOVR    R1,     R3
        ADDI    #LOC_RING, R3
        MVO@    R0,     R3
        MVI@    R4,     R0              ; R decoded
        MOVR    R1,     R3
        ADDI    #RMT_RING, R3
        MVO@    R0,     R3
        MVI@    R4,     R0              ; L keypad
        MOVR    R1,     R3
        ADDI    #LOC_KP, R3
        MVO@    R0,     R3
        MVI@    R4,     R0              ; R keypad
        MOVR    R1,     R3
        ADDI    #RMT_KP, R3
        MVO@    R0,     R3
        PULR    R7
@@vr_put_dec:
        MOVR    R1,     R3
        ADDI    #LOC_RING, R3
        MVO@    R0,     R3
        MOVR    R1,     R3
        ADDI    #RMT_RING, R3
        MVO@    R0,     R3
        MOVR    R5,     R7
@@vr_put_kp:
        MOVR    R1,     R3
        ADDI    #LOC_KP, R3
        MVO@    R0,     R3
        MOVR    R1,     R3
        ADDI    #RMT_KP, R3
        MVO@    R0,     R3
        MOVR    R5,     R7
    ENDI
    IF (SPIKE_REPLAY = 0) AND (SPIKE_SCRIPT <> 0)
        ; Scripted demo first: complete the menus (fuzz alone parks in car
        ; select forever -- the Baseball never-pitched coverage hole), drive
        ; the race, then hand over to the fuzz.
        PSHR    R1
        JSR     R5,     SCR_STEP        ; R2 = row addr, 0 when done
        PULR    R1
        ANDI    #$FF,   R1              ; ring slot
        TSTR    R2
        BEQ     @@vf_fz
        MOVR    R2,     R4
        INCR    R4                      ; row: nticks, Ldec, Rdec, Lkp, Rkp
        MOVR    R1,     R3
        ADDI    #LOC_RING, R3
        MVI@    R4,     R0
        MVO@    R0,     R3
        MOVR    R1,     R3
        ADDI    #RMT_RING, R3
        MVI@    R4,     R0
        MVO@    R0,     R3
        MOVR    R1,     R3
        ADDI    #LOC_KP, R3
        MVI@    R4,     R0
        MVO@    R0,     R3
        MOVR    R1,     R3
        ADDI    #RMT_KP, R3
        MVI@    R4,     R0
        MVO@    R0,     R3
        PULR    R7
@@vf_fz:
        ; deterministic fuzz: advance the PRNG every 8th tick, write the
        ; held pair every tick (the rings must be filled per tick)
        MVI     TICK_LO, R0
        ANDI    #7,     R0
        BNEQ    @@vf_hold
        MVI     SLF_HI, R0
        SWAP    R0,     1
        ADD     SLF_LO, R0
        SLLC    R0,     1
        ADCR    R0                      ; 16-bit rotate left
        ADDI    #$6D2B, R0
        MVO     R0,     SLF_LO
        SWAP    R0,     1
        MVO     R0,     SLF_HI
@@vf_hold:
        ; dec values masked to $3F: disc-space chaos only.  Unmasked fuzz
        ; hits keypad '1' in phase 3 = race restart, whose music re-arm
        ; reads real-frame sound state -- the one stall leak this cart has
        ; (spikes/NOTES.md, M7).  Menus are covered by the script above.
        MOVR    R1,     R3
        ADDI    #LOC_RING, R3
        MVI     SLF_LO, R0
        ANDI    #$3F,   R0
        MVO@    R0,     R3
        MOVR    R1,     R3
        ADDI    #RMT_RING, R3
        MVI     SLF_HI, R0
        ANDI    #$3F,   R0
        MVO@    R0,     R3
        MOVR    R1,     R3
        ADDI    #LOC_KP, R3
        CLRR    R0                      ; fuzz has no keypad stream
        MVO@    R0,     R3
        MOVR    R1,     R3
        ADDI    #RMT_KP, R3
        MVO@    R0,     R3
        PULR    R7
    ENDI
    IF (SPIKE_REPLAY = 0) AND (SPIKE_SCRIPT = 0)
        ; live pads
        ANDI    #$FF,   R1              ; ring slot
        MOVR    R1,     R3
        ADDI    #LOC_RING, R3
        MVI     EXEC_IN_L, R0
        MVO@    R0,     R3
        MOVR    R1,     R3
        ADDI    #RMT_RING, R3
        MVI     EXEC_IN_R, R0
        MVO@    R0,     R3
        MOVR    R1,     R3
        ADDI    #LOC_KP, R3
        MVI     EXEC_KP_L, R0
        MVO@    R0,     R3
        MOVR    R1,     R3
        ADDI    #RMT_KP, R3
        MVI     EXEC_KP_R, R0
        MVO@    R0,     R3
        PULR    R7
    ENDI

; ---------------------------------------------------------------------------
; SCR_STEP -- demo-script sequencer, one call per tick.  Returns R2 = the
; current row address (points at its nticks word), or 0 once the script is
; exhausted.  Clobbers R0/R1/R4.  Shared by VIRT_CAPTURE (local spikes) and
; the NET_FUZZ rig path in lockstep.asm (host plays the left column, guest
; the right, so two consoles complete the menus together).
; ---------------------------------------------------------------------------
    IF (SPIKE_SCRIPT <> 0) OR (NET_FUZZ <> 0)
SCR_STEP:
        MVI     SCR_IDX, R2
        CMPI    #$FF,   R2
        BEQ     @@ss_done
        ADDI    #SCRIPT_TBL, R2
        MOVR    R2,     R4
        MVI@    R4,     R0              ; nticks for this row
        MVI     SCR_CNT, R1
        INCR    R1
        CMPR    R0,     R1
        BLT     @@ss_st
        CLRR    R1
        MVI     SCR_IDX, R0
        ADDI    #5,     R0
        MVO     R0,     SCR_IDX
        ADDI    #SCRIPT_TBL, R0
        MOVR    R0,     R4
        MVI@    R4,     R0              ; peek next row; 0 = script done
        TSTR    R0
        BNEQ    @@ss_st
        MVII    #$FF,   R0
        MVO     R0,     SCR_IDX
@@ss_st:
        MVO     R1,     SCR_CNT
        MOVR    R5,     R7
@@ss_done:
        CLRR    R2
        MOVR    R5,     R7

; Demo script: course 1, cars 1/2, both enters, then gas + steering pulses.
; Digits are 1-based on the wire (the handler 0-indexes); enter = $B.
; Rows are real cell sequences as the scan produces them: keypad release
; marks $C0|k, disc settle = bit 6.
SCRIPT_TBL:
        DECLE   10, $40, $40, 0, 0      ; settle
        DECLE   3,  $81, $40, 0, 0      ; L digit 1: course 1
        DECLE   3,  $C1, $40, 0, 0
        DECLE   3,  $8B, $40, 0, 0      ; L enter: accept course
        DECLE   3,  $CB, $40, 0, 0
        DECLE   3,  $81, $40, 0, 0      ; L digit 1: car 1
        DECLE   3,  $C1, $40, 0, 0
        DECLE   3,  $C1, $82, 0, 0      ; R digit 2: car 2
        DECLE   3,  $C1, $C2, 0, 0
        DECLE   3,  $8B, $C2, 0, 0      ; L enter
        DECLE   3,  $CB, $C2, 0, 0
        DECLE   3,  $CB, $8B, 0, 0      ; R enter -> race init
        DECLE   10, $CB, $CB, 0, 0
        DECLE   40, $CB, $CB, 1, 1      ; race: both hold action class 1
        DECLE   2,  $04, $CB, 1, 1      ; L disc pulse
        DECLE   2,  $44, $CB, 1, 1      ; settle mark
        DECLE   40, $44, $CB, 1, 1
        DECLE   2,  $44, $0C, 1, 1      ; R disc pulse
        DECLE   2,  $44, $4C, 1, 1
        DECLE   60, $44, $4C, 1, 2      ; R shifts to action class 2
        DECLE   40, $44, $4C, 2, 2      ; L shifts too
        DECLE   0                       ; done -> SLF fuzz from here
    ENDI

; ---------------------------------------------------------------------------
; DANCE_SETTLE -- the game's VBLANK display dance tail outlives the tick by
; a frame or two: its final ISR steps paint the last track cells and restore
; the EXEC vector THEMSELVES ($5F2F), and the tick's mainline does not wait
; for them.  Anything about to repaint BACKTAB (the peer-left screen) must
; wait the tail out or race its last writes.  Bounded spin, ~4 frames.
; ---------------------------------------------------------------------------
DANCE_SETTLE:
        PSHR    R5
        MVII    #6000,  R1
@@ds_l: MVI     $101,   R0
        CMPI    #$5E,   R0
        BEQ     @@ds_w
        CMPI    #$5F,   R0
        BNEQ    @@ds_done
@@ds_w: DECR    R1
        BNEQ    @@ds_l
        ; Tail never finished: a dance that started before the previous
        ; tail restored the vector SAVES a game body as "previous", and a
        ; terminal freeze can strand it installed forever -- repainting the
        ; status rows over whatever we draw.  Force the EXEC default.
        DIS
        MVII    #EXEC_ISR_DEF AND $FF, R0
        MVO     R0,     $100
        MVII    #EXEC_ISR_DEF SHR 8, R0
        MVO     R0,     $101
        EIS
@@ds_done:
        PULR    R7

; ---------------------------------------------------------------------------
; REC_CAPTURE -- record build: log the live EXEC cells for this tick into
; $9000 + T*4 ([L dec, R dec, L kp, R kp]); 768 ticks = 38 s at 20 Hz, ends
; at $9BFF (the FujiNet mailbox owns $9C00).  Dump with `m 9000 C00` and
; feed tools/mk_replay.py.
; ---------------------------------------------------------------------------
REC_CAPTURE:
        MVI     TICK_HI, R1
        SWAP    R1,     1
        ADD     TICK_LO, R1
        CMPI    #768,   R1
        BGE     @@rec_done
        SLL     R1,     2
        ADDI    #$9000, R1
        MOVR    R1,     R4
        MVI     EXEC_IN_L, R0
        MVO@    R0,     R4
        MVI     EXEC_IN_R, R0
        MVO@    R0,     R4
        MVI     EXEC_KP_L, R0
        MVO@    R0,     R4
        MVI     EXEC_KP_R, R0
        MVO@    R0,     R4
@@rec_done:
        MOVR    R5,     R7

; ---------------------------------------------------------------------------
; LS_VDISPATCH -- virtual input-event dispatch for one side (VD_SIDE: 0 =
; host/left, 1 = guest/right) at the current tick, replicating the EXEC
; scan's dispatch semantics ($15AC-$15DC) over the exchanged cell streams:
;   keypad cell k != 0 (values 1-3): call handler[k*2+2] with R0 = 1 on a
;     change, else 0 (the EXEC re-fires held keypad every scan)
;   $011F-cell fresh event (changed, bit 6 clear): value >= $80 -> keypad
;     handler [2] with R0 = k; disc (0-15) -> handler [0] with R0 = dir
; For Auto Racing: slot 0 = $5683, slot 2 = $5074 (course/car select uses
; keypad digits through it), slots 4/6/8 = $5103.
; Handlers are entered like the EXEC does it: R1 = controller index (0 =
; left, 1 = right), R0 = event value, return via R5.
; Fidelity note: an imperfect replication differs IDENTICALLY on both
; consoles (same input streams), so it can affect feel but never sync.
; ---------------------------------------------------------------------------
LS_VDISPATCH:
        PSHR    R5
        ; ring base: this side's stream lives in LOC_* if VD_SIDE == our
        ; role, else in RMT_*  (locally NET_ROLE = 0: LOC = left pad)
        MVI     VD_SIDE, R0
        CMP     NET_ROLE, R0
        BNEQ    @@vd_rmt
        MVII    #LOC_RING, R2
        B       @@vd_ld
@@vd_rmt:
        MVII    #RMT_RING, R2
@@vd_ld:
        MVI     TICK_LO, R1
        MOVR    R1,     R3
        ADDR    R2,     R3
        MVI@    R3,     R0
        MVO     R0,     VD_CUR
        DECR    R3
        MVI     TICK_LO, R0
        TSTR    R0
        BNEQ    @@vd_p1
        ADDI    #256,   R3              ; tick 0: prev slot wraps
@@vd_p1:
        MVI@    R3,     R0
        MVO     R0,     VD_PREV
        ADDI    #RMT_KP-RMT_RING, R2    ; matching KP ring (same delta for LOC)
        MVI     TICK_LO, R1
        MOVR    R1,     R3
        ADDR    R2,     R3
        MVI@    R3,     R0
        MVO     R0,     VD_KP
        DECR    R3
        MVI     TICK_LO, R0
        TSTR    R0
        BNEQ    @@vd_p2
        ADDI    #256,   R3
@@vd_p2:
        MVI@    R3,     R0
        MVO     R0,     VD_KPPRE
        ; ---- action-button release (stock: slot cleared -> R0 = -1)
        MVI     VD_KPPRE, R0
        TSTR    R0
        BEQ     @@vd_kp
        CMPI    #3,     R0
        BGT     @@vd_kp
        CMP     VD_KP,  R0
        BEQ     @@vd_kp                 ; unchanged: no release
        SLL     R0,     1
        ADDI    #2,     R0
        MVO     R0,     VD_TMP
        CLRR    R0
        DECR    R0                      ; R0 = -1
        JSR     R5,     LS_VCALL
@@vd_kp:
        ; ---- action-button press / held re-fire (classes 4/6/8 =
        ; top/left/right; the $0121-family cell holds 1-3 while held)
        MVI     VD_KP,  R0
        TSTR    R0
        BEQ     @@vd_disc
        CMPI    #3,     R0
        BGT     @@vd_disc               ; sanity: stored class is 1-3
        SLL     R0,     1
        ADDI    #2,     R0              ; slot = kp*2 + 2
        MVO     R0,     VD_TMP
        MVI     VD_KP,  R0
        CMP     VD_KPPRE, R0
        BEQ     @@vd_kheld
        MVII    #1,     R0              ; fresh press
        B       @@vd_kcall
@@vd_kheld:
        CLRR    R0                      ; held re-fire
@@vd_kcall:
        JSR     R5,     LS_VCALL
@@vd_disc:
        ; ---- fresh $011F event (changed, bit 6 clear): keypad ($80|k) ->
        ; slot 2 with R0 = k; disc (0-15) -> slot 0 with R0 = direction
        MVI     VD_CUR, R0
        CMP     VD_PREV, R0
        BEQ     @@vd_done
        ANDI    #$40,   R0
        BNEQ    @@vd_settle
        MVI     VD_CUR, R0
        ANDI    #$80,   R0
        BEQ     @@vd_d0
        MVII    #2,     R0              ; keypad -> slot 2
        B       @@vd_ds
@@vd_d0:
        CLRR    R0                      ; disc -> slot 0
@@vd_ds:
        MVO     R0,     VD_TMP
        MVI     VD_CUR, R0
        ANDI    #$7F,   R0
        JSR     R5,     LS_VCALL
        B       @@vd_done
@@vd_settle:
        ; ---- disc settle: the scan's held path ($15AC) fires slot 0 with
        ; R0 = -1 exactly once, on the pass after a disc event (the cell
        ; changes dir -> dir|$40).  Auto Racing's disc handler NEEDS it: a
        ; negative event marks the disc released (flag 2 at $0177+p*16);
        ; without it steering latches.  Keypad release marks $C0|k (bit 7
        ; set) and dispatches nothing -- excluded here.
        MVI     VD_CUR, R0
        ANDI    #$80,   R0
        BNEQ    @@vd_done
        CLRR    R0
        MVO     R0,     VD_TMP          ; slot 0
        CLRR    R0
        DECR    R0                      ; R0 = -1
        JSR     R5,     LS_VCALL
@@vd_done:
        PULR    R7

; LS_TBL_ADOPT -- if $035D holds anything but our null table, park it in
; GAME_TBL (an install happened since we last nulled).
LS_TBL_ADOPT:
        MVI     $35D,   R0
        CMPI    #NET_NULL_TBL+4, R0
        BEQ     @@ta_out
        MVO     R0,     GAME_TBL_LO
        SWAP    R0,     1
        MVO     R0,     GAME_TBL_HI
@@ta_out:
        MOVR    R5,     R7

; LS_VCALL -- invoke game handler [live table + VD_TMP] with event value
; R0, controller index = VD_SIDE.  No-op on a null entry.  Reads $035D
; directly so a handler-installed table applies to subsequent events in
; the same tick, exactly as the real scan would behave.
LS_VCALL:
        PSHR    R5
        PSHR    R0
        MVI     $35D,   R1
        TSTR    R1
        BEQ     @@vc_skip
        ADD     VD_TMP, R1
        MOVR    R1,     R4
        MVI@    R4,     R2
        ANDI    #$FF,   R2
        MVI@    R4,     R1
        SWAP    R1,     1
        ANDI    #$FF00, R1
        ADDR    R1,     R2              ; SDBD-equivalent pointer read
        TSTR    R2
        BEQ     @@vc_skip
        MVI     VD_SIDE, R1
        PULR    R0
        MVII    #@@vc_ret, R5
        MOVR    R2,     R7              ; enter the handler, EXEC-style
@@vc_ret:
        PULR    R7
@@vc_skip:
        PULR    R0
        PULR    R7

; LS_RING_INIT -- idle-fill all four input rings ($8400-$87FF): decoded
; cells to $40, keypad cells to 0.
LS_RING_INIT:
        PSHR    R5
        MVII    #RMT_RING, R4
        MVII    #512,   R1
        MVII    #$40,   R0
@@ri_a: MVO@    R0,     R4
        DECR    R1
        BNEQ    @@ri_a
        MVII    #512,   R1
        CLRR    R0
@@ri_b: MVO@    R0,     R4              ; R4 continues into RMT_KP/LOC_KP
        DECR    R1
        BNEQ    @@ri_b
        PULR    R7
