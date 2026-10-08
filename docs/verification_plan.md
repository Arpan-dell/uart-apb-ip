# Verification plan

Keep this file honest: it is what a reviewer reads to decide whether your
verification claims are real. Mark each row with who wrote it and its status.

Legend — **Provided**: shipped in the scaffold. **Mine**: you wrote it.

## 1. Directed tests (provided, in `tb/tb_uart_apb.sv`)

| Test name        | Feature (spec §)                                         | Origin   |
|------------------|----------------------------------------------------------|----------|
| `reset`          | reset values, empty-DATA read has no side effects (§5,§9)| Provided |
| `regs`           | field masks, PSLVERR decode, PADDR[1:0] ignored (§5,§6)  | Provided |
| `tx_single`      | frame format, cycle-exact bit width, busy/empty (§3,§7.1)| Provided |
| `tx_fifo`        | TX FIFO full / overflow dropped / order (§7.3)           | Provided |
| `tx_parity`      | even / odd parity on TX (§3)                             | Provided |
| `rx_basic`       | data patterns × divisors × parity modes (§7.2)           | Provided |
| `rx_fifo_order`  | back-to-back frames, FIFO ordering (§7.2,§7.3)           | Provided |
| `rx_errors`      | parity / framing flags, W1C, recovery (§5,§7.2)          | Provided |
| `rx_break`       | edge-based start detection (§7.2)                        | Provided |
| `rx_false_start` | glitch rejection (§7.2)                                  | Provided |
| `rx_overrun`     | drop-newest policy, sticky flag (§7.2)                   | Provided |
| `rx_tolerance`   | ±3 % baud error (§7.2)                                   | Provided |
| `enables`        | TX_EN / RX_EN gating (§7.1,§7.2)                         | Provided |
| `irq`            | interrupt equation, all three sources (§8)               | Provided |
| `loopback`       | random data / divisor / parity through txd→rxd           | Provided |
| `midreset`       | reset aborts a frame and flushes TX FIFO (§9)            | Provided |

## 2. Your verification work

Fill in as you go. Don't tick a box until the thing exists in the repo and CI runs it.

| # | Item | Status | Notes |
|---|------|--------|-------|
| V1 | Unit testbench for `sync_fifo` (random push/pop vs. queue model) | ☐ | |
| V2 | Unit testbench for `uart_baud_gen` (tick spacing for several divisors, shrinking divisor) | ☐ | |
| V3 | Reference-model **scoreboard**: APB writes/reads and serial traffic checked against a behavioural model, not hard-coded expectations | ☐ | |
| V4 | **Constrained-random** stimulus: random divisors, parity, data, inter-frame gaps, APB access timing, error injection (use `$urandom_range` + your own constraints, or `std::randomize` if your simulator supports it) | ☐ | |
| V5 | **Functional coverage** with real bins and crosses (config × data × error × FIFO level); report in CI; closure target stated here | ☐ | |
| V6 | **SVA** in `tb/uart_sva.sv` (and/or `bind`ed into the DUT): at least 6 properties, each with a one-line intent | ☐ | |
| V7 | Code coverage run (`make cov`), uncovered lines explained | ☐ | |
| V8 | **Mutation testing**: inject ≥10 bugs into your own RTL, record which tests kill them, close the gaps | ☐ | |
| V9 | Wait-state support: make PREADY non-trivial (random wait states) and re-run everything | ☐ | |
| V10 | Seeds regression in CI (`make regress SEEDS=20`) is green | ☐ | |

## 3. Known gaps in the provided testbench

(Found by mutation-testing the scaffold against a private reference design.)

See README.md → "Known testbench gaps". Closing these is item V8.
