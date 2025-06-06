`timescale 1ns / 1ps
// ============================================================================
//  Bitmap Controller (Frame Buffer Display)
//  - Displays a bitmap from memory.
//
//
//        __
//   \\__/ o\    (C) 2008-2025  Robert Finch, Waterloo
//    \  __ /    All rights reserved.
//     \/_//     robfinch<remove>@finitron.ca
//       ||
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
//
//	Verilog 1995
//
//	3367 LUTs / 155 FFs / 5 BRAMs / 7 DSP
// ============================================================================

//`define USE_CLOCK_GATE	1'b1
`define INTERNAL_SYNC_GEN	1'b1
`define WXGA800x600		1'b1
//`define WXGA1366x768	1'b1
`define FBC_ADDR		32'hFD0400001

import const_pkg::*;
`define ABITS	31:0
`define BUSMWID256	1'b1;
`define BUSMWID 256;

import wishbone_pkg::*;
import gfx_pkg::*;
//import Thor2023Pkg::*;
//import Thor2023Mmupkg::*;

module rfFrameBuffer(
	rst_i,
	irq_o,
	cs_config_i,
	cs_io_i,
	s_clk_i, s_cyc_i, s_stb_i, s_ack_o, s_we_i, s_sel_i, s_adr_i, s_dat_i, s_dat_o,
	m_clk_i, m_fst_o, 
//	m_cyc_o, m_stb_o, m_ack_i, m_we_o, m_sel_o, m_adr_o, m_dat_i, m_dat_o,
	wbm_req, wbm_resp,
	dot_clk_i, zrgb_o, xonoff_i, xal_o
`ifdef INTERNAL_SYNC_GEN
	, hsync_o, vsync_o, blank_o, border_o, hctr_o, vctr_o, fctr_o, vblank_o
`else
	, hsync_i, vsync_i, blank_i
`endif
);
parameter BUSWID = 32;
parameter BUSMWID = `BUSMWID;

parameter FBC_ADDR = 32'hFED40001;
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
localparam BITS_IN_ADDR_MAP = PHYS_ADDR_BITS - 14;

parameter MDW = `BUSMWID;		// Bus master data width
parameter MAP = 12'd0;
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
input s_cyc_i;
input s_stb_i;
output s_ack_o;
input s_we_i;
input [BUSWID/8-1:0] s_sel_i;
input [31:0] s_adr_i;
input [BUSWID-1:0] s_dat_i;
output reg [BUSWID-1:0] s_dat_o;

// Video Memory Master Port
// Used to read memory via burst access
input m_clk_i;				// system bus interface clock
output reg m_fst_o;		// first access on scanline
`ifdef BUSMWID256
output wb_cmd_request256_t wbm_req;
input wb_cmd_response256_t wbm_resp;
`else
output wb_cmd_request128_t wbm_req;
input wb_cmd_response128_t wbm_resp;
`endif

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
output [39:0] zrgb_o;		// 36-bit RGB output + 4 bit z-order
reg [39:0] zrgb_o;

input xonoff_i;
output reg xal_o;		// external access line (sprite access)

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
// IO registers
// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
reg irq;
reg rst_irq,rst_irq1;

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
wire vclk;
reg cs,cs2;
reg cs_config;
reg cs_map;
reg cs_reg;
reg we;
reg [7:0] sel;
reg [31:0] adri;
reg [63:0] dat;

always_ff @(posedge s_clk_i)
	cs <= s_cyc_i & s_stb_i & cs_io_i;
always_ff @(posedge s_clk_i)
	we <= s_we_i;
always_ff @(posedge s_clk_i)
	sel <= BUSWID==64 ? s_sel_i : {4'd0,s_sel_i} << {s_adr_i[3],2'b00};
always_ff @(posedge s_clk_i)
	adri <= BUSWID==64 ? s_adr_i : s_adr_i;
always_ff @(posedge s_clk_i)
	dat <= BUSWID==64 ? s_dat_i : {32'd0,s_dat_i} << {s_adr_i[3],5'd0};

always_ff @(posedge s_clk_i)
	cs_config <= s_cyc_i & s_stb_i & cs_config_i && adri[27:20]==CFG_BUS && adri[19:15]==CFG_DEVICE && adri[14:12]==CFG_FUNC;
wire cs_fbc;
always_comb
	cs_map = cs && cs_fbc && adri[15:14]==3'd1;
always_comb
	cs_reg = cs && cs_fbc && adri[15:14]==3'd0;
	
ack_gen #(
	.READ_STAGES(3),
	.WRITE_STAGES(0),
	.REGISTER_OUTPUT(1)
) uag1
(
	.rst_i(rst_i),
	.clk_i(s_clk_i),
	.ce_i(1'b1),
	.i(cs_map|cs_reg|cs_config),
	.we_i(s_cyc_i & s_stb_i & (cs_map|cs_reg|cs_config) & s_we_i),
	.o(s_ack_o),
	.rid_i(0),
	.wid_i(0),
	.rid_o(),
	.wid_o()
);

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
reg [39:0] oob_color;
reg [39:0] color;
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
wire [BITS_IN_ADDR_MAP-1:0] map_out;

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
			.clk_i(clk_i),
			.irq_i(irq),
			.irq_o(irq_o),
			.cs_config_i(cs_config), 
			.we_i(we_i),
			.sel_i(sel_i),
			.adr_i(adr_i),
			.dat_i(dat_i),
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
			.clk_i(clk_i),
			.irq_i(irq),
			.irq_o(irq_o),
			.cs_config_i(cs_config), 
			.we_i(we_i),
			.sel_i(sel_i),
			.adr_i(adr_i),
			.dat_i(dat_i),
			.dat_o(cfg_out),
			.cs_bar0_o(cs_fbc),
			.cs_bar1_o(),
			.cs_bar2_o(),
			.irq_en_o(irq_en)
		);
	end
end
endgenerate

wire [BITS_IN_ADDR_MAP-1:0] map_page;

   // xpm_memory_tdpram: True Dual Port RAM
   // Xilinx Parameterized Macro, version 2022.2

   xpm_memory_tdpram #(
      .ADDR_WIDTH_A(11),               // DECIMAL
      .ADDR_WIDTH_B(11),               // DECIMAL
      .AUTO_SLEEP_TIME(0),            // DECIMAL
      .BYTE_WRITE_WIDTH_A(BITS_IN_ADDR_MAP),
      .BYTE_WRITE_WIDTH_B(BITS_IN_ADDR_MAP),
      .CASCADE_HEIGHT(0),             // DECIMAL
      .CLOCKING_MODE("common_clock"), // String
      .ECC_MODE("no_ecc"),            // String
      .MEMORY_INIT_FILE("fb_map2.mem"),      // String
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
      .addrb(vm_adr_o[26:16]),         // ADDR_WIDTH_B-bit input: Address for port B write and read operations.
      .clka(s_clk_i),                  // 1-bit input: Clock signal for port A. Also clocks port B when
                                       // parameter CLOCKING_MODE is "common_clock".

      .clkb(m_clk_i),                  // 1-bit input: Clock signal for port B when parameter CLOCKING_MODE is
                                       // "independent_clock". Unused when parameter CLOCKING_MODE is
                                       // "common_clock".

      .dina(dat[17:0]),                // WRITE_DATA_WIDTH_A-bit input: Data input for port A write operations.
      .dinb(18'd0),                    // WRITE_DATA_WIDTH_B-bit input: Data input for port B write operations.
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

      .regcea(cs_map),                 // 1-bit input: Clock Enable for the last register stage on the output
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
	wbm_req.padr <= {map_page,vm_adr_o[13:0]};
	
   // End of xpm_memory_tdpram_inst instantiation
				
delay3 #(1) udly1 (.clk(m_clk_i), .ce(1'b1), .i(vm_cyc_o), .o(wbm_req.cyc));

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
	else if (rst_irq|rst_irq1)
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
	hres <= 3'd2;
	vres <= 3'd2;
	windowWidth <= 12'd400;
	windowHeight <= 12'd300;
	onoff <= 1'b1;
	color_depth <= BPP16;
	color_depth2 <= BPP16;
	greyscale <= 1'b0;
	bm_base_addr1 <= BM_BASE_ADDR1;
	bm_base_addr2 <= BM_BASE_ADDR2;
	hrefdelay = 16'd3964;//16'hFF99;//12'd103;
	vrefdelay = 16'hFFF3;//12'd13;
	windowLeft <= 16'h0;
	windowTop <= 16'h0;
	windowWidth <= 16'd400;
	windowHeight <= 16'd300;
	bmpWidth <= 16'd400;
	bmpHeight <= 16'd300;
	map <= MAP;
	pcmd <= 2'b00;
	rstcmd1 <= 1'b0;
	rst_irq1 <= 1'b0;
	rastcmp <= 12'hFFF;
	oob_color <= 40'h00003C00;
	irq_msgadr <= IRQ_MSGADR;
	irq_msgdat <= IRQ_MSGDAT;
end
else begin
	color_depth2 <= color_depth;
	rstcmd1 <= rstcmd;
	rst_irq1 <= 1'b0;
  if (rstcmd & ~rstcmd1)
    pcmd <= 2'b00;
	if (cs_edge) begin
		if (we) begin
			casez(adri[13:3])
			REG_CTRL:
				begin
					if (sel[0]) onoff <= dat[0];
					if (sel[1]) begin
					color_depth <= color_depth_t'(dat[11:8]);
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
					if (sel[7]) rst_irq1 <= dat[63];
				end
			REG_BMPSIZE:
				begin
					if (|sel[1:0]) bmpWidth <= dat[15:0];
					if (|sel[5:4]) bmpHeight <= dat[47:32];
				end
			REG_OOB_COLOR:
				begin
					if (|sel[3:0]) oob_color[31:0] <= dat[31:0];
					if (sel[4]) oob_color[39:32] <= dat[39:32];
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

reg [3:0] hc = 4'd1;
always_ff @(posedge vclk)
if (pe_hsync) begin
	hc <= 4'd1;
	pixelCol <= hrefdelay;
end
else begin
	if (hc==hres) begin
		hc <= 4'd1;
		pixelCol <= pixelCol + 16'd1;
	end
	else
		hc <= hc + 4'd1;
end

reg [3:0] vc = 4'd1;
always_ff @(posedge vclk)
if (pe_vsync) begin
	vc <= 4'd1;
	pixelRow <= vrefdelay;
end
else begin
	if (pe_hsync) begin
		vc <= vc + 4'd1;
		if (vc==vres) begin
			vc <= 4'd1;
			pixelRow <= pixelRow + 16'd1;
		end
	end
end
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
//BPP6: bpp = 5;
BPP8:	bpp = 7;
//BPP12: bpp = 11;
BPP16:	bpp = 15;
//BPP18:	bpp = 17;
//BPP21:	bpp = 20;
BPP24:	bpp = 23;
//BPP27:	bpp = 26;
BPP32:	bpp = 31;
//BPP33:	bpp = 32;
//BPP36:	bpp = 35;
//BPP40:	bpp = 39;
default:	bpp = 15;
endcase

reg [5:0] shifts;
always_comb
case(MDW)
256:
	case(color_depth2)
//	BPP6:   shifts = 6'd21;
	BPP8: 	shifts = 6'd32;
//	BPP12:	shifts = 6'd10;
	BPP16:	shifts = 6'd16;
//	BPP18:	shifts = 6'd7;
//	BPP21:	shifts = 6'd6;
	BPP24:	shifts = 6'd10;
//	BPP27:	shifts = 6'd4;
	BPP32:	shifts = 6'd8;
//	BPP33:	shifts = 6'd3;
//	BPP36:	shifts = 6'd3;
//	BPP40:	shifts = 6'd3;
	default:  shifts = 6'd16;
	endcase
128:
	case(color_depth2)
//	BPP6:   shifts = 6'd21;
	BPP8: 	shifts = 6'd16;
//	BPP12:	shifts = 6'd10;
	BPP16:	shifts = 6'd8;
//	BPP18:	shifts = 6'd7;
//	BPP21:	shifts = 6'd6;
	BPP24:	shifts = 6'd5;
//	BPP27:	shifts = 6'd4;
	BPP32:	shifts = 6'd4;
//	BPP33:	shifts = 6'd3;
//	BPP36:	shifts = 6'd3;
//	BPP40:	shifts = 6'd3;
	default:  shifts = 6'd8;
	endcase
64:
	case(color_depth2)
//	BPP6:   shifts = 6'd10;
	BPP8: 	shifts = 6'd8;
//	BPP12:	shifts = 6'd5;
	BPP16:	shifts = 6'd4;
//	BPP18:	shifts = 6'd3;
//	BPP21:	shifts = 6'd3;
	BPP24:	shifts = 6'd2;
//	BPP27:	shifts = 6'd2;
	BPP32:	shifts = 6'd2;
//	BPP33:	shifts = 6'd1;
//	BPP36:	shifts = 6'd1;
//	BPP40:	shifts = 6'd1;
	default:  shifts = 6'd4;
	endcase
32:
	case(color_depth2)
//	BPP6:   shifts = 6'd5;
	BPP8: 	shifts = 6'd4;
//	BPP12:	shifts = 6'd2;
	BPP16:	shifts = 6'd2;
//	BPP18:	shifts = 6'd1;
//	BPP21:	shifts = 6'd1;
	BPP24:	shifts = 6'd1;
//	BPP27:	shifts = 6'd1;
	BPP32:	shifts = 6'd1;
//	BPP33:	shifts = 6'd1;
//	BPP36:	shifts = 6'd1;
//	BPP40:	shifts = 6'd1;
	default:  shifts = 6'd2;
	endcase
default:
	begin
	$display("rfBitmapController: Bad master bus width");
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
localparam CMS = MDW==256 ? 7 : MDW==128 ? 6 : MDW==64 ? 5 : 4;
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
wire memreq = mapctr==12'd0 && vc==4'd1 && vFetch && onoff && xonoff_i;

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
//BPP6: hCmp = 12'd2688;    // must be 12 bits
BPP8:	hCmp = 12'd2048;
//BPP12: hCmp = 12'd1536;
BPP16:	hCmp = 12'd1024;
//BPP18:	hCmp = 12'd896;
//BPP21:	hCmp = 12'd768;
BPP24:	hCmp = 12'd640;
//BPP27:	hCmp = 12'd512;
BPP32:	hCmp = 12'd512;
//BPP33:	hCmp = 12'd384;
//BPP36:	hCmp = 12'd384;
//BPP40:	hCmp = 12'd384;
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
always_comb wbm_req.bte = wishbone_pkg::LINEAR;
always_comb wbm_req.stb = wbm_req.cyc;
always_comb wbm_req.cid = 4'd0;

reg [31:0] adr;
typedef enum logic [3:0] {
	IDLE = 4'd0,
	LOADCOLOR = 4'd2,
	LOADSTRIP = 4'd3,
	STORESTRIP = 4'd4,
	ACKSTRIP = 4'd5,
	WAITLOAD1 = 4'd6,
	WAITLOAD = 4'd7,
	WAITRST = 4'd8,
	ICOLOR1 = 4'd9,
	ICOLOR2 = 4'd10,
	ICOLOR3 = 4'd11,
	ICOLOR4 = 4'd12,
	LOAD_OOB = 4'd13
} state_t;
state_t state,prev_state;
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

always_ff @(posedge m_clk_i)
	if (fifo_wrst)
		adr <= grAddr;
  else begin
    if ((state==WAITLOAD && (wbm_resp.ack|tocnt[10])) || state==LOAD_OOB)
    	case(MDW)
    	32:		adr <= adr + 32'd4;
    	64:		adr <= adr + 32'd8;
    	128:	adr <= adr + 32'd16;
    	256:	adr <= adr + 32'd32;
    	default:	adr <= adr + 32'd16;
    	endcase
  end

always_ff @(posedge m_clk_i)
	if (fifo_wrst)
		fetchCol <= 12'd0;
  else begin
    if ((state==WAITLOAD && (wbm_resp.ack|tocnt[10])) || state==LOAD_OOB)
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
	32:	modd <= wbm_req.padr[5:2]==4'hF;
	64:	modd <= wbm_req.padr[5:3]==3'h7;
	128:	modd <= wbm_req.padr[5:4]==2'h3;
	256:	modd <= wbm_req.padr[5]==1'b1;
	default:	modd <= wbm_req.padr[5:4]==2'h3;
	endcase

always @(posedge m_clk_i)
if (rst_i)
	tocnt <= 'd0;
else begin
	if (wbm_req.cyc)
		tocnt <= tocnt + 2'd1;
	else
		tocnt <= 'd0;
end

reg [6:0] bcnt;

always @(posedge m_clk_i)
if (rst_i) begin
	wbm_req.tid <= 8'd0;
	wbm_req.cti <= wishbone_pkg::CLASSIC;
	vm_cyc_o <= LOW;
	wbm_req.we <= LOW;
	wbm_req.sel <= 32'h0;
	wbm_req.blen <= 6'd0;
	vm_adr_o <= 32'd0;
  rstcmd <= 1'b0;
  state <= IDLE;
  prev_state <= IDLE;
  rst_irq <= 1'b0;
  bcnt <= 7'd0;
end
else begin
  rst_irq <= 1'b0;
	if (fifo_wrst)
		m_fst_o <= HIGH;
	case(state)
  WAITRST:
    if (pcmd==2'b00 && ~wbm_resp.ack) begin
      rstcmd <= 1'b0;
      prev_state <= WAITRST;
      state <= IDLE;
    end
    else
      rstcmd <= 1'b1;
  IDLE:
  	begin
  		prev_state <= IDLE;
	  	if (load_fifo && !(legal_x && legal_y)) begin
	  		wb_nack();
	 			state <= LOAD_OOB;
	 		end
	    else if (load_fifo & ~wbm_resp.ack) begin
	    	wbm_req.tid <= 8'd0;
	    	wbm_req.cti <= wishbone_pkg::INCR;
	    	wbm_req.blen <= 6'd63;
	      vm_cyc_o <= HIGH;
	      vm_adr_o <= adr;
	      wbm_req.sel <= {MDW/8{1'b1}};
	      bcnt <= 7'd0;
	      state <= WAITLOAD1;
	    end
	    // Send an IRQ message if needed.
	    else if (irq & ~wbm_resp.ack & MSIX) begin
	    	wbm_req.tid.tranid <= 4'd1;
	    	vm_cyc_o <= HIGH;
	    	vm_adr_o <= irq_msgadr;
	    	wbm_req.we <= HIGH;
	    	case(MDW)
	    	256:
	    		begin 
	    			wbm_req.sel <= 32'h0FF << {irq_msgadr[4:3],3'b0};
				    wbm_req.dat <= {4{irq_msgdat}};
	    		end
	    	128:
	    		begin
	    			wbm_req.sel <= irq_msgadr[3] ? 16'hFF00 : 16'h00FF;
				    wbm_req.dat <= {2{irq_msgdat}};
				  end
	    	64:	
	    		begin
	    			wbm_req.sel <= 8'hFF;
				    wbm_req.dat <= irq_msgdat;
	    		end
	    	endcase
	    	rst_irq <= 1'b1;
	    end
	    // The adr_o[5:3]==3'b111 causes the controller to wait until all eight
	    // 64 bit strips from the memory controller have been processed. Otherwise
	    // there would be cache thrashing in the memory controller and the memory
	    // bandwidth available would be greatly reduced. However fetches are also
	    // allowed when loads are not active or all strips for the current scan-
	    // line have been fetched.
	    else if (pcmd!=2'b00 && (modd || !(vFetch && onoff && xonoff_i && fetchCol < windowWidth))) begin
	    	wbm_req.tid <= 8'd2;
	      vm_cyc_o <= HIGH;
	      vm_adr_o <= xyAddr;
	      wbm_req.sel <= {MDW/8{1'b1}};
	      state <= LOADSTRIP;
	    end
  	end
  LOADSTRIP:
    if ((wbm_resp.ack && wbm_resp.tid==8'd2) || tocnt[8]) begin
      wb_nack();
      mem_strip <= wbm_resp.dat;
      icolor1 <= {{MDW-32{1'b0}},color} << mb;
      rstcmd <= 1'b1;
      if (pcmd==2'b01)
        state <= ICOLOR3;
      else if (pcmd==2'b10)
        state <= ICOLOR2;
      else begin
        state <= WAITRST;
      end
      prev_state <= LOADSTRIP;
      if (prev_state != IDLE)
      	state <= IDLE;
    end
  // Registered inline mem2color
  ICOLOR3:
    begin
      color_o <= mem_strip >> mb;
      state <= ICOLOR4;
      prev_state <= ICOLOR3;
      if (prev_state != LOADSTRIP)
      	state <= IDLE;
    end
  ICOLOR4:
    begin
      for (n = 0; n < 32; n = n + 1)
        color_o[n] <= (n <= bpp) ? color_o[n] : 1'b0;
      state <= pcmd == 2'b0 ? (~wbm_resp.ack ? IDLE : WAITRST) : WAITRST;
      if (pcmd==2'b00)
        rstcmd <= 1'b0;
      prev_state <= ICOLOR4;
    end
  // Registered inline color2mem
  ICOLOR2:
    begin
      for (n = 0; n < MDW; n = n + 1)
        wbm_req.dat[n] <= (n >= mb && n <= me)
        	? ((n <= ce) ?	rastop(raster_op, mem_strip[n], icolor1[n]) : icolor1[n])
        	: mem_strip[n];
      if (prev_state != LOADSTRIP)
      	 state <= IDLE;
      else
      	state <= STORESTRIP;
      prev_state <= ICOLOR2;
    end
  STORESTRIP:
    if (~wbm_resp.ack) begin
    	wbm_req.tid <= 8'd3;
      vm_cyc_o <= HIGH;
      wbm_req.we <= HIGH;
      wbm_req.sel <= {MDW/8{1'b1}};
      vm_adr_o <= xyAddr;
      state <= ACKSTRIP;
   		prev_state <= STORESTRIP;
    end
    else begin
    	if (prev_state != ICOLOR2) begin
    		state <= IDLE;
    		prev_state <= STORESTRIP;
    		wb_nack();
    	end
    	else
    		state <= ACKSTRIP;
    end
  ACKSTRIP:
    if ((wbm_resp.ack && wbm_resp.tid==8'd3)||tocnt[8]) begin
      wb_nack();
      state <= pcmd == 2'b0 ? IDLE : WAITRST;
      if (pcmd==2'b00)
        rstcmd <= 1'b0;
      prev_state <= ACKSTRIP;
    end
  WAITLOAD1:
  	begin
    	wbm_req.tid <= 8'd0;
    	wbm_req.cti <= wishbone_pkg::INCR;
    	wbm_req.blen <= 6'd63;
 			vm_cyc_o <= HIGH;
      vm_adr_o <= adr;
      wbm_req.sel <= {MDW/8{1'b1}};
    	state <= WAITLOAD;
      prev_state <= WAITLOAD1;
  	end
  WAITLOAD:
  	begin
  		if (wbm_resp.ack) begin
  			vm_adr_o <= vm_adr_o + (MDW/8);
  			bcnt <= bcnt + 1'd1;
  		end
  		if (bcnt==7'd63) begin
  			wb_nack();
      	state <= IDLE;
      	prev_state <= WAITLOAD;
    	end
  	end
  LOAD_OOB:
  	begin
      state <= IDLE;
      prev_state <= LOAD_OOB;
  	end
  default:	state <= IDLE;
  endcase
end

task wb_nack;
begin
	m_fst_o <= LOW;
	wbm_req.cti <= wishbone_pkg::CLASSIC;
	wbm_req.blen <= 6'd0;
	vm_cyc_o <= LOW;
	wbm_req.we <= LOW;
	wbm_req.sel <= 32'h0000;
	vm_adr_o <= 32'h0;
end
endtask

reg [40:0] rgbo2,rgbo4;
reg [MDW-1:0] rgbo3;
always_ff @(posedge vclk)
case(color_depth2)
//BPP6:	rgbo4 <= {rgbo3[5:3],1'b0,33'd0,rgbo3[2:0]};	// feeds into palette
BPP8:	rgbo4 <= {rgbo3[7:5],1'b0,31'h0,rgbo3[4:0]};		// feeds into palette
//BPP12:	rgbo4 <= {rgbo3[11:9],1'b0,rgbo3[8:6],9'd0,rgbo3[5:3],9'd0,rgbo3[2:0],9'd0};
BPP16:	rgbo4 <= {rgbo3[15:13],1'b0,rgbo3[11:8],8'b0,rgbo3[7:4],8'b0,rgbo3[3:0],8'b0};
//BPP18:	rgbo4 <= {rgbo3[17:15],1'b0,rgbo3[14:10],7'b0,rgbo3[9:5],7'b0,rgbo3[4:0],7'b0};
//BPP21:	rgbo4 <= {rgbo3[20:18],1'b0,rgbo3[17:12],6'b0,rgbo3[11:6],6'b0,rgbo3[5:0],6'b0};
BPP24:	rgbo4 <= {rgbo3[23:21],1'b0,rgbo3[20:14],5'b0,rgbo3[13:7],5'b0,rgbo3[6:0],5'b0};
//BPP27:	rgbo4 <= {rgbo3[26:24],1'b0,rgbo3[23:16],4'b0,rgbo3[15:8],4'b0,rgbo3[7:0],4'b0};
BPP32:	rgbo4 <= {rgbo3[30:27],rgbo3[26:18],3'b0,rgbo3[17:9],3'b0,rgbo3[8:0],3'b0};
//BPP33:	rgbo4 <= {rgbo3[32:30],1'b0,rgbo3[29:20],2'b0,rgbo3[19:10],2'b0,rgbo3[9:0],2'b0};
//BPP36:	rgbo4 <= {rgbo3[35:33],1'b0,rgbo3[32:22],1'b0,rgbo3[21:11],1'b0,rgbo3[10:0],1'b0};
//BPP40:	rgbo4 <= {rgbo3[39:36],rgbo3[35:24],rgbo3[23:12],rgbo3[11:0]};
default:	rgbo4 <= {rgbo3[15:13],1'b0,rgbo3[11:8],8'b0,rgbo3[7:4],8'b0,rgbo3[3:0],8'b0};
endcase

reg rd_fifo,rd_fifo1,rd_fifo2;
reg de;
always_ff @(posedge vclk)
	if (rd_fifo1)
		de <= ~blank_i;

always_ff @(posedge vclk)
	if (onoff && xonoff_i && !blank_i) begin
		if (/*color_depth2==BPP6||*/color_depth2==BPP8) begin
			if (!greyscale)
				zrgb_o <= {pal_o[30:27],pal_o[26:18],3'b0,pal_o[17:9],3'b0,pal_o[8:0],3'b0};
			else
				zrgb_o <= {pal_o[31:28],{3{pal_o[11:0]}}};
		end
		else
			zrgb_o <= rgbo4;
	end
	else
		zrgb_o <= 40'h00000000;

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
//		BPP6:	rgbo3 <= {4'h0,rgbo3[MDW-1:6]};
		BPP8:	rgbo3 <= {8'h0,rgbo3[MDW-1:8]};
//		BPP12: rgbo3 <= {12'h0,rgbo3[MDW-1:12]};
		BPP16:	rgbo3 <= {16'h0,rgbo3[MDW-1:16]};
//		BPP18:	rgbo3 <= {18'h0,rgbo3[MDW-1:18]};
//		BPP21:	rgbo3 <= {21'h0,rgbo3[MDW-1:21]};
		BPP24:	rgbo3 <= {24'h0,rgbo3[MDW-1:24]};
//		BPP27:	rgbo3 <= {27'h0,rgbo3[MDW-1:27]};
		BPP32:	rgbo3 <= {32'h0,rgbo3[MDW-1:32]};
//		BPP33:	rgbo3 <= {33'h0,rgbo3[MDW-1:33]};
//		BPP36:	rgbo3 <= {33'h0,rgbo3[MDW-1:36]};
//		BPP40:	rgbo3 <= {33'h0,rgbo3[MDW-1:40]};
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
//BPP6:	oob_dat <= {MDW/6{oob_color[5:0]}};
BPP8:	oob_dat <= {MDW/8{oob_color[7:0]}};
//BPP12:	oob_dat <= {MDW/12{oob_color[11:0]}};
BPP16:	oob_dat <= {MDW/16{oob_color[15:0]}};
//BPP18:	oob_dat <= {MDW/18{oob_color[17:0]}};
//BPP21:	oob_dat <= {MDW/21{oob_color[20:0]}};
BPP24:	oob_dat <= {MDW/24{oob_color[23:0]}};
//BPP27:	oob_dat <= {MDW/27{oob_color[26:0]}};
BPP32:	oob_dat <= {MDW/32{oob_color[31:0]}};
//BPP33:	oob_dat <= {MDW/33{oob_color[32:0]}};
//BPP36:	oob_dat <= {MDW/33{oob_color[35:0]}};
//BPP40:	oob_dat <= {MDW/33{oob_color[39:0]}};
default:	oob_dat <= {MDW/16{oob_color[15:0]}};
endcase

rfVideoFifo #(MDW) uf1
(
	.wrst(fifo_wrst),
	.wclk(m_clk_i),
	.wr((((wbm_resp.ack|tocnt[10]) && wbm_resp.tid==8'd0) || state==LOAD_OOB) && lef),
	.di((state==LOAD_OOB) ? oob_dat : wbm_resp.dat),
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
	.wr((((wbm_resp.ack|tocnt[10]) && wbm_resp.tid==8'd0) || state==LOAD_OOB) && lof),
	.di((state==LOAD_OOB) ? oob_dat : wbm_resp.dat),
	.rrst(fifo_rrst),
	.rclk(vclk),
	.rd(rd_fifo & lef),
	.dout(rgbo1o),
	.cnt()
);

endmodule
