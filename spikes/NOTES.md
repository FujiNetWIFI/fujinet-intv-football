# NFL Football netplay — working notes

Third port of the FujiNet netplay engine, after Baseball
(`~/Workspace/intv-baseball-experiment`) and Auto Racing
(`~/Workspace/fujinet-intv-auto-racing`). `PORTING.md` in this repo is the
procedure, updated with the Auto Racing port's lessons. EXEC internals live
in the baseball repo's `spikes/NOTES.md`; second-port deltas (injection
recipe, event semantics, VBLANK dance, leak forensics) in the Auto Racing
repo's. This file holds only what is Football-specific.

Everything below is recon.py output (linear scan — candidates, not proof)
plus a manual decode of the raw words at every open-question site, done at
plan time. Each item gets confirmed against `make dis` output at M2;
confirmed items get marked **[dis]**.

## Recon results (recon.py against rom/football.bin, 2026-08-16)

Cart: 4096 words at $5000-$5FFF (8 KB), md5 d0ef7a007e8635a13942fb6da48012a2.
Netcode segment at $6000 is free, as in both prior ports.

Header:

```
timer table    $5026      start-of-game vector target  $5075
GRAM init      $5E54
$500D = $01    border extension
$500E = $00    COLOUR STACK mode  (like Baseball; AR was fg/bg)
CS0..CS3       $01 / $04 / $01 / $01     border $01
```

-> `src/ui/text.asm` is the Baseball colour-stack variant, not AR's fg/bg one.

Timer table @ $5026 — three entries, TWO of them game logic, **slow listed
before fast** (opposite of Auto Racing):

```
entry 0: $1A71 interval $8001   music, stopped/one-shot -> keep verbatim as entry 0
```

The pass is 3 frames — **measured** on this cart at M1 (2026-08-16):
PORTING.md §2.1 recipe, `m 100 8` -> `$0102 = 3, $0103 = 3`. 20 passes/s.
M1 gate: `make verify-org` byte-identical (as1600 0 errors, cmp exact).

```
entry 1: $56EF interval $000F   every 15   = 1.33 Hz, 751 ms  (game clock?)
entry 2: $5034 interval $0001   every pass = 20 Hz, 50 ms tick
```

- The EXEC dispatch walks entries in order, so on every 15th pass the SLOW
  entry fires BEFORE the fast one. MASTER_TICK and LS_PASS must call
  FB_SLOW_STEP before FB_TICK_FAST — the flip of AR's fast-then-slow.
- SLOW_CNT (the /15 countdown) is sim state: freezes in stalls, travels in
  the CRC and the resync image tail, armed to 15 at NET_START (first slow
  fire on pass 15, before that pass's fast tick — matches the EXEC's
  decrement-to-zero-then-reload countdown).
- No calls to $181E/$1831/$1838/$1844 anywhere -> no ARM_AUX_SHIM analogue.

RNG — 3 call sites (operand words verified against raw ROM bytes):

```
$5C2E JSR $167D X_RAND1   patch operand words $5C2F/$5C30 (= $0114/$027D)
$5B29 JSR $169E X_RAND2   patch $5B2A/$5B2B (= $0114/$029E)
$5B2F JSR $169E X_RAND2   patch $5B30/$5B31 (= $0114/$029E)
```

Input — **the Baseball hybrid model (polled + dispatch), not AR's
dispatch-only** (pending [dis]):

```
$5634: ADDI #$0004,R3          ($02FB $0004)
$5636: ADDI #$011F,R2          ($02FA $011F)   <- operand word $5637: PATCH -> SHADOW_CTRL
$5638: MVI@ R2,R1 ...ANDI #$C0...              consumes fresh/held/keypad flag bits
```

- A real computed-index read of $011F+n with the flag-bit consumption idiom,
  exactly Baseball's $55FB pattern. So SHADOW_CTRL/SHADOW_CTRL_R come back
  (Baseball ram map), UPDATE_SHADOW goes hybrid (raw pair + decoded
  pass-through), and LS_PASS re-adds Baseball's role-based shadow feed.
- M2 must chase: what seeds R2 (player selector cell — a phase-machine
  lead), and whether any OTHER $011F/$0120 reads exist (grep dis for
  operands + MVII loads).

Raw-port latch subroutine at $5728 (same shape as AR's pre-latch):

```
$5728: MVI $01FE,R0    <- operand word $5729: PATCH -> SHADOW_RAW_R
$572A: COMR R0
$572B: MVO R0,$0124
$572D: MVI $01FF,R0    <- operand word $572E: PATCH -> SHADOW_RAW_L
$572F: COMR R0
$5730: MVO R0,$0123
$5732: JR R5
```

(Right before left, as AR. The MVO destinations stay — recon's "$572C/$5731"
hits were the MVO operand words, patch class 3 in PORTING.md §3.)

$035D — ONE install, $55F5 (MVO via R4). M2: decode the installed table
address + slot handlers; then a live `w 35D` census title->kickoff->play->
score (Baseball installed tables from dispatched handlers too — invisible to
recon). If per-phase tables exist, GAME_TBL == dead-ball table becomes the
resync quiescent gate, Baseball style.

Display — TWO real STIC writes, in one spot (pending [dis]):

```
$5546: conditional branch (walk at M2: unconditional per tick, or on-change?)
$5548: MVI $0162,R0
$554A: MVO R0,$0030    ; horizontal scroll delay
$554C: MVO R0,$0020    ; display enable handshake
```

- Backing cell $0162 is INSIDE $015D-$01EF -> already covered by LS_CKSUM
  and resync image section 1. No image layout change.
- RS_DISPLAY_RESET must not touch $0030 (AR's variant already doesn't).
- If the write is on-change-only, RS_REBASE must push restored $0162 into
  $0030 after a resync. If per-tick, nothing to do.

Known recon false positives (checked against raw words at plan time):

- $5041 "MVO R6,$0004" — misaligned decode; really two consecutive
  `JSR R5,$5646` / `JSR R5,$5722` instructions ($0004 $0154 $0246 /
  $0004 $0154 $0322).
- $5A12 "$035D reference" — `CMPI #$035D,R4` loop bound in an init loop
  ($5A0F: ADDI #$0005,R4; $5A11: CMPI #$035D,R4; branch back). The object
  table ends at $035C; the loop never touches the handler-table pointer.
  Confirm at M2 that nothing else reads [$035D].

Quiescent point — football has genuine dead-ball moments (between plays,
both keypads picking plays). Candidates: the phase cell that seeds the $5637
read index, the $035D table census, or a state cell found from the $5034 /
$56EF heads. Chosen at M2, wired at M8. RS_PEND_MAX ~ 60 (3 s at 20 Hz).

Sound-gate audit (PORTING.md §7.8, MANDATORY at M2): $1A61 appears ~5x in
the ROM's most-called list. Find every game call into gated EXEC sound
entries and check whether any game LOGIC branches on the X_SFX_OK ($0149)
outcome; if yes, shim the sites in the patch map before determinism work.

ISR dance check (M2): grep the dis for writes to $0100/$0101. None ->
football has no VBLANK dance, DANCE_SETTLE gets deleted, no 4-frame menu
passes expected. Some -> port AR's dance handling wholesale.

## Decisions taken at plan time

- Server: `server/intv_relay_server.py`, default port **9102** (Baseball
  9100, AR 9101); echo latency probe moves to **9103**. DEFAULT_DELAY stays
  3 -> 150 ms at 20 Hz, tuned at M10 from HUD `L`.
- Wire format: Baseball's 5-byte INPUT frame (dec $011F + kp $0121),
  unchanged — the polled site reads the decoded cell and the dispatch replay
  consumes the same two bytes. No SES_FLEN/ghost_peer/server changes.
- Netcode symbols keep Baseball's names; game symbols are FB_*
  (FB_TICK_FAST $5034, FB_TICK_SLOW $56EF, FB_START $5075, FB_PHASE tbd,
  FB_HSCROLL_CELL $0162).
- Host (role 0) = left controller, as both prior ports. Home/visitors
  wording: derive empirically at M7 (score with the left controller, watch
  which scoreboard column moves) unless the manual turns up in learn/.
