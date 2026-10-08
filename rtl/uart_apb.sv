// uart_apb.sv -- top level: APB register file + UART core
//
// TODO(you): implement. Spec: docs/spec.md sections 2, 5, 6, 8, 9
//
// Suggested structure:
//   uart_baud_gen  u_baud (...);
//   sync_fifo      u_txf  (...);   // APB DATA write  -> uart_tx
//   sync_fifo      u_rxf  (...);   // uart_rx         -> APB DATA read
//   uart_tx        u_tx   (...);
//   uart_rx        u_rx   (...);
//   + registers: CTRL, BAUD_DIV, INT_EN, sticky error flags (W1C)
//   + combinational PRDATA read mux, PSLVERR decode, irq equation
//
// Careful with APB side effects: push/pop/W1C only on the cycle that
// COMPLETES a transfer (PSEL & PENABLE & PREADY), exactly once.
//
/* verilator lint_off UNUSEDSIGNAL */
/* verilator lint_off UNUSEDPARAM */
module uart_apb #(
  parameter int FIFO_DEPTH = 8
) (
  input  logic        PCLK,
  input  logic        PRESETn,
  input  logic        PSEL,
  input  logic        PENABLE,
  input  logic        PWRITE,
  input  logic [7:0]  PADDR,
  input  logic [31:0] PWDATA,
  output logic [31:0] PRDATA,
  output logic        PREADY,
  output logic        PSLVERR,

  input  logic        rxd,
  output logic        txd,
  output logic        irq
);

  // ---- stub: tie-offs so the project compiles (testbench will FAIL) ----
  assign PRDATA  = '0;
  assign PREADY  = 1'b1;
  assign PSLVERR = 1'b0;
  assign txd     = 1'b1;
  assign irq     = 1'b0;

endmodule
