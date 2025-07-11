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
//	Address bit 15 selects little-endian (0) or big-endian(1) access
//
// 800x600 40.000 MHz clock
// 1366x768 85.86 MHz clock
// ============================================================================

//`define USE_CLOCK_GATE	1'b1
//`define VGA640x480	1'b1
//`define SVGA800x600		1'b1
`define SVGA800x600_72	1'b1
//`define XGA1024x768		1'b1
//`define WXGA1920x1080		1'b1
//`define WXGA1280x720		1'b1
//`define WXGA1368x768	1'b1

import const_pkg::*;
`define ABITS	31:0

import fta_bus_pkg::*;

//`define BUSWID64	1'b1
`define BUSWID32	1'b1

typedef enum logic [3:0] {
	FB_IDLE = 4'd0,
	FB_NEXT_BURST = 4'd1,
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
	LOAD_OOB = 4'd12,
	PCMD1 = 4'd13,
	PCMD2 = 4'd14,
	PCMD3 = 4'd15
} fb_state_t;

module rfFrameBuffer_fta64 (
	rst_i,
	xonoff_i,
	irq_o,
	cs_config_i,
	s_bus_i,
	m_fst_o, 
	m_bus_o,
	m_rst_busy_i,
	fifo_rst_o,
	video_i,
	video_o,
	xal_o,
	vblank_o
);
parameter BUSWID = 64;
parameter INTERNAL_SYNCGEN = 1'b1;
parameter CORENO = 6'd62;
parameter CHANNEL = 3'd1;
parameter pReverseByteOrder = 1'b0;

parameter pDevName = "FRAMEBUF        ";
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
parameter BURST_INTERVAL = 12'd3000;
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
parameter REG_COLOR_COMPONENT = 11'd19;
parameter REG_PRGB = 11'd20;
parameter REG_COLOR = 11'd21;
parameter REG_PPS = 11'd22;

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

`ifdef SVGA800x600
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

// Sync Generator defaults: 800x600 72Hz
// Driven by a 50MHz clock

`ifdef SVGA800x600_72
parameter phSyncOn  = 56;		//  56 front porch
parameter phSyncOff = 176;		//  120 sync
parameter phBlankOff = 240;	//256	//   64 back porch
//parameter phBorderOff = 336;	//   80 border
parameter phBorderOff = 240;	//   80 border
//parameter phBorderOn = 976;		//  640 display
parameter phBorderOn = 1040;		//  800 display
parameter phBlankOn = 1040;		//   4 border
parameter phTotal = 1040;		// 1056 total clocks
parameter pvSyncOn  = 37;		//    37 front porch
parameter pvSyncOff = 43;		//    6 vertical sync
parameter pvBlankOff = 66;		//   23 back porch (28)
parameter pvBorderOff = 66;		//   44 border	0
//parameter pvBorderOff = 72;		//   44 border	0
parameter pvBorderOn = 666;		//  600 display
parameter pvBlankOn = 666;  	//   44 border	0
parameter pvTotal = 666;		//  666 total scan lines
`endif

// 50 MHz clock
`ifdef FT1000x600
parameter phSyncOn  = 50;		//   40 front porch
parameter phSyncOff = 210;		//  160 sync
parameter phBlankOff = 315;		//   105 back porch
parameter phBorderOff = 318;	//   3 border
parameter phBorderOn = 1318;		//  1000 display
parameter phBlankOn = 1320;		//   2 border
parameter phTotal = 1320;		// 1056 total clocks
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

// 65 MHZ clock
// +,- h,v sync
`ifdef XGA1024x768
parameter phSyncOn  = 24;		//   24 front porch
parameter phSyncOff = 160;		//  136 sync
parameter phBlankOff = 320;	//160	back porch
//parameter phBorderOff = 336;	//   80 border
parameter phBorderOff = 320;	//   80 border
//parameter phBorderOn = 976;		//  640 display
parameter phBorderOn = 1344;		//  800 display
parameter phBlankOn = 1344;		//   4 border
parameter phTotal = 1344;		// 1056 total clocks
parameter pvSyncOn  = 3;		//    3 front porch
parameter pvSyncOff = 9;		//    6 vertical sync
parameter pvBlankOff = 38;		//   29 back porch (28)
parameter pvBorderOff = 38;		//   0 border	0
//parameter pvBorderOff = 72;		//   0 border	0
parameter pvBorderOn = 806;		//  768 display
//parameter pvBorderOn = 584;		//  512 display
parameter pvBlankOn = 806;  	//   44 border	0
parameter pvTotal = 806;		//  768 total scan lines
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

// -hsync, + vsync
`ifdef WXGA1366x768
// Driven by an 85.86MHz clock
parameter phSyncOn  = 72;		//   72 front porch
parameter phSyncOff = 216;		//  144 sync
parameter phBlankOff = 432;		//  216 back porch
parameter phBorderOff = 432;	//    0 border
parameter phBorderOn = 1800;	// 1368 display
parameter phBlankOn = 1800;		//    0 border
parameter phTotal = 1800;		// 1800 total clocks
// 47.7 = 60 * 795 kHz
parameter pvSyncOn  = 1;		//    1 front porch
parameter pvSyncOff = 4;		//    3 vertical sync
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
input xonoff_i;
output reg xal_o;		// external access line (sprite access)

// Peripheral IO slave port
fta_bus_interface.slave s_bus_i;

// Video Memory Master Port
// Used to read memory via burst access
output reg m_fst_o;		// first access on scanline
fta_bus_interface.master m_bus_o;
input m_rst_busy_i;
output reg fifo_rst_o;

// Video
video_bus.in video_i;
video_bus.out video_o;
output vblank_o;

genvar g;
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
	s_req_i = {$bits(fta_cmd_request32_t){1'b0}};
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
//	s_bus_i.resp.adr = s_resp_o.adr;
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
reg [9:0] shifts;
wire [9:0] shift_cnt;
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
reg [63:0] s_dat_o;
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
reg [7:0] burst_len;

always_ff @(posedge s_clk_i)
	reqd <= s_req_i;
always_ff @(posedge s_clk_i)
	we <= s_req_i.we;
always_ff @(posedge s_clk_i)
	sel <= (BUSWID==32)  ? (s_req_i.adr[2] ? {s_req_i.sel,4'b0} : {4'b0,s_req_i.sel}) : s_req_i.sel;
always_ff @(posedge s_clk_i)
	adri <= s_req_i.adr;
always_ff @(posedge s_clk_i)
	if (pReverseByteOrder)
		dat <= (BUSWID==32) ? {2{s_req_i.dat[7:0],s_req_i.dat[15:8],s_req_i.dat[23:16],s_req_i.dat[31:24]}} :
			{s_req_i.dat[ 7: 0],s_req_i.dat[15: 8],s_req_i.dat[23:16],s_req_i.dat[31:24],
			 s_req_i.dat[39:32],s_req_i.dat[47:40],s_req_i.dat[55:48],s_req_i.dat[63:56]};
	else
		dat <= (BUSWID==32) ? {2{s_req_i.dat}} : s_req_i.dat;

always_ff @(posedge s_clk_i)
	cs_config <= cs_config_i;
always_comb
	cs_map = cs_fbc && adri[14]==1'd1;
always_comb
	cs_reg = cs_fbc && adri[14]==1'd0;

wire [31:0] s_resp1_adr;
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
//		s_resp_o.adr <= s_resp1.adr;
		if (pReverseByteOrder)
			s_resp_o.dat <= (BUSWID==32) ? (s_resp1_adr[2] ? 
				 {s_dat_o[39:32],s_dat_o[47:40],s_dat_o[55:48],s_dat_o[63:56]} :
				 {s_dat_o[ 7: 0],s_dat_o[15: 8],s_dat_o[23:16],s_dat_o[31:24]}) :
				 {s_dat_o[ 7: 0],s_dat_o[15: 8],s_dat_o[23:16],s_dat_o[31:24],
				  s_dat_o[39:32],s_dat_o[47:40],s_dat_o[55:48],s_dat_o[63:56]};
		else
			s_resp_o.dat <= (BUSWID==32) ? (s_resp1_adr[2] ? s_dat_o[63:32] : s_dat_o[31:0]) : s_dat_o;
	end
end

vtdl #(.WID(1), .DEP(16)) urdyd1 (.clk(s_clk_i), .ce(1'b1), .a(4'd1), .d(cs_map), .q(latch_map));
vtdl #(.WID(1), .DEP(16)) urdyd2 (.clk(s_clk_i), .ce(1'b1), .a(4'd0), .d((cs_map|cs_edge|cs_config) & ~we), .q(s_resp1.ack));
vtdl #(.WID($bits(fta_tranid_t)), .DEP(16)) urdyd4 (.clk(s_clk_i), .ce(1'b1), .a(4'd1), .d(s_req_i.tid), .q(s_resp1.tid));
vtdl #(.WID(32), .DEP(16)) urdyd5 (.clk(s_clk_i), .ce(1'b1), .a(4'd1), .d(s_req_i.adr), .q(s_resp1_adr));

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
integer n, n1, nr, ng, nb, np;
reg [31:0] fbc_addr;
reg [11:0] rastcmp;
reg [`ABITS] bm_base_addr1,bm_base_addr2;
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
reg [31:0] color_comp;
reg [3:0] red_comp,green_comp,blue_comp,pad_comp;
reg [31:0] colorc;
reg [31:0] bluegreen;
reg [31:0] redpad;
reg [9:0] red,green,blue,pad;
reg [9:0] red_mask,green_mask,blue_mask,pad_mask;
reg [5:0] comp_total;
reg [9:0] pps;
reg [5:0] bpp;
reg [5:0] cbpp;
reg sgLock;
wire pe_hsync, pe_hsync2;
wire pe_vsync;
wire [11:0] tocnt;		// bus timeout counter
reg [4:0] vm_cmd_o;
reg [7:0] vm_blen_o;
reg vm_cyc_o;
reg [31:0] vm_adr_o;
reg vm_we_o;
reg [MDW/8-1:0] vm_sel_o;
fta_tranid_t vm_tid_o;

// config
reg [63:0] irq_msgadr = IRQ_MSGADR;
reg [63:0] irq_msgdat = IRQ_MSGDAT;

wire [BUSWID-1:0] cfg_out;
generate begin : gConfigSpace
	if (BUSWID==32) begin
		ddbb32_config #(
			.pDevName(pDevName),
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
			.pDevName(pDevName),
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
delay3 #(8) udly7 (.clk(m_bus_o.clk), .ce(1'b1), .i(vm_blen_o), .o(m_bus_o.req.blen));

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
`ifdef SVGA800x600	
	windowWidth <= 12'd800;
	windowHeight <= 12'd600;
	bmpWidth <= 16'd800;
	bmpHeight <= 16'd600;
	burst_len <= 8'd99;		// 1 bursts of 100 = 800 pixels
	hrefdelay <= 16'hFF39;//16'd3964;//16'hFF99;//12'd103;
	vrefdelay <= 16'hFFEA;//16'hFFF3;12'd13;
`endif
`ifdef SVGA800x600_72
	windowWidth <= 12'd800;
	windowHeight <= 12'd600;
	bmpWidth <= 16'd800;
	bmpHeight <= 16'd600;
	burst_len <= 8'd99;		// 1 bursts of 100 = 800 pixels
	hrefdelay <= 16'hFF49;//16'd3964;//16'hFF99;//12'd103;
	vrefdelay <= 16'hFFEA;//16'hFFF3;12'd13;
`endif
`ifdef XGA1024x768	
	windowWidth <= 12'd1024;
	windowHeight <= 12'd768;
	bmpWidth <= 16'd1024;
	bmpHeight <= 16'd768;
	burst_len <= 8'd127;		// 1 bursts of 128 = 1024 pixels
	hrefdelay <= 16'hFEF9;//16'd3964;//16'hFF99;//12'd103;
	vrefdelay <= 16'hFFE6;//16'hFFF3;12'd13;
`endif
`ifdef WXGA1366x768
	windowWidth <= 12'd1366;
	windowHeight <= 12'd768;
	bmpWidth <= 16'd1360;
	bmpHeight <= 16'd768;
	burst_len <= 8'd171;		// 1 bursts of 171 1368 pixels
	hrefdelay <= 16'hFF39;//16'd3964;//16'hFF99;//12'd103;
	vrefdelay <= 16'hFFEA;//16'hFFF3;12'd13;
`endif
`ifdef WXGA1920x1080
	windowWidth <= 12'd1920;
	windowHeight <= 12'd1080;
	bmpWidth <= 16'd1920;
	bmpHeight <= 16'd1080;
	burst_len <= 8'd239;		// 1 bursts of 239 1920 pixels
	hrefdelay <= 16'hFF39;//16'd3964;//16'hFF99;//12'd103;
	vrefdelay <= 16'hFFEA;//16'hFFF3;12'd13;
`endif
	onoff <= 1'b1;
	greyscale <= 1'b0;
	color_comp <= 32'h08888;
	bm_base_addr1 <= BM_BASE_ADDR1;
	bm_base_addr2 <= BM_BASE_ADDR2;
	windowLeft <= 16'h0;
	windowTop <= 16'h0;
	burst_interval <= BURST_INTERVAL;
	pcmd <= 2'b00;
	rstcmd1 <= 1'b0;
	rst_irq <= 1'b0;
	rastcmp <= 12'hFFF;
	oob_color <= 32'h00003C00;
	trans_color <= 32'hBFFFFFFF;
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
	max_nburst <= 6'd0;		// 2 bursts of 25 = 50 accesses for 800 pixels
end
else begin
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
					if (sel[4]) burst_len <= dat[39:32];
					if (sel[5]) max_nburst <= dat[45:40];
					if (&sel[7:6]) burst_interval <= dat[59:48];
				end
			REG_REFDELAY:
				begin
					if (&sel[1:0])	hrefdelay <= dat[15:0];
					if (&sel[3:2])  vrefdelay <= dat[31:16];
				end
			REG_PAGE1ADDR:	bm_base_addr1 <= dat;
			REG_PAGE2ADDR:	bm_base_addr2 <= dat;
			REG_PXYZ:
				begin
					if (&sel[1:0])	px <= dat[15:0];
					if (&sel[3:2])	py <= dat[31:16];
					if (&sel[  4])	pz <= dat[39:32];
				end
			REG_PCOLCMD:
				begin
					if (sel[0]) pcmd <= dat[1:0];
			    if (sel[1]) raster_op <= dat[11:8];
			    if (&sel[7:4]) color <= dat[63:32];
			  end
			REG_RASTCMP:	
				begin
					if (sel[0]) rastcmp[7:0] <= dat[7:0];
					if (sel[1]) rastcmp[11:8] <= dat[11:8];
					if (sel[7]) rst_irq <= dat[63];
				end
			REG_BMPSIZE:
				begin
					if (&sel[1:0]) bmpWidth <= dat[15:0];
					if (&sel[5:4]) bmpHeight <= dat[47:32];
				end
			REG_OOB_COLOR:
				begin
					if (&sel[3:0]) oob_color[31:0] <= dat[31:0];
					if (&sel[7:4]) trans_color[31:0] <= dat[63:32];
				end
			REG_WINDOW:
				begin
					if (&sel[1:0])	windowWidth <= dat[11:0];
					if (&sel[3:2])  windowHeight <= dat[27:16];
					if (&sel[5:4])	windowLeft <= dat[47:32];
					if (&sel[7:6])  windowTop <= dat[63:48];
				end
			REG_COLOR_COMPONENT:
				begin
					if (&sel[3:0]) color_comp <= dat[31:0];
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
						if (&sel[1:0]) hTotal <= dat[11:0];
						if (&sel[3:2]) vTotal <= dat[27:16];
					end
					if (&sel[7:4]) begin
						if (dat[63:32]==32'hA1234567)
							sgLock <= 1'b0;
						else if (dat[63:32]==32'h7654321A)
							sgLock <= 1'b1;
					end
				end
			REG_SYNC_ONOFF:
				if (!sgLock) begin
					if (&sel[1:0]) hSyncOff <= dat[11:0];
					if (&sel[3:2]) hSyncOn <= dat[27:16];
					if (&sel[5:4]) vSyncOff <= dat[43:32];
					if (&sel[7:6]) vSyncOn <= dat[59:48];
				end
			REG_BLANK_ONOFF:
				if (!sgLock) begin
					if (&sel[1:0]) hBlankOff <= dat[11:0];
					if (&sel[3:2]) hBlankOn <= dat[27:16];
					if (&sel[5:4]) vBlankOff <= dat[43:32];
					if (&sel[7:6]) vBlankOn <= dat[59:48];
				end
			REG_BORDER_ONOFF:
				begin
					if (&sel[1:0]) hBorderOff <= dat[11:0];
					if (&sel[3:2]) hBorderOn <= dat[27:16];
					if (&sel[5:4]) vBorderOff <= dat[43:32];
					if (&sel[7:6]) vBorderOn <= dat[59:48];
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
		          s_dat_o[12] <= greyscale;
		          s_dat_o[18:16] <= hres;
		          s_dat_o[22:20] <= vres;
		          s_dat_o[24] <= page;
		          s_dat_o[29:25] <= pals;
		          s_dat_o[39:32] <= burst_len;
		          s_dat_o[59:48] <= burst_interval;
		      end
		  REG_REFDELAY:		s_dat_o <= {32'h0,vrefdelay,hrefdelay};
		  REG_PAGE1ADDR:	s_dat_o <= bm_base_addr1;
		  REG_PAGE2ADDR:	s_dat_o <= bm_base_addr2;
		  REG_PXYZ:		    s_dat_o <= {20'h0,pz,py,px};
		  REG_PCOLCMD:    s_dat_o <= {color_o,12'd0,raster_op,14'd0,pcmd};
			REG_BMPSIZE:		s_dat_o <= {16'd0,bmpHeight,16'd0,bmpWidth};
		  REG_OOB_COLOR:	s_dat_o <= {trans_color,oob_color};
		  REG_WINDOW:			s_dat_o <= {windowTop,windowLeft,4'h0,windowHeight,4'h0,windowWidth};
			REG_COLOR_COMPONENT:	s_dat_o <= {32'd0,color_comp};
		  REG_IRQ_MSGADR:	s_dat_o <= irq_msgadr;
		  REG_IRQ_MSGDAT:	s_dat_o <= irq_msgdat;
		  REG_COLOR:	s_dat_o <= {32'd0,colorc};
		  REG_PRGB:		s_dat_o <= {6'd0,pad,6'd0,red,6'd0,green,6'd0,blue};
		  REG_PPS:		s_dat_o <= {10'd0,bpp,6'd0,pps};
		  11'b1?_????_????_?:	s_dat_o <= pal_wo;
		  default:        s_dat_o <= 'd0;
		  endcase
		else
		  casez(adri[13:2])
		  {REG_CTRL,1'b0}:      s_dat_o <= {2{2'd0,pals,page,1'd0,vres,1'd0,hres,3'd0,greyscale,11'd0,onoff}};
		  {REG_CTRL,1'b1}:      s_dat_o <= {2{4'd0,burst_interval,8'd0,burst_len}};
		  {REG_REFDELAY,1'b0}:	s_dat_o <= {2{vrefdelay,hrefdelay}};
		  {REG_PAGE1ADDR,1'b0}:	s_dat_o <= {2{bm_base_addr1}};
		  {REG_PAGE2ADDR,1'b0}:	s_dat_o <= {2{bm_base_addr2}};
		  {REG_PXYZ,1'b0}:		  s_dat_o <= {2{py,px}};
		  {REG_PXYZ,1'b1}:		  s_dat_o <= {2{16'h0,pz}};
		  {REG_PCOLCMD,1'b0}:   s_dat_o <= {2{12'd0,raster_op,14'd0,pcmd}};
		  {REG_PCOLCMD,1'b1}:   s_dat_o <= {2{color_o}};
			{REG_BMPSIZE,1'b0}:		s_dat_o <= {2{16'd0,bmpWidth}};
			{REG_BMPSIZE,1'b1}:		s_dat_o <= {2{16'd0,bmpHeight}};
		  {REG_OOB_COLOR,1'b0}:	s_dat_o <= {2{oob_color}};
		  {REG_OOB_COLOR,1'b1}:	s_dat_o <= {2{trans_color}};
		  {REG_WINDOW,1'b0}:		s_dat_o <= {2{4'h0,windowHeight,4'h0,windowWidth}};
		  {REG_WINDOW,1'b1}:		s_dat_o <= {2{windowTop,windowLeft}};
			{REG_COLOR_COMPONENT,1'b0}:	s_dat_o <= {2{color_comp}};
			{REG_COLOR,1'b0}:			s_dat_o <= {2{colorc}};
			{REG_PRGB,1'b0}:			s_dat_o <= {2{6'd0,green,6'd0,blue}};
			{REG_PRGB,1'b1}:			s_dat_o <= {2{6'd0,pad,6'd0,red}};
		  {REG_PPS,1'b0}:				s_dat_o <= {2{10'd0,bpp,6'd0,pps}};
		  {REG_IRQ_MSGADR,1'b0}:	s_dat_o <= {2{irq_msgadr[31:0]}};
		  {REG_IRQ_MSGADR,1'b1}:	s_dat_o <= {2{irq_msgadr[63:32]}};
		  {REG_IRQ_MSGDAT,1'b0}:	s_dat_o <= {2{irq_msgdat[31:0]}};
		  {REG_IRQ_MSGDAT,1'b1}:	s_dat_o <= {2{irq_msgdat[63:32]}};
		  12'b10_????_????_?0:	s_dat_o <= {2{pal_wo[31:0]}};
		  12'b10_????_????_?1:	s_dat_o <= {2{pal_wo[63:32]}};
			12'b111110000000:	s_dat_o <= "DEV ";
			12'b111110000001:	s_dat_o <= "FRAM";
			12'b111110000010:	s_dat_o <= "EBUF";
			12'b111110000011:	s_dat_o <= {8'h00,"   "};
			12'b111111000000:	s_dat_o <= " VED";
			12'b111111000001:	s_dat_o <= "MARF";
			12'b111111000010:	s_dat_o <= "FUBE";
			12'b111111000011:	s_dat_o <= {"   ",8'h00};
			12'b11111???????:	s_dat_o <= 32'd0;	// dcb RAM
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

reg [2:0] bytpp;
reg [19:0] coeff1;
reg [9:0] coeff2;
reg [3:0] blue_shift;
reg [3:0] green_shift;
reg [4:0] red_shift;
reg [4:0] pad_shift;

always_ff @(posedge s_clk_i)
	pad_comp <= color_comp[15:12];
always_ff @(posedge s_clk_i)
	red_comp <= color_comp[11:8];
always_ff @(posedge s_clk_i)
	green_comp <= color_comp[7:4];
always_ff @(posedge s_clk_i)
	blue_comp <= color_comp[3:0];

// Bits per pixel minus one.
always_ff @(posedge s_clk_i)
	bpp <= {2'b0,pad_comp}+{2'b0,red_comp}+{2'b0,green_comp}+{2'b0,blue_comp};

// Color bits per pixel minus one.
always_ff @(posedge s_clk_i)
	cbpp <= {2'b0,red_comp}+{2'b0,green_comp}+{2'b0,blue_comp};

// Bytes per pixel.
always_ff @(posedge s_clk_i)
	bytpp <= (bpp + 3'd7) >> 2'd3;

// This coefficient is a fixed point fraction representing the inverse of the
// number of pixels per strip. The inverse (reciprocal) is used for a high
// speed divide operation.
always_ff @(posedge s_clk_i)
	coeff1 <= {12'd0,bpp} * (65536/MDW);	// 9x6 multiply - could use a lookup table

// This coefficient is the number of bits used by all pixels in the strip. 
// Used to determine pixel placement in the strip.
wire [9:0] coeff2a [0:32];
wire [9:0] pps1 [0:32];

generate begin : gCoeff2
	assign coeff2a[0] = MDW;
	assign pps1[0] = MDW;
	for (g = 1; g < 33; g = g + 1) begin
		assign coeff2a[g] = MDW - (MDW % g);
		assign pps1[g] = MDW/g;
	end
end
endgenerate

always_ff @(posedge s_clk_i)
	coeff2 <= coeff2a[bpp];

// Pixels per strip
always_ff @(posedge s_clk_i)
	pps <= pps1[bpp];

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

always_ff @(posedge s_clk_i)
	for (nb = 0; nb < 10; nb = nb + 1)
		blue_mask[nb] <= nb < blue_comp;
always_ff @(posedge s_clk_i)
	for (ng = 0; ng < 10; ng = ng + 1)
		green_mask[nb] <= ng < green_comp;
always_ff @(posedge s_clk_i)
	for (nr = 0; nr < 10; nr = nr + 1)
		red_mask[nr] <= nr < red_comp;
always_ff @(posedge s_clk_i)
	for (np = 0; np < 10; np = np + 1)
		pad_mask[np] <= np < pad_comp;
always_ff @(posedge s_clk_i)
if (cs_edge && we && adri[13:3]==REG_COLOR)
	blue <= dat & blue_mask;
else if (cs_edge && we && adri[13:3]==REG_PRGB)
	if (&sel[1:0])
		blue <= dat;
always_ff @(posedge s_clk_i)
if (cs_edge && we && adri[13:3]==REG_COLOR)
	green <= (dat >> blue_comp) & green_mask;
else if (cs_edge && we && adri[13:3]==REG_PRGB)
	if (&sel[3:2])
		green <= dat[31:16];
always_ff @(posedge s_clk_i)
if (cs_edge && we && adri[13:3]==REG_COLOR)
	red <= (dat >> (blue_comp + green_comp)) & red_mask;
else if (cs_edge && we && adri[13:3]==REG_PRGB)
	if (&sel[5:4])
		red <= dat[47:32];
always_ff @(posedge s_clk_i)
if (cs_edge && we && adri[13:3]==REG_COLOR)
	pad <= (dat >> (blue_comp + green_comp + red_comp)) & pad_mask;
else if (cs_edge && we && adri[13:3]==REG_PRGB)
	if (&sel[7:6])
		pad <= dat[63:47];
always_ff @(posedge s_clk_i)
if (cs_edge && ~we && adri[13:3]==REG_COLOR) begin
	colorc <= (pad << (blue_comp + green_comp + red_comp)) |
		(red << (blue_comp + green_comp)) |
		(green << blue_comp) |
		blue
		;
end
else if (cs_edge && we && adri[13:3]==REG_COLOR)
	colorc <= dat;

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
// Horizontal and Vertical timing reference counters
// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

reg lef;	// load even fifo
reg lof;	// load odd fifo
reg bhsync1, bhsync2;
wire pe_hsync3;

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

/*
modHsync3 uh31
(
	.rst(rst_i),
	.clk(vclk),
	.hsync(hsync_o),
	.hsync3(pe_hsync3)
);
*/

// synchronize to bus clock domain.
always_ff @(posedge m_bus_o.clk)
	bhsync1 <= hsync_o;
always_ff @(posedge m_bus_o.clk)
	bhsync2 <= bhsync1;

edge_det edh2
(
	.rst(rst_i),
	.clk(m_bus_o.clk),
	.ce(1'b1),
	.i(bhsync2),
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

always_ff @(posedge vclk)
	xal_o <= vc != 4'd1;

always_comb
	shifts = pps;

wire vFetch = !vblank;//pixelRow < windowHeight;
reg fifo_rrst;
reg fifo_wrst;
reg [3:0] wrstcnt;
always_comb fifo_rrst = hsync_o;	// pixelCol==16'hFFF0;

always_ff @(posedge m_bus_o.clk)
if (m_bus_o.rst)
	wrstcnt <= 4'd0;
else begin
	if (pe_hsync2)
		wrstcnt <= 4'd0;
	else if (wrstcnt!=4'd5)
		wrstcnt <= wrstcnt + 2'd1;
end

always_comb fifo_wrst = wrstcnt!=4'd5;
//always_comb fifo_rrst = wrstcnt!=4'd5;// && vc==4'd1;
always_comb fifo_rst_o = fifo_wrst;

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
	.coeff1_i(coeff1),
	.coeff2_i(coeff2),
	.bpp_i(bpp),
	.cbpp_i(cbpp),
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
	.coeff1_i(coeff1),
	.coeff2_i(coeff2),
	.bpp_i(bpp),
	.cbpp_i(cbpp),
	.bmp_width_i(bmpWidth),
	.x_coord_i(windowLeft+px),
	.y_coord_i(windowTop+py),
	.address_o(xyAddr),
	.mb_o(mb),
	.me_o(me),
	.ce_o(ce)
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
    if ((((m_bus_o.resp.ack && m_bus_o.resp.tid.tranid==4'h0)|tocnt[10])) || state==LOAD_OOB)
      fetchCol <= fetchCol + shifts;
  end

// Check for legal (positive) coordinates
// Illegal coordinates result in a red display
wire [15:0] xcol = fetchCol;
reg legal_x, legal_y;
always_comb legal_x = ~xcol[15] && xcol < windowLeft + windowWidth && xcol >= windowLeft;//bmpWidth;
always_comb legal_y = ~pixelRow[15] && pixelRow < windowTop + windowHeight && pixelRow >= windowTop;//bmpHeight;

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
	vm_blen_o <= 8'd0;
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
	if (memreq && !m_rst_busy_i && !fifo_wrst && !m_bus_o.resp.stall) begin
		m_fst_o <= LOW;
		vm_blen_o <= burst_len;
		vm_tid_o <= {CORENO,CHANNEL,4'h0};
		vm_cmd_o <= fta_bus_pkg::CMD_LOADZ;
    vm_cyc_o <= HIGH;
    vm_we_o <= LOW;//m_fst_o;
    vm_sel_o <= {MDW/8{1'b1}};
//    if (m_fst_o) 
    begin
	    vm_adr_o <= grAddr;
    	next_adr <= grAddr;// + bmpWidth * bytpp;//MDW/8;
    end
/*    
    else begin
	    vm_adr_o <= next_adr + ({10'd0,burst_len} + 2'd1) * (MDW/8);
	    next_adr <= next_adr + ({10'd0,burst_len} + 2'd1) * (MDW/8);
	  end
*/
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
		if (!(memreq && !m_rst_busy_i && !m_bus_o.resp.stall)) begin
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
    if (!(memreq && !m_rst_busy_i && !m_bus_o.resp.stall)) begin
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

always_comb rd_fifo = next_strip & shift_en & (~pixelCol[15] || pixelCol==16'hFFFF);

modMuxRgbo3 #(.MDW(MDW)) umuxrgbo31
(
	.clk(vclk),
	.en(shift_en),
	.rd_fifo(rd_fifo),
	.rgbo1e(rgbo1e),
	.bpp(bpp),
	.cbpp(cbpp),
	.rgbo(rgbo3)
);

modMuxRgbo4 umuxrgbo41
(
	.clk(vclk),
	.color_comp(color_comp[15:0]),
	.rgbo3(rgbo3),
	.rgbo4(rgbo4)
);

modMuxRgbo umuxrgbo1
(
	.clk(vclk),
	.onoff(onoff),
	.xonoff(xonoff_i),
	.blank(blank_i),
	.bpp(bpp),
	.greyscale(greyscale),
	.pal_o(pal_o),
	.trans_color(trans_color),
	.rgbo4(rgbo4),
	.rgb_i(rgb_i),
	.rgb_o(rgb_o)
);

/*
always_ff @(posedge vclk)
if (rst_i)
	addrb <= 10'd0;
else begin
	if (memreq && !m_rst_busy_i && !fifo_wrst) begin
    if (m_fst_o)
	    addrb <= adr[14:5];
    else
	    addrb <= (next_adr + ({10'd0,burst_len} + 2'd1) * (MDW/8)) >> 4'd5;
	end
	else if (rd_fifo)
		addrb <= addrb + 10'd1;
end
*/

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
	.clk(s_clk_i),
	.bpp(bpp),
	.oob_color(oob_color),
	.oob_dat(oob_dat)
);

// Could maybe set pixel color here on timeout, otherwise likely random data
// will be used for the color.

/*
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
*/

wire wr_rst_busy, rd_rst_busy;
reg rd_en;
always_comb
	rd_en = rd_fifo && !rd_rst_busy;
reg wr_en;
always_comb	
	wr_en = (m_bus_o.resp.ack && m_bus_o.resp.tid.tranid==4'h0) && !rst_i && !fifo_wrst && !wr_rst_busy && vc==3'd1;

   // xpm_fifo_async: Asynchronous FIFO
   // Xilinx Parameterized Macro, version 2024.2

   xpm_fifo_async #(
      .CASCADE_HEIGHT(0),
      .CDC_SYNC_STAGES(2),
      .DOUT_RESET_VALUE("0"),
      .ECC_MODE("no_ecc"),
      .EN_SIM_ASSERT_ERR("warning"),
      .FIFO_MEMORY_TYPE("auto"),
      .FIFO_READ_LATENCY(1),
      .FIFO_WRITE_DEPTH(256),
      .FULL_RESET_VALUE(0),
      .PROG_EMPTY_THRESH(10),
      .PROG_FULL_THRESH(250),
      .RD_DATA_COUNT_WIDTH(8),
      .READ_DATA_WIDTH(MDW),
      .READ_MODE("std"),
      .RELATED_CLOCKS(0),
      .SIM_ASSERT_CHK(0),            // DECIMAL; 0=disable simulation messages, 1=enable simulation messages
      .USE_ADV_FEATURES("0000"),
      .WAKEUP_TIME(0),
      .WRITE_DATA_WIDTH(MDW),
      .WR_DATA_COUNT_WIDTH(8)
   )
   xpm_fifo_async_inst (
      .almost_empty(),
      .almost_full(),
      .data_valid(),
      .dbiterr(),
      .dout(rgbo1e),
      .empty(),
      .full(),
      .overflow(),
      .prog_empty(),
      .prog_full(),
      .rd_data_count(),
      .rd_rst_busy(rd_rst_busy),
      .sbiterr(),
      .underflow(),
      .wr_ack(),
      .wr_data_count(),
      .wr_rst_busy(wr_rst_busy),
      .din(m_bus_o.resp.dat),
      .injectdbiterr(1'b0),
      .injectsbiterr(1'b0),
      .rd_clk(vclk),
      .rd_en(rd_en),
      .rst(rst_i|fifo_wrst),
      .sleep(1'b0),
      .wr_clk(m_bus_o.clk),
      .wr_en(wr_en)
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
input [7:0] burst_len;
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
wire [7:0] nburst;

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
	if (bi_ctr==12'd24 && vFetch && on)
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
if (cnt == 4'd6)
	adr <= grAddr;
/*
else begin
  if ((ack|tocnt[10]) || state==LOAD_OOB)
  	adr <= adr + MDW/8;
end
*/
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
input [9:0] shifts;
output reg [9:0] shift_cnt;

always_ff @(posedge clk)
if (pe_hsync)
	shift_cnt <= 10'd1;
else begin
	if (en) begin
		if (pixel_col==16'hFFFF) begin
			shift_cnt <= shifts;
		end
		else if (!pixel_col[15]) begin
			shift_cnt <= shift_cnt + 10'd1;
			if (shift_cnt==shifts)
				shift_cnt <= 10'd1;
		end
		else
			shift_cnt <= 10'd1;
	end
end

endmodule

// This mux extracts pixels from the memory strip.

module modMuxRgbo3(clk, en, rd_fifo, rgbo1e, bpp, cbpp, rgbo);
parameter MDW=256;
input clk;
input en;
input rd_fifo;
input [MDW-1:0] rgbo1e;
input [5:0] bpp;
input [5:0] cbpp;
output reg [31:0] rgbo;

integer n1;
reg [31:0] mask;
reg [MDW-1:0] rgbo3;

always_ff @(posedge clk)
	for (n1 = 0; n1 < 32; n1 = n1 + 1)
		mask[n1] <= n1 <= cbpp;

always_ff @(posedge clk)
	if (en) begin
		if (rd_fifo)
			rgbo3 <= rgbo1e;
		else
			rgbo3 <= rgbo3 >> bpp;
	end

always_comb rgbo = rgbo3[31:0] & mask;

endmodule

// This mux takes the color bits and converts them into a 32-bit value.

module modMuxRgbo4(clk, color_comp, rgbo3, rgbo4);
input clk;
input [15:0] color_comp;
input [31:0] rgbo3;
output reg [31:0] rgbo4;

integer nr,ng,nb;
reg [9:0] red;
reg [9:0] green;
reg [9:0] blue;
reg [4:0] red_shift, green_shift;
reg [4:0] red_shift2, green_shift2, blue_shift2;
reg [9:0] red_mask, green_mask, blue_mask;

always_ff @(posedge clk)
	for (nr = 0; nr < 10; nr = nr + 1)
		red_mask[nr] = nr < color_comp[11:8];
always_ff @(posedge clk)
	for (ng = 0; ng < 10; ng = ng + 1)
		green_mask[ng] = ng < color_comp[7:4];
always_ff @(posedge clk)
	for (nb = 0; nb < 10; nb = nb + 1)
		blue_mask[nb] = nb < color_comp[3:0];
always_ff @(posedge clk)
	red_shift2 = 6'd10 - color_comp[11:8];
always_ff @(posedge clk)
	green_shift2 = 6'd10 - color_comp[7:4];
always_ff @(posedge clk)
	blue_shift2 = 6'd10 - color_comp[3:0];

always_ff @(posedge clk)
	red_shift <= color_comp[7:4] + color_comp[3:0];
always_ff @(posedge clk)
	green_shift <= color_comp[3:0];
always_ff @(posedge clk)
	red <= ((rgbo3 >> red_shift) & red_mask) << red_shift2;
always_ff @(posedge clk)
	green <= ((rgbo3 >> green_shift) & green_mask) << green_shift2;
always_ff @(posedge clk)
	blue <= (rgbo3 & blue_mask) << blue_shift2;

always_ff @(posedge clk)
	rgbo4 <= {red,green,blue};

endmodule

module modMuxRgbo(clk, onoff, xonoff, blank, bpp, greyscale, pal_o, trans_color, rgbo4, rgb_i, rgb_o);
input clk;
input onoff;
input xonoff;
input blank;
input [5:0] bpp;
input greyscale;
input [31:0] pal_o;
input [31:0] trans_color;
input [31:0] rgbo4;
input [31:0] rgb_i;
output reg [31:0] rgb_o;

reg [31:0] zrgb;

always_ff @(posedge clk)
	if (onoff && xonoff && !blank) begin
		if (bpp < 6'd9) begin
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

module modOobColor(clk, bpp, oob_color, oob_dat);
parameter MDW=256;
input clk;
input [5:0] bpp;
input [31:0] oob_color;
output reg [MDW-1:0] oob_dat;

wire [MDW-1:0] oob [0:32];

genvar g;
generate begin : gOOBcolor
	assign oob[0] = {MDW{1'b0}};
	for (g = 1; g < 33; g = g + 1)
		assign oob[g] = {MDW/g{oob_color[g-1:0]}};
end
endgenerate

always_ff @(posedge clk)
	oob_dat <= oob[bpp];

endmodule

// Burst counter
module modBurstCntr(rst, clk, memreq, nburst);
input rst;
input clk;
input memreq;
output reg [7:0] nburst;

always_ff @(posedge clk)
if (rst)
	nburst <= 8'd0;
else begin
 	if (memreq)
		nburst <= nburst + 2'd1;
end

endmodule

// Shape hsync pulse to be 3 clocks wide.

module modHsync3(rst, clk, hsync, hsync3);
input rst;
input clk;
input hsync;
output reg hsync3;

reg r1,r2,r3;

always_ff @(posedge clk)
begin
	if (rst)
		hsync3 <= 1'b0;
	else begin
		r1 <= hsync;
		r2 <= r1;
		r3 <= r2;
		hsync3 <= hsync & ~r3;
	end
end

endmodule

