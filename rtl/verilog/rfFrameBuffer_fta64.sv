`timescale 1ns / 1ps
// ============================================================================
//        __
//   \\__/ o\    (C) 2008-2023  Robert Finch, Waterloo
//    \  __ /    All rights reserved.
//     \/_//     robfinch<remove>@finitron.ca
//       ||
//
// rfFrameBuffer_fta64.sv
//  - Displays a bitmap from memory.
//
//
// BSD 3-Clause License
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are met:
//
// 1. Redistributions of source code must retain the above copyright notice, this
//    list of conditions and the following disclaimer.
//
// 2. Redistributions in binary form must reproduce the above copyright notice,
//    this list of conditions and the following disclaimer in the documentation
//    and/or other materials provided with the distribution.
//
// 3. Neither the name of the copyright holder nor the names of its
//    contributors may be used to endorse or promote products derived from
//    this software without specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
// IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
// DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
// FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
// DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
// SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
// CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
// OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//                                                                          
//
//  The default base screen address is:
//		$0200000 - the third meg of RAM
//
// ============================================================================

//`define USE_CLOCK_GATE	1'b1
`define INTERNAL_SYNC_GEN	1'b1
`define WXGA800x600		1'b1
//`define WXGA1366x768	1'b1
`define FBC_ADDR		32'hFD0400001

import const_pkg::*;
`define ABITS	31:0

import fta_bus_pkg::*;
import gfx_pkg::*;

module rfFrameBuffer_fta64(
	rst_i,
	irq_o,
	cs_config_i,
	cs_io_i,
	s_clk_i, s_req, s_resp,
	m_clk_i, m_fst_o, 
//	m_cyc_o, m_stb_o, m_ack_i, m_we_o, m_sel_o, m_adr_o, m_dat_i, m_dat_o,
	m_req, m_resp,
	dot_clk_i, rgb_i, rgb_o, xonoff_i, xal_o
`ifdef INTERNAL_SYNC_GEN
	, hsync_o, vsync_o, blank_o, border_o, hctr_o, vctr_o, fctr_o, vblank_o
`else
	, hsync_i, vsync_i, blank_i
`endif
);
parameter BUSWID = 64;

parameter FBC_ADDR = 32'hFED70001;
parameter FBC_ADDR_MASK = 32'h00FF0000;

parameter CFG_BUS = 8'd0;
parameter CFG_DEVICE = 5'd0;
parameter CFG_FUNC = 3'd0;
parameter CFG_VENDOR_ID	=	16'h0;
parameter CFG_DEVICE_ID	=	16'h0;
parameter CFG_SUBSYSTEM_VENDOR_ID	= 16'h0;
parameter CFG_SUBSYSTEM_ID = 16'h0;
parameter CFG_ROM_ADDR = 32'hFFFFFFF0;

parameter CFG_REVISION_ID = 8'd0;
parameter CFG_PROGIF = 8'd1;
parameter CFG_SUBCLASS = 8'h80;					// 80 = Other
parameter CFG_CLASS = 8'h03;						// 03 = display controller
parameter CFG_CACHE_LINE_SIZE = 8'd8;		// 32-bit units
parameter CFG_MIN_GRANT = 8'h00;
parameter CFG_MAX_LATENCY = 8'h00;
parameter CFG_IRQ_LINE = 8'd6;

localparam CFG_HEADER_TYPE = 8'h00;			// 00 = a general device

parameter MSIX = 1'b0;
parameter IRQ_MSGADR = 64'h0FD0900C1;
parameter IRQ_MSGDAT = 64'h1;

parameter PHYS_ADDR_BITS = 32;
localparam BITS_IN_ADDR_MAP = PHYS_ADDR_BITS - 16;

parameter MDW = 128;		// Bus master data width
parameter MAP = 12'd0;
parameter BM_BASE_ADDR1 = 32'h00000000;
parameter BM_BASE_ADDR2 = 32'h00100000;
parameter REG_CTRL = 11'd0;
parameter REG_REFDELAY = 11'd1;
parameter REG_PAGE1ADDR = 11'd2;
parameter REG_PAGE2ADDR = 11'd3;
parameter REG_PXYZ = 11'd4;
parameter REG_PCOLCMD = 11'd5;
parameter REG_TOTAL = 11'd8;
parameter REG_SYNC_ONOFF = 11'd9;
parameter REG_BLANK_ONOFF = 11'd10;
parameter REG_BORDER_ONOFF = 11'd11;
parameter REG_RASTCMP = 11'd12;
parameter REG_BMPSIZE = 11'd13;
parameter REG_OOB_COLOR = 11'd14;
parameter REG_WINDOW = 11'd15;
parameter REG_IRQ_MSGADR = 11'd16;
parameter REG_IRQ_MSGDAT = 11'd17;
parameter REG_TRANS_COLOR = 11'd18;

parameter OPBLACK = 4'd0;
parameter OPCOPY = 4'd1;
parameter OPINV = 4'd2;
parameter OPAND = 4'd4;
parameter OPOR = 4'd5;
parameter OPXOR = 4'd6;
parameter OPANDN = 4'd7;
parameter OPNAND = 4'd8;
parameter OPNOR = 4'd9;
parameter OPXNOR = 4'd10;
parameter OPORN = 4'd11;
parameter OPWHITE = 4'd15;

// Sync Generator defaults: 800x600 60Hz
// Driven by a 40MHz clock
`ifdef WXGA800x600
parameter phSyncOn  = 40;		//   40 front porch
parameter phSyncOff = 168;		//  128 sync
parameter phBlankOff = 252;	//256	//   88 back porch
//parameter phBorderOff = 336;	//   80 border
parameter phBorderOff = 256;	//   80 border
//parameter phBorderOn = 976;		//  640 display
parameter phBorderOn = 1056;		//  800 display
parameter phBlankOn = 1052;		//   4 border
parameter phTotal = 1056;		// 1056 total clocks
parameter pvSyncOn  = 1;		//    1 front porch
parameter pvSyncOff = 5;		//    4 vertical sync
parameter pvBlankOff = 28;		//   23 back porch
parameter pvBorderOff = 28;		//   44 border	0
//parameter pvBorderOff = 72;		//   44 border	0
parameter pvBorderOn = 628;		//  600 display
//parameter pvBorderOn = 584;		//  512 display
parameter pvBlankOn = 628;  	//   44 border	0
parameter pvTotal = 628;		//  628 total scan lines
`endif
`ifdef WXGA1366x768
// Driven by an 85.86MHz clock
parameter phSyncOn  = 72;		//   72 front porch
parameter phSyncOff = 216;		//  144 sync
parameter phBlankOff = 434;		//  212 back porch
parameter phBorderOff = 434;	//    0 border
parameter phBorderOn = 1800;	// 1366 display
parameter phBlankOn = 1800;		//    0 border
parameter phTotal = 1800;		// 1800 total clocks
// 47.7 = 60 * 795 kHz
parameter pvSyncOn  = 2;		//    1 front porch
parameter pvSyncOff = 5;		//    3 vertical sync
parameter pvBlankOff = 27;		//   23 back porch
parameter pvBorderOff = 27;		//    2 border	0
parameter pvBorderOn = 795;		//  768 display
parameter pvBlankOn = 795;  	//    1 border	0
parameter pvTotal = 795;		//  795 total scan lines
`endif

// SYSCON
input rst_i;				// system reset
output reg [31:0] irq_o;

input cs_config_i;
input cs_io_i;

// Peripheral IO slave port
input s_clk_i;
input fta_cmd_request64_t s_req;
output fta_cmd_response64_t s_resp;

// Video Memory Master Port
// Used to read memory via burst access
input m_clk_i;				// system bus interface clock
output reg m_fst_o;		// first access on scanline
output fta_cmd_request128_t m_req;
input fta_cmd_response128_t m_resp;

// Video
input dot_clk_i;		// Video clock 80 MHz
`ifdef INTERNAL_SYNC_GEN
output hsync_o;
output vsync_o;
output blank_o;
output vblank_o;
output border_o;
output [11:0] hctr_o;
output [11:0] vctr_o;
output [5:0] fctr_o;
`else
input hsync_i;			// start/end of scan line
input vsync_i;			// start/end of frame
input blank_i;			// blank the output
`endif
input [31:0] rgb_i;
output [31:0] rgb_o;		// 32-bit RGB output
reg [31:0] rgb_o;

input xonoff_i;
output reg xal_o;		// external access line (sprite access)

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
// IO registers
// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
reg irq;
reg rst_irq,rst_irq2;

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
wire vclk;
reg cs,cs2;
reg cs_config;
reg cs_map;
reg cs_reg;
wire cs_edge;
reg we;
reg [7:0] sel;
reg [31:0] adri;
reg [63:0] dat;
wire irq_en;
reg [63:0] s_dat_o;
wire ack;

always_ff @(posedge s_clk_i)
	cs <= s_req.cyc & s_req.stb & cs_io_i;
always_ff @(posedge s_clk_i)
	we <= s_req.we;
always_ff @(posedge s_clk_i)
	sel <= s_req.sel;
always_ff @(posedge s_clk_i)
	adri <= s_req.padr;
always_ff @(posedge s_clk_i)
	dat <= s_req.dat;

always_ff @(posedge s_clk_i)
	cs_config <= s_req.cyc & s_req.stb & cs_config_i && adri[27:20]==CFG_BUS && adri[19:15]==CFG_DEVICE && adri[14:12]==CFG_FUNC;
wire cs_fbc;
always_comb
	cs_map = cs && cs_fbc && adri[15:14]==3'd1;
always_comb
	cs_reg = cs && cs_fbc && adri[15:14]==3'd0;

assign s_resp.next = 1'b0;
assign s_resp.stall = 1'b0;
assign s_resp.err = 1'b0;
assign s_resp.rty = 1'b0;
assign s_resp.pri = 4'd7;
assign s_resp.dat = s_dat_o;

vtdl #(.WID(1), .DEP(16)) urdyd1 (.clk(s_clk_i), .ce(1'b1), .a(4'd3), .d(cs_map|cs_reg|cs_config), .q(ack));
vtdl #(.WID(1), .DEP(16)) urdyd2 (.clk(s_clk_i), .ce(1'b1), .a(4'd4), .d(cs_map|cs_reg|cs_config), .q(s_resp.ack));
vtdl #(.WID(4), .DEP(16)) urdyd3 (.clk(s_clk_i), .ce(1'b1), .a(4'd5), .d(s_req.cid), .q(s_resp.cid));
vtdl #(.WID($bits(fta_tranid_t)), .DEP(16)) urdyd4 (.clk(s_clk_i), .ce(1'b1), .a(4'd5), .d(s_req.tid), .q(s_resp.tid));
vtdl #(.WID(32), .DEP(16)) urdyd5 (.clk(s_clk_i), .ce(1'b1), .a(4'd5), .d(s_req.padr), .q(s_resp.adr));

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
integer n, n1;
reg [31:0] fbc_addr;
reg [11:0] rastcmp;
reg [`ABITS] bm_base_addr1,bm_base_addr2;
color_depth_t color_depth, color_depth2;
wire [7:0] fifo_cnt;
reg onoff;
reg [2:0] hres,vres;
reg greyscale;
reg page;
reg [3:0] pals;				// palette select
reg [15:0] hrefdelay;
reg [15:0] vrefdelay;
reg [15:0] windowLeft;
reg [15:0] windowTop;
reg [11:0] windowWidth,windowHeight;
reg [11:0] map;     // memory access period
reg [11:0] mapctr;
reg [15:0] bmpWidth;		// scan line increment (pixels)
reg [15:0] bmpHeight;
reg [`ABITS] baseAddr;	// base address register
wire [MDW-1:0] rgbo1, rgbo1e, rgbo1o, rgbo1m;
reg [15:0] pixelRow;
reg [15:0] pixelCol;
wire [63:0] pal_wo;
wire [31:0] pal_o;
reg [15:0] px;
reg [15:0] py;
reg [7:0] pz;
reg [1:0] pcmd,pcmd_o;
reg [3:0] raster_op;
reg [31:0] zrgb;
reg [31:0] oob_color;		// out-of-bounds color
reg [31:0] trans_color;	// transparent color
reg [31:0] color;
reg [31:0] color_o;
reg rstcmd,rstcmd1;
reg [11:0] hTotal = phTotal;
reg [11:0] vTotal = pvTotal;
reg [11:0] hSyncOn = phSyncOn, hSyncOff = phSyncOff;
reg [11:0] vSyncOn = pvSyncOn, vSyncOff = pvSyncOff;
reg [11:0] hBlankOn = phBlankOn, hBlankOff = phBlankOff;
reg [11:0] vBlankOn = pvBlankOn, vBlankOff = pvBlankOff;
reg [11:0] hBorderOn = phBorderOn, hBorderOff = phBorderOff;
reg [11:0] vBorderOn = pvBorderOn, vBorderOff = pvBorderOff;
reg sgLock;
wire pe_hsync, pe_hsync2;
wire pe_vsync;
reg [11:0] tocnt;		// bus timeout counter
reg vm_cyc_o;
reg [31:0] vm_adr_o;

// config
reg [63:0] irq_msgadr = IRQ_MSGADR;
reg [63:0] irq_msgdat = IRQ_MSGDAT;

wire [BUSWID-1:0] cfg_out;
generate begin : gConfigSpace
	if (BUSWID==32) begin
		pci32_config #(
			.CFG_BUS(CFG_BUS),
			.CFG_DEVICE(CFG_DEVICE),
			.CFG_FUNC(CFG_FUNC),
			.CFG_VENDOR_ID(CFG_VENDOR_ID),
			.CFG_DEVICE_ID(CFG_DEVICE_ID),
			.CFG_BAR0(FBC_ADDR),
			.CFG_BAR0_MASK(FBC_ADDR_MASK),
			.CFG_SUBSYSTEM_VENDOR_ID(CFG_SUBSYSTEM_VENDOR_ID),
			.CFG_SUBSYSTEM_ID(CFG_SUBSYSTEM_ID),
			.CFG_ROM_ADDR(CFG_ROM_ADDR),
			.CFG_REVISION_ID(CFG_REVISION_ID),
			.CFG_PROGIF(CFG_PROGIF),
			.CFG_SUBCLASS(CFG_SUBCLASS),
			.CFG_CLASS(CFG_CLASS),
			.CFG_CACHE_LINE_SIZE(CFG_CACHE_LINE_SIZE),
			.CFG_MIN_GRANT(CFG_MIN_GRANT),
			.CFG_MAX_LATENCY(CFG_MAX_LATENCY),
			.CFG_IRQ_LINE(CFG_IRQ_LINE)
		)
		ucfg1
		(
			.rst_i(rst_i),
			.clk_i(s_clk_i),
			.irq_i(irq),
			.irq_o(irq_o),
			.cs_config_i(cs_config), 
			.we_i(we),
			.sel_i(sel),
			.adr_i(adri),
			.dat_i(dat),
			.dat_o(cfg_out),
			.cs_bar0_o(cs_fbc),
			.cs_bar1_o(),
			.cs_bar2_o(),
			.irq_en_o(irq_en)
		);
	end
	else if (BUSWID==64) begin
		pci64_config #(
			.CFG_BUS(CFG_BUS),
			.CFG_DEVICE(CFG_DEVICE),
			.CFG_FUNC(CFG_FUNC),
			.CFG_VENDOR_ID(CFG_VENDOR_ID),
			.CFG_DEVICE_ID(CFG_DEVICE_ID),
			.CFG_BAR0(FBC_ADDR),
			.CFG_BAR0_MASK(FBC_ADDR_MASK),
			.CFG_SUBSYSTEM_VENDOR_ID(CFG_SUBSYSTEM_VENDOR_ID),
			.CFG_SUBSYSTEM_ID(CFG_SUBSYSTEM_ID),
			.CFG_ROM_ADDR(CFG_ROM_ADDR),
			.CFG_REVISION_ID(CFG_REVISION_ID),
			.CFG_PROGIF(CFG_PROGIF),
			.CFG_SUBCLASS(CFG_SUBCLASS),
			.CFG_CLASS(CFG_CLASS),
			.CFG_CACHE_LINE_SIZE(CFG_CACHE_LINE_SIZE),
			.CFG_MIN_GRANT(CFG_MIN_GRANT),
			.CFG_MAX_LATENCY(CFG_MAX_LATENCY),
			.CFG_IRQ_LINE(CFG_IRQ_LINE)
		)
		ucfg1
		(
			.rst_i(rst_i),
			.clk_i(s_clk_i),
			.irq_i(irq),
			.irq_o(irq_o),
			.cs_config_i(cs_config), 
			.we_i(we),
			.sel_i(sel),
			.adr_i(adri),
			.dat_i(dat),
			.dat_o(cfg_out),
			.cs_bar0_o(cs_fbc),
			.cs_bar1_o(),
			.cs_bar2_o(),
			.irq_en_o(irq_en)
		);
	end
end
endgenerate

wire [15:0] map_page;
wire [15:0] map_out;

   // xpm_memory_tdpram: True Dual Port RAM
   // Xilinx Parameterized Macro, version 2022.2

   xpm_memory_tdpram #(
      .ADDR_WIDTH_A(11),               // DECIMAL
      .ADDR_WIDTH_B(11),               // DECIMAL
      .AUTO_SLEEP_TIME(0),             // DECIMAL
      .BYTE_WRITE_WIDTH_A(BITS_IN_ADDR_MAP),
      .BYTE_WRITE_WIDTH_B(BITS_IN_ADDR_MAP),
      .CASCADE_HEIGHT(0),             // DECIMAL
      .CLOCKING_MODE("independent_clock"), // String
      .ECC_MODE("no_ecc"),            // String
      .MEMORY_INIT_FILE("fb_map.mem"),      // String
      .MEMORY_INIT_PARAM(""),        // String
      .MEMORY_OPTIMIZATION("true"),   // String
      .MEMORY_PRIMITIVE("auto"),      // String
      .MEMORY_SIZE(2048*BITS_IN_ADDR_MAP),
      .MESSAGE_CONTROL(0),            // DECIMAL
      .READ_DATA_WIDTH_A(BITS_IN_ADDR_MAP),
      .READ_DATA_WIDTH_B(BITS_IN_ADDR_MAP),
      .READ_LATENCY_A(2),             // DECIMAL
      .READ_LATENCY_B(2),             // DECIMAL
      .READ_RESET_VALUE_A("0"),       // String
      .READ_RESET_VALUE_B("0"),       // String
      .RST_MODE_A("SYNC"),            // String
      .RST_MODE_B("SYNC"),            // String
      .SIM_ASSERT_CHK(0),             // DECIMAL; 0=disable simulation messages, 1=enable simulation messages
      .USE_EMBEDDED_CONSTRAINT(0),    // DECIMAL
      .USE_MEM_INIT(1),               // DECIMAL
      .USE_MEM_INIT_MMI(0),           // DECIMAL
      .WAKEUP_TIME("disable_sleep"),  // String
      .WRITE_DATA_WIDTH_A(16),        // DECIMAL
      .WRITE_DATA_WIDTH_B(16),        // DECIMAL
      .WRITE_MODE_A("no_change"),     // String
      .WRITE_MODE_B("no_change"),     // String
      .WRITE_PROTECT(1)               // DECIMAL
   )
   umap (
      .dbiterra(),             // 1-bit output: Status signal to indicate double bit error occurrence
                                       // on the data output of port A.

      .dbiterrb(),             // 1-bit output: Status signal to indicate double bit error occurrence
                                       // on the data output of port A.

      .douta(map_out), 		             // READ_DATA_WIDTH_A-bit output: Data output for port A read operations.
      .doutb(map_page),      // READ_DATA_WIDTH_B-bit output: Data output for port B read operations.
      .sbiterra(),             // 1-bit output: Status signal to indicate single bit error occurrence
                                       // on the data output of port A.

      .sbiterrb(),             // 1-bit output: Status signal to indicate single bit error occurrence
                                       // on the data output of port B.

      .addra(adri[13:3]),              // ADDR_WIDTH_A-bit input: Address for port A write and read operations.
      .addrb(vm_adr_o[26:16]),         // ADDR_WIDTH_B-bit input: Address for port B write and read operations.
      .clka(s_clk_i),                  // 1-bit input: Clock signal for port A. Also clocks port B when
                                       // parameter CLOCKING_MODE is "common_clock".

      .clkb(m_clk_i),                  // 1-bit input: Clock signal for port B when parameter CLOCKING_MODE is
                                       // "independent_clock". Unused when parameter CLOCKING_MODE is
                                       // "common_clock".

      .dina(dat[15:0]),                // WRITE_DATA_WIDTH_A-bit input: Data input for port A write operations.
      .dinb(16'd0),                    // WRITE_DATA_WIDTH_B-bit input: Data input for port B write operations.
      .ena(cs_map),                    // 1-bit input: Memory enable signal for port A. Must be high on clock
                                       // cycles when read or write operations are initiated. Pipelined
                                       // internally.

      .enb(onoff),                     // 1-bit input: Memory enable signal for port B. Must be high on clock
                                       // cycles when read or write operations are initiated. Pipelined
                                       // internally.

      .injectdbiterra(1'b0), // 1-bit input: Controls double bit error injection on input data when
                                       // ECC enabled (Error injection capability is not available in
                                       // "decode_only" mode).

      .injectdbiterrb(1'b0), // 1-bit input: Controls double bit error injection on input data when
                                       // ECC enabled (Error injection capability is not available in
                                       // "decode_only" mode).

      .injectsbiterra(1'b0), // 1-bit input: Controls single bit error injection on input data when
                                       // ECC enabled (Error injection capability is not available in
                                       // "decode_only" mode).

      .injectsbiterrb(1'b0), // 1-bit input: Controls single bit error injection on input data when
                                       // ECC enabled (Error injection capability is not available in
                                       // "decode_only" mode).

      .regcea(1'b1),                 // 1-bit input: Clock Enable for the last register stage on the output
                                       // data path.

      .regceb(onoff),                 // 1-bit input: Clock Enable for the last register stage on the output
                                       // data path.

      .rsta(1'b0),                     // 1-bit input: Reset signal for the final port A output register stage.
                                       // Synchronously resets output port douta to the value specified by
                                       // parameter READ_RESET_VALUE_A.

      .rstb(1'b0),                     // 1-bit input: Reset signal for the final port B output register stage.
                                       // Synchronously resets output port doutb to the value specified by
                                       // parameter READ_RESET_VALUE_B.

      .sleep(~onoff),                  // 1-bit input: sleep signal to enable the dynamic power saving feature.
      .wea(we),                        // WRITE_DATA_WIDTH_A/BYTE_WRITE_WIDTH_A-bit input: Write enable vector
                                       // for port A input data port dina. 1 bit wide when word-wide writes are
                                       // used. In byte-wide write configurations, each bit controls the
                                       // writing one byte of dina to address addra. For example, to
                                       // synchronously write only bits [15-8] of dina when WRITE_DATA_WIDTH_A
                                       // is 32, wea would be 4'b0010.

      .web(1'b0)                       // WRITE_DATA_WIDTH_B/BYTE_WRITE_WIDTH_B-bit input: Write enable vector
                                       // for port B input data port dinb. 1 bit wide when word-wide writes are
                                       // used. In byte-wide write configurations, each bit controls the
                                       // writing one byte of dinb to address addrb. For example, to
                                       // synchronously write only bits [15-8] of dinb when WRITE_DATA_WIDTH_B
                                       // is 32, web would be 4'b0010.

   );

always_comb
	m_req.padr <= {map_page,vm_adr_o[15:0]};
	
   // End of xpm_memory_tdpram_inst instantiation
				
delay3 #(1) udly1 (.clk(m_clk_i), .ce(1'b1), .i(vm_cyc_o), .o(m_req.cyc));

`ifdef INTERNAL_SYNC_GEN
wire hsync_i, vsync_i, blank_i;

VGASyncGen usg1
(
	.rst(rst_i),
	.clk(vclk),
	.eol(),
	.eof(),
	.hSync(hsync_o),
	.vSync(vsync_o),
	.hCtr(hctr_o),
	.vCtr(vctr_o),
  .blank(blank_o),
  .vblank(vblank),
  .vbl_int(),
  .border(border_o),
  .hTotal_i(hTotal),
  .vTotal_i(vTotal),
  .hSyncOn_i(hSyncOn),
  .hSyncOff_i(hSyncOff),
  .vSyncOn_i(vSyncOn),
  .vSyncOff_i(vSyncOff),
  .hBlankOn_i(hBlankOn),
  .hBlankOff_i(hBlankOff),
  .vBlankOn_i(vBlankOn),
  .vBlankOff_i(vBlankOff),
  .hBorderOn_i(hBorderOn),
  .hBorderOff_i(hBorderOff),
  .vBorderOn_i(vBorderOn),
  .vBorderOff_i(vBorderOff)
);
assign hsync_i = hsync_o;
assign vsync_i = vsync_o;
assign blank_i = blank_o;
assign vblank_o = vblank;
`endif

edge_det edcs1
(
	.rst(rst_i),
	.clk(s_clk_i),
	.ce(1'b1),
	.i(cs_reg),
	.pe(cs_edge),
	.ne(),
	.ee()
);

// Frame counter
//
VT163 #(6) ub1
(
	.clk(vclk),
	.clr_n(!rst_i),
	.ent(pe_vsync),
	.enp(1'b1),
	.ld_n(1'b1),
	.d(6'd0),
	.q(fctr_o),
	.rco()
);

always_ff @(posedge vclk)
if (rst_i)
	irq <= LOW;
else begin
	if (hctr_o==12'd02 && rastcmp==vctr_o)
		irq <= HIGH;
	else if (rst_irq|rst_irq2)
		irq <= LOW;
end

always_comb
	baseAddr = page ? bm_base_addr2 : bm_base_addr1;

// Color palette RAM for 8bpp modes
// 64x1024 A side, 32x2048 B side
// 3 cycle latency
fb_palram upal1	// Actually 1024x64
(
  .clka(s_clk_i),    // input wire clka
  .ena(cs & adri[13]),      // input wire ena
  .wea({8{we}}&sel),      // input wire [3 : 0] wea
  .addra(adri[12:3]),  // input wire [8 : 0] addra
  .dina(dat),    			// input wire [31 : 0] dina
  .douta(pal_wo),  // output wire [31 : 0] douta
  .clkb(vclk),    // input wire clkb
  .enb(1'b1),      // input wire enb
  .web(1'b0),      // input wire [3 : 0] web
  .addrb({pals,rgbo4[5:0]}),  // input wire [8 : 0] addrb
  .dinb(32'h0),    // input wire [31 : 0] dinb
  .doutb(pal_o)  // output wire [31 : 0] doutb
);

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
always_ff @(posedge s_clk_i)
if (rst_i) begin
	page <= 1'b0;
	pals <= 4'h0;
	hres <= 3'd1;
	vres <= 3'd1;
	windowWidth <= 12'd800;
	windowHeight <= 12'd600;
	onoff <= 1'b1;
	color_depth <= BPP16;
	color_depth2 <= BPP16;
	greyscale <= 1'b0;
	bm_base_addr1 <= BM_BASE_ADDR1;
	bm_base_addr2 <= BM_BASE_ADDR2;
	hrefdelay <= 16'hFF39;//16'd3964;//16'hFF99;//12'd103;
	vrefdelay <= 16'hFFEA;//16'hFFF3;12'd13;
	windowLeft <= 16'h0;
	windowTop <= 16'h0;
	windowWidth <= 16'd800;
	windowHeight <= 16'd600;
	bmpWidth <= 16'd800;
	bmpHeight <= 16'd600;
	map <= MAP;
	pcmd <= 2'b00;
	rstcmd1 <= 1'b0;
	rst_irq <= 1'b0;
	rastcmp <= 12'hFFF;
	oob_color <= 32'h00003C00;
	irq_msgadr <= IRQ_MSGADR;
	irq_msgdat <= IRQ_MSGDAT;
end
else begin
	color_depth2 <= color_depth;
	rstcmd1 <= rstcmd;
	rst_irq <= 1'b0;
  if (rstcmd & ~rstcmd1)
    pcmd <= 2'b00;
	if (cs_edge) begin
		if (we) begin
			casez(adri[13:3])
			REG_CTRL:
				begin
					if (sel[0]) onoff <= dat[0];
					if (sel[1]) begin
					color_depth <= color_depth_t'(dat[9:8]);
					greyscale <= dat[12];
					end
					if (sel[2]) begin
					hres <= dat[18:16];
					vres <= dat[22:20];
					end
					if (sel[3]) begin
					page <= dat[24];
					pals <= dat[28:25];
					end
					if (|sel[7:6]) map <= dat[59:48];
				end
			REG_REFDELAY:
				begin
					if (|sel[1:0])	hrefdelay <= dat[15:0];
					if (|sel[3:2])  vrefdelay <= dat[31:16];
				end
			REG_PAGE1ADDR:	bm_base_addr1 <= dat;
			REG_PAGE2ADDR:	bm_base_addr2 <= dat;
			REG_PXYZ:
				begin
					if (|sel[1:0])	px <= dat[15:0];
					if (|sel[3:2])	py <= dat[31:16];
					if (|sel[  4])	pz <= dat[39:32];
				end
			REG_PCOLCMD:
				begin
					if (sel[0]) pcmd <= dat[1:0];
			    if (sel[1]) raster_op <= dat[11:8];
			    if (|sel[7:2]) color <= dat[63:16];
			  end
			REG_RASTCMP:	
				begin
					if (sel[0]) rastcmp[7:0] <= dat[7:0];
					if (sel[1]) rastcmp[11:8] <= dat[11:8];
					if (sel[7]) rst_irq <= dat[63];
				end
			REG_BMPSIZE:
				begin
					if (|sel[1:0]) bmpWidth <= dat[15:0];
					if (|sel[5:4]) bmpHeight <= dat[47:32];
				end
			REG_OOB_COLOR:
				begin
					if (|sel[3:0]) oob_color[31:0] <= dat[31:0];
				end
			REG_WINDOW:
				begin
					if (|sel[1:0])	windowWidth <= dat[11:0];
					if (|sel[3:2])  windowHeight <= dat[27:16];
					if (|sel[5:4])	windowLeft <= dat[47:32];
					if (|sel[7:6])  windowTop <= dat[63:48];
				end
			REG_IRQ_MSGADR:
				begin
					if (sel[0]) irq_msgadr <= dat[7:0];
					if (sel[1]) irq_msgadr <= dat[15:8];
					if (sel[2]) irq_msgadr <= dat[23:16];
					if (sel[3]) irq_msgadr <= dat[31:24];
					if (sel[4]) irq_msgadr <= dat[39:32];
					if (sel[5]) irq_msgadr <= dat[47:40];
					if (sel[6]) irq_msgadr <= dat[55:48];
					if (sel[7]) irq_msgadr <= dat[63:56];
				end
			REG_IRQ_MSGDAT:
				begin
					if (sel[0]) irq_msgdat <= dat[7:0];
					if (sel[1]) irq_msgdat <= dat[15:8];
					if (sel[2]) irq_msgdat <= dat[23:16];
					if (sel[3]) irq_msgdat <= dat[31:24];
					if (sel[4]) irq_msgdat <= dat[39:32];
					if (sel[5]) irq_msgdat <= dat[47:40];
					if (sel[6]) irq_msgdat <= dat[55:48];
					if (sel[7]) irq_msgdat <= dat[63:56];
				end

`ifdef INTERNAL_SYNC_GEN
			REG_TOTAL:
				begin
					if (!sgLock) begin
						if (|sel[1:0]) hTotal <= dat[11:0];
						if (|sel[3:2]) vTotal <= dat[27:16];
					end
					if (|sel[7:4]) begin
						if (dat[63:32]==32'hA1234567)
							sgLock <= 1'b0;
						else if (dat[63:32]==32'h7654321A)
							sgLock <= 1'b1;
					end
				end
			REG_SYNC_ONOFF:
				if (!sgLock) begin
					if (|sel[1:0]) hSyncOff <= dat[11:0];
					if (|sel[3:2]) hSyncOn <= dat[27:16];
					if (|sel[5:4]) vSyncOff <= dat[43:32];
					if (|sel[7:6]) vSyncOn <= dat[59:48];
				end
			REG_BLANK_ONOFF:
				if (!sgLock) begin
					if (|sel[1:0]) hBlankOff <= dat[11:0];
					if (|sel[3:2]) hBlankOn <= dat[27:16];
					if (|sel[5:4]) vBlankOff <= dat[43:32];
					if (|sel[7:6]) vBlankOn <= dat[59:48];
				end
			REG_BORDER_ONOFF:
				begin
					if (|sel[1:0]) hBorderOff <= dat[11:0];
					if (|sel[3:2]) hBorderOn <= dat[27:16];
					if (|sel[5:4]) vBorderOff <= dat[43:32];
					if (|sel[7:6]) vBorderOn <= dat[59:48];
				end
`endif
      default:  ;
			endcase
		end
	end
	if (cs_reg) begin
		if (BUSWID==64)
		  casez(adri[13:3])
		  REG_CTRL:
		      begin
		          s_dat_o[0] <= onoff;
		          s_dat_o[11:8] <= color_depth2;
		          s_dat_o[12] <= greyscale;
		          s_dat_o[18:16] <= hres;
		          s_dat_o[22:20] <= vres;
		          s_dat_o[24] <= page;
		          s_dat_o[28:25] <= pals;
		          s_dat_o[47:32] <= bmpWidth;
		          s_dat_o[59:48] <= map;
		      end
		  REG_REFDELAY:		s_dat_o <= {32'h0,vrefdelay,hrefdelay};
		  REG_PAGE1ADDR:	s_dat_o <= bm_base_addr1;
		  REG_PAGE2ADDR:	s_dat_o <= bm_base_addr2;
		  REG_PXYZ:		    s_dat_o <= {20'h0,pz,py,px};
		  REG_PCOLCMD:    s_dat_o <= {color_o,12'd0,raster_op,14'd0,pcmd};
		  REG_OOB_COLOR:	s_dat_o <= {32'h0,oob_color};
		  REG_WINDOW:			s_dat_o <= {windowTop,windowLeft,4'h0,windowHeight,4'h0,windowWidth};
		  REG_IRQ_MSGADR:	s_dat_o <= irq_msgadr;
		  REG_IRQ_MSGDAT:	s_dat_o <= irq_msgdat;
		  11'b1?_????_????_?:	s_dat_o <= pal_wo;
		  default:        s_dat_o <= 'd0;
		  endcase
		else
		  casez(adri[13:2])
		  {REG_CTRL,1'b0}:
		      begin
		          s_dat_o[0] <= onoff;
		          s_dat_o[11:8] <= color_depth2;
		          s_dat_o[12] <= greyscale;
		          s_dat_o[18:16] <= hres;
		          s_dat_o[22:20] <= vres;
		          s_dat_o[24] <= page;
		          s_dat_o[28:25] <= pals;
		      end
		  {REG_CTRL,1'b1}:
		      begin
		          s_dat_o[15: 0] <= bmpWidth;
		          s_dat_o[27:16] <= map;
		      end
		  {REG_REFDELAY,1'b0}:	s_dat_o <= {vrefdelay,hrefdelay};
		  {REG_PAGE1ADDR,1'b0}:	s_dat_o <= bm_base_addr1;
		  {REG_PAGE2ADDR,1'b0}:	s_dat_o <= bm_base_addr2;
		  {REG_PXYZ,1'b0}:		  s_dat_o <= {py,px};
		  {REG_PXYZ,1'b1}:		  s_dat_o <= {16'h0,pz};
		  {REG_PCOLCMD,1'b0}:   s_dat_o <= {12'd0,raster_op,14'd0,pcmd};
		  {REG_PCOLCMD,1'b1}:   s_dat_o <= color_o;
		  {REG_OOB_COLOR,1'b0}:	s_dat_o <= oob_color;
		  {REG_WINDOW,1'b0}:		s_dat_o <= {4'h0,windowHeight,4'h0,windowWidth};
		  {REG_WINDOW,1'b1}:		s_dat_o <= {windowTop,windowLeft};
		  {REG_IRQ_MSGADR,1'b0}:	s_dat_o <= irq_msgadr[31:0];
		  {REG_IRQ_MSGADR,1'b1}:	s_dat_o <= irq_msgadr[63:32];
		  {REG_IRQ_MSGDAT,1'b0}:	s_dat_o <= irq_msgdat[31:0];
		  {REG_IRQ_MSGDAT,1'b1}:	s_dat_o <= irq_msgdat[63:32];
		  12'b1?_????_????_?0:	s_dat_o <= pal_wo;
		  default:        s_dat_o <= 'd0;
		  endcase
	end
	else if (cs_map)
		s_dat_o <= {40'h0,map_out};
	else if (cs_config)
		s_dat_o <= cfg_out;
	else
		s_dat_o <= 'h0;
end

//`ifdef USE_CLOCK_GATE
//BUFHCE ucb1
//(
//	.I(dot_clk_i),
//	.CE(onoff),
//	.O(vclk)
//);
//`else
assign vclk = dot_clk_i;
//`endif


// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
// Horizontal and Vertical timing reference counters
// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

reg lef;	// load even fifo
reg lof;	// load odd fifo

edge_det edh1
(
	.rst(rst_i),
	.clk(vclk),
	.ce(1'b1),
	.i(hsync_i),
	.pe(pe_hsync),
	.ne(),
	.ee()
);

edge_det edh2
(
	.rst(rst_i),
	.clk(m_clk_i),
	.ce(1'b1),
	.i(hsync_i),
	.pe(pe_hsync2),
	.ne(),
	.ee()
);

edge_det edv1
(
	.rst(rst_i),
	.clk(vclk),
	.ce(1'b1),
	.i(vsync_i),
	.pe(pe_vsync),
	.ne(),
	.ee()
);

wire [2:0] hc;
wire [2:0] vc;

pixelCounter upxc1
(
	.rst(pe_hsync),
	.clk(vclk),
	.ce(1'b1),
	.res(hres),
	.d(hrefdelay),
	.q(pixelCol),
	.mq(hc)
);

pixelCounter upxr1
(
	.rst(pe_vsync),
	.clk(vclk),
	.ce(pe_hsync),
	.res(vres),
	.d(vrefdelay),
	.q(pixelRow),
	.mq(vc)
);

always_comb
	lef = ~pixelRow[0];
always_comb
	lof =  pixelRow[0];

always_ff @(posedge vclk)
	xal_o <= vc != 4'd1;

// Bits per pixel minus one.
reg [4:0] bpp;
always_comb
case(color_depth2)
BPP8:	bpp = 7;
BPP16:	bpp = 15;
BPP24:	bpp = 23;
BPP32:	bpp = 31;
default:	bpp = 15;
endcase

reg [5:0] shifts;
always_comb
case(MDW)
128:
	case(color_depth2)
	BPP8: 	shifts = 6'd16;
	BPP16:	shifts = 6'd8;
	BPP24:	shifts = 6'd5;
	BPP32:	shifts = 6'd4;
	default:  shifts = 6'd8;
	endcase
64:
	case(color_depth2)
	BPP8: 	shifts = 6'd8;
	BPP16:	shifts = 6'd4;
	BPP24:	shifts = 6'd2;
	BPP32:	shifts = 6'd2;
	default:  shifts = 6'd4;
	endcase
32:
	case(color_depth2)
	BPP8: 	shifts = 6'd4;
	BPP16:	shifts = 6'd2;
	BPP24:	shifts = 6'd1;
	BPP32:	shifts = 6'd1;
	default:  shifts = 6'd2;
	endcase
default:
	begin
	$display("rfFramBuffer_fta64: Bad master bus width");
	$finish;
	end
endcase

wire vFetch = !vblank;//pixelRow < windowHeight;
reg fifo_rrst;
reg fifo_wrst;
always_comb fifo_rrst = pixelCol==16'hFFFF;
always_comb fifo_wrst = pe_hsync2 && vc==4'd1;

wire[31:0] grAddr,xyAddr;
reg [11:0] fetchCol;
localparam CMS = MDW==128 ? 6 : MDW==64 ? 5 : 4;
wire [CMS:0] mb,me,ce;
reg [MDW-1:0] mem_strip;
wire [MDW-1:0] mem_strip_o;

// Compute fetch address
gfx_calc_address #(.SW(MDW)) u1
(
  .clk(m_clk_i),
	.base_address_i(baseAddr),
	.color_depth_i(color_depth2),
	.bmp_width_i(bmpWidth),
	.x_coord_i(windowLeft),
	.y_coord_i(windowTop + pixelRow),
	.address_o(grAddr),
	.mb_o(),
	.me_o(),
	.ce_o()
);

// Compute address for get/set pixel
gfx_calc_address #(.SW(MDW)) u2
(
  .clk(m_clk_i),
	.base_address_i(baseAddr),
	.color_depth_i(color_depth2),
	.bmp_width_i(bmpWidth),
	.x_coord_i(px),
	.y_coord_i(py),
	.address_o(xyAddr),
	.mb_o(mb),
	.me_o(me),
	.ce_o(ce)
);

always_ff @(posedge m_clk_i)
if (pe_hsync2)
  mapctr <= 12'hFFE;
else begin
  if (mapctr == map)
    mapctr <= 12'd0;
  else
    mapctr <= mapctr + 12'd1;
end
wire memreq = mapctr==12'd0 && vc==4'd1;

// The following bypasses loading the fifo when all the pixels from a scanline
// are buffered in the fifo and the pixel row doesn't change. Since the fifo
// pointers are reset at the beginning of a scanline, the fifo can be used like
// a cache.
wire blankEdge;
edge_det ed2(.rst(rst_i), .clk(m_clk_i), .ce(1'b1), .i(blank_i), .pe(blankEdge), .ne(), .ee() );
reg do_loads;
reg load_fifo = 1'b0;
always_ff @(posedge m_clk_i)
	//load_fifo <= fifo_cnt < 10'd1000 && vFetch && onoff && xonoff && !m_cyc_o && do_loads;
	load_fifo <= /*fifo_cnt < 8'd224 &&*/ vFetch && onoff && xonoff_i && (fetchCol < windowWidth) && memreq;
// The following table indicates the number of pixel that will fit into the
// video fifo. 
reg [11:0] hCmp;
always_comb
case(color_depth2)
BPP8:	hCmp = 12'd2048;
BPP16:	hCmp = 12'd1024;
BPP24:	hCmp = 12'd640;
BPP32:	hCmp = 12'd512;
default:	hCmp = 12'd1024;
endcase
/*
always @(posedge m_clk_i)
	// if windowWidth > hCmp we always load because the fifo isn't large enough to act as a cache.
	if (!(windowWidth < hCmp))
		do_loads <= 1'b1;
	// otherwise load the fifo only when the row changes to conserve memory bandwidth
	else if (vc==4'd1)//pixelRow != opixelRow)
		do_loads <= 1'b1;
	else if (blankEdge)
		do_loads <= 1'b0;
*/
always_comb m_req.bte = fta_bus_pkg::LINEAR;
always_comb m_req.cti = fta_bus_pkg::CLASSIC;
always_comb m_req.blen = 6'd63;
always_comb m_req.stb = m_req.cyc;
always_comb m_req.cid = 'd0;
always_comb m_req.tid = 15'h1234;

reg [31:0] adr;
typedef enum logic [3:0] {
	IDLE = 4'd0,
	LOADCOLOR = 4'd2,
	LOADSTRIP = 4'd3,
	STORESTRIP = 4'd4,
	ACKSTRIP = 4'd5,
	WAITLOAD = 4'd6,
	WAITRST = 4'd7,
	ICOLOR1 = 4'd8,
	ICOLOR2 = 4'd9,
	ICOLOR3 = 4'd10,
	ICOLOR4 = 4'd11,
	LOAD_OOB = 4'd12
} state_t;
state_t state;
reg [127:0] icolor1;

function rastop;
input [3:0] op;
input a;
input b;
case(op)
OPBLACK: rastop = 1'b0;
OPCOPY:  rastop = b;
OPINV:   rastop = ~a;
OPAND:   rastop = a & b;
OPOR:    rastop = a | b;
OPXOR:   rastop = a ^ b;
OPANDN:  rastop = a & ~b;
OPNAND:  rastop = ~(a & b);
OPNOR:   rastop = ~(a | b);
OPXNOR:  rastop = ~(a ^ b);
OPORN:   rastop = a | ~b;
OPWHITE: rastop = 1'b1;
default:	rastop = 1'b0;
endcase
endfunction

always_ff @(posedge m_clk_i)
	if (fifo_wrst)
		adr <= grAddr;
  else begin
    if ((state==WAITLOAD && (m_resp.ack|tocnt[10])) || state==LOAD_OOB)
    	case(MDW)
    	32:		adr <= adr + 32'd4;
    	64:		adr <= adr + 32'd8;
    	default:	adr <= adr + 32'd16;
    	endcase
  end

always_ff @(posedge m_clk_i)
	if (fifo_wrst)
		fetchCol <= 12'd0;
  else begin
    if ((state==WAITLOAD && (m_resp.ack|tocnt[10])) || state==LOAD_OOB)
      fetchCol <= fetchCol + shifts;
  end

// Check for legal (positive) coordinates
// Illegal coordinates result in a red display
wire [15:0] xcol = fetchCol;
reg legal_x, legal_y;
always_comb legal_x = ~&xcol[15:12] && xcol < bmpWidth;
always_comb legal_y = ~&pixelRow[15:12] && pixelRow < bmpHeight;

reg modd;
always_comb
	case(MDW)
	32:	modd <= m_req.padr[5:2]==4'hF;
	64:	modd <= m_req.padr[5:3]==3'h7;
	default:	modd <= m_req.padr[5:4]==2'h3;
	endcase

always_ff @(posedge m_clk_i)
if (rst_i)
	tocnt <= 'd0;
else begin
	if (m_req.cyc)
		tocnt <= tocnt + 2'd1;
	else
		tocnt <= 'd0;
end

always_ff @(posedge m_clk_i, posedge rst_i)
if (rst_i) begin
	vm_cyc_o <= LOW;
	m_req.we <= LOW;
	m_req.sel <= 'd0;
	vm_adr_o <= 'd0;
  rstcmd <= 1'b0;
  state <= IDLE;
  rst_irq2 <= 1'b0;
end
else begin
  wb_nack();
  rst_irq2 <= 1'b0;
	if (fifo_wrst)
		m_fst_o <= HIGH;
	case(state)
  WAITRST:
    if (pcmd==2'b00 && ~m_resp.ack) begin
      rstcmd <= 1'b0;
      state <= IDLE;
    end
    else
      rstcmd <= 1'b1;
  IDLE:
  	if (load_fifo && !(legal_x && legal_y))
 			state <= LOAD_OOB;
    else if (load_fifo & ~m_resp.ack) begin
      vm_cyc_o <= HIGH;
      vm_adr_o <= adr;
      m_req.sel <= 16'hFFFF;
      state <= WAITLOAD;
    end
    // Send an IRQ message if needed.
    else if (irq & ~m_resp.ack & MSIX) begin
    	vm_cyc_o <= HIGH;
    	vm_adr_o <= irq_msgadr;
    	m_req.we <= HIGH;
    	m_req.sel <= irq_msgadr[3] ? 16'hFF00 : 16'h00FF;
    	m_req.data1 <= {2{irq_msgdat}};
    	rst_irq2 <= 1'b1;
    end
    // The adr_o[5:3]==3'b111 causes the controller to wait until all eight
    // 64 bit strips from the memory controller have been processed. Otherwise
    // there would be cache thrashing in the memory controller and the memory
    // bandwidth available would be greatly reduced. However fetches are also
    // allowed when loads are not active or all strips for the current scan-
    // line have been fetched.
    else if (pcmd!=2'b00 && (modd || !(vFetch && onoff && xonoff_i && fetchCol < windowWidth))) begin
      vm_cyc_o <= HIGH;
      vm_adr_o <= xyAddr;
      m_req.sel <= 16'hFFFF;
      state <= LOADSTRIP;
    end
  LOADSTRIP:
    if (m_resp.ack|tocnt[10]) begin
      wb_nack();
      mem_strip <= m_resp.dat;
      icolor1 <= {96'b0,color} << mb;
      rstcmd <= 1'b1;
      if (pcmd==2'b01)
        state <= ICOLOR3;
      else if (pcmd==2'b10)
        state <= ICOLOR2;
      else begin
        state <= WAITRST;
      end
    end
  // Registered inline mem2color
  ICOLOR3:
    begin
      color_o <= mem_strip >> mb;
      state <= ICOLOR4;
    end
  ICOLOR4:
    begin
      for (n = 0; n < 32; n = n + 1)
        color_o[n] <= (n <= bpp) ? color_o[n] : 1'b0;
      state <= pcmd == 2'b0 ? (~m_resp.ack ? IDLE : WAITRST) : WAITRST;
      if (pcmd==2'b00)
        rstcmd <= 1'b0;
    end
  // Registered inline color2mem
  ICOLOR2:
    begin
      for (n = 0; n < MDW; n = n + 1)
        m_req.data1[n] <= (n >= mb && n <= me)
        	? ((n <= ce) ?	rastop(raster_op, mem_strip[n], icolor1[n]) : icolor1[n])
        	: mem_strip[n];
      state <= STORESTRIP;
    end
  STORESTRIP:
    if (~m_resp.ack) begin
      vm_cyc_o <= HIGH;
      m_req.we <= HIGH;
      m_req.sel <= 16'hFFFF;
      vm_adr_o <= xyAddr;
      state <= ACKSTRIP;
    end
  ACKSTRIP:
    if (m_resp.ack|tocnt[10]) begin
      wb_nack();
      state <= pcmd == 2'b0 ? IDLE : WAITRST;
      if (pcmd==2'b00)
        rstcmd <= 1'b0;
    end
  WAITLOAD:
    if (m_resp.ack|tocnt[10]) begin
      wb_nack();
      state <= IDLE;
    end
  LOAD_OOB:
  	state <= IDLE;
  default:	state <= IDLE;
  endcase
end

task wb_nack;
begin
	m_fst_o <= LOW;
	vm_cyc_o <= LOW;
	m_req.we <= LOW;
	m_req.sel <= 16'h0000;
end
endtask

reg [31:0] rgbo2,rgbo4;
reg [MDW-1:0] rgbo3;
always_ff @(posedge vclk)
case(color_depth2)
BPP8:	rgbo4 <= {24'h0,rgbo3[7:0]};		// feeds into palette
BPP16:	rgbo4 <= {rgbo3[15:10],5'b0,rgbo3[9:5],5'b0,rgbo3[4:0],5'b0};
BPP24:	rgbo4 <= {rgbo3[23:16],2'b0,rgbo3[15:8],2'b0,rgbo3[7:0],2'b0};
BPP32:	rgbo4 <= {rgbo3[29:20],rgbo3[19:10],rgbo3[9:0]};
default:	rgbo4 <= {rgbo3[15:10],5'b0,rgbo3[9:5],5'b0,rgbo3[4:0],5'b0};
endcase

reg rd_fifo,rd_fifo1,rd_fifo2;
/*
reg de;
always_ff @(posedge vclk)
	if (rd_fifo1)
		de <= ~blank_i;
*/

always_ff @(posedge vclk)
	if (onoff && xonoff_i && !blank_i) begin
		if (color_depth2==BPP8) begin
			if (!greyscale)
				zrgb <= pal_o;
			else
				zrgb <= {pal_o[31:30],pal_o[9:0],pal_o[9:0],pal_o[9:0]};
		end
		else
			zrgb <= rgbo4;
	end
	else
		zrgb <= 32'h00000000;
always_ff @(posedge vclk)
	if (zrgb==trans_color)
		rgb_o <= rgb_i;
	else
		rgb_o <= zrgb;

// Before the hrefdelay expires, pixelCol will be negative, which is greater
// than windowWidth as the value is unsigned. That means that fifo reading is
// active only during the display area 0 to windowWidth.
reg shift1;
always_comb shift1 = hc==hres;
reg [5:0] shift_cnt;
always_ff @(posedge vclk)
if (pe_hsync)
	shift_cnt <= 5'd1;
else begin
	if (shift1) begin
		if (pixelCol==16'hFFFF)
			shift_cnt <= shifts;
		else if (!pixelCol[15]) begin
			shift_cnt <= shift_cnt + 5'd1;
			if (shift_cnt==shifts)
				shift_cnt <= 5'd1;
		end
		else
			shift_cnt <= 5'd1;
	end
end

reg next_strip;
always_comb next_strip = (shift_cnt==shifts) && (hc==hres);

wire vrd;
reg shift,shift2;
always_ff @(posedge vclk) shift2 <= shift1;
always_ff @(posedge vclk) shift <= shift2;
always_ff @(posedge vclk) rd_fifo2 <= next_strip;
always_ff @(posedge vclk) rd_fifo <= rd_fifo2;
always_ff @(posedge vclk)
	if (rd_fifo)
		rgbo3 <= lef ? rgbo1o : rgbo1e;
	else if (shift) begin
		case(color_depth2)
		BPP8:	rgbo3 <= {8'h0,rgbo3[MDW-1:8]};
		BPP16:	rgbo3 <= {16'h0,rgbo3[MDW-1:16]};
		BPP24:	rgbo3 <= {24'h0,rgbo3[MDW-1:24]};
		BPP32:	rgbo3 <= {32'h0,rgbo3[MDW-1:32]};
		default: rgbo3 <= {16'h0,rgbo3[MDW-1:16]};
		endcase
	end


/* Debugging
wire [127:0] dat;
assign dat[11:0] = pixelRow[0] ? 12'hEA4 : 12'h000;
assign dat[23:12] = pixelRow[1] ? 12'hEA4 : 12'h000;
assign dat[35:24] = pixelRow[2] ? 12'hEA4 : 12'h000;
assign dat[47:36] = pixelRow[3] ? 12'hEA4 : 12'h000;
assign dat[59:48] = pixelRow[4] ? 12'hEA4 : 12'h000;
assign dat[71:60] = pixelRow[5] ? 12'hEA4 : 12'h000;
assign dat[83:72] = pixelRow[6] ? 12'hEA4 : 12'h000;
assign dat[95:84] = pixelRow[7] ? 12'hEA4 : 12'h000;
assign dat[107:96] = pixelRow[8] ? 12'hEA4 : 12'h000;
assign dat[119:108] = pixelRow[9] ? 12'hEA4 : 12'h000;
*/

reg [MDW-1:0] oob_dat;
always_comb
case(color_depth2)
BPP8:	oob_dat <= {MDW/8{oob_color[7:0]}};
BPP16:	oob_dat <= {MDW/16{oob_color[15:0]}};
BPP24:	oob_dat <= {MDW/24{oob_color[23:0]}};
BPP32:	oob_dat <= {MDW/32{oob_color[31:0]}};
default:	oob_dat <= {MDW/16{oob_color[15:0]}};
endcase

rfVideoFifo #(MDW) uf1
(
	.wrst(fifo_wrst),
	.wclk(m_clk_i),
	.wr((((m_resp.ack|tocnt[10]) && state==WAITLOAD) || state==LOAD_OOB) && lef),
	.di((state==LOAD_OOB) ? oob_dat : m_resp.dat),
	.rrst(fifo_rrst),
	.rclk(vclk),
	.rd(rd_fifo & lof),
	.dout(rgbo1e),
	.cnt()
);

rfVideoFifo #(MDW) uf2
(
	.wrst(fifo_wrst),
	.wclk(m_clk_i),
	.wr((((m_resp.ack|tocnt[10]) && state==WAITLOAD) || state==LOAD_OOB) && lof),
	.di((state==LOAD_OOB) ? oob_dat : m_resp.dat),
	.rrst(fifo_rrst),
	.rclk(vclk),
	.rd(rd_fifo & lef),
	.dout(rgbo1o),
	.cnt()
);

endmodule

// Horizontal or vertical pixel counter.
// If the count is negative, step by one keeps the meaning of the refdelay value
// consistent between different resolutions.

module pixelCounter(rst, clk, ce, res, d, q, mq);
input rst;
input clk;
input ce;
input [2:0] res;
input [15:0] d;
output reg [15:0] q;
output reg [2:0] mq;		// modulo count

always_ff @(posedge clk)
if (rst) begin
	mq <= 3'd1;
	q <= d;
end
else begin
	if (ce) begin
		if (&q[15:12]) begin
			q <= q + 16'd1;
			mq <= 3'd1;
		end
		else if (mq==res) begin
			mq <= 3'd1;
			q <= q + 16'd1;
		end
		else
			mq <= mq + 3'd1;
	end
end

endmodule
