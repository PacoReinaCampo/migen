////////////////////////////////////////////////////////////////////////////////
//                                            __ _      _     _               //
//                                           / _(_)    | |   | |              //
//                __ _ _   _  ___  ___ _ __ | |_ _  ___| | __| |              //
//               / _` | | | |/ _ \/ _ \ '_ \|  _| |/ _ \ |/ _` |              //
//              | (_| | |_| |  __/  __/ | | | | | |  __/ | (_| |              //
//               \__, |\__,_|\___|\___|_| |_|_| |_|\___|_|\__,_|              //
//                  | |                                                       //
//                  |_|                                                       //
//                                                                            //
//                                                                            //
//              MSP430 CPU                                                    //
//              Processing Unit                                               //
//                                                                            //
////////////////////////////////////////////////////////////////////////////////

/* Copyright (c) 2015-2016 by the author(s)
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 *
 * =============================================================================
 * Author(s):
 *   Francisco Javier Reina Campo <frareicam@gmail.com>
 */

`ifdef OMSP_NO_INCLUDE
`else
`include "msp430_defines.sv"
`endif

module  msp430_watchdog (
  // OUTPUTs
  output       [15:0] per_dout,       // Peripheral data output
  output              wdt_irq,        // Watchdog-timer interrupt
  output reg          wdt_reset,      // Watchdog-timer reset
  output              wdt_wkup,       // Watchdog Wakeup
  output reg          wdtifg,         // Watchdog-timer interrupt flag
  output              wdtnmies,       // Watchdog-timer NMI edge selection

  // INPUTs
  input               aclk,           // ACLK
  input               aclk_en,        // ACLK enable
  input               dbg_freeze,     // Freeze Watchdog counter
  input               mclk,           // Main system clock
  input        [13:0] per_addr,       // Peripheral address
  input        [15:0] per_din,        // Peripheral data input
  input               per_en,         // Peripheral enable (high active)
  input        [ 1:0] per_we,         // Peripheral write enable (high active)
  input               por,            // Power-on reset
  input               puc_rst,        // Main system reset
  input               scan_enable,    // Scan enable (active during scan shifting)
  input               scan_mode,      // Scan mode
  input               smclk,          // SMCLK
  input               smclk_en,       // SMCLK enable
  input               wdtie,          // Watchdog timer interrupt enable
  input               wdtifg_irq_clr, // Clear Watchdog-timer interrupt flag
  input               wdtifg_sw_clr,  // Watchdog-timer interrupt flag software clear
  input               wdtifg_sw_set   // Watchdog-timer interrupt flag software set
);

  //=============================================================================
  // 1)  PARAMETER DECLARATION
  //=============================================================================

  // Register base address (must be aligned to decoder bit width)
  parameter       [14:0] BASE_ADDR   = 15'h0120;

  // Decoder bit width (defines how many bits are considered for address decoding)
  parameter              DEC_WD      =  2;

  // Register addresses offset
  parameter [DEC_WD-1:0] WDTCTL      = 'h0;

  // Register one-hot decoder utilities
  parameter              DEC_SZ      =  (1 << DEC_WD);
  parameter [DEC_SZ-1:0] BASE_REG    =  {{DEC_SZ-1{1'b0}}, 1'b1};

  // Register one-hot decoder
  parameter [DEC_SZ-1:0] WDTCTL_D    = (BASE_REG << WDTCTL);

  //============================================================================
  // 2)  REGISTER DECODER
  //============================================================================

  // Local register selection
  wire              reg_sel   =  per_en & (per_addr[13:DEC_WD-1]==BASE_ADDR[14:DEC_WD]);

  // Register local address
  wire [DEC_WD-1:0] reg_addr  =  {per_addr[DEC_WD-2:0], 1'b0};

  // Register address decode
  wire [DEC_SZ-1:0] reg_dec   =  (WDTCTL_D & {DEC_SZ{(reg_addr==WDTCTL)}});

  // Read/Write probes
  wire              reg_write =  |per_we & reg_sel;
  wire              reg_read  = ~|per_we & reg_sel;

  // Read/Write vectors
  wire [DEC_SZ-1:0] reg_wr    = reg_dec & {DEC_SZ{reg_write}};
  wire [DEC_SZ-1:0] reg_rd    = reg_dec & {DEC_SZ{reg_read}};

  //============================================================================
  // 3) REGISTERS
  //============================================================================

  // WDTCTL Register
  //-----------------
  // WDTNMI is not implemented and therefore masked

  reg  [7:0] wdtctl;

  wire       wdtctl_wr = reg_wr[WDTCTL];

  `ifdef CLOCK_GATING
  wire       mclk_wdtctl;
  msp430_clock_gate clock_gate_wdtctl (
    .gclk(mclk_wdtctl),
    .clk (mclk),
    .enable(wdtctl_wr),
    .scan_enable(scan_enable)
  );
  `else
  wire       mclk_wdtctl = mclk;
  `endif

  `ifdef NMI
  parameter [7:0] WDTNMIES_MASK = 8'h40;
  `else
  parameter [7:0] WDTNMIES_MASK = 8'h00;
  `endif

  `ifdef ASIC_CLOCKING
  `ifdef WATCHDOG_MUX
  parameter [7:0] WDTSSEL_MASK  = 8'h04;
  `else
  parameter [7:0] WDTSSEL_MASK  = 8'h00;
  `endif
  `else
  parameter [7:0] WDTSSEL_MASK  = 8'h04;
  `endif

  parameter [7:0] WDTCTL_MASK   = (8'b1001_0011 | WDTSSEL_MASK | WDTNMIES_MASK);

  always @ (posedge mclk_wdtctl or posedge puc_rst) begin
    if (puc_rst)        wdtctl <=  8'h00;
    `ifdef CLOCK_GATING
    else                wdtctl <=  per_din[7:0] & WDTCTL_MASK;
    `else
    else if (wdtctl_wr) wdtctl <=  per_din[7:0] & WDTCTL_MASK;
    `endif
  end

  wire       wdtpw_error = wdtctl_wr & (per_din[15:8]!=8'h5a);
  wire       wdttmsel    = wdtctl[4];
  assign     wdtnmies    = wdtctl[6];

  //============================================================================
  // 4) DATA OUTPUT GENERATION
  //============================================================================

  `ifdef NMI
  parameter [7:0] WDTNMI_RD_MASK  = 8'h20;
  `else
  parameter [7:0] WDTNMI_RD_MASK  = 8'h00;
  `endif
  `ifdef WATCHDOG_MUX
  parameter [7:0] WDTSSEL_RD_MASK = 8'h00;
  `else
  `ifdef WATCHDOG_NOMUX_ACLK
  parameter [7:0] WDTSSEL_RD_MASK = 8'h04;
  `else
  parameter [7:0] WDTSSEL_RD_MASK = 8'h00;
  `endif
  `endif
  parameter [7:0] WDTCTL_RD_MASK  = WDTNMI_RD_MASK | WDTSSEL_RD_MASK;

  // Data output mux
  wire [15:0] wdtctl_rd  = {8'h69, wdtctl | WDTCTL_RD_MASK} & {16{reg_rd[WDTCTL]}};
  assign      per_dout   =  wdtctl_rd;

  //=============================================================================
  // 5)  WATCHDOG TIMER (ASIC IMPLEMENTATION)
  //=============================================================================
  `ifdef ASIC_CLOCKING

  // Watchdog clock source selection
  //---------------------------------
  wire wdt_clk;

  `ifdef WATCHDOG_MUX
  msp430_clock_mux clock_mux_watchdog (
    .clk_out   (wdt_clk),
    .clk_in0   (smclk),
    .clk_in1   (aclk),
    .reset     (puc_rst),
    .scan_mode (scan_mode),
    .selection (wdtctl[2])
  );
  `else
  `ifdef WATCHDOG_NOMUX_ACLK
  assign wdt_clk =  aclk;
  `else
  assign wdt_clk =  smclk;
  `endif
  `endif

  // Reset synchronizer for the watchdog local clock domain
  //--------------------------------------------------------

  wire wdt_rst_noscan;
  wire wdt_rst;

  // Reset Synchronizer
  msp430_sync_reset sync_reset_por (
    .rst_s        (wdt_rst_noscan),
    .clk          (wdt_clk),
    .rst_a        (puc_rst)
  );

  // Scan Reset Mux
  msp430_scan_mux scan_mux_wdt_rst (
    .scan_mode    (scan_mode),
    .data_in_scan (puc_rst),
    .data_in_func (wdt_rst_noscan),
    .data_out     (wdt_rst)
  );

  // Watchog counter clear (synchronization)
  //-----------------------------------------

  // Toggle bit whenever the watchog needs to be cleared
  reg        wdtcnt_clr_toggle;
  wire       wdtcnt_clr_detect = (wdtctl_wr & per_din[3]);
  always @ (posedge mclk or posedge puc_rst) begin
    if (puc_rst)                wdtcnt_clr_toggle <= 1'b0;
    else if (wdtcnt_clr_detect) wdtcnt_clr_toggle <= ~wdtcnt_clr_toggle;
  end

  // Synchronization
  wire wdtcnt_clr_sync;
  msp430_sync_cell sync_cell_wdtcnt_clr (
    .data_out  (wdtcnt_clr_sync),
    .data_in   (wdtcnt_clr_toggle),
    .clk       (wdt_clk),
    .rst       (wdt_rst)
  );

  // Edge detection
  reg wdtcnt_clr_sync_dly;
  always @ (posedge wdt_clk or posedge wdt_rst) begin
    if (wdt_rst)  wdtcnt_clr_sync_dly <= 1'b0;
    else          wdtcnt_clr_sync_dly <= wdtcnt_clr_sync;
  end

  wire wdtqn_edge;
  wire wdtcnt_clr = (wdtcnt_clr_sync ^ wdtcnt_clr_sync_dly) | wdtqn_edge;

  // Watchog counter increment (synchronization)
  //----------------------------------------------
  wire wdtcnt_incr;

  msp430_sync_cell sync_cell_wdtcnt_incr (
    .data_out  (wdtcnt_incr),
    .data_in   (~wdtctl[7] & ~dbg_freeze),
    .clk       (wdt_clk),
    .rst       (wdt_rst)
  );

  // Watchdog 16 bit counter
  //--------------------------
  reg  [15:0] wdtcnt;

  wire [15:0] wdtcnt_nxt  = wdtcnt+16'h0001;

  `ifdef CLOCK_GATING
  wire       wdtcnt_en   = wdtcnt_clr | wdtcnt_incr;
  wire       wdt_clk_cnt;
  msp430_clock_gate clock_gate_wdtcnt (
    .gclk(wdt_clk_cnt),
    .clk (wdt_clk),
    .enable(wdtcnt_en),
    .scan_enable(scan_enable)
  );
  `else
  wire       wdt_clk_cnt = wdt_clk;
  `endif

  always @ (posedge wdt_clk_cnt or posedge wdt_rst) begin
    if (wdt_rst)           wdtcnt <= 16'h0000;
    else if (wdtcnt_clr)   wdtcnt <= 16'h0000;
    `ifdef CLOCK_GATING
    else                   wdtcnt <= wdtcnt_nxt;
    `else
    else if (wdtcnt_incr)  wdtcnt <= wdtcnt_nxt;
    `endif
  end

  // Local synchronizer for the wdtctl.WDTISx
  // configuration (note that we can live with
  // a full bus synchronizer as it won't hurt
  // if we get a wrong WDTISx value for a
  // single clock cycle)
  //--------------------------------------------
  reg [1:0] wdtisx_s;
  reg [1:0] wdtisx_ss;
  always @ (posedge wdt_clk_cnt or posedge wdt_rst) begin
    if (wdt_rst) begin
      wdtisx_s  <=  2'h0;
      wdtisx_ss <=  2'h0;
    end
    else begin
      wdtisx_s  <=  wdtctl[1:0];
      wdtisx_ss <=  wdtisx_s;
    end
  end

  // Interval selection mux
  //--------------------------
  reg        wdtqn;

  always @(wdtisx_ss or wdtcnt_nxt) begin
    case(wdtisx_ss)
      2'b00  : wdtqn =  wdtcnt_nxt[15];
      2'b01  : wdtqn =  wdtcnt_nxt[13];
      2'b10  : wdtqn =  wdtcnt_nxt[9];
      default: wdtqn =  wdtcnt_nxt[6];
    endcase
  end

  // Watchdog event detection
  //-----------------------------

  // Interval end detection
  assign     wdtqn_edge =  (wdtqn & wdtcnt_incr);

  // Toggle bit for the transmition to the MCLK domain
  reg        wdt_evt_toggle;
  always @ (posedge wdt_clk_cnt or posedge wdt_rst) begin
    if (wdt_rst)         wdt_evt_toggle <= 1'b0;
    else if (wdtqn_edge) wdt_evt_toggle <= ~wdt_evt_toggle;
  end

  // Synchronize in the MCLK domain
  wire       wdt_evt_toggle_sync;
  msp430_sync_cell sync_cell_wdt_evt (
    .data_out  (wdt_evt_toggle_sync),
    .data_in   (wdt_evt_toggle),
    .clk       (mclk),
    .rst       (puc_rst)
  );

  // Delay for edge detection of the toggle bit
  reg        wdt_evt_toggle_sync_dly;
  always @ (posedge mclk or posedge puc_rst) begin
    if (puc_rst) wdt_evt_toggle_sync_dly <= 1'b0;
    else         wdt_evt_toggle_sync_dly <= wdt_evt_toggle_sync;
  end

  wire       wdtifg_evt =  (wdt_evt_toggle_sync_dly ^ wdt_evt_toggle_sync) | wdtpw_error;

  // Watchdog wakeup generation
  //-------------------------------------------------------------

  // Clear wakeup when the watchdog flag is cleared (glitch free)
  reg  wdtifg_clr_reg;
  wire wdtifg_clr;
  always @ (posedge mclk or posedge puc_rst) begin
    if (puc_rst) wdtifg_clr_reg <= 1'b1;
    else         wdtifg_clr_reg <= wdtifg_clr;
  end

  // Set wakeup when the watchdog event is detected (glitch free)
  reg  wdtqn_edge_reg;
  always @ (posedge wdt_clk_cnt or posedge wdt_rst) begin
    if (wdt_rst) wdtqn_edge_reg <= 1'b0;
    else         wdtqn_edge_reg <= wdtqn_edge;
  end

  // Watchdog wakeup cell
  wire wdt_wkup_pre;
  msp430_wakeup_cell wakeup_cell_wdog (
    .wkup_out   (wdt_wkup_pre),    // Wakup signal (asynchronous)
    .scan_clk   (mclk),            // Scan clock
    .scan_mode  (scan_mode),       // Scan mode
    .scan_rst   (puc_rst),         // Scan reset
    .wkup_clear (wdtifg_clr_reg),  // Glitch free wakeup event clear
    .wkup_event (wdtqn_edge_reg)   // Glitch free asynchronous wakeup event
  );

  // When not in HOLD, the watchdog can generate a wakeup when:
  //     - in interval mode (if interrupts are enabled)
  //     - in reset mode (always)
  reg  wdt_wkup_en;
  always @ (posedge mclk or posedge puc_rst) begin
    if (puc_rst) wdt_wkup_en <= 1'b0;
    else         wdt_wkup_en <= ~wdtctl[7] & (~wdttmsel | (wdttmsel & wdtie));
  end

  // Make wakeup when not enabled
  msp430_and_gate and_wdt_wkup (
    .y(wdt_wkup),
    .a(wdt_wkup_pre),
    .b(wdt_wkup_en)
  );

  // Watchdog interrupt flag
  //------------------------------
  wire       wdtifg_set =  wdtifg_evt                  |  wdtifg_sw_set;
  assign     wdtifg_clr =  (wdtifg_irq_clr & wdttmsel) |  wdtifg_sw_clr;

  always @ (posedge mclk or posedge por) begin
    if (por)             wdtifg <=  1'b0;
    else if (wdtifg_set) wdtifg <=  1'b1;
    else if (wdtifg_clr) wdtifg <=  1'b0;
  end

  // Watchdog interrupt generation
  //---------------------------------
  assign  wdt_irq       = wdttmsel & wdtifg & wdtie;

  // Watchdog reset generation
  //-----------------------------
  always @ (posedge mclk or posedge por) begin
    if (por) wdt_reset <= 1'b0;
    else     wdt_reset <= wdtpw_error | (wdtifg_set & ~wdttmsel);
  end

  //=============================================================================
  // 6)  WATCHDOG TIMER (FPGA IMPLEMENTATION)
  //=============================================================================
  `else

  // Watchdog clock source selection
  //---------------------------------
  wire  clk_src_en = wdtctl[2] ? aclk_en : smclk_en;

  // Watchdog 16 bit counter
  //--------------------------
  reg [15:0] wdtcnt;

  wire        wdtifg_evt;
  wire        wdtcnt_clr  = (wdtctl_wr & per_din[3]) | wdtifg_evt;
  wire        wdtcnt_incr = ~wdtctl[7] & clk_src_en & ~dbg_freeze;

  wire [15:0] wdtcnt_nxt  = wdtcnt+16'h0001;

  always @ (posedge mclk or posedge puc_rst) begin
    if (puc_rst)           wdtcnt <= 16'h0000;
    else if (wdtcnt_clr)   wdtcnt <= 16'h0000;
    else if (wdtcnt_incr)  wdtcnt <= wdtcnt_nxt;
  end

  // Interval selection mux
  //--------------------------
  reg        wdtqn;

  always @(wdtctl or wdtcnt_nxt) begin
    case(wdtctl[1:0])
      2'b00  : wdtqn =  wdtcnt_nxt[15];
      2'b01  : wdtqn =  wdtcnt_nxt[13];
      2'b10  : wdtqn =  wdtcnt_nxt[9];
      default: wdtqn =  wdtcnt_nxt[6];
    endcase
  end

  // Watchdog event detection
  //-----------------------------

  assign     wdtifg_evt =  (wdtqn & wdtcnt_incr) | wdtpw_error;

  // Watchdog interrupt flag
  //------------------------------
  wire       wdtifg_set =  wdtifg_evt                  |  wdtifg_sw_set;
  wire       wdtifg_clr =  (wdtifg_irq_clr & wdttmsel) |  wdtifg_sw_clr;

  always @ (posedge mclk or posedge por) begin
    if (por)             wdtifg <=  1'b0;
    else if (wdtifg_set) wdtifg <=  1'b1;
    else if (wdtifg_clr) wdtifg <=  1'b0;
  end

  // Watchdog interrupt generation
  //---------------------------------
  assign  wdt_irq       = wdttmsel & wdtifg & wdtie;
  assign  wdt_wkup      =  1'b0;

  // Watchdog reset generation
  //-----------------------------
  always @ (posedge mclk or posedge por) begin
    if (por) wdt_reset <= 1'b0;
    else     wdt_reset <= wdtpw_error | (wdtifg_set & ~wdttmsel);
  end
  `endif
endmodule // msp430_watchdog

`ifdef OMSP_NO_INCLUDE
`else
`include "msp430_undefines.sv"
`endif
