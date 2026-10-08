# UART + APB Peripheral — Specification (v1.0)

This document is the contract between your RTL and the testbench in `tb/`.
If the RTL and this document disagree, the RTL is wrong (or open an issue and
change the spec *and* the testbench together).

## 1. Overview

A memory-mapped UART with an AMBA APB slave interface.

```
                 +--------------------------------------------------+
   APB master    |                    uart_apb                      |
  ------------>  |  APB regs ──► TX FIFO ──► uart_tx ──► txd        |
  PSEL/PENABLE   |     │            (8)         ▲                   |
  PADDR/PWDATA   |     │                        │ tick16            |
  PRDATA/PREADY  |     │        uart_baud_gen ──┤                   |
  <------------  |     │                        ▼                   |
                 |     └◄── RX FIFO ◄── uart_rx ◄── rxd             |
                 |            (8)                          irq ──►  |
                 +--------------------------------------------------+
```

Suggested decomposition (the testbench only sees the top level, so you may
restructure internally): `sync_fifo`, `uart_baud_gen`, `uart_tx`, `uart_rx`,
`uart_apb` (registers + glue).

## 2. Top-level ports — `uart_apb`

| Port      | Dir | Width | Description                                   |
|-----------|-----|-------|-----------------------------------------------|
| PCLK      | in  | 1     | APB clock, also the UART core clock           |
| PRESETn   | in  | 1     | Active-low **asynchronous** reset (assert), synchronous release |
| PSEL      | in  | 1     | APB select                                    |
| PENABLE   | in  | 1     | APB enable                                    |
| PWRITE    | in  | 1     | 1 = write, 0 = read                           |
| PADDR     | in  | 8     | Byte address. Bits [1:0] are ignored          |
| PWDATA    | in  | 32    | Write data                                    |
| PRDATA    | out | 32    | Read data (valid in the access phase)         |
| PREADY    | out | 1     | May be tied to 1 (zero wait states)           |
| PSLVERR   | out | 1     | See §4                                        |
| rxd       | in  | 1     | Serial input (asynchronous to PCLK)           |
| txd       | out | 1     | Serial output (registered, idles high)        |
| irq       | out | 1     | Level interrupt, see §8                       |

Parameter: `FIFO_DEPTH` (default 8, must be a power of two) — depth of **both** FIFOs.

## 3. Serial frame

`start(0)` · `d0 … d7` (LSB first) · `[parity]` · `stop(1)` — always 8 data
bits and exactly one stop bit.

* Parity (when `PARITY_EN=1`): `PARITY_ODD=0` → even parity, i.e. the parity
  bit equals `^data`; `PARITY_ODD=1` → odd parity, parity bit equals `~^data`.
* Frame length: 10 bits without parity, 11 with parity.
* Changing `PARITY_EN`/`PARITY_ODD`/`BAUD_DIV` while a frame is in flight is
  undefined. The testbench never does it.

## 4. Baud generation

`tick16` is a **single-cycle pulse every `BAUD_DIV` PCLK cycles** (free-running).
One bit time = 16 ticks = `16 × BAUD_DIV` PCLK cycles.

* `BAUD_DIV` = 0 is reserved (undefined). Reset value = 1.
* Lowering `BAUD_DIV` must take effect promptly (do not wait for a long old
  count to expire) — use `>=`-style compare, not `==`.

## 5. Register map

32-bit registers, word aligned. Unlisted bits read as 0 and ignore writes.

| Offset | Name     | Access | Reset | Description |
|--------|----------|--------|-------|-------------|
| 0x00   | DATA     | R/W    | 0     | **Write**: bits [7:0] pushed to TX FIFO (dropped if full). **Read**: bits [7:0] = RX FIFO head, entry is popped; reads 0 and pops nothing if empty. |
| 0x04   | STATUS   | R / W1C| 0x0A  | see below |
| 0x08   | CTRL     | R/W    | 0x03  | `[0]` TX_EN, `[1]` RX_EN, `[2]` PARITY_EN, `[3]` PARITY_ODD |
| 0x0C   | BAUD_DIV | R/W    | 1     | `[15:0]` divisor |
| 0x10   | INT_EN   | R/W    | 0     | `[0]` RX_NOT_EMPTY, `[1]` TX_EMPTY, `[2]` ERROR |

STATUS bits:

| Bit | Name        | Description |
|-----|-------------|-------------|
| 0   | TX_FULL     | TX FIFO full |
| 1   | TX_EMPTY    | TX FIFO empty (the byte currently being shifted out is *not* counted) |
| 2   | TX_BUSY     | 1 from the start of the start bit until the end of the stop bit |
| 3   | RX_EMPTY    | RX FIFO empty |
| 4   | RX_FULL     | RX FIFO full |
| 5   | FRAME_ERR   | sticky, **write-1-to-clear** |
| 6   | PARITY_ERR  | sticky, **write-1-to-clear** |
| 7   | OVERRUN_ERR | sticky, **write-1-to-clear** |

Writes to STATUS only act on bits [7:5]; writing 0 clears nothing; bits [4:0]
are read-only. If a flag is set and cleared in the same cycle, **set wins**.

Reset STATUS = `0x0A` (TX_EMPTY | RX_EMPTY).

## 6. APB behaviour

* Standard APB3: setup phase (`PSEL=1,PENABLE=0`) then access phase
  (`PSEL=1,PENABLE=1`). The transfer completes in the access-phase cycle in
  which `PREADY=1`.
* Side effects (TX push, RX pop, W1C) happen **exactly once**, on the clock edge
  that completes the transfer — never in the setup phase, never twice.
* `PRDATA` must be valid in the access phase (combinational read mux from
  registered state is fine).
* `PSLVERR=1` in the completing cycle of any access whose `PADDR[7:2]` is
  greater than 4 (offset > 0x10): reads return 0, writes are ignored.
  Mapped registers never raise `PSLVERR`.

## 7. UART core

### 7.1 Transmitter

* Everything in the TX state machine, including every `txd` transition, happens
  on a `tick16` clock edge. Consequently **every bit lasts exactly
  `16 × BAUD_DIV` PCLK cycles** (the testbench checks this cycle-exactly).
* A frame starts at the first tick when `TX_EN=1`, the TX FIFO is non-empty and
  the transmitter is idle; the byte is popped at that moment. Latency from FIFO
  write to start bit must be ≤ 1 tick + 4 PCLK cycles.
* Gap between back-to-back frames: 0 or more whole ticks (implementation choice).
* Clearing `TX_EN` does not abort a frame in flight; it only prevents new ones.
* `txd` is 1 during reset and while idle.

### 7.2 Receiver

* `rxd` goes through a 2-flop synchroniser (reset value 1).
* A frame starts on a **falling edge** of the synchronised `rxd` while `RX_EN=1`
  and the receiver is idle. (Edge, not level: a line held low after a framing
  error / break produces exactly one frame.)
* The start bit is re-checked ~8 ticks after the edge; if the line is high the
  glitch is rejected and the receiver returns to idle without any flag.
* Data / parity / stop are then sampled every 16 ticks (centre of each bit).
* After the stop-bit sample the receiver returns to idle immediately, ready for
  the next falling edge (so back-to-back frames with no gap must work).
* The receiver must tolerate a sender whose bit rate is off by up to ±3 %
  (so sample close to the middle of each bit -- do not sample "late but still
  inside the bit").
* Per received frame:
  * `FRAME_ERR` set if the stop bit sampled 0.
  * `PARITY_ERR` set if parity is enabled and the bit mismatches.
  * The byte is **pushed into the RX FIFO even if it has errors.**
  * If the RX FIFO is already full, the new byte is **dropped** (older data is
    preserved) and `OVERRUN_ERR` is set.
* Clearing `RX_EN` does not abort a frame in flight; it only prevents new ones.

### 7.3 FIFOs

Synchronous, first-word-fall-through (head visible on `rd_data` without
asserting `rd_en`). Write when full and read when empty are ignored (no
pointer/count corruption). Provides `full`, `empty`, `count`.

## 8. Interrupt

```
irq = (INT_EN[0] & ~RX_EMPTY)
    | (INT_EN[1] &  TX_EMPTY)
    | (INT_EN[2] & (FRAME_ERR | PARITY_ERR | OVERRUN_ERR));
```

Purely a function of STATUS/INT_EN (level-sensitive, no extra state).

## 9. Reset

Asynchronous assert / synchronous release. After reset: `txd=1`, both FIFOs
empty, registers at their reset values, error flags clear, receiver and
transmitter idle. Asserting reset mid-frame must abort the frame immediately
and flush any pending TX data.
