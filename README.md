# uart-apb-ip

A UART (TX, RX, baud generator, FIFOs) with an AMBA APB3 register interface,
written in SystemVerilog and verified with a self-checking testbench, SVA, and
a regression that runs in CI. Free toolchain only: **Verilator ≥ 5.0**.

> **Status: scaffold.** The RTL under `rtl/` is intentionally empty tie-off
> stubs, so `make` fails until you implement it. That red → green journey is
> the project.

## Who wrote what (keep this table truthful)

| Part                                                      | Origin   |
|-----------------------------------------------------------|----------|
| `docs/spec.md` — architecture, register map, protocol     | Provided |
| `tb/tb_uart_apb.sv` — APB BFM, txd monitor, rxd driver, 16 directed/loopback tests, tiny coverage tracker | Provided |
| `tb/apb_checker.sv` — APB protocol assertions             | Provided |
| `Makefile`, `.github/workflows/ci.yml`                    | Provided |
| `rtl/*.sv` — the design                                   | **You**  |
| Unit tests for FIFO / baud gen, scoreboard, constrained-random env, real functional coverage, SVA in `tb/uart_sva.sv`, mutation testing | **You** (see `docs/verification_plan.md`) |

Commit the scaffold untouched as your first commit (message: "scaffold") so
history shows exactly what you added. On a resume, claim the RTL and the
verification items you actually build — not the provided testbench.

## Quick start

```bash
sudo apt-get install verilator make      # Ubuntu 24.04 ships 5.020
make lint            # strict -Wall lint of rtl/ only
make                 # build + run all tests (fails on the stubs: 280+ errors)
make TEST=rx_errors  # one test
make regress SEEDS=20
make wave TEST=tx_single   # build_trace/wave.vcd -> gtkwave
make cov             # line/toggle coverage -> build_cov/annot (includes TB lines; read the rtl/ ones)
```

Waveform viewer: `sudo apt-get install gtkwave` (or use Surfer / the VS Code
WaveTrace extension).

## Layout

```
rtl/   sync_fifo.sv  uart_baud_gen.sv  uart_tx.sv  uart_rx.sv  uart_apb.sv   <- you
tb/    tb_uart_apb.sv  apb_checker.sv  uart_sva.sv                           <- provided / yours
docs/  spec.md  verification_plan.md
```

## Milestones

| M | Goal | Done when |
|---|------|-----------|
| 0 | Toolchain works | `make lint` clean on the stubs; `make` runs and fails |
| 1 | `sync_fifo` | your own unit TB (`tb/tb_sync_fifo.sv`, run with `make TOP=tb_sync_fifo TB_FILES=tb/tb_sync_fifo.sv`) covers fill/drain/simultaneous r+w/overflow/underflow |
| 2 | `uart_baud_gen` + `uart_tx` | `reset`, `tx_single`, `tx_fifo`, `tx_parity` pass (needs the register file — do the minimal `uart_apb` for DATA/STATUS/CTRL/BAUD_DIV first) |
| 3 | `uart_rx` | `rx_*` tests pass |
| 4 | Full `uart_apb` | all 16 tests pass, `make regress SEEDS=20` green, `make lint` clean, CI green |
| 5 | Verification depth | V3–V7 in `docs/verification_plan.md` |
| 6 | Mutation testing | V8: inject bugs, close the gaps below |
| 7 | Stretch | 5–9 data bits / 2 stop bits, APB wait states, DMA-style `rx_ready` flow control, port the TB to UVM-lite on Questa/Xcelium if you have access |

Write the RTL yourself, then send it for review: I'll look at bugs, spec
conformance, lint, synthesizability (latches, reset style, CDC on `rxd`), and
style — not rewrite it.

## Known testbench gaps (found by mutation-testing the scaffold)

The provided tests were run against a private reference implementation and
against 27 injected bugs (wrong parity polarity, off-by-one baud period, bit
width, late RX sampling, FIFO overwrite/underflow, W1C clearing everything,
PSLVERR decode, irq terms, reset values, double-pop on read, …). All were
caught except:

1. **Set-vs-clear priority on the sticky error flags.** If a frame error
   arrives in the *same clock* as a W1C write to that flag, the spec says set
   wins (§5). No directed test can hit that cycle without seeing internals.
   Close it with a `bind`ed assertion on your own flag logic, or a random test
   that sweeps the W1C write across the RX sample point and checks against a
   cycle-accurate model.

Add your own finds to this list as you build the stronger testbench.

## Reference reading (look, learn, don't copy)

Different register maps, different tools — useful for ideas on structure and
what a good verification story looks like:

* [huzaifa07mcs/Uart-IP-Core](https://github.com/huzaifa07mcs/Uart-IP-Core) — full-duplex UART IP with 16-deep FIFOs, parity and error flags.
* [zlsjtj/apb-uart-fifo-uvm](https://github.com/zlsjtj/apb-uart-fifo-uvm) — APB-UART with async FIFOs and a full UVM environment, coverage and fault-injection (needs Questa/ModelSim for UVM).
* [ysunita-dev/uart-verification-systemverilog](https://github.com/ysunita-dev/uart-verification-systemverilog) — randomized tests, assertions, functional coverage, scoreboard.
* [huytra05/UART-Design-and-Verification](https://github.com/huytra05/UART-Design-and-Verification) — UART RX with an object-oriented SystemVerilog testbench.

## CI

`.github/workflows/ci.yml` installs Verilator on Ubuntu 24.04, lints the RTL,
and runs a 10-seed regression. It is red until M4 — that's expected.
