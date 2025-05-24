`timescale 1ns / 1ps
// ============================================================================
//        __
//   \\__/ o\    (C) 2008-2025  Robert Finch, Waterloo
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
// 800x600 40.000MHz clock
// 1366x768 85.86 MHz clock
// ============================================================================

//`define USE_CLOCK_GATE	1'b1
//`define VGA640x480	1'b1
//`define WXGA800x600		1'b1
`define WXGA1920x1080		1'b1
//`define WXGA1280x720		1'b1
//`define WXGA1366x768	1'b1

import const_pkg::*;
`define ABITS	31:0

import fta_bus_pkg::*;
import gfx_pkg::*;

//`define BUSWID64	1'b1
`define BUSWID32	1'b1

module rfFrameBuffer_fta64 (
	rst_i,
	xonoff_i,
	irq_o,
	cs_config_i,
	s_bus_i,
	m_fst_o, 
	m_bus_o,
	m_rst_busy_i,
	video_i,
	video_o,
	xal_o,
	vblank_o
);
parameter BUSWID = 64;
parameter INTERNAL_SYNCGEN = 1'b1;
parameter CORENO = 6'd62;
parameter CHANNEL = 3'd1;

//parameter FBC_ADDR = 32'hFED70001;
parameter FBC_ADDR = 32'hFD200001;
parameter FBC_ADDR_MASK = 32'hFFFF0000;

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
localparam BITS_IN_ADDR_MAP = 18;

parameter MDW = 256;			// Bus master data width
parameter BURST_INTERVAL = 12'd600;
parameter BM_BASE_ADDR1 = 32'h00000000;
parameter BM_BASE_ADDR2 = 32'h00400000;
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
// Driven by a 40.000MHz clock
/*
`ifdef VGA640x480
parameter phSyncOn  = 16;		//   16 front porch
parameter phSyncOff = 112;		//  96 sync
parameter phBlankOff = 160;	//256	//   48 back porch
//parameter phBorderOff = 336;	//   80 border
parameter phBorderOff = 160;	//   80 border
//parameter phBorderOn = 976;		//  640 display
parameter phBorderOn = 800;		//  800 display
parameter phBlankOn = 800;		//   4 border
parameter phTotal = 800;		// 1056 total clocks
parameter pvSyncOn  = 10;		//    10 front porch
parameter pvSyncOff = 12;		//    2 vertical sync
parameter pvBlankOff = 45;		//   33 back porch
parameter pvBorderOff = 51;		//   44 border	0
//parameter pvBorderOff = 72;		//   44 border	0
parameter pvBorderOn = 519;		//  600 display
//parameter pvBorderOn = 584;		//  512 display
parameter pvBlankOn = 525;  	//   44 border	0
parameter pvTotal = 525;		//  628 total scan lines
/*
// Driven by a 25.175MHz clock
parameter phSyncOn  = 16;		//   16 front porch
parameter phSyncOff = 112;		//  96 sync
parameter phBlankOff = 160;	//256	//   48 back porch
//parameter phBorderOff = 336;	//   80 border
parameter phBorderOff = 160;	//   80 border
//parameter phBorderOn = 976;		//  640 display
parameter phBorderOn = 800;		//  800 display
parameter phBlankOn = 800;		//   4 border
parameter phTotal = 800;		// 1056 total clocks
parameter pvSyncOn  = 10;		//    10 front porch
parameter pvSyncOff = 12;		//    2 vertical sync
parameter pvBlankOff = 45;		//   33 back porch
parameter pvBorderOff = 51;		//   44 border	0
//parameter pvBorderOff = 72;		//   44 border	0
parameter pvBorderOn = 519;		//  600 display
//parameter pvBorderOn = 584;		//  512 display
parameter pvBlankOn = 525;  	//   44 border	0
parameter pvTotal = 525;		//  628 total scan lines
*/
//`endif

// Sync Generator defaults: 800x600 60Hz
// Driven by a 40MHz clock

`ifdef WXGA800x600
parameter phSyncOn  = 40;		//   40 front porch
parameter phSyncOff = 168;		//  128 sync
parameter phBlankOff = 252;	//256	//   88 back porch
//parameter phBorderOff = 336;	//   80 border
parameter phBorderOff = 254;	//   80 border
//parameter phBorderOn = 976;		//  640 display
parameter phBorderOn = 1054;		//  800 display
parameter phBlankOn = 1056;		//   4 border
parameter phTotal = 1056;		// 1056 total clocks
parameter pvSyncOn  = 1;		//    1 front porch
parameter pvSyncOff = 5;		//    4 vertical sync
parameter pvBlankOff = 28;		//   23 back porch (28)
parameter pvBorderOff = 28;		//   44 border	0
//parameter pvBorderOff = 72;		//   44 border	0
parameter pvBorderOn = 628;		//  600 display
//parameter pvBorderOn = 584;		//  512 display
parameter pvBlankOn = 628;  	//   44 border	0
parameter pvTotal = 628;		//  628 total scan lines
`endif

// 148.5 MHz clock
// -hsync, -vsync
`ifdef WXGA1920x1080
parameter phSyncOn  = 88;		//   88 front porch
parameter phSyncOff = 132;		//  44 sync
parameter phBlankOff = 280;	//256	//   148 back porch
parameter phBorderOff = 280;	//   0 border
parameter phBorderOn = 2200;		//  1920 display
parameter phBlankOn = 2200;		//   0 border
parameter phTotal = 2200;		// 2200 total clocks
parameter pvSyncOn  = 4;		//    4 front porch
parameter pvSyncOff = 9;		//    9 vertical sync
parameter pvBlankOff = 45;		//   45 back porch (36)
parameter pvBorderOff = 45;		//   44 border	0
parameter pvBorderOn = 1125;		//  600 display
parameter pvBlankOn = 1125;  	//   44 border	0
parameter pvTotal = 1125;		//  628 total scan lines
`endif

// 74.25 MHz clock
// -hsync, -vsync
`ifdef WXGA960x1080
parameter phSyncOn  = 44;		//   88 front porch
parameter phSyncOff = 66;		//  44 sync
parameter phBlankOff = 140;	//256	//   148 back porch
parameter phBorderOff = 140;	//   0 border
parameter phBorderOn = 1100;		//  1920 display
parameter phBlankOn = 1100;		//   0 border
parameter phTotal = 1100;		// 2200 total clocks
parameter pvSyncOn  = 4;		//    4 front porch
parameter pvSyncOff = 9;		//    9 vertical sync
parameter pvBlankOff = 45;		//   45 back porch (36)
parameter pvBorderOff = 45;		//   44 border	0
parameter pvBorderOn = 1125;		//  600 display
parameter pvBlankOn = 1125;  	//   44 border	0
parameter pvTotal = 1125;		//  628 total scan lines
`endif

// 74.25 MHz clock (148.5 MHz clock/2)
// +hsync, +vsync
`ifdef WXGA1280x720
parameter phSyncOn  = 220;		// 110 front porch
parameter phSyncOff = 300;		//  40 sync
parameter phBlankOff = 740;		// 220	back porch
//parameter phBorderOff = 336;	//   0 border
parameter phBorderOff = 740;	//   0 border
parameter phBorderOn = 3300;		//  1280 (2560) display
parameter phBlankOn = 3300;		//   0 border
parameter phTotal = 3300;		// 2200 total clocks
parameter pvSyncOn  = 5;		//    5 front porch
parameter pvSyncOff = 10;		//    5 vertical sync
parameter pvBlankOff = 30;		//   20 back porch (36)
parameter pvBorderOff = 30;		//   44 border	0
//parameter pvBorderOff = 72;		//   44 border	0
parameter pvBorderOn = 750;		//  600 display
//parameter pvBorderOn = 584;		//  512 display
parameter pvBlankOn = 750;  	//   44 border	0
parameter pvTotal = 750;			//  628 total scan lines
`endif

/*
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
*/
// SYSCON
input rst_i;				// system reset
output reg [31:0] irq_o;
input cs_config_i;
input xonoff_i;
output reg xal_o;		// external access line (sprite access)

// Peripheral IO slave port
fta_bus_interface.slave s_bus_i;

// Video Memory Master Port
// Used to read memory via burst access
output reg m_fst_o;		// first access on scanline
fta_bus_interface.master m_bus_o;
input m_rst_busy_i;

// Video
video_bus.in video_i;
video_bus.out video_o;
output vblank_o;


wire s_clk_i = s_bus_i.clk;
`ifdef BUSWID64
fta_cmd_request64_t s_req_i;
fta_cmd_response64_t s_resp_o;
`endif
`ifdef BUSWID32
fta_cmd_request32_t s_req_i;
fta_cmd_response32_t s_resp_o;
`endif
always_comb
begin
	s_req_i.tid = s_bus_i.req.tid;
	s_req_i.cyc = s_bus_i.req.cyc;
	s_req_i.we = s_bus_i.req.we;
	s_req_i.sel = s_bus_i.req.sel;
	s_req_i.adr = s_bus_i.req.adr;
	s_req_i.dat = s_bus_i.req.data1;
end
always_comb
begin
	s_bus_i.resp.tid = s_resp_o.tid;
	s_bus_i.resp.adr = s_resp_o.adr;
	s_bus_i.resp.dat = s_resp_o.dat;
	s_bus_i.resp.ack = s_resp_o.ack;
	s_bus_i.resp.stall = s_resp_o.stall;
	s_bus_i.resp.rty = s_resp_o.rty;
	s_bus_i.resp.err = s_resp_o.err;
	s_bus_i.resp.next = s_resp_o.next;
	s_bus_i.resp.pri = s_resp_o.pri;
end

wire dot_clk_i = video_i.clk;		// video clock (40 MHz)
wire hsync_i = video_i.hsync;		// start/end of scan line
wire vsync_i = video_i.vsync;		// start/end of frame
wire blank_i = video_i.blank;		// blank the output
wire border_i = video_i.border;
wire [31:0] rgb_i = video_i.data;
wire hsync_o;
wire vsync_o;
wire blank_o;
wire border_o;
reg [31:0] rgb_o;							// 32-bit RGB output
assign video_o.clk = video_i.clk;
assign video_o.hsync = hsync_o;
assign video_o.vsync = vsync_o;
assign video_o.blank = blank_o;
assign video_o.border = border_o;
assign video_o.data = rgb_o;

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
// IO registers
// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
reg irq;
reg rst_irq,rst_irq2;

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
wire vclk;
wire [15:0] hctr;
wire [11:0] scanline;
wire [5:0] shifts;
wire [5:0] shift_cnt;
reg cs2;
reg cs_config;
reg cs_map;
reg cs_reg;
wire cs_edge;
wire cs_fbc;
wire latch_map;
reg we;
reg [7:0] sel;
reg [31:0] adri;
reg [63:0] dat;
wire irq_en;
reg [63:0] s_dat_o, s_dato;
wire ack;
`ifdef BUSWID64
fta_cmd_request64_t reqd;
fta_cmd_response64_t s_resp1;
fta_cmd_response64_t cfg_resp;
`endif
`ifdef BUSWID32
fta_cmd_request32_t reqd;
fta_cmd_response32_t s_resp1;
fta_cmd_response32_t cfg_resp;
`endif
reg [5:0] max_nburst;
reg [5:0] burst_len;

always_ff @(posedge s_clk_i)
	reqd <= s_req_i;
always_ff @(posedge s_clk_i)
	we <= s_req_i.we;
always_ff @(posedge s_clk_i)
	sel <= (BUSWID==32)  ? (s_req_i.adr[2] ? {s_req_i.sel,4'b0} : {4'b0,s_req_i.sel}) : s_req_i.sel;
always_ff @(posedge s_clk_i)
	adri <= s_req_i.adr;
always_ff @(posedge s_clk_i)
	dat <= (BUSWID==32) ? {2{s_req_i.dat}} : s_req_i.dat;

always_ff @(posedge s_clk_i)
	cs_config <= cs_config_i;
always_comb
	cs_map = cs_fbc && adri[15:14]==3'd1;
always_comb
	cs_reg = cs_fbc && adri[15:14]==3'd0;

always_ff @(posedge s_clk_i)
if (rst_i)
	s_resp_o <= {$bits(fta_cmd_response64_t){1'b0}};
else begin
	if (cfg_resp.ack)
		s_resp_o <= cfg_resp;
	else begin
		s_resp_o.ack <= s_resp1.ack;
		s_resp_o.tid <= s_resp1.tid;
		s_resp_o.next <= 1'b0;
		s_resp_o.stall <= 1'b0;
		s_resp_o.err <= fta_bus_pkg::OKAY;
		s_resp_o.rty <= 1'b0;
		s_resp_o.pri <= 4'd7;
		s_resp_o.adr <= s_resp1.adr;
		s_resp_o.dat <= (BUSWID==32) ? (s_resp1.adr[2] ? s_dat_o[63:32] : s_dat_o[31:0]) : s_dat_o;
	end
end

vtdl #(.WID(1), .DEP(16)) urdyd1 (.clk(s_clk_i), .ce(1'b1), .a(4'd1), .d(cs_map), .q(latch_map));
vtdl #(.WID(1), .DEP(16)) urdyd2 (.clk(s_clk_i), .ce(1'b1), .a(4'd0), .d((cs_map|cs_edge|cs_config) & ~we), .q(s_resp1.ack));
vtdl #(.WID($bits(fta_tranid_t)), .DEP(16)) urdyd4 (.clk(s_clk_i), .ce(1'b1), .a(4'd1), .d(s_req_i.tid), .q(s_resp1.tid));
vtdl #(.WID(32), .DEP(16)) urdyd5 (.clk(s_clk_i), .ce(1'b1), .a(4'd1), .d(s_req_i.adr), .q(s_resp1.adr));

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
reg [4:0] pals;				// palette select
reg [15:0] hrefdelay;
reg [15:0] vrefdelay;
reg [15:0] windowLeft;
reg [15:0] windowTop;
reg [11:0] windowWidth,windowHeight;
reg [11:0] burst_interval;     // memory access period
reg [11:0] bi_ctr;
reg [15:0] bmpWidth;		// scan line increment (pixels)
reg [15:0] bmpHeight;
reg [`ABITS] baseAddrDisplay;	// base address register
reg [`ABITS] baseAddrWork;	// base address register
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
wire [11:0] tocnt;		// bus timeout counter
reg [4:0] vm_cmd_o;
reg [5:0] vm_blen_o;
reg vm_cyc_o;
reg [31:0] vm_adr_o;
reg vm_we_o;
reg [MDW/8-1:0] vm_sel_o;
fta_tranid_t vm_tid_o;
wire row_change;

// config
reg [63:0] irq_msgadr = IRQ_MSGADR;
reg [63:0] irq_msgdat = IRQ_MSGDAT;

wire [BUSWID-1:0] cfg_out;
generate begin : gConfigSpace
	if (BUSWID==32) begin
		ddbb32_config #(
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
			.cs_i(cs_config), 
			.req_i(reqd),
			.resp_o(cfg_resp),
			.cs_bar0_o(cs_fbc),
			.cs_bar1_o(),
			.cs_bar2_o()
		);
	end
	else if (BUSWID==64) begin
		ddbb64_config #(
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
			.cs_i(cs_config), 
			.req_i(reqd),
			.resp_o(cfg_resp),
			.cs_bar0_o(cs_fbc),
			.cs_bar1_o(),
			.cs_bar2_o()
		);
	end
end
endgenerate

wire [BITS_IN_ADDR_MAP-1:0] map_page;
wire [BITS_IN_ADDR_MAP-1:0] map_out;
reg [BITS_IN_ADDR_MAP-1:0] map_out_latch;

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
      .MEMORY_INIT_FILE("fb_map2.mem"),      // String
      .MEMORY_INIT_PARAM(""),        // String
      .MEMORY_OPTIMIZATION("true"),   // String
      .MEMORY_PRIMITIVE("auto"),      // String
      .MEMORY_SIZE(2048*BITS_IN_ADDR_MAP),
      .MESSAGE_CONTROL(0),            // DECIMAL
      .READ_DATA_WIDTH_A(BITS_IN_ADDR_MAP),
      .READ_DATA_WIDTH_B(BITS_IN_ADDR_MAP),
      .READ_LATENCY_A(1),             // DECIMAL
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
      .WRITE_DATA_WIDTH_A(BITS_IN_ADDR_MAP),        // DECIMAL
      .WRITE_DATA_WIDTH_B(BITS_IN_ADDR_MAP),        // DECIMAL
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
      .addrb(vm_adr_o[24:14]),         // ADDR_WIDTH_B-bit input: Address for port B write and read operations.
      .clka(s_clk_i),                  // 1-bit input: Clock signal for port A. Also clocks port B when
                                       // parameter CLOCKING_MODE is "common_clock".

      .clkb(m_bus_o.clk),                  // 1-bit input: Clock signal for port B when parameter CLOCKING_MODE is
                                       // "independent_clock". Unused when parameter CLOCKING_MODE is
                                       // "common_clock".

      .dina(dat[BITS_IN_ADDR_MAP-1:0]),  // WRITE_DATA_WIDTH_A-bit input: Data input for port A write operations.
      .dinb({BITS_IN_ADDR_MAP{1'b0}}),   // WRITE_DATA_WIDTH_B-bit input: Data input for port B write operations.
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

delay3 #(5) udly0 (.clk(m_bus_o.clk), .ce(1'b1), .i(vm_cmd_o), .o(m_bus_o.req.cmd));
delay3 #(1) udly1 (.clk(m_bus_o.clk), .ce(1'b1), .i(vm_cyc_o), .o(m_bus_o.req.cyc));
delay3 #(1) udly2 (.clk(m_bus_o.clk), .ce(1'b1), .i(vm_we_o), .o(m_bus_o.req.we));
delay3 #(MDW/8) udly3 (.clk(m_bus_o.clk), .ce(1'b1), .i(vm_sel_o), .o(m_bus_o.req.sel));
//delay3 #(32) udly4 (.clk(m_bus_o.clk), .ce(1'b1), .i(vm_adr_o), .o(m_bus_o.req.adr));
delay3 #(14) udly5 (.clk(m_bus_o.clk), .ce(1'b1), .i(vm_adr_o[13:0]), .o(m_bus_o.req.adr[13:0]));
delay1 #(18) udly8 (.clk(m_bus_o.clk), .ce(1'b1), .i(map_page), .o(m_bus_o.req.adr[31:14]));
delay3 #(13) udly6 (.clk(m_bus_o.clk), .ce(1'b1), .i(vm_tid_o), .o(m_bus_o.req.tid));
delay3 #(6) udly7 (.clk(m_bus_o.clk), .ce(1'b1), .i(vm_blen_o), .o(m_bus_o.req.blen));

wire vblank;
generate begin : gSyncGen
if (INTERNAL_SYNCGEN) begin
VGASyncGen usg1
(
	.rst(rst_i),
	.clk(vclk),
	.eol(),
	.eof(),
	.hSync(hsync_o),
	.vSync(vsync_o),
	.hCtr(),
	.vCtr(),
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
assign vblank_o = vblank;
end
else begin
assign hsync_o = hsync_i;
assign vsync_o = vsync_i;
assign blank_o = blank_i;
assign border_o = border_i;
assign vblank_o = 1'b0;
end
end
endgenerate

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

vid_counter #(16) u_hctr 
(
	.rst(rst_i),
	.clk(vclk),
	.ce(1'b1),
	.ld(pe_hsync),
	.d(16'h0),
	.q(hctr),
	.tc()
);

// Raw scanline counter
vid_counter #(12) u_vctr
(
	.rst(rst_i),
	.clk(vclk),
	.ce(pe_hsync),
	.ld(pe_vsync),
	.d(12'h0),
	.q(scanline),
	.tc()
);

// Frame counter
//
wire [5:0] fctr_o;
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
	if (hctr==16'd02 && rastcmp==scanline)
		irq <= HIGH;
	else if (rst_irq|rst_irq2)
		irq <= LOW;
end

always_comb
	baseAddrDisplay = page ? bm_base_addr2 : bm_base_addr1;
always_comb
	baseAddrWork = page ? bm_base_addr1 : bm_base_addr2;

// Color palette RAM for 8bpp modes
// 64x1024 A side, 32x2048 B side
// 3 cycle latency
fb_palram upal1	// Actually 1024x64
(
  .clka(s_clk_i),    // input wire clka
  .ena(cs_reg & adri[13]),      // input wire ena
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
	pals <= 5'h0;
	hres <= 3'd1;
	vres <= 3'd1;
`ifdef WXGA800x600	
	windowWidth <= 12'd800;
	windowHeight <= 12'd600;
	bmpWidth <= 16'd800;
	bmpHeight <= 16'd600;
`endif
`ifdef WXGA1366x768
	windowWidth <= 12'd1366;
	windowHeight <= 12'd768;
	bmpWidth <= 16'd1360;
	bmpHeight <= 16'd768;
`endif
`ifdef WXGA1920x1080
	windowWidth <= 12'd1920;
	windowHeight <= 12'd1080;
	bmpWidth <= 16'd1920;
	bmpHeight <= 16'd1080;
`endif
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
	burst_interval <= BURST_INTERVAL;
	pcmd <= 2'b00;
	rstcmd1 <= 1'b0;
	rst_irq <= 1'b0;
	rastcmp <= 12'hFFF;
	oob_color <= 32'h00003C00;
	irq_msgadr <= IRQ_MSGADR;
	irq_msgdat <= IRQ_MSGDAT;
	hTotal <= phTotal;
	vTotal <= pvTotal;
	hSyncOn <= phSyncOn; hSyncOff <= phSyncOff;
	vSyncOn <= pvSyncOn; vSyncOff <= pvSyncOff;
	hBlankOn <= phBlankOn; hBlankOff <= phBlankOff;
	vBlankOn <= pvBlankOn; vBlankOff <= pvBlankOff;
	hBorderOn <= phBorderOn; hBorderOff <= phBorderOff;
	vBorderOn <= pvBorderOn; vBorderOff <= pvBorderOff;
	max_nburst <= 6'd1;		// 2 bursts of 25 = 50 accesses for 800 pixels
	burst_len <= 6'd59;		// 2 bursts of 60 = 120 access for 1920 pixels
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
					pals <= dat[29:25];
					end
					if (sel[4]) burst_len <= dat[37:32];
					if (sel[5]) max_nburst <= dat[45:40];
					if (|sel[7:6]) burst_interval <= dat[59:48];
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
			    if (|sel[7:4]) color <= dat[63:32];
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
      default:  ;
			endcase
		end
	end
	if (cs_edge) begin
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
		          s_dat_o[29:25] <= pals;
		          s_dat_o[47:32] <= bmpWidth;
		          s_dat_o[59:48] <= burst_interval;
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
		          s_dat_o[29:25] <= pals;
		      end
		  {REG_CTRL,1'b1}:
		      begin
		          s_dat_o[15: 0] <= bmpWidth;
		          s_dat_o[27:16] <= burst_interval;
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
		s_dat_o <= {40'h0,map_out_latch};
	else if (cs_config)
		s_dat_o <= cfg_out;
	else if (irq)
		s_dat_o <= {2{irq_msgdat}};
	else
		s_dat_o <= 64'd0;
	if (latch_map)
		map_out_latch <= map_out;
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
	.i(hsync_o),
	.pe(pe_hsync),
	.ne(),
	.ee()
);

edge_det edh2
(
	.rst(rst_i),
	.clk(m_bus_o.clk),
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
	.i(vsync_o),
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

// Bytes per pixel.
reg [2:0] bytpp;
always_comb
case(color_depth2)
BPP8:	bytpp = 1;
BPP16:	bytpp = 2;
BPP24:	bytpp = 3;
BPP32:	bytpp = 4;
default:	bytpp = 2;
endcase

modCalcShifts ucalcshft 
(
	.color_depth(color_depth2),
	.shifts(shifts)
);

wire vFetch = !vblank;//pixelRow < windowHeight;
reg fifo_rrst;
reg fifo_wrst;
reg [3:0] wrstcnt;
always_comb fifo_rrst = pe_hsync;	// pixelCol==16'hFFF0;

always_ff @(posedge m_bus_o.clk)
if (m_bus_o.rst)
	wrstcnt <= 4'd0;
else begin
	if (pe_hsync2)
		wrstcnt <= 4'd0;
	else if (wrstcnt!=4'd5)
		wrstcnt <= wrstcnt + 2'd1;
end

always_comb fifo_wrst = wrstcnt!=4'd5;// && vc==4'd1;

wire[31:0] grAddr,xyAddr;
reg [11:0] fetchCol;
localparam CMS = MDW==256 ? 7 : MDW==128 ? 6 : MDW==64 ? 5 : 4;
wire [CMS:0] mb,me,ce;
reg [MDW-1:0] mem_strip;
wire [MDW-1:0] mem_strip_o;

// Compute fetch address, this is the first address on a pixel row.
// This will update when the row changes, but otherwise remain stable.
// There is a 3 cycle latency for the address calc, so the address should not
// be used before the latency occurs.
gfx_calc_address 
#(
	.SW(MDW)
)
u1
(
  .clk(m_bus_o.clk),
	.base_address_i(baseAddrDisplay),
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
gfx_calc_address
#(
	.SW(MDW)
)
u2
(
  .clk(m_bus_o.clk),
	.base_address_i(baseAddrWork),
	.color_depth_i(color_depth2),
	.bmp_width_i(bmpWidth),
	.x_coord_i(windowLeft+px),
	.y_coord_i(windowTop+py),
	.address_o(xyAddr),
	.mb_o(mb),
	.me_o(me),
	.ce_o(ce)
);

modRowChange urc1
(
	.clk(m_bus_o.clk),
	.pixelRow(pixelRow),
	.row_change(row_change)
);

wire memreq,first_memreq;
modMemReqGen umrgen1
(
	.rst(rst_i),
	.clk(m_bus_o.clk),
	.burst_len(burst_len),
	.max_nburst(max_nburst),
	.pe_hsync(pe_hsync2),
	.on(onoff | xonoff_i),
	.vFetch(vFetch),
	.ack(vm_cyc_o && vm_tid_o[3:0]==4'h0),
	.vc(vc),
	.burst_interval(burst_interval),
	.memreq(memreq),
	.first_memreq(first_memreq)
);

// The following bypasses loading the fifo when all the pixels from a scanline
// are buffered in the fifo and the pixel row doesn't change. Since the fifo
// pointers are reset at the beginning of a scanline, the fifo can be used like
// a cache.
wire blankEdge;
edge_det ed2(.rst(rst_i), .clk(m_bus_o.clk), .ce(1'b1), .i(blank_i), .pe(blankEdge), .ne(), .ee() );
reg do_loads;
reg load_fifo = 1'b0;
//always_ff @(posedge m_bus_o.clk)
	//load_fifo <= fifo_cnt < 10'd1000 && vFetch && onoff && xonoff && !m_cyc_o && do_loads;
//	load_fifo <= /*fifo_cnt < 8'd224 &&*/ vFetch && onoff && xonoff_i && (fetchCol < windowWidth) && memreq;

// The following table indicates the number of pixel that will fit into the
// video fifo. The fifo contains 256 rows that are MDW bits wide.
wire [15:0] hCmp;
modPixelsInFifo 
#(
	.MDW(256),
	.FIFO_DEPTH(256)
)
upif1
(
	.color_depth(color_depth2),
	.pif(hCmp)
);
/*
always @(posedge m_bus_o.clk)
	// if windowWidth > hCmp we always load because the fifo isn't large enough to act as a cache.
	if (!(windowWidth < hCmp))
		do_loads <= 1'b1;
	// otherwise load the fifo only when the row changes to conserve memory bandwidth
	else if (vc==4'd1)//pixelRow != opixelRow)
		do_loads <= 1'b1;
	else if (blankEdge)
		do_loads <= 1'b0;
*/
always_comb m_bus_o.req.seg = 13'd0;
always_comb m_bus_o.req.pv = 1'b0;
always_comb m_bus_o.req.bte = fta_bus_pkg::LINEAR;
always_comb m_bus_o.req.cti = fta_bus_pkg::CLASSIC;
always_comb m_bus_o.req.om = 2'd0;
always_comb m_bus_o.req.sz = 4'd0;
always_comb m_bus_o.req.ctag = 1'b0;
always_comb m_bus_o.req.data2 = 256'd0;
always_comb m_bus_o.req.csr = 1'b0;
always_comb m_bus_o.req.key[0] = 20'd0;
always_comb m_bus_o.req.key[1] = 20'd0;
always_comb m_bus_o.req.key[2] = 20'd0;
always_comb m_bus_o.req.key[3] = 20'd0;
always_comb m_bus_o.req.pl = 8'h00;
always_comb m_bus_o.req.pri = 4'd7;
always_comb m_bus_o.req.cache = 4'd0;

wire [31:0] adr;
fb_state_t state;
reg [MDW-1:0] icolor1;

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

modAddrGen uaddrgen1
(
	.clk(m_bus_o.clk),
	.state(state),
	.pe_hsync(pe_hsync2),
	.grAddr(grAddr),
	.ack(m_bus_o.resp.ack && m_bus_o.resp.tid.tranid==4'h0),
	.tocnt(tocnt),
	.adr(adr)
);

always_ff @(posedge m_bus_o.clk)
	if (fifo_wrst)
		fetchCol <= 12'd0;
  else begin
    if ((state==WAITLOAD && ((m_bus_o.resp.ack && m_bus_o.resp.tid.tranid==4'h0)|tocnt[10])) || state==LOAD_OOB)
      fetchCol <= fetchCol + shifts;
  end

// Check for legal (positive) coordinates
// Illegal coordinates result in a red display
wire [15:0] xcol = fetchCol;
reg legal_x, legal_y;
always_comb legal_x = ~xcol[15] && xcol < windowLeft + windowWidth && xcol >= windowLeft;//bmpWidth;
always_comb legal_y = ~pixelRow[15] && pixelRow < windowTop + windowHeight && pixelRow >= windowTop;//bmpHeight;

reg modd;
always_comb
	case(MDW)
	32:	modd <= m_bus_o.req.adr[5:2]==4'hF;
	64:	modd <= m_bus_o.req.adr[5:3]==3'h7;
	128:	modd <= m_bus_o.req.adr[5:4]==2'h3;
	256:	modd <= m_bus_o.req.adr[5]==1'h1;
	default:	modd <= m_bus_o.req.adr[5]==1'h1;
	endcase

// Bus timeout counter
modTocnt utocnt1
(
	.rst(rst_i),
	.clk(m_bus_o.clk),
	.cyc(m_bus_o.req.cyc),
	.ack(m_bus_o.resp.ack),
	.tocnt(tocnt)
);

reg [31:0] next_adr;
reg [31:0] pcmd_adr;

always_ff @(posedge m_bus_o.clk)
if (m_bus_o.rst) begin
	vm_blen_o <= 6'd0;
	vm_cmd_o <= fta_bus_pkg::CMD_LOADZ;
	vm_cyc_o <= LOW;
	vm_we_o <= LOW;
	vm_sel_o <= {MDW/8{1'b0}};
	vm_adr_o <= 32'd0;
	vm_tid_o <= {CORENO,CHANNEL,4'h0};
  rstcmd <= 1'b0;
  state <= FB_IDLE;
  rst_irq2 <= 1'b0;
  next_adr <= 32'd0;
  pcmd_adr <= 32'd0;
	m_fst_o <= LOW;
end
else begin
  wb_nack();
  rst_irq2 <= 1'b0;
	if (fifo_wrst) begin
		m_fst_o <= HIGH;
	end

	// For burst only a single request is submitted, but many responses may occur
	if (memreq && !m_rst_busy_i) begin
		m_fst_o <= LOW;
		vm_blen_o <= burst_len;
		vm_tid_o <= {CORENO,CHANNEL,4'h0};
		vm_cmd_o <= fta_bus_pkg::CMD_LOADZ;
    vm_cyc_o <= HIGH;
    vm_we_o <= LOW;//m_fst_o;
    vm_sel_o <= {MDW/8{1'b1}};
    if (m_fst_o) begin
	    vm_adr_o <= adr;
    	next_adr <= adr;// + bmpWidth * bytpp;//MDW/8;
    end
    else begin
	    vm_adr_o <= next_adr + ({10'd0,burst_len} + 2'd1) * (MDW/8);
	    next_adr <= next_adr + ({10'd0,burst_len} + 2'd1) * (MDW/8);
	  end
	end

	case(state)
  WAITRST:
    if (pcmd==2'b00) begin
      rstcmd <= 1'b0;
      state <= FB_IDLE;
    end
    else
      rstcmd <= 1'b1;

  // Wait for a plot pixel or get pixel command, then process.
  // Must also wait the latency of the address calculation before attempting
  // to fetch/store data.
  FB_IDLE:
/*
  	if (load_fifo && !(legal_x && legal_y))
 			state <= LOAD_OOB;
*/    
    if (pcmd!=2'b00 && !m_rst_busy_i)
      state <= PCMD1;
  PCMD1:
  	state <= PCMD2;
  PCMD2:
  	state <= PCMD3;
  PCMD3:
  	// Make sure a strip request will not be present before using the bus.
		if (!(memreq && !m_rst_busy_i)) begin
			if (pcmd_adr != xyAddr) begin
				pcmd_adr <= xyAddr;
	    	vm_blen_o <= 6'd0;
				vm_tid_o <= {CORENO,CHANNEL,2'b0,pcmd[1:0]};
				vm_cmd_o <= fta_bus_pkg::CMD_LOADZ;
	      vm_cyc_o <= HIGH;
	      vm_adr_o <= xyAddr;
	      vm_we_o <= LOW;
	      vm_sel_o <= {MDW/8{1'b1}};
	      state <= WAITLOAD;
    	end
    	else begin
    		case(pcmd[1:0])
    		2'b01:	
    			begin
	      		icolor1 <= {224'b0,color} << mb;
	      		rstcmd <= 1'b1;
        		state <= ICOLOR3;
        	end
        2'b10:
        	begin
			      icolor1 <= {224'b0,color} << mb;
	  		    rstcmd <= 1'b1;
        		state <= ICOLOR2;
        	end
        default:	state <= FB_IDLE;
    		endcase
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
      if (pcmd==2'b00)
        rstcmd <= 1'b0;
      state <= pcmd != 2'b00 ? WAITRST : FB_IDLE;
    end
  // Registered inline color2mem
  ICOLOR2:
    begin
      for (n = 0; n < MDW; n = n + 1)
        m_bus_o.req.data1[n] <= (n >= mb && n <= me)
        	? ((n <= ce) ?	rastop(raster_op, mem_strip[n], icolor1[n]) : icolor1[n])
        	: mem_strip[n];
      state <= STORESTRIP;
    end
  STORESTRIP:
    if (!(memreq && !m_rst_busy_i)) begin
    	mem_strip <= m_bus_o.req.data1;		// cache the new value
    	vm_blen_o <= 6'd0;
			vm_tid_o <= {CORENO,CHANNEL,4'h3};
			vm_cmd_o <= fta_bus_pkg::CMD_STORE;
      vm_cyc_o <= HIGH;
      vm_we_o <= HIGH;
      vm_sel_o <= {MDW/8{1'b1}};
      vm_adr_o <= xyAddr;
      state <= pcmd != 2'b00 ? WAITRST : FB_IDLE;
    end
  WAITLOAD:
  	;
  LOAD_OOB:
  	state <= FB_IDLE;
  default:	state <= FB_IDLE;
  endcase

	// Process responses from memory
  if (m_bus_o.resp.ack) begin
  	case(m_bus_o.resp.tid.tranid)
  	4'd1:	// Get pixel
  		begin
	      mem_strip <= m_bus_o.resp.dat;
	      icolor1 <= {224'b0,color} << mb;
	      rstcmd <= 1'b1;
        state <= ICOLOR3;
  		end
  	4'd2:	// Plot pixesl (RMW cycle)
  		begin
	      mem_strip <= m_bus_o.resp.dat;
	      icolor1 <= {224'b0,color} << mb;
	      rstcmd <= 1'b1;
        state <= ICOLOR2;
  		end
  	default:	;
  	endcase
  end
end

task wb_nack;
begin
	vm_cmd_o <= fta_bus_pkg::CMD_LOADZ;
	vm_cyc_o <= LOW;
	vm_we_o <= LOW;
	vm_sel_o <= {MDW/8{1'b0}};
end
endtask

reg [31:0] rgbo2;
wire [31:0] rgbo3, rgbo4;

reg rd_fifo,rd_fifo1,rd_fifo2;
/*
reg de;
always_ff @(posedge vclk)
	if (rd_fifo1)
		de <= ~blank_i;
*/

// Before the hrefdelay expires, pixelCol will be negative, which is greater
// than windowWidth as the value is unsigned. That means that fifo reading is
// active only during the display area 0 to windowWidth.
reg shift_en;
always_comb shift_en = hc==hres;
modShiftCntr ushftcnt1
(
	.clk(vclk),
	.pe_hsync(pe_hsync),
	.en(shift_en),
	.pixel_col(pixelCol),
	.shifts(shifts),
	.shift_cnt(shift_cnt)
);

reg next_strip;
always_comb next_strip = shift_cnt==shifts;

always_comb rd_fifo = next_strip & shift_en & ~pixelCol[15];

modMuxRgbo3 #(.MDW(MDW)) umuxrgbo31
(
	.clk(vclk),
	.en(shift_en),
	.rd_fifo(rd_fifo),
	.rgbo1e(rgbo1e),
	.color_depth(color_depth2),
	.rgbo(rgbo3)
);

modMuxRgbo4 umuxrgbo41
(
	.clk(vclk),
	.color_depth(color_depth2),
	.rgbo3(rgbo3),
	.rgbo4(rgbo4)
);

modMuxRgbo umuxrgbo1
(
	.clk(vclk),
	.onoff(onoff),
	.xonoff(xonoff_i),
	.blank(blank_i),
	.color_depth(color_depth2),
	.greyscale(greyscale),
	.pal_o(pal_o),
	.trans_color(trans_color),
	.rgbo4(rgbo4),
	.rgb_i(rgb_i),
	.rgb_o(rgb_o)
);

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

wire [MDW-1:0] oob_dat;
modOobColor #(.MDW(MDW)) uoobdat1
(
	.color_depth(color_depth2),
	.oob_color(oob_color),
	.oob_dat(oob_dat)
);

// Could maybe set pixel color here on timeout, otherwise likely random data
// will be used for the color.


rescan_fifo #(.WIDTH(MDW), .DEPTH(256)) uf1
(
	.wrst(fifo_wrst),
	.wclk(m_bus_o.clk),
//	.wr((((m_bus_o.resp.ack|tocnt[10]) && state==WAITLOAD) || state==LOAD_OOB) && lef),
//	.di((state==LOAD_OOB) ? oob_dat : m_bus_o.resp.dat),
	.wr(m_bus_o.resp.ack && m_bus_o.resp.tid.tranid==4'h0),
	.din(m_bus_o.resp.dat),
	.rrst(fifo_wrst),
	.rclk(vclk),
	.rd(rd_fifo),
	.dout(rgbo1e),
	.cnt()
);

/*
wire wr_rst_busy, rd_rst_busy;
reg rd_en;
always_comb
	rd_en = next_strip && shift_en && !rd_rst_busy;
reg wr_en;
always_comb	
	wr_en = (m_bus_o.resp.ack && m_bus_o.resp.tid.tranid==4'h0) && !rst_i && !fifo_wrst && !wr_rst_busy;

   // xpm_fifo_async: Asynchronous FIFO
   // Xilinx Parameterized Macro, version 2024.2

   xpm_fifo_async #(
      .CASCADE_HEIGHT(0),            // DECIMAL
      .CDC_SYNC_STAGES(2),           // DECIMAL
      .DOUT_RESET_VALUE("0"),        // String
      .ECC_MODE("no_ecc"),           // String
      .EN_SIM_ASSERT_ERR("warning"), // String
      .FIFO_MEMORY_TYPE("auto"),     // String
      .FIFO_READ_LATENCY(1),         // DECIMAL
      .FIFO_WRITE_DEPTH(256),       // DECIMAL
      .FULL_RESET_VALUE(0),          // DECIMAL
      .PROG_EMPTY_THRESH(10),        // DECIMAL
      .PROG_FULL_THRESH(250),         // DECIMAL
      .RD_DATA_COUNT_WIDTH(8),       // DECIMAL
      .READ_DATA_WIDTH(MDW),          // DECIMAL
      .READ_MODE("std"),             // String
      .RELATED_CLOCKS(0),            // DECIMAL
      .SIM_ASSERT_CHK(0),            // DECIMAL; 0=disable simulation messages, 1=enable simulation messages
      .USE_ADV_FEATURES("0000"),     // String
      .WAKEUP_TIME(0),               // DECIMAL
      .WRITE_DATA_WIDTH(MDW),         // DECIMAL
      .WR_DATA_COUNT_WIDTH(8)        // DECIMAL
   )
   xpm_fifo_async_inst (
      .almost_empty(),   						// 1-bit output: Almost Empty : When asserted, this signal indicates that
                                     // only one more read can be performed before the FIFO goes to empty.

      .almost_full(),     					// 1-bit output: Almost Full: When asserted, this signal indicates that
                                     // only one more write can be performed before the FIFO is full.

      .data_valid(),       					// 1-bit output: Read Data Valid: When asserted, this signal indicates
                                     // that valid data is available on the output bus (dout).

      .dbiterr(),				             // 1-bit output: Double Bit Error: Indicates that the ECC decoder detected
                                     // a double-bit error and data in the FIFO core is corrupted.

      .dout(rgbo1e),                 // READ_DATA_WIDTH-bit output: Read Data: The output data bus is driven
                                     // when reading the FIFO.

      .empty(),			                 // 1-bit output: Empty Flag: When asserted, this signal indicates that the
                                     // FIFO is empty. Read requests are ignored when the FIFO is empty,
                                     // initiating a read while empty is not destructive to the FIFO.

      .full(),  	                   // 1-bit output: Full Flag: When asserted, this signal indicates that the
                                     // FIFO is full. Write requests are ignored when the FIFO is full,
                                     // initiating a write when the FIFO is full is not destructive to the
                                     // contents of the FIFO.

      .overflow(),           				// 1-bit output: Overflow: This signal indicates that a write request
                                     // (wren) during the prior clock cycle was rejected, because the FIFO is
                                     // full. Overflowing the FIFO is not destructive to the contents of the
                                     // FIFO.

      .prog_empty(),					       // 1-bit output: Programmable Empty: This signal is asserted when the
                                     // number of words in the FIFO is less than or equal to the programmable
                                     // empty threshold value. It is de-asserted when the number of words in
                                     // the FIFO exceeds the programmable empty threshold value.

      .prog_full(),					         // 1-bit output: Programmable Full: This signal is asserted when the
                                     // number of words in the FIFO is greater than or equal to the
                                     // programmable full threshold value. It is de-asserted when the number of
                                     // words in the FIFO is less than the programmable full threshold value.

      .rd_data_count(),							 // RD_DATA_COUNT_WIDTH-bit output: Read Data Count: This bus indicates the
                                     // number of words read from the FIFO.

      .rd_rst_busy(rd_rst_busy),     // 1-bit output: Read Reset Busy: Active-High indicator that the FIFO read
                                     // domain is currently in a reset state.

      .sbiterr(),					           // 1-bit output: Single Bit Error: Indicates that the ECC decoder detected
                                     // and fixed a single-bit error.

      .underflow(),					         // 1-bit output: Underflow: Indicates that the read request (rd_en) during
                                     // the previous clock cycle was rejected because the FIFO is empty. Under
                                     // flowing the FIFO is not destructive to the FIFO.

      .wr_ack(),			               // 1-bit output: Write Acknowledge: This signal indicates that a write
                                     // request (wr_en) during the prior clock cycle is succeeded.

      .wr_data_count(), 							// WR_DATA_COUNT_WIDTH-bit output: Write Data Count: This bus indicates
                                     // the number of words written into the FIFO.

      .wr_rst_busy(wr_rst_busy),     // 1-bit output: Write Reset Busy: Active-High indicator that the FIFO
                                     // write domain is currently in a reset state.

      .din(m_bus_o.resp.dat), 			 // WRITE_DATA_WIDTH-bit input: Write Data: The input data bus used when
                                     // writing the FIFO.

      .injectdbiterr(1'b0), // 1-bit input: Double Bit Error Injection: Injects a double bit error if
                                     // the ECC feature is used on block RAMs or UltraRAM macros.

      .injectsbiterr(1'b0), // 1-bit input: Single Bit Error Injection: Injects a single bit error if
                                     // the ECC feature is used on block RAMs or UltraRAM macros.

      .rd_clk(vclk),                 // 1-bit input: Read clock: Used for read operation. rd_clk must be a free
                                     // running clock.

      .rd_en(rd_en),                 // 1-bit input: Read Enable: If the FIFO is not empty, asserting this
                                     // signal causes data (on dout) to be read from the FIFO. Must be held
                                     // active-low when rd_rst_busy is active high.

      .rst(rst_i|fifo_wrst),         // 1-bit input: Reset: Must be synchronous to wr_clk. The clock(s) can be
                                     // unstable at the time of applying reset, but reset must be released only
                                     // after the clock(s) is/are stable.

      .sleep(!vFetch),               // 1-bit input: Dynamic power saving: If sleep is High, the memory/fifo
                                     // block is in power saving mode.

      .wr_clk(m_bus_o.clk),               // 1-bit input: Write clock: Used for write operation. wr_clk must be a
                                     // free running clock.

      .wr_en(wr_en)                  // 1-bit input: Write Enable: If the FIFO is not full, asserting this
                                     // signal causes data (on din) to be written to the FIFO. Must be held
                                     // active-low when rst or wr_rst_busy is active high.

   );

   // End of xpm_fifo_async_inst instantiation
				
*/				
/*
rescan_fifo #(.WIDTH(MDW), .DEPTH(256)) uf2
(
	.wrst(fifo_wrst),
	.wclk(m_bus_o.clk),
	.wr(((m_bus_o.resp.ack && m_bus_o.resp.tid.tranid==4'h0)|tocnt[10]) && lof),
	.din(m_bus_o.resp.dat),
	.rrst(fifo_rrst),
	.rclk(vclk),
	.rd(next_strip & lef),
	.dout(rgbo1o),
	.cnt()
);
*/
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
		if (q[15]) begin
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

// Compute the number of shifts required to empty out pixels in the memory
// strip.

module modCalcShifts(color_depth, shifts);
input color_depth_t color_depth;
output reg [5:0] shifts;

parameter MDW=256;

always_comb
case(MDW)
256:
	case(color_depth)
	BPP8: 	shifts = 6'd32;
	BPP16:	shifts = 6'd16;
	BPP24:	shifts = 6'd10;
	BPP32:	shifts = 6'd8;
	default:  shifts = 6'd16;
	endcase
128:
	case(color_depth)
	BPP8: 	shifts = 6'd16;
	BPP16:	shifts = 6'd8;
	BPP24:	shifts = 6'd5;
	BPP32:	shifts = 6'd4;
	default:  shifts = 6'd8;
	endcase
64:
	case(color_depth)
	BPP8: 	shifts = 6'd8;
	BPP16:	shifts = 6'd4;
	BPP24:	shifts = 6'd2;
	BPP32:	shifts = 6'd2;
	default:  shifts = 6'd4;
	endcase
32:
	case(color_depth)
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

endmodule


// Figure out when to request a strip of pixels.
// burst_interval may be set to zero for a continuous fetch.
// Fetching always starts at the leading edge of horizontal sync.
// The burst interval should be often enough that the line cache (fifo) is
// filled before the data is needed.

module modMemReqGen(rst, clk, max_nburst, burst_len, on, pe_hsync, vFetch, ack, vc, burst_interval,
	memreq, first_memreq);
input rst;
input clk;
input [5:0] max_nburst;				// maximum number of bursts per scan-line
input [5:0] burst_len;
input on;
input pe_hsync;
input vFetch;
input ack;										// 1 if memory access has started
input [2:0] vc;
input [11:0] burst_interval;	// how often to request memory
output reg memreq;
output reg first_memreq;			// first memreq on line

reg first;
reg memreq1;
reg [15:0] bi_ctr;
wire [5:0] nburst;

modBurstCntr ubc1
(
	.rst(rst|pe_hsync),
	.clk(clk),
	.memreq(memreq),
	.nburst(nburst)
);

always_ff @(posedge clk)
if (rst|pe_hsync)
  bi_ctr <= burst_interval;
else begin
  if (bi_ctr==burst_interval)
    bi_ctr <= 12'd0;
  else
    bi_ctr <= bi_ctr + 12'd1;
end

always_ff @(posedge clk)
if (rst|pe_hsync)
	memreq1 <= FALSE;
else begin
	// vc ties the request to the first row of pixels
	if (bi_ctr==12'd24 && vc==3'd1 && vFetch && on)
		memreq1 <= TRUE;
	else if (ack)
		memreq1 <= FALSE;
end

assign memreq = memreq1;// && nburst <= max_nburst;

always_ff @(posedge clk)
if (rst|pe_hsync)
	first <= TRUE;
else begin
	if (memreq)
		first <= FALSE;
end

always_comb first_memreq = memreq & first;

endmodule


// The following table indicates the number of pixel that will fit into the
// video fifo. The fifo contains 256 rows that are MDW bits wide.

module modPixelsInFifo(color_depth, pif);
parameter MDW = 256;
parameter FIFO_DEPTH = 256;
input color_depth_t color_depth;
output reg [15:0] pif;

always_comb
case(color_depth)
BPP8:	pif = FIFO_DEPTH * MDW/8;
BPP16:	pif = FIFO_DEPTH * MDW/16;
BPP24:	pif = FIFO_DEPTH * MDW/24;
BPP32:	pif = FIFO_DEPTH * MDW/32;
default:	pif = FIFO_DEPTH * MDW/16;
endcase

endmodule

// To get the first address of a row, a latency of 3 clock cycles must pass
// after the row changes before the address is valid.

module modRowChange(clk, pixelRow, row_change);
input clk;
input [15:0] pixelRow;
output reg row_change;

reg [15:0] opixelRow;
reg [2:0] tmr;
always_ff @(posedge clk)
	opixelRow <= pixelRow;
always_ff @(posedge clk)
	if (pixelRow != opixelRow)
		tmr <= 3'b000;
	else if (tmr != 3'd7)
		tmr <= tmr + 3'd1;
always_comb
	row_change = tmr==3'd3;

endmodule

// hsync causes the video row to be incremented, it then takes about three
// clocks for the start address of the row to be calculated. So, there is a
// delay to account for after an hsync. The address must also be available
// for the memory request generation logic, which allows a delay of 12 clock
// cycles.

module modAddrGen(clk, state, pe_hsync, grAddr, ack, tocnt, adr);
parameter MDW=256;
input clk;
input fb_state_t state;
input pe_hsync;
input [31:0] grAddr;
input ack;
input [11:0] tocnt;
output reg [31:0] adr;

reg [3:0] cnt;
always_ff @(posedge clk)
	if (pe_hsync)
		cnt <= 4'h0;
	else if (cnt != 4'd15)
		cnt <= cnt + 4'd1;

always_ff @(posedge clk)
if (cnt == 4'd5)
	adr <= grAddr;
else begin
  if ((ack|tocnt[10]) || state==gfx_pkg::LOAD_OOB)
  	adr <= adr + MDW/8;
end

endmodule

module modTocnt(rst, clk, cyc, ack, tocnt);
input rst;
input clk;
input cyc;
input ack;
output reg [11:0] tocnt;

reg tocnt_act;

always_ff @(posedge clk)
if (rst)
	tocnt_act <= FALSE;
else begin
	if (cyc)
		tocnt_act <= TRUE;
	else if (ack)
		tocnt_act <= FALSE;
end

always_ff @(posedge clk)
if (rst)
	tocnt <= 12'd0;
else begin
	if (tocnt_act)
		tocnt <= tocnt + 2'd1;
	else
		tocnt <= 12'd0;
end

endmodule

module modShiftCntr(clk, pe_hsync, en, pixel_col, shifts, shift_cnt);
input clk;
input pe_hsync;
input en;
input [15:0] pixel_col;
input [5:0] shifts;
output reg [5:0] shift_cnt;

always_ff @(posedge clk)
if (pe_hsync)
	shift_cnt <= 6'd1;
else begin
	if (en) begin
		if (pixel_col==16'hFFFF) begin
			shift_cnt <= shifts;
		end
		else if (!pixel_col[15]) begin
			shift_cnt <= shift_cnt + 6'd1;
			if (shift_cnt==shifts)
				shift_cnt <= 6'd1;
		end
		else
			shift_cnt <= 6'd1;
	end
end

endmodule

// This mux extracts pixels from the memory strip.

module modMuxRgbo3(clk, en, rd_fifo, rgbo1e, color_depth, rgbo);
parameter MDW=256;
input clk;
input en;
input rd_fifo;
input [MDW-1:0] rgbo1e;
input color_depth_t color_depth;
output reg [31:0] rgbo;

reg [MDW-1:0] rgbo3;

always_ff @(posedge clk)
	if (en) begin
		if (rd_fifo)
			rgbo3 <= rgbo1e;
		else begin
			case(color_depth)
			BPP8:	rgbo3 <= {8'h0,rgbo3[MDW-1:8]};
			BPP16:	rgbo3 <= {16'h0,rgbo3[MDW-1:16]};
			BPP24:	rgbo3 <= {24'h0,rgbo3[MDW-1:24]};
			BPP32:	rgbo3 <= {32'h0,rgbo3[MDW-1:32]};
			default: rgbo3 <= {16'h0,rgbo3[MDW-1:16]};
			endcase
		end
	end

always_comb rgbo = rgbo3[31:0];

endmodule

// This mux takes the color bits and converts them into a 32-bit value.

module modMuxRgbo4(clk, color_depth, rgbo3, rgbo4);
input clk;
input color_depth_t color_depth;
input [31:0] rgbo3;
output reg [31:0] rgbo4;

always_ff @(posedge clk)
case(color_depth)
BPP8:	rgbo4 <= {24'h0,rgbo3[7:0]};		// feeds into palette
BPP16:	rgbo4 <= {rgbo3[14:10],5'b0,rgbo3[9:5],5'b0,rgbo3[4:0],5'b0};
BPP24:	rgbo4 <= {rgbo3[23:16],2'b0,rgbo3[15:8],2'b0,rgbo3[7:0],2'b0};
BPP32:	rgbo4 <= {rgbo3[31:30],rgbo3[29:20],rgbo3[19:10],rgbo3[9:0]};
default:	rgbo4 <= {rgbo3[14:10],5'b0,rgbo3[9:5],5'b0,rgbo3[4:0],5'b0};
endcase

endmodule

module modMuxRgbo(clk, onoff, xonoff, blank, color_depth, greyscale, pal_o, trans_color, rgbo4, rgb_i, rgb_o);
input clk;
input onoff;
input xonoff;
input blank;
input color_depth_t color_depth;
input greyscale;
input [31:0] pal_o;
input [31:0] trans_color;
input [31:0] rgbo4;
input [31:0] rgb_i;
output reg [31:0] rgb_o;

reg [31:0] zrgb;

always_ff @(posedge clk)
	if (onoff && xonoff && !blank) begin
		if (color_depth==BPP8) begin
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

always_ff @(posedge clk)
	if (zrgb==trans_color)
		rgb_o <= rgb_i;
	else
		rgb_o <= zrgb;

endmodule

module modOobColor(color_depth, oob_color, oob_dat);
parameter MDW=256;
input color_depth_t color_depth;
input [31:0] oob_color;
output reg [MDW-1:0] oob_dat;

always_comb
case(color_depth)
BPP8:	oob_dat <= {MDW/8{oob_color[7:0]}};
BPP16:	oob_dat <= {MDW/16{oob_color[15:0]}};
BPP24:	oob_dat <= {MDW/24{oob_color[23:0]}};
BPP32:	oob_dat <= {MDW/32{oob_color[31:0]}};
default:	oob_dat <= {MDW/16{oob_color[15:0]}};
endcase

endmodule

// Burst counter
module modBurstCntr(rst, clk, memreq, nburst);
input rst;
input clk;
input memreq;
output reg [5:0] nburst;

always_ff @(posedge clk)
if (rst)
	nburst <= 6'd0;
else begin
 	if (memreq)
		nburst <= nburst + 2'd1;
end

endmodule
