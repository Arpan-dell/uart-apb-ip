// uart_sva.sv -- YOUR assertions live here.
//
// One starter property is provided so you can see the flow. Add more as you
// understand the design (and list each one in docs/verification_plan.md).
//
// Ideas (all checkable from the DUT's external ports):
//   * txd is 1 while idle -- and after reset.
//   * txd transitions are always at least 16*BAUD_DIV cycles apart
//     (hint: you need to know BAUD_DIV -- mirror it in the TB or use bind).
//   * irq == function of STATUS/INT_EN (needs the TB to mirror those regs, or
//     bind this module into the DUT to see the internals).
//   * RX_FULL and RX_EMPTY are never both 1.
//   * TX_FULL and TX_EMPTY are never both 1.
//   * a write to DATA never changes the RX side of STATUS.
//
// Bonus: `bind` this module into uart_apb so you can assert on internal state
// (FIFO counts never exceed DEPTH, FSM one-hot, etc.).
module uart_sva (
  input logic PCLK,
  input logic PRESETn,
  input logic txd,
  input logic irq
);

  // txd must idle high (and irq low) once reset has been held for a full clock
  // ($past avoids a false hit at time 0, where PRESETn starts low with no edge)
  a_reset_outputs: assert property (@(posedge PCLK) (!PRESETn && $past(!PRESETn)) |-> (txd && !irq))
    else $error("SVA: txd/irq not at reset value during reset");

  // TODO(you): add more properties

endmodule
