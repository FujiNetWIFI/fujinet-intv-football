# Auto Racing FujiNet netplay

Port of Mattel Intellivision Auto Racing (1979) to two-player FujiNet netplay,
following the working Baseball port at `~/Workspace/intv-baseball-experiment`.

Read these before changing anything:

- **`PORTING.md`** — the porting procedure (copied from the baseball repo).
  §8 is the gated milestone sequence this repo follows; §9 is the release
  checklist. Every claim in it is measured, not assumed.
- **`spikes/NOTES.md`** — Auto-Racing-specific recon, risks, and decisions.
  EXEC internals live in the baseball repo's `spikes/NOTES.md`.

Conventions:

- Netcode symbols keep Baseball's names (LS_/RS_/SES_/NET_/FT_/MB_*);
  game symbols are `AR_*`. Build artifacts are `build/autorace_*`.
- Netcode RAM starts at `$8080` — never below (STIC decode alias), and the
  build cfg declares cart RAM only to `$9BFF` (FujiNet mailbox owns `$9C00+`).
- `make rig` / `m4` / `peerleft` / `lobby` force the 127.0.0.1 server; never
  point automated runs at a production endpoint.
- Server: `server/intv_relay_server.py`, default port 9101 (Baseball owns
  9100 on a shared host).

Toolchain: as1600 / dis1600 / bin2rom; jzIntv at
`~/Workspace/jzintv-20200712-src/bin/jzintv` (headless: SDL dummy drivers);
fujinet-pc-rs232 dist at `~/Workspace/fujinet-pc-rs232/build/dist`.
