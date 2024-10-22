`timescale 1ns / 1ps
// ============================================================================
//        __
//   \\__/ o\    (C) 2006-2024  Robert Finch, Waterloo
//    \  __ /    All rights reserved.
//     \/_//     robfinch<remove>@finitron.ca
//       ||
//
//	rfTextController_fta32.sv
//		text controller
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
//	Text Controller
//
//	FEATURES
//
//	This core requires an external timing generator to provide horizontal
//	and vertical sync signals, but otherwise can be used as a display
//  controller on it's own. However, this core may also be embedded within
//  another core such as a VGA controller.
//
//	Window positions are referenced to the rising edge of the vertical and
//	horizontal sync pulses.
//
//	The core includes an embedded dual port RAM to hold the screen
//	characters.
//
//  The controller expects a 256kB memory region to be reserved.
//
//  Memory Map:
//  00000-0FFFF   display ram (64kB)
//  10000-13FFF   character bitmap ram (16kB)
//  1FF00-1FFFF   controller registers
//
//--------------------------------------------------------------------
// Registers
//
// 00h
//	7 - 0		         cccccccc  number of columns (horizontal displayed number of characters)
//	15- 8		         rrrrrrrr	 number of rows (vertical displayed number of characters)
//  19-16                dddd  character output delay
// 04h
//	11- 0       nnnn nnnnnnnn  window left       (horizontal sync position - reference for left edge of displayed)
//	27-16       nnnn nnnnnnnn  window top        (vertical sync position - reference for the top edge of displayed)
// 08h
//	 5- 0              nnnnnn  char height in pixels, maximum scan line
//  11- 8							   wwww	 pixel size - width 
//  15-12							   hhhh	 pixel size - height 
//  21-16              nnnnnn  char width in pixels
//  24                      r  reset state bit
// 0Ch
//   0                      e  controller enable
//   8                      m  multi-color mode
//   9                      a  anti-alias mode
//  16-20               nnnnn  yscroll
//  24-28               nnnnn  xscroll
// 10h
//	30- 0   cccccccc cccccccc  color code for transparent background RGB 4,9,9,9 (only RGB 7,7,7 used)
//  63-32   cccc...cccc        border color ZRGB 4,9,9,9
// 18h
//	30- 0   cccccccc cccccccc  tile color code 1
//  62-32   cccccccc cccccccc  tile color code 2
// 20h
//   4- 0               eeeee	 cursor end
//   7- 5                 bbb  blink control
//                             BP: 00=no blink
//                             BP: 01=no display
//                             BP: 10=1/16 field rate blink
//                             BP: 11=1/32 field rate blink
//  12- 8               sssss  cursor start
//  15-13									ttt	 cursor image type (none, box, underline, sidebar, checker, solid
// 24h
//  15- 0   aaaaaaaa aaaaaaaa	 cursor position
// 28h
//  15- 0   aaaaaaaa aaaaaaaa  start address (index into display memory)
// 30h
//  15- 0   aaaaaaaa aaaaaaaa  font address in char bitmap memory
//  31-24              dddddd  font ascent
// 34h
//  31- 0   nnnnnnnn nnnnnnnn  font ram lock "LOCK" or "UNLK"
//--------------------------------------------------------------------
//
// 1209 LUTs / 1003 FFs / 12 BRAMs / 1 DSP
// ============================================================================

`define VGA_800x600	1
//`define USE_CLOCK_GATE
//`define SUPPORT_AAM	1
import fta_bus_pkg::*;

module rfTextController_fta32 (
	rst_i, clk_i, cs_config_i, req, resp,
	dot_clk_i, hsync_i, vsync_i, blank_i, border_i, zrgb_i, zrgb_o, xonoff_i,
	hsync_o, vsync_o, blank_o, border_o
);
parameter num = 4'd1;
parameter COLS = 8'd64;
parameter ROWS = 8'd32;
parameter BUSWID = 32;
parameter TEXT_CELL_COUNT = 8192;
parameter INTERNAL_SYNCGEN = 1;

parameter RAM_ADDR = 32'hFEC00001;
parameter CBM_ADDR = 32'hFEC10001;
parameter REG_ADDR = 32'hFEC1FF01;
parameter RAM_ADDR_MASK = 32'hFFFF0000;
parameter CBM_ADDR_MASK = 32'hFFFF0000;
parameter REG_ADDR_MASK = 32'hFFFFFF00;

parameter CFG_BUS = 8'd0;
parameter CFG_DEVICE = 5'd1;
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
parameter CFG_IRQ_LINE = 8'hFF;

parameter ASYNCH = 1'b1;

`ifdef VGA_800x600
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

`ifdef WXGA_1366x768
// Needs 
//	Input clock:     85.86 MHz/4 (50 MHz * 12/7) (85.7142)/4
//	Input clock:     21.4286 MHz (100 MHz * 3/14)
//	Horizontal freq: 47.7 kHz	(generated) (47.619KHz)
//	Vertical freq:   60.00  Hz (generated)  (59.89 Hz)
parameter phSyncOn  = 18;		//   72 front porch
parameter phSyncOff = 54;		//  144 sync
parameter phBlankOff = 107;		//  212 back porch
parameter phBorderOff = 119;	//    0 border
parameter phBorderOn = 439;	// 1366 display
parameter phBlankOn = 450;		//    0 border
parameter phTotal = 450;		// 1800 total clocks
// 47.7 = 60 * 795 kHz
parameter pvSyncOn  = 2;		//    1 front porch
parameter pvSyncOff = 5;		//    3 vertical sync
parameter pvBlankOff = 27;		//   23 back porch
parameter pvBorderOff = 27;		//    2 border	0
parameter pvBorderOn = 795;		//  768 display
parameter pvBlankOn = 795;  	//    1 border	0
parameter pvTotal = 795;		//  795 total scan lines

`endif

localparam CFG_HEADER_TYPE = 8'h00;			// 00 = a general device

// Syscon
input  rst_i;			// reset
input  clk_i;			// clock

// Slave signals
input cs_config_i;
input fta_cmd_request32_t req;
output fta_cmd_response32_t resp;

// Video signals
input dot_clk_i;		// video dot clock
input hsync_i;			// end of scan line
input vsync_i;			// end of frame
input blank_i;			// blanking signal
input border_i;			// border area
input [31:0] zrgb_i;		// input pixel stream
output reg [31:0] zrgb_o;	// output pixel stream

output reg hsync_o;
output reg vsync_o;
output reg blank_o;
output reg border_o;

input xonoff_i;

integer n2,n3;

fta_cmd_response32_t resp1;
assign resp1.next = 1'b0;
assign resp1.stall = 1'b0;
assign resp1.err = fta_bus_pkg::OKAY;
assign resp1.rty = 1'b0;
assign resp1.pri = 4'd7;

reg controller_enable;
reg [31:0] bkColor40, bkColor40d, bkColor40d2, bkColor40d3;	// background color
reg [31:0] fgColor40, fgColor40d, fgColor40d2, fgColor40d3;	// foreground color

wire [1:0] pix;				// pixel value from character generator 1=on,0=off

reg por;
wire vclk;

reg cs_config;
fta_cmd_request32_t cfg_req;
fta_cmd_response32_t cfg_resp;
reg [31:0] rego;
reg [5:0] yscroll;
reg [5:0] xscroll;
reg [11:0] windowTop;
reg [11:0] windowLeft;
reg [ 7:0] numCols;
reg [ 7:0] numRows;
reg [ 7:0] charOutDelay;
reg [ 1:0] mode;
reg [ 5:0] maxRowScan;
reg [ 5:0] maxScanpix;
reg [1:0] tileWidth;		// width of tile in bytes (0=1,1=2,2=4,3=8)
reg [ 5:0] cursorStart, cursorEnd;
reg [15:0] cursorPos;
reg [2:0] cursorType;
reg [15:0] startAddress;
reg [15:0] fontAddress;
reg font_locked;
reg [5:0] fontAscent;
reg [ 2:0] rBlink;
reg [31:0] bdrColor;		// Border color
reg [ 3:0] pixelWidth;	// horizontal pixel width in clock cycles
reg [ 3:0] pixelHeight;	// vertical pixel height in scan lines
reg mcm;								// multi-color mode
reg aam;								// anti-alias mode

wire [11:0] hctr;		// horizontal reference counter (counts clocks since hSync)
wire [11:0] scanline;	// scan line
reg [ 7:0] row;		// vertical reference counter (counts rows since vSync)
reg [ 7:0] col;		// horizontal column
reg [ 5:0] rowscan;	// scan line within row
reg [ 5:0] colscan;	// pixel column number within cell
wire nxt_row;			// when to increment the row counter
wire nxt_col;			// when to increment the column counter
reg [ 5:0] bcnt;		// blink timing counter
wire blink;
reg  iblank;
reg [5:0] maxScanlinePlusOne;

wire nhp;				// next horizontal pixel
wire ld_shft = nxt_col & nhp;


// display and timing signals
reg [15:0] txtAddr;		// index into memory
reg [15:0] penAddr;
wire [31:0] screen_ram_out;		// character code
wire [23:0] txtBkColor;	// background color code
wire [23:0] txtFgColor;	// foreground color code
wire [5:0] txtZorder;
reg  [30:0] txtTcCode;	// transparent color code
reg [30:0] tileColor1;
reg [30:0] tileColor2;
reg  bgt, bgtd, bgtd2;

wire [31:0] tdat_o;
wire [31:0] chdat_o;
reg [31:0] cfg_dat [0:31];
reg [31:0] cfg_out;

function [31:0] fnRbo;
input n;
input [31:0] i;
	fnRbo = n ? {i[7:0],i[15:8],i[23:16],i[31:24]} : i;
endfunction

//--------------------------------------------------------------------
// bus interfacing
// Address Decoding
// I/O range Dx
//--------------------------------------------------------------------
// Register the inputs
reg cs_rom, cs_reg, cs_text, cs_any;
reg cs_rom1, cs_reg1, cs_text1;
reg erc;
wire cs_text2,cs_reg2,cs_rom2;
reg [31:0] radr_i;
reg [31:0] rdat_i;
reg rwr_i;
reg [7:0] rsel_i;
reg [7:0] wrs_i;
reg [31:0] tc_ram_addr;
reg [31:0] tc_cbm_addr;
reg [31:0] tc_reg_addr;
wire ack;

always_ff @(posedge clk_i)
	cs_config <= cs_config_i;
always_ff @(posedge clk_i)
	erc <= req.cti==fta_bus_pkg::ERC;
always_ff @(posedge clk_i)
begin
	cfg_req.cyc <= FALSE;
	if (req.cyc)
		cfg_req <= req;
end
always_comb
	cs_rom1 <= cs_rom2;
always_comb
	cs_reg1 <= cs_reg2;
always_comb
	cs_text1 <= cs_text2;
always_comb
	cs_rom <= cs_rom1 & ~cs_reg1;
always_comb
	cs_reg <= cs_reg1;
always_comb
	cs_text <= cs_text1;
always_ff @(posedge clk_i)
	wrs_i <= (BUSWID==64) ? {8{req.we}} & req.sel :
		req.padr[2] ? {{4{req.we}} & req.sel,4'h0} : {4'h0,{4{req.we}} & req.sel};
always_ff @(posedge clk_i)
	rwr_i <= req.we;
always_ff @(posedge clk_i)
	rsel_i <= req.sel;
always_ff @(posedge clk_i)
	radr_i <= req.padr;
always_ff @(posedge clk_i)
	rdat_i <= req.dat;

// Register outputs
always_ff @(posedge clk_i)
if (ack) begin
	casez({cs_rom,cs_reg,cs_text})
	3'b1??:	resp1.dat <= chdat_o;
	3'b01?:	resp1.dat <= rego;
	3'b001:	resp1.dat <= tdat_o;
	default:	;//resp1.dat <= {$bits(fta_cmd_response32_t){1'b0}};
	endcase
end
else
	resp1.dat <= {$bits(fta_cmd_response32_t){1'b0}};

assign resp = cfg_resp.ack ? cfg_resp : resp1;

//always @(posedge clk_i)
//	if (cs_text) begin
//		$display("TC WRite: %h %h", adr_i, dat_i);
//		$stop;
//	end

// - there is a four cycle latency for reads, an ack is generated
//   after the synchronous RAM read
// - writes can be acknowledged right away. If not recording errors no need to
//   ack a write

vtdl #(.WID(1), .DEP(16)) urdyd1 (.clk(clk_i), .ce(1'b1), .a(4'd3), .d(cs_rom|cs_reg|cs_text), .q(ack));
vtdl #(.WID(1), .DEP(16)) urdyd2 (.clk(clk_i), .ce(1'b1), .a(4'd4), .d((cs_rom|cs_reg|cs_text)&(erc|~rwr_i)), .q(resp1.ack));
//vtdl #(.WID(6), .DEP(16)) urdyd3 (.clk(clk_i), .ce(1'b1), .a(4'd5), .d(req.cid), .q(resp.cid));
vtdl #(.WID($bits(fta_tranid_t)), .DEP(16)) urdyd4 (.clk(clk_i), .ce(1'b1), .a(4'd5), .d(req.tid), .q(resp1.tid));
vtdl #(.WID($bits(fta_address_t)), .DEP(16)) urdyd5 (.clk(clk_i), .ce(1'b1), .a(4'd5), .d(req.padr), .q(resp1.adr));

//--------------------------------------------------------------------
// config
//--------------------------------------------------------------------

ddbb32_config #(
	.CFG_BUS(CFG_BUS),
	.CFG_DEVICE(CFG_DEVICE),
	.CFG_FUNC(CFG_FUNC),
	.CFG_VENDOR_ID(CFG_VENDOR_ID),
	.CFG_DEVICE_ID(CFG_DEVICE_ID),
	.CFG_BAR0(RAM_ADDR),
	.CFG_BAR0_MASK(RAM_ADDR_MASK),
	.CFG_BAR1(CBM_ADDR),
	.CFG_BAR1_MASK(CBM_ADDR_MASK),
	.CFG_BAR2(REG_ADDR),
	.CFG_BAR2_MASK(REG_ADDR_MASK),
	.CFG_SUBSYSTEM_VENDOR_ID(CFG_SUBSYSTEM_VENDOR_ID),
	.CFG_SUBSYSTEM_ID(CFG_SUBSYSTEM_ID),
	.CFG_ROM_ADDR(CFG_ROM_ADDR),
	.CFG_REVISION_ID(CFG_REVISION_ID),
	.CFG_PROGIF(CFG_PROGIF),
	.CFG_SUBCLASS(CFG_SUBCLASS),
	.CFG_CLASS(CFG_CLASS),
	.CFG_CACHE_LINE_SIZE(CFG_CACHE_LINE_SIZE),
	.CFG_MIN_GRANT(CFG_MIN_GRANT),
	.CFG_MAX_LATENCY(CFG_MAX_LATENCY)
)
ucfg1
(
	.rst_i(rst_i),
	.clk_i(clk_i),
	.cs_i(cs_config),
	.irq_i(1'b0),
	.req_i(cfg_req),
	.resp_o(cfg_resp),
	.cs_bar0_o(cs_text2),
	.cs_bar1_o(cs_rom2),
	.cs_bar2_o(cs_reg2)
);

//--------------------------------------------------------------------
//--------------------------------------------------------------------
`ifdef USE_CLOCK_GATE
BUFHCE ucb1 (.I(dot_clk_i), .CE(controller_enable), .O(vclk));
`else
assign vclk = dot_clk_i;
`endif

//--------------------------------------------------------------------
// Video Memory
//--------------------------------------------------------------------
//- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
// Address Calculation:
//  - Simple: the row times the number of  cols plus the col plus the
//    base screen address
//- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

reg [15:0] rowcol;
always_ff @(posedge vclk)
	txtAddr <= startAddress + rowcol + col;

// Register read-back memory
// This core to be found under Memory-Cores folder
// Allows reading back of register values by shadowing them with ram

wire [4:0] rrm_adr = radr_i[6:2];
wire [31:0] rrm_o;

regReadbackMem32 #(.WID(8)) rrm0L
(
  .wclk(clk_i),
  .adr(rrm_adr),
  .wce(cs_reg),
  .we(rwr_i & rsel_i[0]),
  .i(rdat_i[7:0]),
  .o(rrm_o[7:0])
);

regReadbackMem32 #(.WID(8)) rrm0H
(
  .wclk(clk_i),
  .adr(rrm_adr),
  .wce(cs_reg),
  .we(rwr_i & rsel_i[1]),
  .i(rdat_i[15:8]),
  .o(rrm_o[15:8])
);

regReadbackMem32 #(.WID(8)) rrm1L
(
  .wclk(clk_i),
  .adr(rrm_adr),
  .wce(cs_reg),
  .we(rwr_i & rsel_i[2]),
  .i(rdat_i[23:16]),
  .o(rrm_o[23:16])
);

regReadbackMem32 #(.WID(8)) rrm1H
(
  .wclk(clk_i),
  .adr(rrm_adr),
  .wce(cs_reg),
  .we(rwr_i & rsel_i[3]),
  .i(rdat_i[31:24]),
  .o(rrm_o[31:24])
);

wire [26:0] lfsr1_o;
lfsr27 #(.WID(27)) ulfsr1(rst_i, dot_clk_i, 1'b1, 1'b0, lfsr1_o);
wire [31:0] lfsr_o = {6'h10,2'b00,lfsr1_o[23:16],lfsr1_o[15:8],lfsr1_o[7:0]};

/* This snippit of code for performing burst accesses, under construction.
wire pe_cs;
edge_det u1(.rst(rst_i), .clk(clk_i), .ce(1'b1), .i(cs_text), .pe(pe_cs), .ne(), .ee() );

reg [14:0] ctr;
always @(posedge clk_i)
	if (pe_cs) begin
		if (cti_i==3'b000)
			ctr <= adr_i[16:3];
		else
			ctr <= adr_i[16:3] + 12'd1;
		cnt <= 3'b000;
	end
	else if (cs_text && cnt[2:0]!=3'b100 && cti_i!=3'b000) begin
		ctr <= ctr + 2'd1;
		cnt <= cnt + 3'd1;
	end

reg [13:0] radr;
always @(posedge clk_i)
	radr <= pe_cs ? adr_i[16:3] : ctr;
*/

//- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
// text screen RAM
//- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
rfTextScreenRam32 #(
	.TEXT_CELL_COUNT(TEXT_CELL_COUNT)	// 32kB
)
screen_ram1
(
	.clka_i(clk_i),
	.csa_i(cs_text),
	.wea_i(rwr_i),
	.sela_i(rsel_i),
	.adra_i(radr_i[15:2]),
	.data_i(rdat_i),
	.data_o(tdat_o),
	.clkb_i(vclk),
	.csb_i(ld_shft|por),
	.web_i(por),
	.selb_i(4'hF),
	.adrb_i(txtAddr[12:0]),
	.datb_i(lfsr_o),//txtAddr[12:0] > 13'd1664 ? lfsr_o1 : lfsr_o), 
	.datb_o(screen_ram_out)
);

//- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
// Character bitmap RAM (16kB)
// - room for 455 12x18 characters
//- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
wire [63:0] char_bmp;		// character ROM output

rfTextCharRam32 charRam0
(
	.clk_i(clk_i),
	.cs_i(cs_rom),
	.we_i(rwr_i & ~font_locked),
	.sel_i(rsel_i),
	.adr_i(radr_i[15:2]),
	.dat_i(rdat_i[31:0]),
	.dat_o(chdat_o),
	.dot_clk_i(vclk),
	.ce_i(ld_shft),
	.fontAddress_i(fontAddress),
	.char_code_i({1'd0,txtAddr[12:0]}),//{2'h0,screen_ram_out[25:24],screen_ram_out[7:0]}),
	.maxScanpix_i(maxScanpix),
	.maxscanline_i(maxScanlinePlusOne),
	.scanline_i(rowscan[5:0]),
	.bmp_o(char_bmp)
);

// pipeline delay - sync color with character bitmap output
reg [23:0] txtBkCode1;
reg [23:0] txtFgCode1;
reg [5:0] txtZorder1;
always_ff @(posedge vclk)
	if (ld_shft) txtBkCode1 <= {screen_ram_out[15:13],5'b0,screen_ram_out[12:10],5'b0,screen_ram_out[9:8],6'b0};
always_ff @(posedge vclk)
	if (ld_shft) txtFgCode1 <= {screen_ram_out[23:21],5'b0,screen_ram_out[20:18],5'b0,screen_ram_out[17:16],6'b0};
always_ff @(posedge vclk)
	if (ld_shft) txtZorder1 <= 6'd0;

//- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
// Register read port
//- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
always_comb
	if (cs_reg)
		rego <= rrm_o;
	else
		rego <= 32'h0000;


//- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
// Register write port
//- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

always_ff @(posedge clk_i)
	if (rst_i) begin
	  por <= 1'b1;
	  mcm <= 1'b0;
	  aam <= 1'b0;
	  controller_enable <= 1'b1;
    xscroll 		 <= 5'd0;
    yscroll 		 <= 5'd0;
    txtTcCode    <= 24'h1ff;
    bdrColor     <= 32'hFFBF2020;
    startAddress <= 16'h0000;
    fontAddress  <= 16'h0000;
    font_locked  <= 1'b1;
    fontAscent   <= 6'd12;
    cursorStart  <= 5'd00;
    cursorEnd    <= 5'd31;
    cursorPos    <= 16'h0003;
    cursorType 	 <= 3'd4;	// checker
// 104x63
/*
		windowTop    <= 12'd26;
		windowLeft   <= 12'd260;
		pixelWidth   <= 4'd0;
		pixelHeight  <= 4'd1;		// 525 pixels (408 with border)
*/
// 52x31
/*
		// 84x47
		windowTop    <= 12'd16;
		windowLeft   <= 12'd90;
		pixelWidth   <= 4'd1;		// 681 pixels
		pixelHeight  <= 4'd1;		// 384 pixels
*/
		// 64x32
		if (num==4'd1) begin
      windowTop    <= 12'd4058;//12'd16;
      windowLeft   <= 12'd3918;//12'd3956;//12'd86;
      pixelWidth   <= 4'd0;		// 800 pixels
      pixelHeight  <= 4'd0;		// 600 pixels
      numCols      <= COLS;
      numRows      <= ROWS;
      maxRowScan   <= 6'd17;
      maxScanpix   <= 6'd11;
      rBlink       <= 3'b111;		// 01 = non display
      charOutDelay <= 8'd5;
		end
		else if (num==4'd2) begin
      windowTop    <= 12'd4032;//12'd16;
      windowLeft   <= 12'd3720;//12'd86;
      pixelWidth   <= 4'd0;        // 800 pixels
      pixelHeight  <= 4'd0;        // 600 pixels
      numCols      <= 40;
      numRows      <= 25;
      maxRowScan   <= 5'd7;
      maxScanpix   <= 6'd7;
      rBlink       <= 3'b111;        // 01 = non display
      charOutDelay <= 8'd6;
		end
	end
	else begin
		
		if (bcnt > 6'd10)
			por <= 1'b0;
		
		if (cs_reg & rwr_i) begin	// register write ?
			$display("TC Write: r%d=%h", rrm_adr, rdat_i);
			case(rrm_adr)
			4'd0:
				begin
					if (rsel_i[0]) numCols    <= rdat_i[7:0];
					if (rsel_i[1]) numRows    <= rdat_i[15:8];
					if (rsel_i[2]) charOutDelay <= rdat_i[23:16];
				end
			4'd1:
				begin
					if (rsel_i[0]) windowLeft[7:0] <= rdat_i[7:0];
					if (rsel_i[1]) windowLeft[11:8] <= rdat_i[11:8];
					if (rsel_i[2]) windowTop[7:0]  <= rdat_i[23:16];
					if (rsel_i[3]) windowTop[11:8]  <= rdat_i[27:24];
				end
			4'd2:
				begin
					if (rsel_i[0]) maxRowScan <= rdat_i[4:0];
					if (rsel_i[1]) begin
						pixelHeight <= rdat_i[15:12];
						pixelWidth  <= rdat_i[11:8];	// horizontal pixel width
					end
					if (rsel_i[2]) maxScanpix <= rdat_i[20:16];
					if (rsel_i[3]) por <= rdat_i[24];
				end
			4'd3:
				begin
					if (rsel_i[0]) controller_enable <= rdat_i[0];
					if (rsel_i[1])
						begin
						 	mcm <= rdat_i[8];
						 	aam <= rdat_i[9];
						end
					if (rsel_i[2]) yscroll <= rdat_i[20:16];
					if (rsel_i[3]) xscroll <= rdat_i[28:24];
				end
			4'd4:	// Color Control
				begin
					if (rsel_i[0]) txtTcCode[7:0] <= rdat_i[7:0];
					if (rsel_i[1]) txtTcCode[15:8] <= rdat_i[15:8];
					if (rsel_i[2]) txtTcCode[23:16] <= rdat_i[23:16];
				end
			4'd5:
				begin
					if (rsel_i[0]) bdrColor[7:0] <= rdat_i[7:0];
					if (rsel_i[1]) bdrColor[15:8] <= rdat_i[15:8];
					if (rsel_i[2]) bdrColor[23:16] <= rdat_i[23:16];
				end
			4'd6:	// Color Control 2
				begin
					if (rsel_i[0]) tileColor1[7:0] <= rdat_i[7:0];
					if (rsel_i[1]) tileColor1[15:8] <= rdat_i[15:8];
					if (rsel_i[2]) tileColor1[23:16] <= rdat_i[23:16];
				end
			4'd7:
				begin
					if (rsel_i[0]) tileColor2[7:0] <= rdat_i[7:0];
					if (rsel_i[1]) tileColor2[15:8] <= rdat_i[15:8];
					if (rsel_i[2]) tileColor2[23:16] <= rdat_i[23:16];
				end
			4'd8:	// Cursor Control
				begin
					if (rsel_i[0]) begin
						cursorEnd <= rdat_i[4:0];	// scan line sursor starts on
						rBlink      <= rdat_i[7:5];
					end
					if (rsel_i[1]) begin
						cursorStart <= rdat_i[12:8];	// scan line cursor ends on
						cursorType  <= rdat_i[15:13];
					end
				end
			4'd9:
				begin
					if (rsel_i[0]) cursorPos[7:0] <= rdat_i[7:0];
					if (rsel_i[1]) cursorPos[15:8] <= rdat_i[15:8];
				end
			4'd10:	// Page flipping / scrolling
				begin
					if (rsel_i[0]) startAddress[7:0] <= rdat_i[7:0];
					if (rsel_i[1]) startAddress[15:8] <= rdat_i[15:8];
				end
			4'd12:	// 
				begin
					if (rsel_i[0]) fontAddress[7:0] <= rdat_i[7:0];
					if (rsel_i[1]) fontAddress[15:8] <= rdat_i[15:8];
					if (rsel_i[3]) fontAscent[5:0] <= rdat_i[5:0];
				end
			4'd13:
				begin
					if (&rsel_i[3:0]) begin
						if (rdat_i[31:0]=="LOCK")
							font_locked <= 1'b1;
						else if (rdat_i[31:0]=="UNLK")
							font_locked <= 1'b0;
					end
				end
			default: ;
			endcase
		end
	end


//--------------------------------------------------------------------
// Cursor image is computed based on the font size, so the available
// hardware cursors are really simple. More sophisticated hardware
// cursors can be had via the sprite controller.
//--------------------------------------------------------------------

reg [31:0] curout;
wire [31:0] curout1;
always_ff @(posedge vclk)
if (ld_shft) begin
	curout = 'd0;
	case(cursorType)
	// No cursor
	3'd0:	;
	// "Box" cursor
	3'd1:
		begin
			case(rowscan)
			maxRowScan,5'd0: curout = 32'hFFFFFFFF;
			/*
			maxRowScan-1:
				if (rowscan==maxRowScan-1) begin
					curout[maxScanpix[5:1]] = 1'b1;
					curout[maxScanpix[5:1]+1] = 1'b1;
				end
			*/
			default:
				begin
					curout[maxScanpix] = 1'b1;
					curout[0] = 1'b1;
				end
			endcase
		end
	// Vertical Line cursor
	3'd2:	curout[maxScanpix] = 1'b1;
	// Underline cursor
	3'd3:
		if (rowscan==fontAscent)
			curout = 32'hFFFFFFFF;
	// Checker cursor
	3'd4:	curout = rowscan[1] ? 32'h33333333 : 32'hCCCCCCCC;
	// Solid cursor
	3'd7:	curout = 32'hFFFFFFFF;
	default:	curout = 32'hFFFFFFFF;
	endcase
end

ft_delay
#(
	.WID(32),
	.DEP(3)
)
uftd1
(
	.clk(vclk),
	.ce(ld_shft),
	.i(curout),
	.o(curout1)
);

//-------------------------------------------------------------
// Video Stuff
//-------------------------------------------------------------

wire pe_hsync;
wire pe_vsync;
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

// We generally don't care about the exact reset point, unless debugging in
// simulation. The counters will eventually cycle to a proper state. A little
// bit of logic / routing can be avoided by omitting the reset.
`ifdef SIM
wire sym_rst = rst_i;
`else
wire sym_rst = 1'b0;
`endif

// Raw scanline counter
vid_counter #(12) u_vctr (.rst(sym_rst), .clk(vclk), .ce(pe_hsync), .ld(pe_vsync), .d(windowTop), .q(scanline), .tc());
vid_counter #(12) u_hctr (.rst(sym_rst), .clk(vclk), .ce(1'b1), .ld(pe_hsync), .d(windowLeft), .q(hctr), .tc());

// Vertical pixel height counter, synchronized to scanline #0
reg [3:0] vpx;
wire nvp = vpx==pixelHeight;
always @(posedge vclk)
if (sym_rst)
	vpx <= 4'b0;
else begin
	if (pe_hsync) begin
		if (scanline==12'd0)
			vpx <= 4'b0;
		else if (nvp)
			vpx <= 4'd0;
		else
			vpx <= vpx + 4'd1;
	end
end

reg [3:0] hpx;
assign nhp = hpx==pixelWidth;
always @(posedge vclk)
if (sym_rst)
	hpx <= 4'b0;
else begin
	if (hctr==12'd0)
		hpx <= 4'b0;
	else if (nhp)
		hpx <= 4'd0;
	else
		hpx <= hpx + 4'd1;
end

// The scanline row within a character bitmap
always @(posedge vclk)
if (sym_rst)
	rowscan <= 5'd0;
else begin
	if (pe_hsync & nvp) begin
		if (scanline==12'd0)
			rowscan <= yscroll;
		else if (rowscan==maxRowScan)
			rowscan <= 5'd0;
		else
			rowscan <= rowscan + 5'd1;
	end
end

assign nxt_col = colscan==maxScanpix;
always @(posedge vclk)
if (sym_rst)
	colscan <= 5'd0;
else begin
	if (nhp) begin
		if (hctr==12'd0)
			colscan <= xscroll;
		else if (nxt_col)
			colscan <= 5'd0;
		else
			colscan <= colscan + 5'd1;
	end
end

// The screen row
always @(posedge vclk)
if (sym_rst)
	row <= 8'd0;
else begin
	if (pe_hsync & nvp) begin
		if (scanline==12'd0)
			row <= 8'd0;
		else if (rowscan==maxRowScan)
			row <= row + 8'd1;
	end
end

// The screen column
always @(posedge vclk)
if (sym_rst)
	col <= 8'd0;
else begin
	if (hctr==12'd0)
		col <= 8'd0;
	else if (nhp) begin
		if (nxt_col)
			col <= col + 8'd1;
	end
end

// More useful, the offset of the start of the text display on a line.
always @(posedge vclk)
if (sym_rst)
	rowcol <= 16'd0;
else begin
	if (pe_hsync & nvp) begin
		if (scanline==12'd0)
			rowcol <= 8'd0;
		else if (rowscan==maxRowScan)
			rowcol <= rowcol + numCols;
	end
end

// Takes 3 clock for scanline to become stable, but should be stable before any
// chars are displayed.
reg [13:0] rxmslp1;
always_ff @(posedge vclk)
	maxScanlinePlusOne <= maxRowScan + 4'd1;


// Blink counter
//
always_ff @(posedge vclk)
if (sym_rst)
	bcnt <= 6'd0;
else begin
	if (pe_vsync)
		bcnt <= bcnt + 6'd1;
end

reg blink_en;
always_ff @(posedge vclk)
	blink_en <= (cursorPos+charOutDelay-2'd1==txtAddr);// && (rowscan[4:0] >= cursorStart) && (rowscan[4:0] <= cursorEnd);

VT151 ub2
(
	.e_n(!blink_en),
	.s(rBlink),
	.i0(1'b1), .i1(1'b0), .i2(bcnt[4]), .i3(bcnt[5]),
	.i4(1'b1), .i5(1'b0), .i6(bcnt[4]), .i7(bcnt[5]),
	.z(blink),
	.z_n()
);

always_ff @(posedge vclk)
	if (ld_shft)
		bkColor40 <= {2'b0,txtBkCode1[23:16],2'b0,txtBkCode1[15:8],2'b0,txtBkCode1[7:0],2'b0};
always_ff @(posedge vclk)
	if (ld_shft)
		bkColor40d <= bkColor40;
always_ff @(posedge vclk)
	if (ld_shft)
		bkColor40d2 <= bkColor40d;
always_ff @(posedge vclk)
	if (nhp)
		bkColor40d3 <= bkColor40d2;
always_ff @(posedge vclk)
	if (ld_shft)
		fgColor40 <= {2'b0,txtFgCode1[23:16],2'b0,txtFgCode1[15:8],2'b0,txtFgCode1[7:0],2'b0};
always_ff @(posedge vclk)
	if (ld_shft)
		fgColor40d <= fgColor40;
always_ff @(posedge vclk)
	if (ld_shft)
		fgColor40d2 <= fgColor40d;
always_ff @(posedge vclk)
	if (nhp)
		fgColor40d3 <= fgColor40d2;

always_ff @(posedge vclk)
	if (ld_shft)
		bgt <= txtBkCode1=={txtTcCode[23:16],txtTcCode[15:8],txtTcCode[7:0]};
always_ff @(posedge vclk)
	if (ld_shft)
		bgtd <= bgt;
always_ff @(posedge vclk)
	if (nhp)
		bgtd2 <= bgtd;

// Convert character bitmap to pixels
reg [63:0] charout1;
always_ff @(posedge vclk)
	charout1 <= blink ? (char_bmp ^ curout1) : char_bmp;

// Convert parallel to serial
rfTextShiftRegister ups1
(
	.rst(rst_i),
	.clk(vclk),
	.mcm(mcm),
//	.aam(aam),
	.ce(nhp),
	.ld(ld_shft),
	.a(maxScanpix[5:0]),
	.qin(2'b0),
	.d(charout1),
	.qh(pix)
);

// Pipelining Effect:
// - character output is delayed by 2 or 3 character times relative to the video counters
//   depending on the resolution selected
// - this means we must adapt the blanking signal by shifting the blanking window
//   two or three character times.
wire bpix = hctr[2] ^ rowscan[4];// ^ blink;
always_ff @(posedge vclk)
	if (nhp)	
		iblank <= (row >= numRows) || (col >= numCols + charOutDelay) || (col < charOutDelay);

`ifdef SUPPORT_AAM
function [9:0] fnBlendComponent;
input [9:0] c1;
input [9:0] c2;
input [1:0] pix;
case(pix)
2'b00:	fnBlendComponent = c2;
2'b01:	fnBlendComponent = ((c1 * 4'd5) + (c2 * 4'd11)) >> 4;
2'b10:	fnBlendComponent = ((c1 * 4'd11) + (c2 * 4'd5)) >> 4;
2'b11:	fnBlendComponent = c1;
endcase
endfunction

function [31:0] fnBlend;
input [31:0] c1;
input [31:0] c2;
input [1:0] pix;
fnBlend = {
	|pix ? c1[31:30] : c2[31:30],
	fnBlendComponent(c1[29:20],c2[29:20]),
	fnBlendComponent(c1[19:10],c2[19:10]),
	fnBlendComponent(c1[ 9: 0],c2[ 9: 0])
};
endfunction
`endif

// Choose between input RGB and controller generated RGB
// Select between foreground and background colours.
// Note the ungated dot clock must be used here, or output from other
// controllers would not be visible if the clock were gated off.
always_ff @(posedge dot_clk_i)
	casez({controller_enable&xonoff_i,blank_o,iblank,border_o,bpix,mcm,aam,pix})
	9'b01???????:	zrgb_o <= zrgb_i;
	9'b11???????:	zrgb_o <= 32'h00000000;
	9'b1001?????:	zrgb_o <= {2'b0,bdrColor[23:16],2'b0,bdrColor[15:8],2'b0,bdrColor[7:0],2'b0};
`ifdef SUPPORT_AAM	
	9'b1000?01??:	zrgb_o <= fnBlend(fgColor40d3, bgtd2 ? zrgb_i : bkColor40d3, pix);
`endif	
	9'b1000?000?:	zrgb_o <= bgtd2 ? zrgb_i : bkColor40d3;
	9'b1000?001?:	zrgb_o <= fgColor40d3; // ToDo: compare z-order
	9'b1000?1000:	zrgb_o <= bgtd2 ? zrgb_i : bkColor40d3;
	9'b1000?1001:	zrgb_o <= fgColor40d3;
	9'b1000?1010:	zrgb_o <= {2'b0,tileColor1[23:16],2'b0,tileColor1[15:8],2'b0,tileColor1[7:0],2'b0};
	9'b1000?1011:	zrgb_o <= {2'b0,tileColor2[23:16],2'b0,tileColor2[15:8],2'b0,tileColor2[7:0],2'b0};
//	6'b1010?0:	zrgb_o <= bgtd ? zrgb_i : bkColor32d;
	default:	zrgb_o <= zrgb_i;
	endcase

// ----------------------------------------------------------------------------
// SYNC generator
// ----------------------------------------------------------------------------

generate begin : gSyncgen
if (INTERNAL_SYNCGEN) begin

wire dot_clk = dot_clk_i;
wire [11:0] hCtr, vCtr;
reg hBlank1;
wire vBlank1;
wire hSync1,vSync1;
reg hBorder1,vBorder1,hBorder2;
reg vblank;
reg eof;
reg eol;

wire eol1 = hCtr==phTotal;
wire eof1 = vCtr==pvTotal;

assign vSync1 = vCtr >= pvSyncOn && vCtr < pvSyncOff;
assign hSync1 = hCtr >= phSyncOn && hCtr < phSyncOff;
assign vBlank1 = vCtr >= pvBlankOn || vCtr < pvBlankOff;
assign vBorder1 = vCtr >= pvBorderOn || vCtr < pvBorderOff;

counter #(12) u1syncgen (.rst(rst), .clk(dot_clk), .ce(1'b1), .ld(eol1), .d(12'd1), .q(hCtr), .tc() );
counter #(12) u2syncgen (.rst(rst), .clk(dot_clk), .ce(eol1), .ld(eof1), .d(12'd1), .q(vCtr), .tc() );
counter #(6)  u3syncgen (.rst(rst), .clk(dot_clk), .ce(eof1), .ld(1'b0), .d(6'd1), .q(frame_cnt), .tc() );

always @(posedge dot_clk)
if (rst)
  hBlank1 <= 1'b0;
else begin
  if (hCtr==phBlankOn)
    hBlank1 <= 1'b1;
  else if (hCtr==phBlankOff)
    hBlank1 <= 1'b0;
end

modHborder u4syncgen
(
	.rst(rst),
	.dot_clk(dot_clk),
	.hCtr(hCtr), 
	.border_on(phBorderOn),
	.border_off(phBorderOff),
	.border(hBorder1)
);

// Register signals.

always @(posedge dot_clk_i)
  border_o <= #1 hBorder1|vBorder1;
always @(posedge dot_clk_i)
  blank_o <= #1 hBlank1|vBlank1;
always @(posedge dot_clk_i)
  vblank <= #1 vBlank1;
always @(posedge dot_clk_i)
	hsync_o <= #1 hSync1;
always @(posedge dot_clk_i)
	vsync_o <= #1 vSync1;
always @(posedge dot_clk_i)
  eof <= eof1;
always @(posedge dot_clk_i)
  eol <= eol1;
//always @(posedge dot_clk)
//  vbl_irq <= hCtr==8'd1 && vCtr==pvBlankOn;
end
else begin
	always_comb vsync_o = vsync_i;
	always_comb hsync_o = hsync_i;
	always_comb blank_o = blank_i;
	always_comb border_o = border_i;
end
end
endgenerate

endmodule

// Horizontal border timing

module modHborder(rst, dot_clk, hCtr, border_on, border_off, border);
input rst;
input dot_clk;
input [11:0] hCtr;
input [11:0] border_on;
input [11:0] border_off;
output reg border;

always @(posedge dot_clk)
if (rst)
  border <= 1'b0;
else begin
	if (hCtr==border_on)
	  border <= 1'b1;
	else if (hCtr==border_off)
	  border <= 1'b0;
end
endmodule

