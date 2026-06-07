# m1_grin_miner

Standalone Grin Cuckatoo-32 miner for Apple Silicon, built around a Metal full
solver and a small stratum submit pipeline.

The current target machine is an Apple M1 Ultra. Warm C32 throughput is about
0.53 graphs/second, or roughly 1.9 seconds per graph. The first graph is slower
because it includes Metal setup and unified-memory first touch.

Recovered 42-cycles are checked with the ported Tromp verifier before submit.
In the live validation run, submitted shares were accepted by a local Grin
5.4.0 mainnet node.

## Project Layout

```text
src/mine34_live.m            Metal solver, stratum client, steering, submit path
src/mine34_steer.m           steering support
submit_source/               C support code for keys, job assignment, submit
debug/strat_probe.c          stratum login and job-template probe
Makefile                     builds mine34_live and debug tools
miner.conf                   runtime configuration
run.sh                       foreground runner
start.sh                     detached launcher
stop.sh                      stopper and cleanup script
releases/                    packaged binary releases
```

## Requirements

- Apple Silicon macOS with Metal support.
- Enough unified memory for Cuckatoo-32. The miner reports about 74 GB in use.
- Grin 5.4.0 mainnet node.
- Grin wallet foreign API for coinbase generation.

The miner uses system Apple tooling and frameworks:

```text
xcrun
Metal
Foundation
```

## Node And Wallet

Start the treasury wallet before starting the node. The node needs the wallet
foreign API for coinbase output construction.

Expected local ports:

```text
treasury wallet foreign API   127.0.0.1:3417
node owner API                127.0.0.1:3413
node stratum                  127.0.0.1:3416
```

The node config should match the wallet listener:

```toml
wallet_listener_url = "http://127.0.0.1:3417"
enable_stratum_server = true
stratum_server_addr = "127.0.0.1:3416"
```

Check stratum readiness with:

```sh
./debug/strat_probe 127.0.0.1 3416
```

A usable response includes `result:"ok"` and a non-zero job height. If the miner
prints `STRATUM_LOGIN_FAIL`, check the wallet listener and the node's
`wallet_listener_url` first.

## Build

```sh
make
```

The default build produces:

```text
./mine34_live
./debug/strat_probe
```

Clean build output with:

```sh
make clean
```

## Configuration

Edit `miner.conf`. It is a simple `KEY=VALUE` file.

Common settings:

```text
M1_STRATUM_HOST
M1_STRATUM_PORT
M1_STRATUM_LOGIN
M1_STRATUM_PASSWORD
EDGE_BITS=32
ROUNDS=160
MAXGRAPHS=0
M1_STEER=
M1_TELEMETRY_PATH=
```

`MAXGRAPHS=0` runs continuously. Leave `M1_STEER` and `M1_TELEMETRY_PATH` blank
for the conservative local-node path.

## Run

Foreground:

```sh
./run.sh
```

Headless:

```sh
./start.sh
tail -f logs/miner-*.log
./stop.sh
```

Use foreground mode while checking a new node or wallet setup.

## Submit Verification

The miner log shows the local proof and submit path:

```text
42-CYCLE found! ... verify=POW_OK
SUBMITTING share -> node
SUBMIT resp: ...
```

`SUBMIT resp` confirms the node received the submit. The node log gives the
accepted-or-stale verdict:

```sh
grep -E 'Got share|submitted too late' ~/.local/share/grin/node/grin-server.log
```

Typical outcomes:

```text
Got share at height H ... submitted by m1miner
Share at height H ... submitted too late
```

## Validation Snapshot

Live C32 run against a local Grin 5.4.0 node and wallet:

```text
warm throughput:  about 0.53 graphs/second
warm timing:      about 1.83-1.86 seconds/graph
cold first graph: about 6.5 seconds in earlier full first-touch runs
```

Correctness and submit summary:

```text
found=22
ok=22
fail=0
submitted=22
graphs=1124
```

The miner reports the share-mining path, not exhaustive cycle enumeration.

## Current Limitation

The miner currently refreshes its job every 8 graphs and does not consume the
node's unsolicited `method:"job"` updates. If the chain advances during that
window, a locally valid cycle can arrive after the node has moved to the next
height and will be logged as stale.

The next improvement is to consume job updates inside the mining loop so height
changes are picked up quickly without disturbing the verified solver path.

## Binary Release

The current packaged binary release is under:

```text
releases/m1_grin_miner_m1ultra_binaries_a67866a_20260607T091251Z/
```

Inside that directory:

```sh
shasum -a 256 -c SHA256SUMS
./run-no-telemetry.sh
```
