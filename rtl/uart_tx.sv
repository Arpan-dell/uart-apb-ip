// uart_tx.sv -- UART transmitter (8 data bits, optional parity, 1 stop bit)
//
// TODO(you): implement. Spec: docs/spec.md section 7.1
//   * Every state change (incl. txd) happens only when tick16 is high, so each
//     bit lasts exactly 16 ticks -- the testbench checks this cycle-exactly.
//   * Idle: when tx_en && in_valid, pop the byte (in_ready pulses) and drive
//     the start bit on that same tick.
//   * LSB first; parity bit = ^data (even) or ~^data (odd); then stop bit = 1.
//   * busy = 1 from start bit through end of stop bit.
//   * Reset: txd = 1, state = idle.
//
/* verilator lint_off UNUSEDSIGNAL */
module uart_tx (
  input  logic       clk,
  input  logic       rst_n,
  input  logic       tick16,

  input  logic       tx_en,
  input  logic       parity_en,
  input  logic       parity_odd,

  // byte source (FIFO head, FWFT): handshake completes when in_valid && in_ready
  input  logic [7:0] in_data,
  input  logic       in_valid,
  output logic       in_ready,

  output logic       busy,
  output logic       txd
);

  // ---- stub ----
  assign in_ready = 1'b0;
  assign busy     = 1'b0;
  assign txd      = 1'b1;

endmodule
