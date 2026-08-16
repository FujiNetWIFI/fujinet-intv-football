# NFL Football — FujiNet two-player netplay

Mattel Intellivision NFL Football (©1978/79), patched for two-console
lockstep netplay over FujiNet. Third port of the engine, after Baseball
(`~/Workspace/intv-baseball-experiment`) and Auto Racing
(`~/Workspace/fujinet-intv-auto-racing`). Procedure and lessons:
`PORTING.md`; Football-specific engineering log: `spikes/NOTES.md`.

## Architecture

Both consoles run the whole original game, patched at 13 words (header
vectors, 3 RNG call sites, the polled-input operand, 2 raw-latch operands),
in delay lockstep: one 6-byte INPUT frame per player per 50 ms game tick,
relayed by `server/intv_relay_server.py` (port 9102), CRC compared every 64
ticks, desync repaired by a host state push gated on football's dead-ball
phases. The original timer table (slow game clock BEFORE the 20 Hz fast
tick) is virtualized slow-then-fast in the master dispatcher. Input is the
Baseball hybrid: one polled computed-index read (shadow pair) plus the
`$035D` event dispatch (nulled for the real scan, replayed in sim space).

Seats: host = left seat = HOME (defense first), guest = right seat =
VISITOR (first possession). Each player uses their own left controller.

## Status (2026-08-16)

All emulated gates pass:

- `make verify-org` — byte-identical rebuild of the original ROM
- `make verify-patch` — 13/13 declared patch sites, no undeclared diffs
- cadence + `make run-hook` — stock timer behaviour, slow-before-fast
- virt == hook — bit-identical with injected events through tick 300+
- `make run-lag` — both input surfaces lag exactly d ticks
- `make det` — A/B determinism with stall injection, 1024 ticks, incl. a
  complete scripted play (picks, snap, live run, tackle, next down)
- `make echo-test` — 100/100 transport rounds
- `make rig` — two consoles auto-matched: 2,970 ticks, 44 CRC pairs, 0
  mismatches, DIAG all zero
- `make lobby` — 12/12 UI checks, both roles, handover to the stock game
- `make m4` — injected desync detected and repaired at the dead-ball gate
- `make peerleft` — both branches (OPPONENT LEFT / CONNECTION LOST)

Not yet done: real-hardware validation on two PiRTO IIs
(`build/football_net.rom` release, `build/football_nethud.rom` bring-up
with the HUD row; endpoint `fujinet.online:9102` baked in via
`make rom SRV_HOST=... SRV_PORT=...`), and a record-and-replay determinism
pass over live human play (`make run-rec`).

## Build / test

Targets mirror the sibling ports: `verify-org`, `verify-patch`, `hook`,
`virt`, `lag`, `det`, `echo-test`, `rig`, `m4`, `peerleft`, `lobby`,
`rom`, `rom-hud`, `dis`, `recon`. Automated network tests always force the
127.0.0.1 relay on port 9102. Toolchain: as1600 / dis1600 / bin2rom,
jzIntv at `~/Workspace/jzintv-20200712-src/bin/jzintv` (headless via SDL
dummy drivers), fujinet-pc-rs232 dist at
`~/Workspace/fujinet-pc-rs232/build/dist`.
