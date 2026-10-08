// tb_uart_apb.sv -- self-checking directed testbench for uart_apb (provided)
//
// What is here:   APB bus-functional tasks, a cycle-exact txd monitor, an rxd
//                 frame driver (incl. parity/stop-bit error injection), 12
//                 directed tests, a small loopback-random test, and a tiny
//                 hand-rolled functional-coverage tracker.
// What is NOT here (your milestones): a constrained-random environment with a
//                 reference-model scoreboard, real functional coverage closure,
//                 SVA of your own, mutation testing. See README.md.
//
// Run one test:  make TEST=<name>      names are the strings in the RUN() list
// Run seeds:     make regress SEEDS=20

`timescale 1ns/1ps

`define RUN(NAME, CALL) \
  if (selected(NAME)) begin begin_test(NAME); CALL; end_test(); end

module tb_uart_apb;

  // ------------------------------------------------------------------ params
  localparam int CLK_PERIOD = 10;
  localparam int DEPTH      = 8;

  localparam logic [7:0] R_DATA   = 8'h00;
  localparam logic [7:0] R_STATUS = 8'h04;
  localparam logic [7:0] R_CTRL   = 8'h08;
  localparam logic [7:0] R_DIV    = 8'h0C;
  localparam logic [7:0] R_INTEN  = 8'h10;

  localparam logic [31:0] B_TXFULL  = 32'h01;
  localparam logic [31:0] B_TXEMPTY = 32'h02;
  localparam logic [31:0] B_TXBUSY  = 32'h04;
  localparam logic [31:0] B_RXEMPTY = 32'h08;
  localparam logic [31:0] B_RXFULL  = 32'h10;
  localparam logic [31:0] B_FERR    = 32'h20;
  localparam logic [31:0] B_PERR    = 32'h40;
  localparam logic [31:0] B_OERR    = 32'h80;
  localparam logic [31:0] B_ERRS    = 32'hE0;

  // ------------------------------------------------------------------ signals
  logic        PCLK     = 1'b0;
  logic        PRESETn  = 1'b0;
  logic        PSEL     = 1'b0;
  logic        PENABLE  = 1'b0;
  logic        PWRITE   = 1'b0;
  logic [7:0]  PADDR    = '0;
  logic [31:0] PWDATA   = '0;
  logic [31:0] PRDATA;
  logic        PREADY;
  logic        PSLVERR;
  logic        txd;
  logic        irq;

  logic        rxd_drv  = 1'b1;   // what the testbench drives onto rxd
  logic        loopback = 1'b0;   // 1: connect txd -> rxd
  wire         rxd      = loopback ? txd : rxd_drv;

  uart_apb #(.FIFO_DEPTH(DEPTH)) dut (.*);
  apb_checker u_apb_chk (.*);
  uart_sva    u_sva     (.*);

  always #(CLK_PERIOD/2) PCLK = ~PCLK;

  // ------------------------------------------------------------ bookkeeping
  int    errors = 0;
  int    checks = 0;
  string cur_test = "";
  int    err_at_start = 0;
  string sel;

  task automatic check(input bit cond, input string msg);
    checks++;
    if (!cond) begin
      errors++;
      $display("[%0t] ERROR: %s", $time, msg);
    end
  endtask

  task automatic check_eq(input longint unsigned got, input longint unsigned expv, input string msg);
    checks++;
    if (got !== expv) begin
      errors++;
      $display("[%0t] ERROR: %s: got 0x%0h, expected 0x%0h", $time, msg, got, expv);
    end
  endtask

  function automatic bit selected(input string n);
    return (sel == "all") || (sel == n);
  endfunction

  task automatic begin_test(input string n);
    cur_test = n;
    err_at_start = errors;
    $display("---- %s", n);
  endtask

  task automatic end_test();
    $display("%s  %s", (errors == err_at_start) ? "PASS" : "FAIL", cur_test);
  endtask

  // -------------------------------------------------- tiny functional coverage
  int cov_bins[string];

  task automatic cov_need(input string n);
    cov_bins[n] = 0;
  endtask

  task automatic cov_hit(input string n);
    if (cov_bins.exists(n)) cov_bins[n] = cov_bins[n] + 1;
    else                    cov_bins[n] = 1;
  endtask

  task automatic cov_report();
    int total = 0, hit = 0;
    $display("---- functional coverage (hand-rolled bins) ----");
    foreach (cov_bins[k]) begin
      total++;
      if (cov_bins[k] > 0) hit++;
      else $display("  MISS  %s", k);
    end
    $display("  %0d / %0d bins hit", hit, total);
  endtask

  // ------------------------------------------------------------------- APB BFM
  logic last_slverr;

  task automatic apb_xfer(input bit write, input logic [7:0] addr,
                          input logic [31:0] wdata, output logic [31:0] rdata);
    int guard;
    @(posedge PCLK); #1;
    PSEL = 1; PENABLE = 0; PWRITE = write; PADDR = addr;
    PWDATA = write ? wdata : 32'h0;
    @(posedge PCLK); #1;
    PENABLE = 1;
    @(posedge PCLK);                 // access phase edge
    guard = 0;
    while (!PREADY) begin
      @(posedge PCLK);
      guard++;
      if (guard > 64) begin check(0, "APB: timeout waiting for PREADY"); break; end
    end
    rdata       = PRDATA;
    last_slverr = PSLVERR;
    #1; PSEL = 0; PENABLE = 0; PWRITE = 0;
  endtask

  task automatic wr(input logic [7:0] a, input logic [31:0] d);
    logic [31:0] dummy;
    apb_xfer(1, a, d, dummy);
  endtask

  task automatic rd(input logic [7:0] a, output logic [31:0] d);
    apb_xfer(0, a, 32'h0, d);
  endtask

  task automatic rd_expect(input logic [7:0] a, input logic [31:0] expv, input string msg);
    logic [31:0] v;
    rd(a, v);
    check_eq(v, expv, msg);
  endtask

  task automatic chk_status(input logic [31:0] mask, input logic [31:0] val, input string msg);
    logic [31:0] s;
    rd(R_STATUS, s);
    checks++;
    if ((s & mask) !== val) begin
      errors++;
      $display("[%0t] ERROR: %s: STATUS=0x%02h, (STATUS & 0x%02h) = 0x%02h, expected 0x%02h",
               $time, msg, s, mask, s & mask, val);
    end
  endtask

  task automatic chk_irq(input bit expv, input string msg);
    repeat (2) @(negedge PCLK);
    check_eq(irq, expv, {"irq: ", msg});
  endtask

  // ------------------------------------------- UART configuration (+ TB model)
  int cur_div  = 1;
  bit cur_pen  = 0;
  bit cur_podd = 0;

  task automatic cfg(input int div, input bit pen, input bit podd,
                     input bit txen = 1, input bit rxen = 1);
    wr(R_DIV,  div);
    wr(R_CTRL, {28'b0, podd, pen, rxen, txen});
    cur_div = div; cur_pen = pen; cur_podd = podd;
    cov_hit($sformatf("div_%0d", div));
    cov_hit(!pen ? "par_none" : (podd ? "par_odd" : "par_even"));
  endtask

  logic [7:0] tx_q[$];     // bytes decoded by the txd monitor
  logic [7:0] exp_q[$];    // bytes the test expects to see

  task automatic do_reset();
    @(negedge PCLK);
    PRESETn = 0; PSEL = 0; PENABLE = 0; PWRITE = 0;
    rxd_drv = 1; loopback = 0;
    repeat (4) @(negedge PCLK);
    PRESETn = 1;
    repeat (2) @(negedge PCLK);
    tx_q.delete(); exp_q.delete();
    cur_div = 1; cur_pen = 0; cur_podd = 0;
  endtask

  task automatic settle();
    repeat (8) @(negedge PCLK);
  endtask

  // --------------------------------------------------------- txd monitor
  // Wakes on the falling edge of the start bit, then samples txd on every PCLK
  // negedge for the whole frame. Every bit must be perfectly stable for exactly
  // 16*BAUD_DIV cycles, which also proves tick alignment and the baud divider.
  task automatic mon_frame();
    int          nbits, bc;
    logic [10:0] f;
    logic        first;
    bit          width_err;
    logic [7:0]  data;
    bit          exp_p;
    nbits     = 10 + (cur_pen ? 1 : 0);
    bc        = 16 * cur_div;
    width_err = 0;
    f         = '0;
    first     = 1'b0;
    for (int b = 0; b < nbits; b++) begin
      for (int k = 0; k < bc; k++) begin
        @(negedge PCLK);
        if (!PRESETn) return;                     // reset aborts the frame
        if (k == 0) first = txd;
        else if (txd !== first) width_err = 1;
      end
      f[b] = first;
    end
    data = f[8:1];
    check(!width_err, "TX: a bit was not exactly 16*BAUD_DIV PCLK cycles wide");
    check_eq(f[0], 0, "TX: start bit must be 0");
    if (cur_pen) begin
      exp_p = (^data) ^ cur_podd;
      check_eq(f[9], exp_p, "TX: parity bit");
    end
    check_eq(f[nbits-1], 1, "TX: stop bit must be 1");
    tx_q.push_back(data);
  endtask

  initial begin : tx_monitor
    forever begin
      @(negedge txd);
      if (PRESETn) mon_frame();
    end
  end

  // --------------------------------------------------------- rxd driver
  task automatic drive_bit(input logic v, input int n);
    rxd_drv = v;
    repeat (n) @(negedge PCLK);
  endtask

  int rx_bit_clks = 0;   // 0: nominal 16*BAUD_DIV; else per-bit clocks (baud-error injection)

  task automatic send_frame(input logic [7:0] d, input bit bad_par = 0, input bit bad_stop = 0);
    int   bc;
    logic p;
    bc = (rx_bit_clks != 0) ? rx_bit_clks : 16 * cur_div;
    @(negedge PCLK);
    drive_bit(1'b0, bc);                              // start
    for (int i = 0; i < 8; i++) drive_bit(d[i], bc);  // data, LSB first
    if (cur_pen) begin
      p = (^d) ^ cur_podd;
      if (bad_par) p = ~p;
      drive_bit(p, bc);
    end
    drive_bit(bad_stop ? 1'b0 : 1'b1, bc);            // stop
    rxd_drv = 1'b1;                                    // back to idle
  endtask

  // ------------------------------------------------------------- helpers
  task automatic wait_tx_idle();
    logic [31:0] s;
    for (int i = 0; i < 4000; i++) begin
      rd(R_STATUS, s);
      if (s[1] && !s[2]) begin                 // TX_EMPTY && !TX_BUSY
        repeat (16 * cur_div) @(negedge PCLK); // let the monitor finish
        return;
      end
      repeat (8) @(negedge PCLK);
    end
    check(0, "timeout waiting for TX_EMPTY && !TX_BUSY");
  endtask

  task automatic cmp_tx_exp(input string msg);
    check_eq(tx_q.size(), exp_q.size(), {msg, ": number of frames on txd"});
    for (int i = 0; i < tx_q.size() && i < exp_q.size(); i++)
      check_eq(tx_q[i], exp_q[i], $sformatf("%s: frame %0d", msg, i));
  endtask

  // =================================================================== TESTS

  task automatic t_reset();
    do_reset();
    rd_expect(R_DATA,   32'h0,  "DATA reads 0 when RX FIFO is empty");
    rd_expect(R_STATUS, 32'h0A, "STATUS reset value (TX_EMPTY|RX_EMPTY)");
    rd_expect(R_CTRL,   32'h03, "CTRL reset value (TX_EN|RX_EN)");
    rd_expect(R_DIV,    32'h01, "BAUD_DIV reset value");
    rd_expect(R_INTEN,  32'h00, "INT_EN reset value");
    check_eq(txd, 1, "txd idles high after reset");
    check_eq(irq, 0, "irq low after reset");
    // reading DATA on an empty FIFO must not corrupt anything
    rd_expect(R_STATUS, 32'h0A, "STATUS unchanged after empty DATA read");
  endtask

  task automatic t_regs();
    logic [31:0] v;
    do_reset();
    wr(R_CTRL, 32'hFFFF_FFFF);  rd_expect(R_CTRL,  32'h0F,   "CTRL implements bits [3:0] only");
    wr(R_DIV,  32'hFFFF_FFFF);  rd_expect(R_DIV,   32'hFFFF, "BAUD_DIV implements bits [15:0]");
    wr(R_INTEN,32'hFFFF_FFFF);  rd_expect(R_INTEN, 32'h07,   "INT_EN implements bits [2:0]");
    wr(R_STATUS, 32'hFFFF_FFFF);
    rd_expect(R_STATUS, 32'h0A, "STATUS RO bits unaffected by writes");
    rd(R_STATUS, v);            check_eq(last_slverr, 0, "no PSLVERR on mapped register");
    // unmapped addresses
    rd(8'h14, v);               check_eq(last_slverr, 1, "PSLVERR on read of unmapped 0x14");
                                check_eq(v, 0,           "unmapped read returns 0");
    wr(8'h14, 32'h1234_5678);   check_eq(last_slverr, 1, "PSLVERR on write of unmapped 0x14");
    rd(8'hFC, v);               check_eq(last_slverr, 1, "PSLVERR on read of unmapped 0xFC");
    wr(R_CTRL, 32'h3);          check_eq(last_slverr, 0, "no PSLVERR on mapped write");
    // unmapped write must not disturb registers
    rd_expect(R_CTRL, 32'h3, "CTRL intact after unmapped accesses");
    // word alignment: PADDR[1:0] are ignored
    wr(8'h0A, 32'h2);           // byte address inside CTRL word
    rd_expect(R_CTRL, 32'h2, "PADDR[1:0] ignored (0x0A aliases CTRL)");
  endtask

  task automatic t_tx_single();
    int         divs[3] = '{1, 3, 5};
    logic [7:0] pats[5] = '{8'hA5, 8'h00, 8'hFF, 8'h01, 8'h80};
    do_reset();
    foreach (divs[i]) begin
      cfg(divs[i], 0, 0);
      foreach (pats[j]) begin
        tx_q.delete(); exp_q.delete();
        wr(R_DATA, pats[j]);
        exp_q.push_back(pats[j]);
        repeat (4 * cur_div + 8) @(negedge PCLK);
        chk_status(B_TXBUSY | B_TXEMPTY, B_TXBUSY | B_TXEMPTY,
                   "TX_BUSY=1, TX_EMPTY=1 while the byte is shifting out");
        wait_tx_idle();
        cmp_tx_exp("tx_single");
        check_eq(txd, 1, "txd back to idle high");
      end
    end
  endtask

  task automatic t_tx_fifo();
    do_reset();
    cfg(2, 0, 0, 0, 1);                       // TX disabled: bytes pile up in the FIFO
    for (int i = 0; i < DEPTH - 1; i++) wr(R_DATA, 8'h10 + i);
    chk_status(B_TXFULL | B_TXEMPTY, 0, "after DEPTH-1 writes: not full, not empty");
    wr(R_DATA, 8'h10 + DEPTH - 1);
    chk_status(B_TXFULL | B_TXEMPTY, B_TXFULL, "after DEPTH writes: TX_FULL");
    wr(R_DATA, 8'hEE);                        // must be dropped
    wr(R_DATA, 8'hEF);                        // must be dropped
    chk_status(B_TXFULL, B_TXFULL, "still full");
    cov_hit("tx_fifo_full");
    for (int i = 0; i < DEPTH; i++) exp_q.push_back(8'h10 + i);
    wr(R_CTRL, 32'h3);                        // enable TX
    wait_tx_idle();
    cmp_tx_exp("tx_fifo: oldest-first, overflow dropped");
    chk_status(B_TXFULL | B_TXEMPTY, B_TXEMPTY, "FIFO drained");
  endtask

  task automatic t_tx_parity();
    logic [7:0] pats[6] = '{8'h00, 8'hFF, 8'hA5, 8'h01, 8'h80, 8'h7E};
    do_reset();
    for (int pm = 0; pm < 3; pm++) begin      // 0:none 1:even 2:odd
      cfg(2, pm != 0, pm == 2);
      tx_q.delete(); exp_q.delete();
      foreach (pats[j]) begin
        wr(R_DATA, pats[j]);
        exp_q.push_back(pats[j]);
      end
      wait_tx_idle();
      cmp_tx_exp($sformatf("tx_parity mode %0d", pm));
    end
  endtask

  task automatic t_rx_basic();
    int         divs[3] = '{1, 2, 3};
    logic [7:0] pats[6] = '{8'h00, 8'hFF, 8'h55, 8'hAA, 8'hA5, 8'h3C};
    logic [31:0] v;
    do_reset();
    for (int pm = 0; pm < 3; pm++) begin
      foreach (divs[i]) begin
        cfg(divs[i], pm != 0, pm == 2);
        foreach (pats[j]) begin
          send_frame(pats[j]);
          settle();
          chk_status(B_RXEMPTY | B_ERRS, 0, "frame received, no error flags");
          rd(R_DATA, v);
          check_eq(v, pats[j], $sformatf("RX data (div=%0d pm=%0d)", divs[i], pm));
          chk_status(B_RXEMPTY, B_RXEMPTY, "RX FIFO empty after read");
          if (pats[j] == 8'h00) cov_hit("rx_data_00");
          if (pats[j] == 8'hFF) cov_hit("rx_data_ff");
          if (pats[j] == 8'h55) cov_hit("rx_data_55");
          if (pats[j] == 8'hAA) cov_hit("rx_data_aa");
        end
      end
    end
  endtask

  task automatic t_rx_fifo_order();
    logic [31:0] v;
    do_reset();
    cfg(1, 0, 0);
    for (int i = 0; i < 5; i++) begin         // back-to-back, zero gap between frames
      exp_q.push_back($urandom_range(255, 0));
      send_frame(exp_q[i]);
    end
    settle();
    for (int i = 0; i < 5; i++) begin
      rd(R_DATA, v);
      check_eq(v, exp_q[i], $sformatf("RX FIFO order, entry %0d", i));
    end
    chk_status(B_RXEMPTY | B_ERRS, B_RXEMPTY, "empty and clean after draining");
    // FIFO memory still holds stale data: an empty read must return 0, not that
    rd_expect(R_DATA, 32'h0, "DATA reads 0 (not stale data) when RX FIFO is empty");
    chk_status(B_RXEMPTY | B_ERRS, B_RXEMPTY, "empty DATA read changed nothing");
  endtask

  task automatic t_rx_errors();
    logic [31:0] v;
    do_reset();
    cfg(2, 1, 0);                             // even parity
    send_frame(8'h3C);                        settle();
    chk_status(B_ERRS, 0, "clean frame: no flags");
    rd(R_DATA, v); check_eq(v, 8'h3C, "clean frame data");

    send_frame(8'h81, 1, 0);                  settle();   // wrong parity bit
    chk_status(B_ERRS | B_RXEMPTY, B_PERR, "parity error: only PERR set, byte still pushed");
    cov_hit("rx_parity_err");
    rd(R_DATA, v); check_eq(v, 8'h81, "byte with parity error is still delivered");

    send_frame(8'h7E, 0, 1);                  settle();   // stop bit = 0
    chk_status(B_ERRS, B_PERR | B_FERR, "framing error set, parity flag still sticky");
    cov_hit("rx_frame_err");
    rd(R_DATA, v); check_eq(v, 8'h7E, "byte with framing error is still delivered");

    wr(R_STATUS, B_PERR);
    chk_status(B_ERRS, B_FERR, "W1C clears only the flag that was written");
    wr(R_STATUS, 32'h0);
    chk_status(B_ERRS, B_FERR, "writing 0 clears nothing");
    wr(R_STATUS, B_FERR);
    chk_status(B_ERRS, 0, "FERR cleared");

    send_frame(8'hC3);                        settle();   // receiver recovered?
    chk_status(B_ERRS, 0, "no flags on frame after errors");
    rd(R_DATA, v); check_eq(v, 8'hC3, "frame after errors received correctly");

    cfg(2, 0, 0);                             // framing error with parity disabled
    send_frame(8'h11, 0, 1);                  settle();
    chk_status(B_ERRS, B_FERR, "framing error, parity disabled: only FERR");
    rd(R_DATA, v); check_eq(v, 8'h11, "data delivered");
    wr(R_STATUS, B_FERR);
    chk_status(B_ERRS, 0, "FERR cleared (no parity)");
  endtask

  task automatic t_rx_break();
    logic [31:0] v;
    do_reset();
    cfg(2, 0, 0);
    @(negedge PCLK);
    rxd_drv = 0;                              // hold the line low for ~4 frames
    repeat (4 * 10 * 16 * cur_div) @(negedge PCLK);
    rxd_drv = 1;
    repeat (3 * 10 * 16 * cur_div) @(negedge PCLK);
    chk_status(B_ERRS | B_RXEMPTY, B_FERR, "break: framing error, one byte");
    rd(R_DATA, v); check_eq(v, 8'h00, "break produces a single 0x00 byte");
    chk_status(B_RXEMPTY, B_RXEMPTY, "no extra bytes: start detection is edge-based");
  endtask

  task automatic t_rx_false_start();
    logic [31:0] v;
    do_reset();
    cfg(2, 0, 0);                             // bit time = 32 clocks
    @(negedge PCLK);
    rxd_drv = 0;
    repeat (6) @(negedge PCLK);               // glitch << half a bit
    rxd_drv = 1;
    repeat (400) @(negedge PCLK);
    chk_status(B_RXEMPTY | B_ERRS, B_RXEMPTY, "short glitch on rxd is not a frame");
    send_frame(8'hC9);                        settle();
    rd(R_DATA, v); check_eq(v, 8'hC9, "real frame after a glitch");
  endtask

  task automatic t_rx_overrun();
    logic [31:0] v;
    do_reset();
    cfg(1, 0, 0);
    for (int i = 0; i < DEPTH; i++) send_frame(8'h20 + i);
    settle();
    chk_status(B_RXFULL | B_OERR | B_RXEMPTY, B_RXFULL, "RX_FULL after DEPTH frames, no overrun yet");
    cov_hit("rx_fifo_full");
    send_frame(8'hEE);                        settle();
    chk_status(B_RXFULL | B_OERR, B_RXFULL | B_OERR, "overrun flagged, FIFO still full");
    cov_hit("rx_overrun");
    for (int i = 0; i < DEPTH; i++) begin
      rd(R_DATA, v);
      check_eq(v, 8'h20 + i, $sformatf("oldest data preserved, entry %0d", i));
    end
    chk_status(B_RXEMPTY | B_RXFULL | B_OERR, B_RXEMPTY | B_OERR, "drained; OVERRUN is sticky");
    wr(R_STATUS, B_OERR);
    chk_status(B_OERR, 0, "OVERRUN cleared by W1C");
    send_frame(8'h99);                        settle();
    rd(R_DATA, v); check_eq(v, 8'h99, "receiver accepts data again after draining");
  endtask

  task automatic t_enables();
    logic [31:0] v;
    do_reset();
    cfg(2, 0, 0, 0, 1);                       // TX_EN=0
    wr(R_DATA, 8'h5A);
    repeat (3 * 10 * 16 * cur_div) @(negedge PCLK);
    check_eq(tx_q.size(), 0, "no frame while TX_EN=0");
    check_eq(txd, 1, "txd idle while TX_EN=0");
    chk_status(B_TXEMPTY, 0, "byte stays queued while TX_EN=0");
    wr(R_CTRL, 32'h3);
    exp_q.push_back(8'h5A);
    wait_tx_idle();
    cmp_tx_exp("TX_EN re-enabled");

    cfg(2, 0, 0, 1, 0);                       // RX_EN=0
    send_frame(8'h77);                        settle();
    chk_status(B_RXEMPTY, B_RXEMPTY, "frame ignored while RX_EN=0");
    wr(R_CTRL, 32'h3);
    send_frame(8'h42);                        settle();
    rd(R_DATA, v); check_eq(v, 8'h42, "RX works again after RX_EN=1 (and 0x77 never arrived)");
  endtask

  task automatic t_irq();
    logic [31:0] v;
    do_reset();
    cfg(2, 0, 0, 0, 1);                       // TX_EN=0 so TX_EMPTY is under our control
    wr(R_INTEN, 32'h7);
    chk_irq(1, "TX_EMPTY enabled and true"); cov_hit("irq_tx");
    wr(R_INTEN, 32'h5);
    chk_irq(0, "TX_EMPTY masked off");
    wr(R_INTEN, 32'h7);
    wr(R_DATA, 8'h01);
    chk_irq(0, "TX not empty, RX empty, no errors");
    send_frame(8'h42);                        settle();
    chk_irq(1, "RX not empty"); cov_hit("irq_rx");
    rd(R_DATA, v);
    chk_irq(0, "cleared by draining RX");
    send_frame(8'h13, 0, 1);                  settle();
    rd(R_DATA, v);
    chk_irq(1, "error flag keeps irq high (RX already drained)"); cov_hit("irq_err");
    wr(R_STATUS, B_FERR);
    chk_irq(0, "cleared by W1C");
    send_frame(8'h14, 0, 1);                  settle();
    rd(R_DATA, v);
    wr(R_INTEN, 32'h0);
    chk_irq(0, "INT_EN=0 masks everything");

    // PARITY_ERR and OVERRUN_ERR also feed the ERROR interrupt
    wr(R_STATUS, 32'hE0);
    cfg(2, 1, 0, 0, 1);
    wr(R_INTEN, 32'h4);                       // ERROR only
    send_frame(8'h55, 1, 0);                  settle();
    rd(R_DATA, v);
    chk_irq(1, "PARITY_ERR drives the ERROR interrupt");
    wr(R_STATUS, B_PERR);
    chk_irq(0, "PARITY_ERR cleared");
    cfg(1, 0, 0, 0, 1);
    for (int i = 0; i <= DEPTH; i++) send_frame(8'h30 + i);
    settle();
    for (int i = 0; i < DEPTH; i++) rd(R_DATA, v);
    chk_irq(1, "OVERRUN_ERR drives the ERROR interrupt");
    wr(R_STATUS, B_OERR);
    chk_irq(0, "OVERRUN_ERR cleared");
  endtask

  // Receiver must tolerate +-3% bit-rate error (sender faster / slower than nominal)
  task automatic t_rx_baud_tolerance();
    int          bits[2] = '{62, 66};         // BAUD_DIV=4 -> nominal 64 clocks/bit
    logic [31:0] v;
    do_reset();
    for (int pm = 0; pm < 3; pm++) begin
      cfg(4, pm != 0, pm == 2);
      foreach (bits[i]) begin
        rx_bit_clks = bits[i];
        for (int k = 0; k < 4; k++) begin
          logic [7:0] b = $urandom_range(255, 0);
          send_frame(b);                      settle();
          chk_status(B_ERRS | B_RXEMPTY, 0, "tolerance: frame accepted without errors");
          rd(R_DATA, v);
          check_eq(v, b, $sformatf("tolerance: data (bit=%0d clks, pm=%0d)", bits[i], pm));
        end
      end
    end
    rx_bit_clks = 0;
  endtask

  task automatic t_loopback_random();
    int          divs[4] = '{1, 2, 3, 5};
    logic [31:0] v;
    do_reset();
    loopback = 1;
    repeat (8) begin
      int d  = divs[$urandom_range(3, 0)];
      int pm = $urandom_range(2, 0);
      int n  = $urandom_range(DEPTH, 1);
      cfg(d, pm != 0, pm == 2);
      tx_q.delete(); exp_q.delete();
      for (int k = 0; k < n; k++) begin
        logic [7:0] b = $urandom_range(255, 0);
        exp_q.push_back(b);
        wr(R_DATA, b);
      end
      wait_tx_idle();
      repeat (2 * 16 * cur_div) @(negedge PCLK);          // receiver finishes the last stop bit
      cmp_tx_exp("loopback: txd");
      chk_status(B_ERRS, 0, "loopback: no error flags");
      for (int k = 0; k < n; k++) begin
        rd(R_DATA, v);
        check_eq(v, exp_q[k], $sformatf("loopback: received byte %0d (div=%0d pm=%0d)", k, d, pm));
      end
      chk_status(B_RXEMPTY, B_RXEMPTY, "loopback: all bytes read back");
    end
  endtask

  task automatic t_midreset();
    do_reset();
    cfg(2, 0, 0);
    for (int i = 0; i < 4; i++) wr(R_DATA, 8'h00 + i);
    repeat (3 * 16 * cur_div + 5) @(negedge PCLK);        // inside the first frame
    PRESETn = 0;
    repeat (2) @(negedge PCLK);
    check_eq(txd, 1, "txd returns to idle high while in reset");
    @(negedge PCLK);
    PRESETn = 1;
    repeat (2) @(negedge PCLK);
    tx_q.delete();
    cur_div = 1; cur_pen = 0; cur_podd = 0;
    rd_expect(R_STATUS, 32'h0A, "STATUS back to reset value (TX FIFO flushed)");
    rd_expect(R_CTRL,   32'h03, "CTRL back to reset value");
    rd_expect(R_DIV,    32'h01, "BAUD_DIV back to reset value");
    repeat (3 * 11 * 16) @(negedge PCLK);
    check_eq(tx_q.size(), 0, "no frames after reset: pending TX data was flushed");
  endtask

  // ==================================================================== main
  initial begin
    if (!$value$plusargs("TEST=%s", sel)) sel = "all";
`ifdef WAVES
    if ($test$plusargs("WAVE")) begin
      $dumpfile("wave.vcd");
      $dumpvars(0, tb_uart_apb);
    end
`endif
    cov_need("div_1");  cov_need("div_2");  cov_need("div_3");  cov_need("div_5");
    cov_need("par_none"); cov_need("par_even"); cov_need("par_odd");
    cov_need("rx_data_00"); cov_need("rx_data_ff"); cov_need("rx_data_55"); cov_need("rx_data_aa");
    cov_need("tx_fifo_full"); cov_need("rx_fifo_full"); cov_need("rx_overrun");
    cov_need("rx_frame_err"); cov_need("rx_parity_err");
    cov_need("irq_tx"); cov_need("irq_rx"); cov_need("irq_err");

    `RUN("reset",         t_reset())
    `RUN("regs",          t_regs())
    `RUN("tx_single",     t_tx_single())
    `RUN("tx_fifo",       t_tx_fifo())
    `RUN("tx_parity",     t_tx_parity())
    `RUN("rx_basic",      t_rx_basic())
    `RUN("rx_fifo_order", t_rx_fifo_order())
    `RUN("rx_errors",     t_rx_errors())
    `RUN("rx_break",      t_rx_break())
    `RUN("rx_false_start",t_rx_false_start())
    `RUN("rx_overrun",    t_rx_overrun())
    `RUN("rx_tolerance",  t_rx_baud_tolerance())
    `RUN("enables",       t_enables())
    `RUN("irq",           t_irq())
    `RUN("loopback",      t_loopback_random())
    `RUN("midreset",      t_midreset())

    if (sel == "all") cov_report();
    $display("======== %0d checks, %0d errors ========", checks, errors);
    if (errors != 0) $fatal(1, "TEST FAILED (%0d errors)", errors);
    $display("ALL TESTS PASSED");
    $finish;
  end

  // global watchdog (100 ms of simulated time)
  initial begin
    #100_000_000;
    $fatal(1, "WATCHDOG: simulation timed out");
  end

endmodule
