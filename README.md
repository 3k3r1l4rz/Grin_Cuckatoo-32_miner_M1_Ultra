# m1_grin_miner — standalone Grin Cuckatoo-32 miner (Apple M1 Ultra / Metal)

A self-contained live miner: GPU full-solve (Metal) + stratum job/submit pipeline +
optional cheap telemetry (not included) + headless launcher. Carved from `mine34_platform`.

- **Speed:** ~**0.53 graphs/s** warm C32 (≈1.9 s/graph; cold first graph ~6.5 s for the 93 GB first-touch). Verified live, bit-for-bit the source solver.
- **Correctness:** recovered 42-cycles pass the ported Tromp `verify()` → `POW_OK` before any submit.
- **Self-contained:** system Apple clang (`xcrun`), `-framework Metal -framework Foundation`. No external repo; the live binary needs no vendored Tromp.

## Layout
```
src/mine34_live.m            the miner: Metal solver + stratum client + parallel steerer + submit
submit_source/               linked C deps: m1rsi_core (bit-exact keys), sidecar job-assigner + submit
Makefile                     `make` -> ./mine34_live
miner.conf                   all config (stratum, solver, steerer, telemetry, supervisor)
start.sh / stop.sh           headless launcher (detached, pidfile, auto-restart) / stopper
debug/strat_probe.c          standalone stratum login/job probe (diagnostics)
```

## Prerequisites — the node side MUST be serving real jobs
The miner needs a grin 5.4.0 mainnet node whose **stratum** is up AND building real block
templates. That requires the **treasury wallet** to be listening so the node can fetch a coinbase:

1. **Treasury wallet** (foreign API) up: `~/.local/bin/start-grin-wallet-treasury-listen.sh` → listens on **3417**.
2. **Node** up with `wallet_listener_url = "http://127.0.0.1:3417"` (MUST match the wallet's `api_listen_port`)
   → `~/.local/bin/start-grin-node.sh` → stratum on **3416**.
3. **Readiness = a real non-zero job height**, not just "port open". Check:
   ```
   ./debug/strat_probe 127.0.0.1 3416     # expect result:"ok" + getjobtemplate height>0
   ```
> If the miner prints `STRATUM_LOGIN_FAIL`, it is almost always node-side: the node can't reach the
> treasury wallet (wrong port / wallet down), so stratum has no job and stays silent on login.

## Build
```
make            # -> ./mine34_live   (also: make clean)
```

## Configure
Edit `miner.conf` (KEY=VALUE). Safe defaults mine a local node with steerer + telemetry OFF.
Key knobs: `M1_STRATUM_HOST/PORT/LOGIN/PASSWORD`, `EDGE_BITS=32`, `ROUNDS=160`, `MAXGRAPHS=0` (forever),
`M1_STEER` (leave blank = OFF; unvalidated), `M1_TELEMETRY_PATH` (blank = zero-cost OFF).

## Run (headless)
```
./start.sh           # detached, logs to ./logs/miner-<ts>.log, pidfile, auto-restart
./start.sh -f        # foreground (live console)
tail -f logs/miner-*.log
./stop.sh            # clean SIGTERM -> SIGKILL escalation + orphan sweep
```

## Verifying submits (node-side is authoritative)
The miner prints `42-CYCLE found! ... verify=POW_OK` → `SUBMITTING share -> node` → `SUBMIT resp: ...`.
**`SUBMIT resp` only means *received*, not *accepted*** (the node returns `result:ok` on receipt even for a
stale share). The real verdict is in the node log:
```
grep -E 'Got share|submitted too late' ~/.local/share/grin/node/grin-server.log
```
- `Got share at height H ... submitted by m1miner` = **accepted share**.
- `Share at height H ... submitted too late` = **stale** (the node already advanced past that height).

## Known limitation — stale shares
The miner refreshes its job only every 8 graphs and does **not** consume the node's unsolicited job
pushes, so when a new block arrives mid-loop it keeps mining the old height for up to ~15 s and those
found cycles are rejected `submitted too late`. Measured ~3% of graphs yield a 42-cycle (the real
Cuckatoo rate) and roughly half of those submit in time at mainnet's churn. **Improvement:** consume the
node's `method:"job"` pushes to refresh height within ~2 s → most found shares would land. (Not yet
applied; it touches the verified solver loop.)
