# In-place patch map for autorace.bin (word address -> as1600 expression).
# Symbols are defined in src/hook.asm / src/ram.asm.  Every site confirmed in
# build/autorace.dis (see spikes/NOTES.md, M2).  Building with
# tools/dump_rom.py and NO patch file must stay byte-identical to the
# original (make verify-org).
{
    # --- Cart header ---
    # $5002/$5003: EXEC timer table pointer -> relocated table in $6000 seg.
    0x5002: "NEW_TIMER_TBL AND $FF",
    0x5003: "NEW_TIMER_TBL SHR 8",
    # $5004/$5005: start-of-game vector -> netcode init shim (falls through
    # to the original $5037).
    0x5004: "NET_START AND $FF",
    0x5005: "NET_START SHR 8",

    # (No aux-timer arm shim: Auto Racing never calls the EXEC set-timer
    # APIs; its second game entry $51B7/interval 15 is virtualized whole in
    # the master dispatcher.)

    # --- Game RNG call sites -> canonical-RNG wrappers ---
    # The EXEC sound engine calls X_RAND1 every frame while noise SFX play
    # (caller $1CCE), advancing the shared LFSR at $035E in real-frame time.
    # The game's four RAND calls are therefore routed through wrappers that
    # swap the canonical (sim-space) RNG in and out around the call.
    # $5064 is in the start-of-game path (random default course).
    0x5065: "((NET_RAND2 SHR 10) SHL 2) OR $0100",   # JSR R5 @ $5064
    0x5066: "NET_RAND2 AND $3FF",
    0x54F7: "((NET_RAND2 SHR 10) SHL 2) OR $0100",   # JSR R5 @ $54F6
    0x54F8: "NET_RAND2 AND $3FF",
    0x52F9: "((NET_RAND1 SHR 10) SHL 2) OR $0100",   # JSR R5 @ $52F8
    0x52FA: "NET_RAND1 AND $3FF",
    0x59C9: "((NET_RAND1 SHR 10) SHL 2) OR $0100",   # JSR R5 @ $59C8
    0x59CA: "NET_RAND1 AND $3FF",

    # --- Raw-port latch reads (top of the 20 Hz tick) ---
    # MVI $01FE/$01FF operands.  The values feed ONLY the EXEC scan's
    # edge-detection cells $0123/$0124 (never read back by cart code) --
    # input reaches game state exclusively through the $035D dispatch.
    # Redirected to the shadow pair anyway so no live-port read remains in
    # game code.  Note right port first, then left.
    0x5120: "SHADOW_RAW_R",                          # was MVI $01FE @ $511F
    0x5125: "SHADOW_RAW_L",                          # was MVI $01FF @ $5124
}
