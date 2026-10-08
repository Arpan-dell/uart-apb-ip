// uart_rx.sv -- UART receiver (8 data bits, optional parity, 1 stop bit)
//
// TODO(you): implement. Spec: docs/spec.md section 7.2
//   * 2-flop synchroniser on rxd (reset value 1), plus a 'previous' flop for
//     falling-edge detection.
//   * Start = falling edge while rx_en && idle (EDGE, not level).
//   * ~8 ticks later re-check: line still low -> real start; else glitch,
//     go back to idle silently.
//   * Then sample every 16 ticks: d0..d7 (LSB first), [parity], stop.
//   * After the stop sample go straight back to idle.
//   * Report the frame with a ONE-cycle out_valid pulse; frame_err / parity_err
//     are valid in that same cycle. Errored frames still produce out_valid.
//
/* verilator lint_off UNUSEDSIGNAL */
module uart_rx (
  input  logic       clk,
  input  logic       rst_n,
  input  logic       tick16,

  input  logic       rx_en,
  input  logic       parity_en,
  input  logic       parity_odd,

  input  logic       rxd,

  output logic [7:0] out_data,
  output logic       out_valid,    // 1-cycle pulse: a frame has been received
  output logic       frame_err,    // stop bit was 0
  output logic       parity_err    // parity mismatch (only if parity_en)
);

  // ---- stub ----
  assign out_data   = '0;
  assign out_valid  = 1'b0;
  assign frame_err  = 1'b0;
  assign parity_err = 1'b0;

endmodule
