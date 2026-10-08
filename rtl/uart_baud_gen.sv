// uart_baud_gen.sv -- 16x oversampling tick generator
//
// TODO(you): implement. Spec: docs/spec.md section 4
//   * tick16 is a ONE-cycle pulse every `div` clk cycles, free-running.
//   * One UART bit = 16 ticks = 16*div clk cycles.
//   * div == 0 is reserved. Lowering div must take effect promptly
//     (think: why does `cnt == div-1` break when div shrinks?).
//
/* verilator lint_off UNUSEDSIGNAL */
module uart_baud_gen (
  input  logic        clk,
  input  logic        rst_n,
  input  logic [15:0] div,
  output logic        tick16
);

  // ---- stub ----
  assign tick16 = 1'b0;

endmodule
