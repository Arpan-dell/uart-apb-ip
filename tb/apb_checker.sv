// apb_checker.sv -- passive APB protocol assertions (provided)
//
// Rules 1-3 police the bus master (the testbench driver), rule 4-5 police the
// slave (your DUT). Add your own in tb/uart_sva.sv.
module apb_checker (
  input logic        PCLK,
  input logic        PRESETn,
  input logic        PSEL,
  input logic        PENABLE,
  input logic        PWRITE,
  input logic [7:0]  PADDR,
  input logic [31:0] PWDATA,
  input logic        PREADY
);

  // NOTE: this tool version lacks "default disable iff", so each property carries its own.

  // 1. PENABLE only ever accompanies PSEL
  a_enable_needs_sel: assert property (@(posedge PCLK) disable iff (!PRESETn) PENABLE |-> PSEL)
    else $error("APB: PENABLE without PSEL");

  // 2. A setup phase is followed by an access phase in the next cycle
  a_setup_then_access: assert property (@(posedge PCLK) disable iff (!PRESETn)
      (PSEL && !PENABLE) |=> (PSEL && PENABLE))
    else $error("APB: setup phase not followed by access phase");

  // 3. Control/address/write-data stay stable while the slave inserts wait states
  a_stable_in_wait: assert property (@(posedge PCLK) disable iff (!PRESETn)
      (PSEL && PENABLE && !PREADY) |=> ($stable(PADDR) && $stable(PWRITE) && $stable(PWDATA) && PENABLE))
    else $error("APB: signals changed during wait state");

  // 4. (slave) wait states must be bounded -- a hung PREADY is a DUT bug
  logic [5:0] wait_cnt;
  always_ff @(posedge PCLK or negedge PRESETn) begin
    if (!PRESETn)                          wait_cnt <= '0;
    else if (PSEL && PENABLE && !PREADY)   wait_cnt <= wait_cnt + 6'd1;
    else                                   wait_cnt <= '0;
  end
  a_bounded_wait: assert property (@(posedge PCLK) disable iff (!PRESETn) wait_cnt < 6'd32)
    else $error("APB: slave held PREADY low for 32+ cycles");

endmodule
