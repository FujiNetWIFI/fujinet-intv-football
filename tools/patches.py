# In-place patch map for football.bin (word address -> as1600 expression).
# Symbols are defined in src/hook.asm / src/ram.asm.  Every site confirmed in
# build/football.dis (see spikes/NOTES.md, M2).  Building with
# tools/dump_rom.py and NO patch file must stay byte-identical to the
# original (make verify-org).
{
    # --- Cart header ---
    # $5002/$5003: EXEC timer table pointer -> relocated table in $6000 seg.
    0x5002: "NEW_TIMER_TBL AND $FF",
    0x5003: "NEW_TIMER_TBL SHR 8",
    # $5004/$5005: start-of-game vector -> netcode init shim (falls through
    # to the original $5075).
    0x5004: "NET_START AND $FF",
    0x5005: "NET_START SHR 8",

    # (No aux-timer arm shim: Football never calls the EXEC set-timer APIs;
    # both game entries -- $56EF/15 slow game clock and $5034/1 fast tick --
    # are virtualized whole in the master dispatcher, slow BEFORE fast to
    # match the original table order.)

    # --- Game RNG call sites -> canonical-RNG wrappers ---
    # The EXEC sound engine calls X_RAND1 every frame while noise SFX play
    # (caller $1CCE), advancing the shared LFSR at $035E in real-frame time.
    # The game's three RAND calls are therefore routed through wrappers that
    # swap the canonical (sim-space) RNG in and out around the call.
    0x5C2F: "((NET_RAND1 SHR 10) SHL 2) OR $0100",   # JSR R5 @ $5C2E
    0x5C30: "NET_RAND1 AND $3FF",
    0x5B2A: "((NET_RAND2 SHR 10) SHL 2) OR $0100",   # JSR R5 @ $5B29
    0x5B2B: "NET_RAND2 AND $3FF",
    0x5B30: "((NET_RAND2 SHR 10) SHL 2) OR $0100",   # JSR R5 @ $5B2F
    0x5B31: "NET_RAND2 AND $3FF",

    # --- Polled decoded-input read (inside the fast tick, via L_55F7) ---
    # ADDI #$011F,R2 operand at $5636; the index seed is G_016B XOR an
    # inline param, so the site reads EITHER controller's decoded cell.
    # SHADOW_CTRL/SHADOW_CTRL_R must therefore be consecutive cells in
    # left,right order, exactly like the EXEC pair.  This is the Baseball
    # hybrid model: Football polls AND dispatches.
    0x5637: "SHADOW_CTRL",                           # was ADDI #$011F @ $5636

    # --- Raw-port latch reads (inside the fast tick, via L_5722) ---
    # MVI $01FE/$01FF operands.  The values feed ONLY the EXEC scan's
    # edge-detection cells $0123/$0124 (never read back by cart code).
    # Redirected to the shadow pair anyway so no live-port read remains in
    # game code.  Note right port first, then left.  The whole latch routine
    # is gated by the per-phase input mask (G_0182 AND 3).
    0x5729: "SHADOW_RAW_R",                          # was MVI $01FE @ $5728
    0x572E: "SHADOW_RAW_L",                          # was MVI $01FF @ $572D
}
