// sync_fifo.sv -- synchronous first-word-fall-through FIFO
//
// TODO(you): implement. Spec: docs/spec.md section 7.3
//   * DEPTH is a power of two.
//   * rd_data shows the head entry whenever !empty (FWFT).
//   * wr_en while full  -> ignored.   rd_en while empty -> ignored.
//   * count = number of stored entries (0..DEPTH).
//
// Remove the lint_off line below once the ports are really used.
/* verilator lint_off UNUSEDSIGNAL */
module sync_fifo #(
  parameter int WIDTH = 8,
  parameter int DEPTH = 8
) (
  input  logic                   clk,
  input  logic                   rst_n,   // async assert, active low

  input  logic                   wr_en,
  input  logic [WIDTH-1:0]       wr_data,
  output logic                   full,

  input  logic                   rd_en,
  output logic [WIDTH-1:0]       rd_data,
  output logic                   empty,

  output logic [$clog2(DEPTH):0] count
);

  // ---- stub: tie-offs so the project compiles. Replace with real logic. ----
  assign full    = 1'b0;
  assign rd_data = '0;
  assign empty   = 1'b1;
  assign count   = '0;

endmodule
