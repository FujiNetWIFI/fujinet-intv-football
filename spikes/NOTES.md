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

## M2 findings (dis1600, 2026-08-16) — every plan-time decode CONFIRMED

**1. Input model = Baseball hybrid, confirmed [dis].** Exactly ONE code
reference to $011F/$0120 in the whole cart: the `ADDI #$011F,R2` at $5636
(other grep hits are graphics data tables). The enclosing routine L_561E
reads `[$011F + (G_016B XOR inline-param)]` — the computed index selects
EITHER controller, so the shadow pair must be consecutive left,right cells
and the single operand patch covers both. The read is reached from L_55F7,
called at $503B **inside the fast tick** — polling happens in sim space.
Consumption: `ANDI #$C0` — zero (fresh disc event) triggers `.EXEC.629`
with R4 = an inline param. G_0182 (per-phase input mask) gates it.

**2. $5A12 confirmed benign [dis].** `MVO@` init loop stepping R4 by 5,
`CMPI #$035D / BLT` exclusive bound — last write ≤ $035C (object table
init). Nothing in the cart ever READS [$035D]; only the EXEC scan does.
Adopt/null logic fully safe. The block ($5A03-$5A1D) ends: `MVO R3,G_0160`,
phase := 0, install EXEC null table — the between-plays reset.

**3. $5041 confirmed misdecode [dis].** dis1600 shows `JSR R5,L_5646` at
$503E and `JSR R5,L_5722` at $5041 — fast-tick body calls, not a STIC write.
Real STIC writes: $554A ($0030) and $554C ($0020) only, both INSIDE the
game ISR body (below).

**4. Football HAS a VBLANK ISR dance** (plan-time recon missed it — the
writes are labelled `.ISRVEC.0/1` in the dis, not `$0100/$0101`; grep for
`ISRVEC` too, future ports). Same class as Auto Racing's:

```
L_54E8 (display routine, called at $5047 from the fast tick EVERY tick):
  $54F9-$5505  scroll params -> $0166/$0167/$0168
  $5506-$550C  save current ISR vector ($0100/$0101) -> $0163/$0164
  $550D-$5513  install game ISR body = R7+$16 = $5524 -> $0100/$0101
  L_5515       mainline EIS + spin on mailbox G_0169 (SARC bit flags)
game ISR body $5524:
  integrates object motion ($031D+ table, scroll accum $0160/$0161),
  shifts BACKTAB rows ($0200-$02E6 / $0212+ walks, direction by G_0166),
  $5548: MVI G_0162 -> MVO $0030 (hscroll) -> MVO $0020 (display enable)
  $5552: restore saved vector from $0163/$0164
  $5594: MVO R2,G_0169  (completion flags -- the mailbox)
```

- The dance runs EVERY fast tick -> the hscroll reassert is per-tick, so
  RS_REBASE needs NO $0030 re-push after a resync (AR conclusion carries).
- All dance state ($0160-$0169) is inside $015D-$01EF: CRC-covered, and at
  tick boundaries the vector is EXEC_ISR_DEF and the mailbox is settled.
- DANCE_SETTLE STAYS (M9): watch $0101 == $55 (FB_ISR_BODY high byte),
  force-restore EXEC_ISR_DEF on timeout.
- Passes can be >3 real frames mid-dance; cadence gate measures pass
  alignment, not wall time (PORTING.md §2.1 caveat applies).

**5. Handler tables: ONE MVO site, VARIABLE tables — the inline-table-after-
JSR idiom** (Baseball's $5450 pattern). L_55D6: `JSR R4,L_55ED` leaves R4 =
$55D9 (table base); `ADD@ R5,R4` adds the CALLER's inline offset; MVO at
$55F4 installs. L_55F0 installs the EXEC null table $1906. Table $55D9
slots (byte-pair lo,hi per 2 words): +0 null, +2 $5752, +4 $588A, +6 $5874,
+8 $5874, rest null. Callers: $573E (offset 0), $5A3E (offset word $000A),
null installs at $50CD (end-of-quarter path) and $5A1B (between-plays
reset). GAME_TBL values observed live at M3 will label the phases; the
quiescent gate can read GAME_TBL == NULL ($1906) AND FB_PHASE == 0.

**6. Phase machine [dis].** G_016A = phase, 0-$B. Setter L_5597 (inline
param) also loads G_0182 (input mask) from the per-phase table at $559D.
Observed inline phase values: 0 ($50FB boot, $5968, $5A17 reset), 1 ($50B8),
2 ($573A play setup), 3 ($5800), 4 ($5851), 5 ($560C), 6 ($58A8), 7 ($5AF6),
8 ($5B1F), 9 ($59D9), $A ($512A), and CMPI #$B at $5601. Semantics pinned
live at M3/M8.

**7. Sound-gate audit: CLEAN — no shims needed.** Cart sound calls:
`.EXEC.A61` ($1A61 music arm) x5 with inline track words, X_PLAY_CHEER1 x5,
X_PLAY_SFX1 x4 (inline SFX data), X_PLAY_WHST1 x2, X_PLAY_NOTE x1,
X_PLAY_MUS2 x1. ZERO cart reads of any sound-state cell ($0149, $014A/B,
$0159, $0125/6, $0143/4, $035F) and no conditional branch consumes a sound
return anywhere. Sound is presentation-only, Baseball-style. The AR leak
class does not apply to this cart.

**8. Scratch census [dis].** Cart's direct cell references: $0116/$0117
(EXEC playfield boundary limits, written ONCE at FB_START with $B4/$00 —
constants, read by the EXEC motion engine; no coverage needed), $0123/$0124
(latch writes), $0160-$0198 (game scratch — inside $015D-$01EF), $031F-$0323
+ $035B/$035C (object table), $035D. **CRC range $015D-$01EF and the AR
resync image layout copy verbatim.** Image tail: RNG_LO/HI, SLOW_CNT,
RS_SPARE, GAME_TBL_LO/HI.

**9. Slow tick $56EF = the game clock [dis].** G_0181 bit 0 = clock hold
(skip). Decrements the 16-bit clock at $016F/$0170 with a $C4 borrow rule;
at zero: G_0181 := 3, JSR L_5FDF (fanfare), and if FB_PHASE <= 4 runs the
end-of-quarter sequence L_50CC (null table + $1A61 + cheer). No input, no
RNG inside. Pure sim state, all CRC-covered. L_5719 (XOR toggle of G_0181
bit 0) = clock start/stop, called from game logic.

**10. $0121/$0122: zero cart references** — action/keypad classes enter only
through the dispatch. Wire format unchanged (dec $011F + kp $0121).

**11. Patch map: 13 words**, written to tools/patches.py — header 4, RNG 6,
polled-input 1 ($5637), raw-latch 2 ($5729/$572E). No timer shims, no sound
shims. Gate `make verify-patch` runs once the M3 hook builds.

## M3 findings (2026-08-16)

- **verify-patch PASS**: 13 declared sites, 13 changed, no undeclared diffs.
- **Cadence gate PASS (objective)**: stock vs hooked, breakpoints on $5034 +
  $56EF — identical pattern `14xF, S, 15xF, S, ...` (slow fires first on
  pass 15 and every 15th after, BEFORE that pass's fast tick, both builds).
- **Tick rate measured**: ~59.9k cycles/tick ≈ 4 NTSC frames wall in the
  pre-game phase — the display dance replaces the EXEC ISR ~1 frame/tick
  and $0102 doesn't count it (PORTING.md §2.1 caveat; AR saw the same).
  Individual passes ranged 2-6 frames. Sim semantics stay per-pass (20 Hz
  nominal); at ~15 Hz wall, d=3 costs ~200 ms.
- **virt == hook bit-identical**, two forms:
  (a) idle run parked at tick 239: game scratch + BACKTAB + object table +
  $035D all identical;
  (b) injected-event run (16 checkpoints through tick 304: keypad digits,
  Enter, action top, disc on both sides — real state mutations included)
  identical except $035E/$035F (real-frame sound domain, excluded by
  design).
- **Headless injection recipe for THIS cart** (hybrid model — simpler than
  AR's): `b 5034` + `b 1532`. Per pass: at the $5034 stop poke the raw
  shadows (`e 8142 <~L>`, `e 8143 <~R>`, active-low), then force the scan's
  post-XOR value at two $1532 stops (`g 2 <L>`, `g 2 <R>`, active-high).
  The game's own latch (L_5722) is phase-gated and reads the POKED shadow
  cells inside the tick, so latch and scan always agree with 3 stops/pass
  and no conditional breakpoints. Scripts generated by scratch
  gen_probe.py.
- **Boot flow observed**: phase 1 (intro, $035D=$1906 null) auto-advances
  to phase 2 (play select, $035D=$55D9, clock parked 15:00, G_0181 hold=1).
  Screen: row 0 `Home 15:00 Visitor` (Home = LEFT column), row 11
  `1st and 10 on 20` — the game opens at scrimmage, NO kickoff.
  **Lobby handover marker: `Home` in BACKTAB row 0** (colour-stack cards).
- **Play-select mechanics (partial, for the M5 script)**: table at $57AA =
  per-side valid pick ranges. First-scanned side writes $0172 via keys
  7/8/9 -> picks 1/2/3 (its handler path gates on G_0171 bit 0); the other
  side's picks go to $0176 (bit 1); '0' ($A) = special (L_574A/L_574F),
  Enter ($B) = L_5749 ready path. Observed: def '8' -> $0172=2, then both
  Enters -> G_0171=3, phase:=3 (play live, mask $50). In-play the play sat
  static with only R-disc bits ($0171 -> $F) registering — offense side /
  runner-motion mapping still open, resolved at M5.
- Scan order note: the first $1532 hit each pass maps to the side whose
  pick lands in $0172; which physical port that is (left vs right) is
  pinned at M5 with the BACKTAB score columns.

## M4 findings (2026-08-16) — interception proof, objective form

Lag build (SPIKE_VIRT, d=20): keypad '8' injected at ticks 100-104.
- Dispatch surface: the pick cell $0172 flipped at tick ~121 — exactly
  d=20 ticks after the press (virt-d0 registers it within the hold window).
- Polled surface: the shadow pair showed the delayed $88 (fresh) at tick
  ~120 and $C8 (held) at ~124 while the live $011F/$0120 had long returned
  to idle — SHADOW_FROM_RINGS delivers ring[T], proven.
- No cell changed during the delay window: no unpatched immediate path.

**Scan-order correction (this cart): the first $1532 scan hit each pass is
the RIGHT controller ($0120), the second the LEFT ($011F)** — proven by the
press landing in RMT_RING/SHADOW_CTRL_R. The injection harness pairs the
first g-force with the right pad accordingly (gen_probe.py fixed).  The
crossed version went unnoticed in phase 2 because the game latch is
phase-gated off there (mask $D0 AND 3 = 0) — in latch-live phases
(5/6/7/8/$B) scan and latch MUST agree per side or every pass looks like
an edge.  Consequence: the "L-x" probe results above were physically the
RIGHT pad; with G_016B=0 the right pad owns the $0172 pick path.

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
