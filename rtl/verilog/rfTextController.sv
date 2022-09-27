// ============================================================================
//        __
//   \\__/ o\    (C) 2006-2022  Robert Finch, Waterloo
//    \  __ /    All rights reserved.
//     \/_//     robfinch<remove>@finitron.ca
//       ||
//
//	rfTextController.sv
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
//  The controller expects a 128kB memory region to be reserved.
//
//  Memory Map:
//  00000-0FFFF   display ram
//  10000-1FEFF   character bitmap ram
//  1FF00-1FFFF   controller registers
//
//--------------------------------------------------------------------
// Registers
//
// 00h
//	7 - 0		         cccccccc  number of columns (horizontal displayed number of characters)
//	15- 8		         rrrrrrrr	 number of rows (vertical displayed number of characters)
//  19-16                dddd  character output delay
//	43-32       nnnn nnnnnnnn  window left       (horizontal sync position - reference for left edge of displayed)
//	59-48       nnnn nnnnnnnn  window top        (vertical sync position - reference for the top edge of displayed)
// 01h
//	 4- 0               nnnnn  char height in pixels, maximum scan line (char ROM max value is 7)
//  11- 8							   wwww	 pixel size - width 
//  15-12							   hhhh	 pixel size - height 
//  20-16               nnnnn  char width in pixels
//  24                      r  reset state bit
//  32                      e  controller enable
//  40                      m  multi-color mode
//  48-52               nnnnn  yscroll
//  56-60               nnnnn  xscroll
// 02h
//	30- 0   cccccccc cccccccc  color code for transparent background RGB 9,9,9,4 (only RGB 7,7,7 used)
//  63-32   cccc...cccc        border color ZRGB 9,9,9,4
// 03h
//	30- 0   cccccccc cccccccc  tile color code 1
//  62-32   cccccccc cccccccc  tile color code 2
// 04h
//   4- 0               eeeee	 cursor end
//   7- 5                 bbb  blink control
//                             BP: 00=no blink
//                             BP: 01=no display
//                             BP: 10=1/16 field rate blink
//                             BP: 11=1/32 field rate blink
//  12- 8               sssss  cursor start
//  15-14									 tt	 cursor image type (box, underline, sidebar, asterisk
//  47-32   aaaaaaaa aaaaaaaa	 cursor position
// 05h
//  15- 0   aaaaaaaa aaaaaaaa  start address (index into display memory)
// 06h
//  15- 0   aaaaaaaa aaaaaaaa  font address in char bitmap memory
//  63-32   nnnnnnnn nnnnnnnn  font ram lock "LOCK" or "UNLK"
//--------------------------------------------------------------------
//
// ============================================================================

//`define USE_CLOCK_GATE

module rfTextController(
	rst_i, clk_i, cs_i,
	cti_i, cyc_i, stb_i, ack_o, wr_i, sel_i, adr_i, dat_i, dat_o,
	dot_clk_i, hsync_i, vsync_i, blank_i, border_i, zrgb_i, zrgb_o, xonoff_i
);
parameter num = 4'd1;
parameter COLS = 8'd64;
parameter ROWS = 8'd32;
parameter BUSWID = 64;


// Syscon
input  rst_i;			// reset
input  clk_i;			// clock

// Slave signals
input  cs_i;            // circuit select
input  [2:0] cti_i;
input  cyc_i;				// valid bus cycle
input  stb_i;       // data strobe
output ack_o;				// data acknowledge
input  wr_i;				// write
input  [BUSWID/8-1:0] sel_i;	// byte lane select
input  [16:0] adr_i;	// address
input  [BUSWID-1:0] dat_i;			// data input
output reg [BUSWID-1:0] dat_o;	// data output

// Video signals
input dot_clk_i;		// video dot clock
input hsync_i;			// end of scan line
input vsync_i;			// end of frame
input blank_i;			// blanking signal
input border_i;			// border area
input [39:0] zrgb_i;		// input pixel stream
output reg [39:0] zrgb_o;	// output pixel stream
input xonoff_i;

reg controller_enable;
reg [39:0] bkColor40, bkColor40d;	// background color
reg [39:0] fgColor40, fgColor40d;	// foreground color

wire [1:0] pix;				// pixel value from character generator 1=on,0=off

reg por;
wire vclk;
assign txt_clk_o = vclk;
assign txt_we_o = por;
assign txt_sel_o = 8'hFF;
assign cbm_clk_o = vclk;
assign cbm_we_o = 1'b0;
assign cbm_sel_o = 8'hFF;

reg [63:0] rego;
reg [4:0] yscroll;
reg [5:0] xscroll;
reg [11:0] windowTop;
reg [11:0] windowLeft;
reg [ 7:0] numCols;
reg [ 7:0] numRows;
reg [ 7:0] charOutDelay;
reg [ 1:0] mode;
reg [ 4:0] maxRowScan;
reg [ 5:0] maxScanpix;
reg [1:0] tileWidth;		// width of tile in bytes (0=1,1=2,2=4,3=8)
reg [ 4:0] cursorStart, cursorEnd;
reg [15:0] cursorPos;
reg [1:0] cursorType;
reg [15:0] startAddress;
reg [15:0] fontAddress;
reg font_locked;
reg [ 2:0] rBlink;
reg [31:0] bdrColor;		// Border color
reg [ 3:0] pixelWidth;	// horizontal pixel width in clock cycles
reg [ 3:0] pixelHeight;	// vertical pixel height in scan lines
reg mcm;								// multi-color mode

wire [11:0] hctr;		// horizontal reference counter (counts clocks since hSync)
wire [11:0] scanline;	// scan line
reg [ 7:0] row;		// vertical reference counter (counts rows since vSync)
reg [ 7:0] col;		// horizontal column
reg [ 4:0] rowscan;	// scan line within row
reg [ 5:0] colscan;	// pixel column number within cell
wire nxt_row;			// when to increment the row counter
wire nxt_col;			// when to increment the column counter
reg [ 5:0] bcnt;		// blink timing counter
wire blink;
reg  iblank;
reg [4:0] maxScanlinePlusOne;

wire nhp;				// next horizontal pixel
wire ld_shft = nxt_col & nhp;


// display and timing signals
reg [15:0] txtAddr;		// index into memory
reg [15:0] penAddr;
wire [63:0] screen_ram_out;		// character code
wire [20:0] txtBkColor;	// background color code
wire [20:0] txtFgColor;	// foreground color code
wire [5:0] txtZorder;
reg  [30:0] txtTcCode;	// transparent color code
reg [30:0] tileColor1;
reg [30:0] tileColor2;
reg  bgt, bgtd;

wire [63:0] tdat_o;
wire [8:0] chdat_o;

wire [2:0] scanindex = rowscan[2:0];

//--------------------------------------------------------------------
// bus interfacing
// Address Decoding
// I/O range Dx
//--------------------------------------------------------------------
// Register the inputs
reg cs_rom, cs_reg, cs_text, cs_any;
reg [16:0] radr_i;
reg [63:0] rdat_i;
reg rwr_i;
reg [7:0] rsel_i;
reg [7:0] wrs_i;
always_ff @(posedge clk_i)
	cs_rom <= cs_i && cyc_i && stb_i && (adr_i[16:8] >= 9'h100 && adr_i[16:8] < 9'h1FF);
always_ff @(posedge clk_i)
	cs_reg <= cs_i && cyc_i && stb_i && (adr_i[16:8] == 9'h1FF);
always_ff @(posedge clk_i)
	cs_text <= cs_i && cyc_i && stb_i && (adr_i[16:8] < 9'h100);
always_ff @(posedge clk_i)
	cs_any <= cs_i && cyc_i && stb_i;
always_ff @(posedge clk_i)
	wrs_i <= BUSWID==64 ? {8{wr_i}} & sel_i :
		adr_i[2] ? {{4{wr_i}} & sel_i,4'h0} : {4'h0,{4{wr_i}} & sel_i};
always_ff @(posedge clk_i)
	rwr_i <= wr_i;
always_ff @(posedge clk_i)
	rsel_i <= BUSWID==64 ? sel_i : adr_i[2] ? {sel_i,4'h0} : {4'h0,sel_i};
always_ff @(posedge clk_i)
	radr_i <= adr_i;
always_ff @(posedge clk_i)
	rdat_i <= BUSWID==64 ? dat_i : {2{dat_i}};

// Register outputs
always @(posedge clk_i)
if (BUSWID==64)
	casez({cs_rom,cs_reg,cs_text})
	3'b1??:	dat_o <= {8{chdat_o}};
	3'b01?:	dat_o <= rego;
	3'b001:	dat_o <= tdat_o;
	default:	dat_o <= 'h0;
	endcase
else if (BUSWID==32)
	casez({cs_rom,cs_reg,cs_text})
	3'b1??:	dat_o <= {4{chdat_o}};
	3'b01?:	dat_o <= radr_i[2] ? rego[63:32] : rego[31:0];
	3'b001:	dat_o <= radr_i[2] ? tdat_o[63:32] : tdat_o[31:0];
	default:	dat_o <= 'd0;
	endcase
else
	dat_o <= 'd0;

//always @(posedge clk_i)
//	if (cs_text) begin
//		$display("TC WRite: %h %h", adr_i, dat_i);
//		$stop;
//	end

// - there is a four cycle latency for reads, an ack is generated
//   after the synchronous RAM read
// - writes can be acknowledged right away.

ack_gen #(
	.READ_STAGES(5),
	.WRITE_STAGES(1),
	.REGISTER_OUTPUT(1)
)
uag1 (
	.clk_i(clk_i),
	.ce_i(1'b1),
	.i(cs_any),
	.we_i(cs_any & rwr_i),
	.o(ack_o),
	.rid_i(0),
	.wid_i(0),
	.rid_o(),
	.wid_o()
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

wire [3:0] rrm_adr = radr_i[6:3];
wire [63:0] rrm_o;

regReadbackMem #(.WID(8)) rrm0L
(
  .wclk(clk_i),
  .adr(rrm_adr),
  .wce(cs_reg),
  .we(rwr_i & rsel_i[0]),
  .i(rdat_i[7:0]),
  .o(rrm_o[7:0])
);

regReadbackMem #(.WID(8)) rrm0H
(
  .wclk(clk_i),
  .adr(rrm_adr),
  .wce(cs_reg),
  .we(rwr_i & rsel_i[1]),
  .i(rdat_i[15:8]),
  .o(rrm_o[15:8])
);

regReadbackMem #(.WID(8)) rrm1L
(
  .wclk(clk_i),
  .adr(rrm_adr),
  .wce(cs_reg),
  .we(rwr_i & rsel_i[2]),
  .i(rdat_i[23:16]),
  .o(rrm_o[23:16])
);

regReadbackMem #(.WID(8)) rrm1H
(
  .wclk(clk_i),
  .adr(rrm_adr),
  .wce(cs_reg),
  .we(rwr_i & rsel_i[3]),
  .i(rdat_i[31:24]),
  .o(rrm_o[31:24])
);

regReadbackMem #(.WID(8)) rrm2L
(
  .wclk(clk_i),
  .adr(rrm_adr),
  .wce(cs_reg),
  .we(rwr_i & rsel_i[4]),
  .i(rdat_i[39:32]),
  .o(rrm_o[39:32])
);

regReadbackMem #(.WID(8)) rrm2H
(
  .wclk(clk_i),
  .adr(rrm_adr),
  .wce(cs_reg),
  .we(rwr_i & rsel_i[5]),
  .i(rdat_i[47:40]),
  .o(rrm_o[47:40])
);

regReadbackMem #(.WID(8)) rrm3L
(
  .wclk(clk_i),
  .adr(rrm_adr),
  .wce(cs_reg),
  .we(rwr_i & rsel_i[6]),
  .i(rdat_i[55:48]),
  .o(rrm_o[55:48])
);

regReadbackMem #(.WID(8)) rrm3H
(
  .wclk(clk_i),
  .adr(rrm_adr),
  .wce(cs_reg),
  .we(rwr_i & rsel_i[7]),
  .i(rdat_i[63:56]),
  .o(rrm_o[63:56])
);

wire [23:0] lfsr1_o;
lfsr #(24) ulfsr1(rst_i, dot_clk_i, 1'b1, 1'b0, lfsr1_o);
wire [63:0] lfsr_o = {6'h20,
												lfsr1_o[23:21],4'b0,lfsr1_o[20:18],4'b0,lfsr1_o[17:16],5'b0,
												lfsr1_o[15:13],4'b0,lfsr1_o[12:10],4'b0,lfsr1_o[9:8],5'b0,
												8'h00,lfsr1_o[7:0]
										};
assign m_dat_o = lfsr_o;									

/*
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
// text screen RAM
wire [13:0] bram_adr = radr_i[16:3];

// Generated using block RAM generator tool from ip catalogue.
// True dual-port RAM using independent clocks
// 8192 deep by 64 bits wide, with 8 bit byte write enables.
// Using primitives output register, so read latency is two.
syncRam8kx64 screen_ram1
(
  .clka(clk_i),
  .ena(cs_text),
  .wea(wrs_i),
  .addra(bram_adr),
  .dina(rdat_i),
  .douta(tdat_o),
  .clkb(vclk),
  .enb(ld_shft|por),
  .web({8{por}}),
  .addrb(txtAddr[13:0]),
  .dinb(lfsr_o),
  .doutb(screen_ram_out)
);

//- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
// Character bitmap ROM
// - room for 512 8x8 characters
// - This core can be found in the Memory-Cores repository
//- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
wire [63:0] char_bmp;		// character ROM output
char_ram charRam0
(
	.clk_i(clk_i),
	.cs_i(cs_rom),
	.we_i(rwr_i & ~font_locked),
	.adr_i(radr_i[15:0]),
	.dat_i(rdat_i[7:0]),
	.dat_o(chdat_o),
	.dot_clk_i(vclk),
	.ce_i(ld_shft),
	.fontAddress_i(fontAddress),
	.char_code_i(screen_ram_out[12:0]),
	.maxScanpix_i(maxScanpix),
	.maxscanline_i(maxScanlinePlusOne),
	.scanline_i(rowscan[4:0]),
	.bmp_o(char_bmp)
);

/*
syncRam4kx9 charRam0
(
  .clka(clk_i),    // input wire clka
  .ena(cs_rom),      // input wire ena
  .wea(1'b0),//rwr_i),      // input wire [0 : 0] wea
  .addra(bram_adr),  // input wire [11 : 0] addra
  .dina(rdat_i[8:0]),    // input wire [8 : 0] dina
  .douta(chdat_o),  // output wire [8 : 0] douta
  .clkb(vclk),    // input wire clkb
  .enb(ld_shft),      // input wire enb
  .web(1'b0),      // input wire [0 : 0] web
  .addrb({screen_ram_out[8:0],scanline[2:0]}),  // input wire [11 : 0] addrb
  .dinb(9'h0),    // input wire [8 : 0] dinb
  .doutb(char_bmp)  // output wire [8 : 0] doutb
);
*/

// pipeline delay - sync color with character bitmap output
reg [20:0] txtBkCode1;
reg [20:0] txtFgCode1;
reg [5:0] txtZorder1;
always @(posedge vclk)
	if (ld_shft) txtBkCode1 <= screen_ram_out[36:16];
always @(posedge vclk)
	if (ld_shft) txtFgCode1 <= screen_ram_out[57:37];
always @(posedge vclk)
	if (ld_shft) txtZorder1 <= screen_ram_out[63:58];

//- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
// Register read port
//- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
always_comb
	if (cs_reg)
		rego <= rrm_o;
	else
		rego <= 64'h0000;


//- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
// Register write port
//- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

always_ff @(posedge clk_i)
	if (rst_i) begin
	  por <= 1'b1;
	  mcm <= 1'b0;
	  controller_enable <= 1'b1;
    xscroll 		 <= 5'd0;
    yscroll 		 <= 5'd0;
    txtTcCode    <= 24'h1ff;
    bdrColor     <= 32'hFFBF2020;
    startAddress <= 16'h0000;
    fontAddress  <= 16'h0000;
    font_locked  <= 1'b1;
    cursorStart  <= 5'd00;
    cursorEnd    <= 5'd31;
    cursorPos    <= 16'h0003;
    cursorType 	 <= 2'b00;
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
		// 48x29
		if (num==4'd1) begin
      windowTop    <= 12'd4058;//12'd16;
      windowLeft   <= 12'd3956;//12'd86;
      pixelWidth   <= 4'd0;		// 800 pixels
      pixelHeight  <= 4'd0;		// 600 pixels
      numCols      <= COLS;
      numRows      <= ROWS;
      maxRowScan  <= 6'd17;
      maxScanpix   <= 6'd11;
      rBlink       <= 3'b111;		// 01 = non display
      charOutDelay <= 8'd7;
		end
		else if (num==4'd2) begin
      windowTop    <= 12'd4032;//12'd16;
      windowLeft   <= 12'd3720;//12'd86;
      pixelWidth   <= 4'd0;        // 800 pixels
      pixelHeight  <= 4'd0;        // 600 pixels
      numCols      <= 40;
      numRows      <= 25;
      maxRowScan  <= 5'd7;
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
			4'd0:	begin
					if (rsel_i[0]) numCols    <= rdat_i[7:0];
					if (rsel_i[1]) numRows    <= rdat_i[15:8];
					if (rsel_i[2]) charOutDelay <= rdat_i[23:16];
					if (rsel_i[4]) windowLeft[7:0] <= rdat_i[39:32];
					if (rsel_i[5]) windowLeft[11:8] <= rdat_i[43:40];
					if (rsel_i[6]) windowTop[7:0]  <= rdat_i[55:48];
					if (rsel_i[7]) windowTop[11:8]  <= rdat_i[59:56];
					end
			4'd1:
				begin
					if (rsel_i[0]) maxRowScan <= rdat_i[4:0];
					if (rsel_i[1]) begin
						pixelHeight <= rdat_i[15:12];
						pixelWidth  <= rdat_i[11:8];	// horizontal pixel width
					end
					if (rsel_i[2]) maxScanpix <= rdat_i[20:16];
					if (rsel_i[3]) por <= rdat_i[24];
					if (rsel_i[4]) controller_enable <= rdat_i[32];
					if (rsel_i[5]) mcm <= rdat_i[40];
					if (rsel_i[6]) yscroll <= rdat_i[52:48];
					if (rsel_i[7]) xscroll <= rdat_i[60:56];
				end
			4'd2:	// Color Control
				begin
					if (rsel_i[0]) txtTcCode[7:0] <= rdat_i[7:0];
					if (rsel_i[1]) txtTcCode[15:8] <= rdat_i[15:8];
					if (rsel_i[2]) txtTcCode[23:16] <= rdat_i[23:16];
					if (rsel_i[3]) txtTcCode[30:24] <= rdat_i[30:24];
					if (rsel_i[4]) bdrColor[7:0] <= dat_i[39:32];
					if (rsel_i[5]) bdrColor[15:8] <= dat_i[47:40];
					if (rsel_i[6]) bdrColor[23:16] <= dat_i[55:48];
					if (rsel_i[7]) bdrColor[31:24] <= dat_i[63:56];
				end
			4'd3:	// Color Control 2
				begin
					if (rsel_i[0]) tileColor1[7:0] <= rdat_i[7:0];
					if (rsel_i[1]) tileColor1[15:8] <= rdat_i[15:8];
					if (rsel_i[2]) tileColor1[23:16] <= rdat_i[23:16];
					if (rsel_i[3]) tileColor1[30:24] <= rdat_i[30:24];
					if (rsel_i[4]) tileColor2[7:0] <= rdat_i[39:32];
					if (rsel_i[5]) tileColor2[15:8] <= rdat_i[47:40];
					if (rsel_i[6]) tileColor2[23:16] <= rdat_i[55:48];
					if (rsel_i[7]) tileColor2[30:24] <= rdat_i[62:56];
				end
			4'd4:	// Cursor Control
				begin
					if (rsel_i[0]) begin
						cursorEnd <= rdat_i[4:0];	// scan line sursor starts on
						rBlink      <= rdat_i[7:5];
					end
					if (rsel_i[1]) begin
						cursorStart <= rdat_i[12:8];	// scan line cursor ends on
						cursorType  <= rdat_i[15:14];
					end
					if (rsel_i[4]) cursorPos[7:0] <= rdat_i[39:32];
					if (rsel_i[5]) cursorPos[15:8] <= rdat_i[47:40];
				end
			4'd5:	// Page flipping / scrolling
				begin
					if (rsel_i[0]) startAddress[7:0] <= rdat_i[7:0];
					if (rsel_i[1]) startAddress[15:8] <= rdat_i[15:8];
				end
			4'd6:	// 
				begin
					if (rsel_i[0]) fontAddress[7:0] <= rdat_i[7:0];
					if (rsel_i[1]) fontAddress[15:8] <= rdat_i[15:8];
					if (&rsel_i[7:4])
						font_locked <= rdat_i[63:32]=="LOCK";
				end
			default: ;
			endcase
		end
	end


//--------------------------------------------------------------------
//--------------------------------------------------------------------

// "Box" cursor bitmap
reg [7:0] curout;
always @*
	case({cursorType,scanindex})
	// Box cursor
	5'b00_000:	curout = 8'b11111110;
	5'b00_001:	curout = 8'b10000010;
	5'b00_010:	curout = 8'b10000010;
	5'b00_011:	curout = 8'b10000010;
	5'b00_100:	curout = 8'b10000010;
	5'b00_101:	curout = 8'b10000010;
	5'b00_110:	curout = 8'b10010010;
	5'b00_111:	curout = 8'b11111110;
	// vertical bar cursor
	5'b01_000:	curout = 8'b11000000;
	5'b01_001:	curout = 8'b10000000;
	5'b01_010:	curout = 8'b10000000;
	5'b01_011:	curout = 8'b10000000;
	5'b01_100:	curout = 8'b10000000;
	5'b01_101:	curout = 8'b10000000;
	5'b01_110:	curout = 8'b10000000;
	5'b01_111:	curout = 8'b11000000;
	// underline cursor
	5'b10_000:	curout = 8'b00000000;
	5'b10_001:	curout = 8'b00000000;
	5'b10_010:	curout = 8'b00000000;
	5'b10_011:	curout = 8'b00000000;
	5'b10_100:	curout = 8'b00000000;
	5'b10_101:	curout = 8'b00000000;
	5'b10_110:	curout = 8'b00000000;
	5'b10_111:	curout = 8'b11111111;
	// Asterisk
	5'b11_000:	curout = 8'b00000000;
	5'b11_001:	curout = 8'b00000000;
	5'b11_010:	curout = 8'b00100100;
	5'b11_011:	curout = 8'b00011000;
	5'b11_100:	curout = 8'b01111110;
	5'b11_101:	curout = 8'b00011000;
	5'b11_110:	curout = 8'b00100100;
	5'b11_111:	curout = 8'b00000000;
	endcase


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
	.i(hsync_i),
	.pe(pe_hsync),
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
//always @(posedge vclk)
//	rxmslp1 <= row * maxScanlinePlusOne;
//always @(posedge vclk)
//	scanline <= scanline - rxmslp1;


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
	blink_en <= (cursorPos+3==txtAddr) && (rowscan[4:0] >= cursorStart) && (rowscan[4:0] <= cursorEnd);

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
		bkColor40 <= {txtZorder1[5:2],txtBkCode1[20:14],5'b0,txtBkCode1[13:7],5'b0,txtBkCode1[6:0],5'b0};
always_ff @(posedge vclk)
	if (ld_shft)
		bkColor40d <= bkColor40;
always_ff @(posedge vclk)
	if (ld_shft)
		fgColor40 <= {txtZorder1[5:2],txtFgCode1[20:14],5'b0,txtFgCode1[13:7],5'b0,txtFgCode1[6:0],5'b0};
always_ff @(posedge vclk)
	if (ld_shft)
		fgColor40d <= fgColor40;

always_ff @(posedge vclk)
	if (ld_shft)
		bgt <= txtBkCode1=={txtTcCode[26:20],txtTcCode[17:11],txtTcCode[8:2]};
always_ff @(posedge vclk)
	if (ld_shft)
		bgtd <= bgt;

// Convert character bitmap to pixels
reg [63:0] charout1;
always_ff @(posedge vclk)
	charout1 <= blink ? (char_bmp ^ curout) : char_bmp;

// Convert parallel to serial
ParallelToSerial ups1
(
	.rst(rst_i),
	.clk(vclk),
	.mcm(mcm),
	.ce(nhp),
	.ld(ld_shft),
	.a(maxScanpix[5:0]),
	.qin(2'b0),
	.d(charout1),
	.qh(pix)
);
/*
always_ff @(posedge vclk)
if (rst_i) begin
	pix <= 64'd0;
end
else begin
	if (nhp) begin
		if (ld_shft)
			pix <= charout1;
		else begin
			if (mcm)
				pix <= {2'b00,pix[63:2]};
			else
				pix <= {1'b0,pix[63:1]};
		end
	end
end
*/
/*
reg [1:0] pix1;
always_ff @(posedge vclk)
	if (nhp)	
    pix1 <= pix[1:0];
*/
// Pipelining Effect:
// - character output is delayed by 2 or 3 character times relative to the video counters
//   depending on the resolution selected
// - this means we must adapt the blanking signal by shifting the blanking window
//   two or three character times.
wire bpix = hctr[2] ^ rowscan[4];// ^ blink;
always_ff @(posedge vclk)
	if (nhp)	
		iblank <= (row >= numRows) || (col >= numCols + charOutDelay) || (col < charOutDelay);
	

// Choose between input RGB and controller generated RGB
// Select between foreground and background colours.
// Note the ungated dot clock must be used here, or output from other
// controllers would not be visible if the clock were gated off.
always_ff @(posedge dot_clk_i)
	casez({controller_enable&xonoff_i,blank_i,iblank,border_i,bpix,mcm,pix})
	8'b01??????:	zrgb_o <= 40'h00000000;
	8'b11??????:	zrgb_o <= 40'h00000000;
	8'b1001????:	zrgb_o <= {bdrColor[30:27],bdrColor[26:18],3'b0,bdrColor[17:9],3'b0,bdrColor[8:0],3'b0};
	//6'b10010?:	zrgb_o <= 32'hFFBF2020;
	//6'b10011?:	zrgb_o <= 32'hFFDFDFDF;
	8'b1000?00?:	zrgb_o <= (zrgb_i[39:36] > bkColor40d[39:36]) ? zrgb_i : bkColor40d;
//	8'b1000?0?0:	zrgb_o <= bkColor32d;
	8'b1000?01?:	zrgb_o <= fgColor40d; // ToDo: compare z-order
	8'b1000?100:	zrgb_o <= (zrgb_i[39:36] > bkColor40d[39:36]) ? zrgb_i : bkColor40d;
	8'b1000?101:	zrgb_o <= fgColor40d;
	8'b1000?110:	zrgb_o <= {tileColor1[30:27],tileColor1[26:18],3'b0,tileColor1[17:9],3'b0,tileColor1[8:0],3'b0};
	8'b1000?111:	zrgb_o <= {tileColor2[30:27],tileColor2[26:18],3'b0,tileColor2[17:9],3'b0,tileColor2[8:0],3'b0};
//	6'b1010?0:	zrgb_o <= bgtd ? zrgb_i : bkColor32d;
//	6'b1010?1:	zrgb_o <= fgColor32d;
	default:	zrgb_o <= zrgb_i;
	endcase

endmodule

