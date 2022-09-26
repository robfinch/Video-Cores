// ============================================================================
//        __
//   \\__/ o\    (C) 2019  Robert Finch, Waterloo
//    \  __ /    All rights reserved.
//     \/_//     robfinch<remove>@finitron.ca
//       ||
//
// rtfGraphicsAccelerator.v
// - a 128-bit bus master and 64-bit bus slave
//
// This source file is free software: you can redistribute it and/or modify 
// it under the terms of the GNU Lesser General Public License as published 
// by the Free Software Foundation, either version 3 of the License, or     
// (at your option) any later version.                                      
//                                                                          
// This source file is distributed in the hope that it will be useful,      
// but WITHOUT ANY WARRANTY; without even the implied warranty of           
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the            
// GNU General Public License for more details.                             
//                                                                          
// You should have received a copy of the GNU General Public License        
// along with this program.  If not, see <http://www.gnu.org/licenses/>. 
//
// Features:
// - 1024 entry command fifo
// - blitter (3 sources, 1 destination channel)
// - text blitter
// -    fonts up to 32x32 pixel characters
// -    variable width font support
// - point plot
// - line draw
// - filled triangle draw (standard method)
// - bezier curve draw
// - filled rectangle draw
// - clipping
// - hardware flood fill
// - 16/32 bpp color depth
// - programmable target area
//
// ============================================================================
//
`define BEZIER_CURVE	1'b1
`define FLOOD_FILL	1'b1
`define ABITS	31:0

`define TRUE	1'b1
`define FALSE	1'b0
`define HIGH	1'b1
`define LOW		1'b0

`define A		15
`define RBits		14:10
`define GBits		9:5
`define BBits		4:0

`define BLACK	16'h0000
`define WHITE	16'h7FFF
`define BLACK32	32'h00000000
`define WHITE32	32'h00FFFFFF

`define CMDDAT	31:0
`define CMDCMD	47:32

module rtfGraphicsAccelerator(
	rst_i, clk_i, cs_i, cyc_i, stb_i, ack_o, we_i, sel_i, adr_i, dat_i, dat_o, irq_o,
	m_clk_i, m_cyc_o, m_stb_o, m_ack_i, m_we_o, m_sel_o, m_adr_o, m_dat_i, m_dat_o,
	vclk,
	state
);
// WISHBONE slave port
input rst_i;
input clk_i;
input cs_i;
input cyc_i;
input stb_i;
output reg ack_o;
input we_i;
input [7:0] sel_i;
input [11:0] adr_i;
input [63:0] dat_i;
output reg [63:0] dat_o;
output irq_o;
// WISHBONE master port
input m_clk_i;
output reg m_cyc_o;
output m_stb_o;
input m_ack_i;
output reg m_we_o;
output reg [15:0] m_sel_o;
output reg [`ABITS] m_adr_o;
input [127:0] m_dat_i;
output reg [127:0] m_dat_o;
// Video Port
input vclk;
output reg [7:0] state = 8'd00;	// IDLE

parameter ST_IDLE = 8'd0;
parameter OTHERS = 8'd13;
parameter ST_READ_FONT_TBL = 8'd15;
parameter ST_READ_FONT_TBL_NACK = 8'd16;
parameter ST_READ_GLYPH_ENTRY = 8'd17;
parameter ST_READ_GLYPH_ENTRY_NACK = 8'd18;
parameter ST_READ_CHAR_BITMAP = 8'd19;
parameter ST_READ_CHAR_BITMAP_NACK = 8'd20;
parameter ST_WRITE_CHAR = 8'd21;
parameter ST_WRITE_CHAR2 = 8'd22;
parameter ST_WRITE_CHAR2_NACK = 8'd23;
parameter ST_CMD = 8'd24;
parameter ST_PLOT = 8'd27;
parameter ST_PLOT_READ = 8'd28;
parameter ST_PLOT_WRITE = 8'd29;
parameter ST_LATCH_DATA = 8'd30;
parameter DELAY1 = 8'd31;
parameter DELAY2 = 8'd32;
parameter DELAY3 = 8'd33;
parameter DELAY4 = 8'd34;
parameter DL_PRECALC = 8'd35;
parameter DL_GETPIXEL = 8'd36;
parameter DL_SETPIXEL = 8'd37;
parameter DL_TEST = 8'd38;
parameter DL_RET = 8'd39;
parameter ST_BLTDMA2 = 8'd42;
parameter ST_BLTDMA2_NACK = 8'd43;
parameter ST_BLTDMA4 = 8'd44;
parameter ST_BLTDMA4_NACK = 8'd45;
parameter ST_BLTDMA6 = 8'd46;
parameter ST_BLTDMA6_NACK = 8'd47;
parameter ST_BLTDMA8 = 8'd48;
parameter ST_BLTDMA8_NACK = 8'd51;
parameter ST_FILLRECT = 8'd60;
parameter ST_FILLRECT_CLIP = 8'd61;
parameter ST_FILLRECT2 = 8'd62;
parameter ST_WAIT_ACK = 8'd64;
parameter ST_WAIT_NACK = 8'd65;
parameter HL_LINE = 8'd70;
parameter HL_GETPIXEL = 8'd71;
parameter HL_GETPIXEL_NACK = 8'd72;
parameter HL_SETPIXEL = 8'd73;
parameter HL_SETPIXEL_NACK = 8'd74;
// Triangle draw states
parameter DT_START = 8'd80;
parameter DT_SORT = 8'd81;
parameter DT_SLOPE1 = 8'd82;
parameter DT_SLOPE1a = 8'd83;
parameter DT_SLOPE2 = 8'd84;
parameter DT_INCY = 8'd85;
parameter DT1 = 8'd86;
parameter DT2 = 8'd87;
parameter DT3 = 8'd88;
parameter DT4 = 8'd89;
parameter DT5 = 8'd90;
parameter DT6 = 8'd91;
parameter ST_WRITE_CHAR1 = 6'd92;
// Bezier curve states
parameter BC0 = 8'd100;
parameter BC1 = 8'd101;
parameter BC2 = 8'd102;
parameter BC3 = 8'd103;
parameter BC4 = 8'd104;
parameter BC5 = 8'd105;
parameter BC6 = 8'd106;
parameter BC7 = 8'd107;
parameter BC8 = 8'd108;
parameter BC9 = 8'd109;
parameter BC5a = 8'd110;
// Flood Fill states
parameter FF1 = 8'd111;
parameter FF2 = 8'd112;
parameter FF3 = 8'd113;
parameter FF4 = 8'd114;
parameter FF5 = 8'd115;
parameter FF6 = 8'd116;
parameter FF7 = 8'd117;
parameter FF8 = 8'd118;
parameter FF_EXIT = 8'd119;
parameter FLOOD_FILL = 8'd120;

// Onlly BPP32 or BPP16 supported
parameter BPP4 = 3'd0;
parameter BPP8 = 3'd1;
parameter BPP12 = 3'd2;
parameter BPP16 = 3'd3;
parameter BPP20 = 3'd4;
parameter BPP32 = 3'd5;

assign m_stb_o = m_cyc_o;

reg bpp = 0;			// 0=16, 1=32
// Interrupt sources
// -------- -----rbv
//               ||+-- vertical blank  
//               |+--- blitter done
//               +---- raster

reg [31:0] irq_en = 32'h0;
reg [31:0] irq_status;
assign irq_o = |(irq_status & irq_en);

reg [`ABITS] TargetBase = 32'h100000;
reg [15:0] TargetWidth = 16'd400;
reg [15:0] TargetHeight = 16'd300;
reg zorder;
// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
reg clipEnable;
reg [15:0] clipX0, clipY0, clipX1, clipY1;


integer n;

wire [31:0] fixedOne = 32'h010000;  // Fixed point 1.0
wire [31:0] fixedHalf = 32'h08000;  // Fixed point 0.5

function [4:0] R;
input [15:0] cl;
R = zorder ? {cl[11:8],1'b0} : cl[14:10];
endfunction
function [4:0] G;
input [15:0] cl;
G = zorder ? {cl[7:4],1'b0} : cl[9:5];
endfunction
function [4:0] B;
input [15:0] cl;
B = zorder ? {cl[3:0],1'b0} : cl[4:0];
endfunction
function [3:0] Z;
input [15:0] cl;
Z = cl[15:12];
endfunction

function [7:0] R8;
input [31:0] cl;
R8 = cl[23:16];
endfunction
function [7:0] G8;
input [31:0] cl;
G8 = cl[15:8];
endfunction
function [7:0] B8;
input [31:0] cl;
B8 = cl[7:0];
endfunction
function [3:0] Z8;
input [31:0] cl;
Z8 = cl[31:24];
endfunction

function [15:0] fixToInt;
input [31:0] nn;
	fixToInt = nn[31:16];
endfunction

// Integer part of a fixed point number
function [31:0] ipart;
input [31:0] nn;
    ipart = {nn[31:16],16'h0000};
endfunction

// Fractional part of a fixed point number
function [31:0] fpart;
input [31:0] nn;
    fpart = {16'h0,nn[15:0]};
endfunction

function [31:0] rfpart;
input [31:0] nn;
    rfpart = (fixedOne - fpart(nn));
endfunction

// Round fixed point number (+0.5)
function [31:0] round;
input [31:0] nn;
    round = ipart(nn + fixedHalf); 
endfunction

function [20:0] blend1;
input [4:0] comp;
input [15:0] alpha;
	blend1 = comp * alpha;
endfunction

function [15:0] blend;
input [15:0] color1;
input [15:0] color2;
input [15:0] alpha;
reg [20:0] blendR;
reg [20:0] blendG;
reg [20:0] blendB;
begin
	blendR = blend1(R(color1),alpha) + blend1(R(color2),(16'hFFFF-alpha));
	blendG = blend1(G(color1),alpha) + blend1(G(color2),(16'hFFFF-alpha));
	blendB = blend1(B(color1),alpha) + blend1(B(color2),(16'hFFFF-alpha));
	blend = {blendR[20:16],blendG[20:16],blendB[20:16]};
end
endfunction

function [23:0] blend1a;
input [7:0] comp;
input [15:0] alpha;
	blend1a = comp * alpha;
endfunction

function [31:0] blend8;
input [31:0] color1;
input [31:0] color2;
input [15:0] alpha;
reg [23:0] blendR;
reg [23:0] blendG;
reg [23:0] blendB;
begin
	blendR = blend1a(R8(color1),alpha) + blend1a(R8(color2),(16'hFFFF-alpha));
	blendG = blend1a(G8(color1),alpha) + blend1a(G8(color2),(16'hFFFF-alpha));
	blendB = blend1a(B8(color1),alpha) + blend1a(B8(color2),(16'hFFFF-alpha));
	blend8 = {blendR[23:16],blendG[23:16],blendB[23:16]};
end
endfunction

function [127:0] fnClearPixel;
input [127:0] data;
input [31:0] addr;
begin
	fnClearPixel = bpp ? data & ~(128'h0FFFFFFFF << {addr[3:2],5'h0}) : data & ~(128'h0FFFF << {addr[3:1],4'h0});
end
endfunction

function [127:0] fnFlipPixel;
input [127:0] data;
input [31:0] addr;
begin
	fnFlipPixel = bpp ? data ^ (128'h0FFFFFFFF << {addr[3:2],5'h0}) : data ^ (128'h0FFFF << {addr[3:1],4'h0});
end
endfunction

function [127:0] fnShiftPixel;
input [31:0] color;
input [31:0] addr;
begin
	fnShiftPixel = bpp ? ({96'h0,color} << {addr[3:2],5'h0}) : ({112'h0,color[15:0]} << {addr[3:1],4'h0});
end
endfunction

function fnClip;
input [15:0] x;
input [15:0] y;
begin
	fnClip = (x >= TargetWidth || y >= TargetHeight)
			 || (clipEnable && (x < clipX0 || x >= clipX1 || y < clipY0 || y >= clipY1))
			;
end
endfunction


// The bus timeout depends on the clock frequency (m_clk_i) of the core
// relative to the memory controller's clock frequency (100MHz). So it's
// been made a core parameter.
reg [7:0] busto = BUSTO;
reg [7:0] tocnt;
reg [7:0] num_strips = 8'd100;

// Graphics cursor position
reg [15:0] gcx;
reg [15:0] gcy;

// Untransformed points
reg [31:0] up0x, up0y, up0z;
reg [31:0] up1x, up1y, up1z;
reg [31:0] up2x, up2y, up2z;
reg [31:0] up0xs, up0ys, up0zs;
reg [31:0] up1xs, up1ys, up1zs;
reg [31:0] up2xs, up2ys, up2zs;
// Points after transform
reg [31:0] p0x, p0y, p0z;
reg [31:0] p1x, p1y, p1z;
reg [31:0] p2x, p2y, p2z;

wire signed [31:0] absx1mx0 = (p1x < p0x) ? p0x-p1x : p1x-p0x;
wire signed [31:0] absy1my0 = (p1y < p0y) ? p0y-p1y : p1y-p0y;

// Triangle draw
reg fbt;	// flat bottom=1 or top=0 triangle
reg [7:0] trimd;	// timer for mult
reg tri_shade;
reg [31:0] v0x, v0y, v1x, v1y, v2x, v2y, v3x, v3y;
reg [31:0] w0x, w0y, w1x, w1y, w2x, w2y;
reg signed [31:0] invslope0, invslope1;
reg [31:0] curx0, curx1, cdx;
reg [15:0] endx;
reg [31:0] minY, minX, maxY, maxX;
reg div_ld;
reg signed [31:0] diff_x1x0;
reg signed [31:0] diff_y2y0;
reg signed [31:0] diff_x2x0;
reg signed [31:0] diff_y1y0;
wire signed [15:0] diff_x1x0_int = fixToInt(diff_x1x0);
wire signed [15:0] diff_y2y0_int = fixToInt(diff_y2y0);
wire signed [15:0] diff_x2x0_int = fixToInt(diff_x2x0);
wire signed [15:0] diff_y1y0_int = fixToInt(diff_y1y0);

reg signed [31:0] triangle_area;
reg signed [31:0] triangle_area0;
reg signed [31:0] triangle_area1;

// edge0
reg signed [15:0] triangle_edge0_y2y1;
reg signed [15:0] triangle_edge0_xx1;
reg signed [15:0] triangle_edge0_x2x1;
reg signed [15:0] triangle_edge0_yy1;

// edge1
reg signed [15:0] triangle_edge1_y0y2;
reg signed [15:0] triangle_edge1_xx2;
reg signed [15:0] triangle_edge1_x0x2;
reg signed [15:0] triangle_edge1_yy2;

//edge2
reg signed [15:0] triangle_edge2_y1y0;
reg signed [15:0] triangle_edge2_xx0;
reg signed [15:0] triangle_edge2_x1x0;
reg signed [15:0] triangle_edge2_yy0;

wire signed [31:0] triangle_edge0_val1 = triangle_edge0_y2y1 * triangle_edge0_xx1;
wire signed [31:0] triangle_edge0_val2 = triangle_edge0_x2x1 * triangle_edge0_yy1;
wire signed [31:0] triangle_edge1_val1 = triangle_edge1_y0y2 * triangle_edge1_xx2;
wire signed [31:0] triangle_edge1_val2 = triangle_edge1_x0x2 * triangle_edge1_yy2;
wire signed [31:0] triangle_edge2_val1 = triangle_edge2_y1y0 * triangle_edge2_xx0;
wire signed [31:0] triangle_edge2_val2 = triangle_edge2_x1x0 * triangle_edge2_yy0;

// e0(x,y) = -(p2y-p1y)(x-p1x)+(p2x-p1x)(y+p1y)
wire signed [31:0] triangle_edge0 = triangle_edge0_val2 - triangle_edge0_val1;
// e1(x,y) = -(p0y-p2y)(x-p2x)+(p0x-p2x)(y+p2y)
wire signed [31:0] triangle_edge1 = triangle_edge1_val2 - triangle_edge1_val1;
// e2(x,y) = -(p1y-p0y)(x-p0x)+(p1x-p0x)(y+p2y)
wire signed [31:0] triangle_edge2 = triangle_edge2_val2 - triangle_edge2_val1;

// Bezier Curves
reg [1:0] fillCurve;
reg [31:0] bv0x, bv0y, bv1x, bv1y, bv2x, bv2y;
reg [31:0] bezierT, bezier1mT, bezierInc = 32'h0010;
reg [63:0] bezier1mTP0xw, bezier1mTP1xw;
reg [63:0] bezier1mTP0yw, bezier1mTP1yw;
reg [63:0] bezierTP1x, bezierTP2x;
reg [63:0] bezierTP1y, bezierTP2y;
reg [31:0] bezierP0plusP1x, bezierP1plusP2x;
reg [31:0] bezierP0plusP1y, bezierP1plusP2y;
reg [63:0] bezierBxw, bezierByw;

// Point Transform
reg transform, otransform;
reg [31:0] aa, ab, ac, at;
reg [31:0] ba, bb, bc, bt;
reg [31:0] ca, cb, cc, ct;
wire signed [63:0] aax0 = aa * up0x;
wire signed [63:0] aby0 = ab * up0y;
wire signed [63:0] acz0 = ac * up0z;
wire signed [63:0] bax0 = ba * up0x;
wire signed [63:0] bby0 = bb * up0y;
wire signed [63:0] bcz0 = bc * up0z;
wire signed [63:0] cax0 = ca * up0x;
wire signed [63:0] cby0 = cb * up0y;
wire signed [63:0] ccz0 = cc * up0z;
wire signed [63:0] aax1 = aa * up1x;
wire signed [63:0] aby1 = ab * up1y;
wire signed [63:0] acz1 = ac * up1z;
wire signed [63:0] bax1 = ba * up1x;
wire signed [63:0] bby1 = bb * up1y;
wire signed [63:0] bcz1 = bc * up1z;
wire signed [63:0] cax1 = ca * up1x;
wire signed [63:0] cby1 = cb * up1y;
wire signed [63:0] ccz1 = cc * up1z;
wire signed [63:0] aax2 = aa * up2x;
wire signed [63:0] aby2 = ab * up2y;
wire signed [63:0] acz2 = ac * up2z;
wire signed [63:0] bax2 = ba * up2x;
wire signed [63:0] bby2 = bb * up2y;
wire signed [63:0] bcz2 = bc * up2z;
wire signed [63:0] cax2 = ca * up2x;
wire signed [63:0] cby2 = cb * up2y;
wire signed [63:0] ccz2 = cc * up2z;

wire signed [63:0] x0_prime = aax0 + aby0 + acz0 + {at,16'h0000};
wire signed [63:0] y0_prime = bax0 + bby0 + bcz0 + {bt,16'h0000};
wire signed [63:0] z0_prime = cax0 + cby0 + ccz0 + {ct,16'h0000};
wire signed [63:0] x1_prime = aax1 + aby1 + acz1 + {at,16'h0000};
wire signed [63:0] y1_prime = bax1 + bby1 + bcz1 + {bt,16'h0000};
wire signed [63:0] z1_prime = cax1 + cby1 + ccz1 + {ct,16'h0000};
wire signed [63:0] x2_prime = aax2 + aby2 + acz2 + {at,16'h0000};
wire signed [63:0] y2_prime = bax2 + bby2 + bcz2 + {bt,16'h0000};
wire signed [63:0] z2_prime = cax2 + cby2 + ccz2 + {ct,16'h0000};

always @(posedge clk_i)
	p0x <= transform ? x0_prime[47:16] : up0x;
always @(posedge clk_i)
	p0y <= transform ? y0_prime[47:16] : up0y;
always @(posedge clk_i)
	p0z <= transform ? z0_prime[47:16] : up0z;
always @(posedge clk_i)
	p1x <= transform ? x1_prime[47:16] : up1x;
always @(posedge clk_i)
	p1y <= transform ? y1_prime[47:16] : up1y;
always @(posedge clk_i)
	p1z <= transform ? z1_prime[47:16] : up1z;
always @(posedge clk_i)
	p2x <= transform ? x2_prime[47:16] : up2x;
always @(posedge clk_i)
	p2y <= transform ? y2_prime[47:16] : up2y;
always @(posedge clk_i)
	p2z <= transform ? z2_prime[47:16] : up2z;

reg [7:0] ngs = OTHERS;		// next graphic state for continue
reg [7:0] pushstate;
`ifdef FLOOD_FILL
reg [11:0] retsp;
reg [11:0] pointsp;
reg [7:0] retstack [0:4095];
reg [31:0] pointstack [0:4095];
`endif
reg [7:0] stkstate [0:7];
reg [7:0] strip_cnt;
reg [5:0] delay_cnt;
wire [63:0] douta;

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
// Command queue vars.
// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
reg [63:0] cmdq_in;
wire [63:0] cmdq_out;
wire cmdp;				// command pulse
wire cmdpe;				// command pulse edge

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
// Text Blitting
// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
reg [`ABITS] font_tbl_adr;
reg [15:0] font_id;
reg [`ABITS] glyph_tbl_adr;
reg font_fixed;
reg [5:0] font_width;
reg [5:0] font_height;
reg tblit_active;
reg [7:0] tblit_state;
reg [`ABITS] tblit_adr;
reg [`ABITS] tgtaddr, tgtadr;
reg [15:0] tgtindex;
reg char_upd_xpos;
reg [15:0] charcode;
reg [31:0] charndx;
reg [31:0] charbmp;
reg [31:0] charbmpr;
reg [`ABITS] charBmpBase;
reg [5:0] pixhc, pixvc;
reg [31:0] charBoxX0, charBoxY0;

reg [15:0] alpha;
reg [31:0] penColor, fillColor;
reg [23:0] missColor = 24'h7c0000;	// med red

reg zbuf;
reg [3:0] zlayer;

reg [11:0] ppl;
reg [31:0] cyPPL;
reg [`ABITS] offset;
reg [`ABITS] ma;

// Line draw vars
reg signed [15:0] dx,dy;
reg signed [15:0] sx,sy;
reg signed [15:0] err;
wire signed [15:0] e2 = err << 1;
// Anti-aliased line draw
reg steep;
reg [31:0] openColor;
reg [31:0] xend, yend, gradient, xgap;
reg [31:0] xpxl1, ypxl1, xpxl2, ypxl2;
reg [31:0] intery;
reg signed [31:0] dxa,dya;

reg [`ABITS] rdadr;

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
// blitter vars
// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

reg [7:0] blit_state;
reg [31:0] bltSrcWid, bltSrcWidx;
reg [31:0] bltDstWid, bltDstWidx;
//  ch  321033221100       
//  TBDzddddebebebeb
//  |||   |       |+- bitmap mode
//  |||   |       +-- channel enabled
//  |||   +---------- direction 0=normal,1=decrement
//  ||+-------------- done indicator
//  |+--------------- busy indicator
//  +---------------- trigger bit
reg [15:0] bltCtrl,bltCtrlx;
reg [15:0] bltA_shift, bltB_shift, bltC_shift;
reg [15:0] bltLWMask = 16'hFFFF;
reg [15:0] bltFWMask = 16'hFFFF;

reg [`ABITS] bltA_badr;               // base address
reg [31:0] bltA_mod;                // modulo
reg [31:0] bltA_cnt;
reg [`ABITS] bltA_badrx;               // base address
reg [31:0] bltA_modx;                // modulo
reg [31:0] bltA_cntx;
reg [`ABITS] bltA_wadr;				// working address
reg [31:0] bltA_wcnt;				// working count
reg [31:0] bltA_dcnt;				// working count
reg [31:0] bltA_hcnt;

reg [`ABITS] bltB_badr;
reg [31:0] bltB_mod;
reg [31:0] bltB_cnt;
reg [`ABITS] bltB_badrx;
reg [31:0] bltB_modx;
reg [31:0] bltB_cntx;
reg [`ABITS] bltB_wadr;				// working address
reg [31:0] bltB_wcnt;				// working count
reg [31:0] bltB_dcnt;				// working count
reg [31:0] bltB_hcnt;

reg [`ABITS] bltC_badr;
reg [31:0] bltC_mod;
reg [31:0] bltC_cnt;
reg [`ABITS] bltC_badrx;
reg [31:0] bltC_modx;
reg [31:0] bltC_cntx;
reg [`ABITS] bltC_wadr;				// working address
reg [31:0] bltC_wcnt;				// working count
reg [31:0] bltC_dcnt;				// working count
reg [31:0] bltC_hcnt;

reg [`ABITS] bltD_badr;
reg [31:0] bltD_mod;
reg [31:0] bltD_cnt;
reg [`ABITS] bltD_badrx;
reg [31:0] bltD_modx;
reg [31:0] bltD_cntx;
reg [`ABITS] bltD_wadr;				// working address
reg [31:0] bltD_wcnt;				// working count
reg [31:0] bltD_hcnt;

reg [15:0] blt_op;
reg [15:0] blt_opx;
reg [6:0] bitcnt;
reg [3:0] bitinc;
reg [1:0] blt_nch;
reg bltDone1;

// May need to set the pipeline depth to zero if copying neighbouring pixels
// during a blit. So the app is allowed to control the pipeline depth. Depth
// should not be set >28.
reg [4:0] bltPipedepth = 5'd15;
reg [4:0] bltPipedepthx;
reg [31:0] bltinc;
reg [4:0] bltAa,bltBa,bltCa;
reg wrA, wrB, wrC;
reg [31:0] blt_bmpA;
reg [31:0] blt_bmpB;
reg [31:0] blt_bmpC;
reg [31:0] bltA_residue;
reg [31:0] bltB_residue;
reg [31:0] bltC_residue;
reg [31:0] bltD_residue;

wire [31:0] bltA_out, bltB_out, bltC_out;
wire [31:0] bltA_out1, bltB_out1, bltC_out1;
reg  [31:0] bltA_dat, bltB_dat, bltC_dat, bltD_dat;
reg  [31:0] bltA_datx, bltB_datx, bltC_datx, bltD_datx;
// Convert an input bit into a color (black or white) to allow use as a mask.
wire [31:0] bltA_in =
	bpp ? (bltCtrlx[0] ? (blt_bmpA[bitcnt] ? 32'hFFFFFFFF : 32'h00000000) : blt_bmpA) :
				(bltCtrlx[0] ? (blt_bmpA[bitcnt] ? 16'h7FFF : 16'h0000) : blt_bmpA);
wire [31:0] bltB_in =
	bpp ? (bltCtrlx[2] ? (blt_bmpB[bitcnt] ? 32'hFFFFFFFF : 32'h00000000) : blt_bmpB);
				(bltCtrlx[2] ? (blt_bmpB[bitcnt] ? 16'h7FFF : 16'h0000) : blt_bmpB);
wire [31:0] bltC_in =
	bpp ? (bltCtrlx[4] ? (blt_bmpC[bitcnt] ? 32'hFFFFFFFF : 32'h00000000) : blt_bmpC);
				(bltCtrlx[4] ? (blt_bmpC[bitcnt] ? 16'h7FFF : 16'h0000) : blt_bmpC);
assign bltA_out = bltA_datx;
assign bltB_out = bltB_datx;
assign bltC_out = bltC_datx;

reg [31:0] bltab;
reg [31:0] bltabc;

// Perform alpha blending between the two colors.
wire [16:0] blndR =
						bpp ? (R8(bltB_out) * bltA_out[7:0]) + (R8(bltC_out) * ~bltA_out[7:0]) :
									(R(bltB_out) * bltA_out[7:0]) + (R(bltC_out) * ~bltA_out[7:0]);
wire [16:0] blndG = 
						bpp ? (G8(bltB_out) * bltA_out[7:0]) + (G8(bltC_out) * ~bltA_out[7:0]) :
									(G(bltB_out) * bltA_out[7:0]) + (G(bltC_out) * ~bltA_out[7:0]);
wire [16:0] blndB =
						bpp ? (B8(bltB_out) * bltA_out[7:0]) + (B8(bltC_out) * ~bltA_out[7:0]) :
									(B(bltB_out) * bltA_out[7:0]) + (B(bltC_out) * ~bltA_out[7:0]);

always @*
	case(blt_opx[3:0])
	4'h1:	bltab <= bltA_out;
	4'h2:	bltab <= bltB_out;
	4'h3:	bltab <= ~bltA_out;
	4'h4:	bltab <= ~bltB_out;
	4'h8:	bltab <= bltA_out & bltB_out;
	4'h9:	bltab <= bltA_out | bltB_out;
	4'hA:	bltab <= bltA_out ^ bltB_out;
	4'hB:	bltab <= bltA_out & ~bltB_out;
	4'hF:	bltab <= bpp ? `WHITE32 : `WHITE;
	default:bltab <= bpp ? `BLACK32 : `BLACK;
	endcase
always @*
	case(blt_opx[7:4])
	4'h1:	bltabc <= bltab;
	4'h2:	bltabc <= bltC_out;
	4'h3:	if (bltab[`A]) begin
				bltabc[`RBits] <= R(bltC_out) >> bltab[2:0];
				bltabc[`GBits] <= G(bltC_out) >> bltab[5:3];
				bltabc[`BBits] <= B(bltC_out) >> bltab[8:6];
			end
			else
				bltabc <= bltab;
	4'h4:	bltabc <= bpp ? {blndR[15:8],blndG[15:8],blndB[15:8]} : {blndR[12:8],blndG[12:8],blndB[12:8]};
	4'h7: bltabc <= (bltC_out & ~bltB_out) | bltA_out; 
	4'h8:	bltabc <= bltab & bltC_out;
	4'h9:	bltabc <= bltab | bltC_out;
	4'hA:	bltabc <= bltab ^ bltC_out;
	4'hB:	bltabc <= bltab & ~bltC_out;
	4'hF:	bltabc <= bpp ? `WHITE32 : `WHITE;
	default:bltabc <= bpp ? `BLACK32 : `BLACK;
	endcase

reg signed [31:0] div_a, div_b;
wire signed [63:0] div_qo;
wire div_idle;

rtfGA_Divider #(.WID(64)) udiv1
(
	.rst(rst_i),
	.clk(m_clk_i),
	.ld(div_ld),
	.abort(1'b0),
	.sgn(1'b1),
	.sgnus(1'b0),
	.a({{16{div_a[31]}},div_a,16'h0}),
	.b({{32{div_b[31]}},div_b}),
	.qo(div_qo),
	.ro(),
	.dvByZr(),
	.done(),
	.idle(div_idle)
);

wire [63:0] trimult;
rtfGA_TriMult umul3
(
  .CLK(clk_i),
  .A(div_qo[31:0]),
  .B(v2x-v0x),
  .P(trimult)
);


// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
// Command queue
// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

reg rst_cmdq;
wire [9:0] cmdq_rcnt, cmdq_wcnt;
wire cmdq_full;
wire cmdq_empty;
wire cmdq_valid;
wire cs = cs_i & cyc_i & stb_i;
wire cs_cmdq = cpu_wr_reg && adr[9:3]==7'b01_1101_0;
wire wr_cmd_fifo = cs_cmdq & cmdp;
reg rd_cmd_fifo;

rtfGraphicsAccelerator_CmdFifo ucf1
(
	.rst(rst_i|rst_cmdq), 
	.wr_clk(clk_i),
	.rd_clk(m_clk_i),
	.din(cmdq_in),
	.wr_en(wr_cmd_fifo),
	.rd_en(rd_cmd_fifo),
	.dout(cmdq_out),
	.full(),
	.almost_full(cmdq_full),
	.empty(cmdq_empty),
	.valid(cmdq_valid),
	.rd_data_count(cmdq_rcnt),
	.wr_data_count(cmdq_wcnt),
	.wr_rst_busy(),
	.rd_rst_busy() 
);

edge_det ued20 (.rst(rst_i), .clk(clk_i), .ce(1'b1), .i(rdy2|rdy3), .pe(cmdp), .ne(), .ee());
// Here m_clk_i needs to be faster than clk_i.
//edge_det ued1 (.rst(rst_i), .clk(m_clk_i), .ce(1'b1), .i(cs_cmdq), .pe(cmdpe), .ne(), .ee());

// Command queue index signal
always @(posedge m_clk_i)
if (rst_i)
	rd_cmd_fifo <= `FALSE;
else begin
	rd_cmd_fifo <= `FALSE;
	// A lot of other events to process before handling the command queue.
	// First check for audio DMA requests then check for outstanding
	// active graphics requests. Finally process the next command from
	// the queue.
	if (state==OTHERS) begin
		if (tblit_active)
 			;
		else if (bltCtrlx[14])
			;
		else if (bltCtrlx[15])
			;
 		else if (ctrl[14])
			;
		else if (!cmdq_empty)
			rd_cmd_fifo <= `TRUE;
	end
end

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
// WISHBONE slave port - register interface.
// clk_i domain
// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

(* ram_style="distributed" *)
reg [63:0] mem [0:127];
always @(posedge clk_i)
begin
	if (cs & cpu_wr_reg & sel_i[0]) mem[adr_i[9:3]][7:0] <= dat[7:0];
	if (cs & cpu_wr_reg & sel_i[1]) mem[adr_i[9:3]][15:8] <= dat[15:8];
	if (cs & cpu_wr_reg & sel_i[2]) mem[adr_i[9:3]][23:16] <= dat[23:16];
	if (cs & cpu_wr_reg & sel_i[3]) mem[adr_i[9:3]][31:24] <= dat[31:24];
	if (cs & cpu_wr_reg & sel_i[4]) mem[adr_i[9:3]][39:32] <= dat[39:32];
	if (cs & cpu_wr_reg & sel_i[5]) mem[adr_i[9:3]][47:40] <= dat[47:40];
	if (cs & cpu_wr_reg & sel_i[6]) mem[adr_i[9:3]][55:48] <= dat[55:48];
	if (cs & cpu_wr_reg & sel_i[7]) mem[adr_i[9:3]][63:56] <= dat[63:56];
end
assign douta = mem[adr_i[9:3]];


reg [31:0] dat_ix;
wire peBltCtrl;
wire peBltAdatx;
wire peBltBdatx;
wire peBltCdatx;
wire peBltDdatx;
wire peBltDbadrx,peBltDmodx,peBltDcntx;
wire peBltDstWidx;
wire cs_bltCtrl = cpu_wr_reg && adr[9:3]==7'b0_1100_11 && |sel[1:0];
wire cs_bltAdatx = cpu_wr_reg && adr[9:3]==7'b0_1000_11 && |sel[1:0];
wire cs_bltBdatx = cpu_wr_reg && adr[9:3]==7'b0_1001_11 && |sel[1:0];
wire cs_bltCdatx = cpu_wr_reg && adr[9:3]==7'b0_1010_11 && |sel[1:0];
wire cs_bltDdatx = cpu_wr_reg && adr[9:3]==7'b0_1011_11 && |sel[1:0];
wire cs_bltDbadrx = cpu_wr_reg && adr[9:3]==7'b0_1011_00 && |sel[1:0];
wire cs_bltDbmodx = cpu_wr_reg && adr[9:3]==7'b0_1011_01 && |sel[1:0];
wire cs_bltDbcntx = cpu_wr_reg && adr[9:3]==7'b0_1011_10 && |sel[1:0];
wire cs_bltDstWidx = cpu_wr_reg && adr[9:3]==7'b0_1100_01 && |sel[1:0];
edge_det ed2(.rst(rst_i), .clk(m_clk_i), .ce(1'b1), .i(cs_bltCtrl), .pe(peBltCtrl), .ne(), .ee());
edge_det ed3(.rst(rst_i), .clk(m_clk_i), .ce(1'b1), .i(cs_bltAdatx), .pe(peBltAdatx), .ne(), .ee());
edge_det ed4(.rst(rst_i), .clk(m_clk_i), .ce(1'b1), .i(cs_bltBdatx), .pe(peBltBdatx), .ne(), .ee());
edge_det ed5(.rst(rst_i), .clk(m_clk_i), .ce(1'b1), .i(cs_bltCdatx), .pe(peBltCdatx), .ne(), .ee());
edge_det ed6(.rst(rst_i), .clk(m_clk_i), .ce(1'b1), .i(cs_bltDdatx), .pe(peBltDdatx), .ne(), .ee());
edge_det ed7(.rst(rst_i), .clk(m_clk_i), .ce(1'b1), .i(cs_bltDbadrx), .pe(peBltDbadrx), .ne(), .ee());
edge_det ed8(.rst(rst_i), .clk(m_clk_i), .ce(1'b1), .i(cs_bltDmodx), .pe(peBltDmodx), .ne(), .ee());
edge_det ed9(.rst(rst_i), .clk(m_clk_i), .ce(1'b1), .i(cs_bltDcntx), .pe(peBltDcntx), .ne(), .ee());
edge_det ed10(.rst(rst_i), .clk(m_clk_i), .ce(1'b1), .i(cs_bltDstWidx), .pe(peBltDstWidx), .ne(), .ee());

always @(posedge m_clk_i)
	dat_ix <= dat_i;

assign sel = sel_i;
assign adr = adr_i;
assign dat = dat_i;
assign cpu_wr_reg = cs & we_i & (rdy2|rdy3) & ~rdy4;

always @(posedge clk_i)
begin
	if (cpu_wr_reg)
		casez(adr[9:3])
		// Blitter: $100 to $198
		7'b01_0000_0:	bltA_badr <= dat[`ABITS];
		7'b01_0000_1:	bltA_mod <= dat;
		7'b01_0001_0:	bltA_cnt <= dat;
		7'b01_0010_0:	bltB_badr <= dat[`ABITS];
		7'b01_0010_1:	bltB_mod <= dat;
		7'b01_0011_0:	bltB_cnt <= dat;
		7'b01_0100_0:	bltC_badr <= dat[`ABITS];
		7'b01_0100_1:	bltC_mod <= dat;
		7'b01_0101_0:	bltC_cnt <= dat;
		7'b01_0110_0:	bltD_badr <= dat[`ABITS];
		7'b01_0110_1:	bltD_mod <= dat;
		7'b01_0111_0:	bltD_cnt <= dat;
		7'b01_0111_1:	bltD_dat <= dat[15:0];

		7'b01_1000_0:	bltSrcWid <= dat;
		7'b01_1000_1:	bltDstWid <= dat;

		7'b01_1001_0:	blt_op <= dat[15:0];
		7'b01_1001_1:	
							begin
							if (sel[3]) bltPipedepth <= dat[29:24];
							if (|sel[1:0]) bltCtrl <= dat[15:0];
							end
		// Command queue $1C0
		7'b01_1100_0:	
			begin
				if (sel[5:4]) cmdq_in[47:32] <= dat[47:32];
				if (sel[0]) cmdq_in[7:0] <= dat[7:0];
				if (sel[1]) cmdq_in[15:8] <= dat[15:8];
				if (sel[2]) cmdq_in[23:16] <= dat[23:16];
				if (sel[3]) cmdq_in[31:24] <= dat[31:24];
			end
		7'b01_1100_1:	;//cmdq_in[63:32] <= dat;
		7'b01_1110_0:	font_tbl_adr <= dat[`ABITS];
		7'b01_1110_1:	font_id <= dat[15:0];

    7'b11_1100_0:		TargetBase <= dat[`ABITS];
    7'b11_1101_0:
    	begin
				if (|sel[3:2]) TargetWidth <= dat[31:16];
				if (|sel[1:0]) TargetHeight <= dat[15:0];
			end

		7'b11_1101_0:	irq_en <= dat;
		7'b11_1101_1:	irq_status <= irq_status & ~dat;

    7'b11_1110_0:
     	begin
				if (sel[2]) num_strips = dat[23:16];
				if (sel[0]) lowres <= dat[1:0];
				if (sel[0]) bpp <= dat[7:5]==BPP32 ? 1'b1 : 1'b0;
				if (sel[1]) zorder <= dat[15];   
			end
		default:	;	// do nothing
		endcase
end
always @(posedge clk_i)
	case(adr_i[9:3])
	7'b01_1001_1:	dat_o <= {bltPipedepth,8'h00,bltCtrlx};
	7'b01_1101_0:	dat_o <= {22'd0,cmdq_wcnt};
	7'b11_1010_1:	dat_o <= {27'h0,fpos,4'h0,vpos,4'h0,hpos};
	7'b11_1101_1: dat_o <= irq_status;
	default:	dat_o <= douta;
	endcase

always @(posedge clk_i)
	rdy1 <= cs;
always @(posedge clk_i)
	rdy2 <= rdy1 & cs;
always @(posedge clk_i)
	rdy3 <= rdy2 & cs;
always @(posedge clk_i)
	rdy4 <= rdy3 & cs;
//assign ack_o = cs ? rdy4 : pAckStyle;
always @*
	ack_o <= rdy4;


// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

wire [31:0] pixel_i = bpp ? (m_dat_i >> {ma[3:2],5'b0}) & 32'hFFFFFFFF :
													  (m_dat_i >> {ma[3:1],4'b0}) & 16'hFFFF;

`ifdef FLOOD_FILL
reg [31:0] pointToPush;
reg rstst, pushst, popst;
reg rstpt, pushpt, poppt;

always @(posedge clk_i)
    if (pushst)
        retstack[retsp-12'd1] <= pushstate;
wire [7:0] retstacko = retstack[retsp];

always @(posedge clk_i)
    if (pushpt)
        pointstack[pointsp-12'd1] <= pointToPush;
wire [31:0] pointstacko = pointstack[pointsp];
wire [15:0] lgcx = pointstacko[31:16];
wire [15:0] lgcy = pointstacko[15:0];

always @(posedge clk_i)
    if (rstst)
        retsp <= 12'd0;
    else if (pushst)
        retsp <= retsp - 12'd1;
    else if (popst)
        retsp <= retsp + 12'd1;

always @(posedge clk_i)
    if (rstpt)
        pointsp <= 12'd0;
    else if (pushpt)
        pointsp <= pointsp - 12'd1;
    else if (poppt)
        pointsp <= pointsp + 12'd1;
`endif


// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
always @*
case(font_width[4:3])
2'd0:	for (n = 0; n < 8; n = n + 1)
			charbmpr[n] = charbmp[7-n];
2'd1:	for (n = 0; n < 16; n = n + 1)
			charbmpr[n] = charbmp[15-n];
2'd2,2'd3:	for (n = 0; n < 32; n = n + 1)
			charbmpr[n] = charbmp[31-n];
endcase

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
// Register blitter controls across clock domain.
// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
always @(posedge m_clk_i)
	bltA_badrx <= bltA_badr;
always @(posedge m_clk_i)
	bltA_modx <= bltA_mod;
always @(posedge m_clk_i)
	bltA_cntx <= bltA_cnt;
always @(posedge m_clk_i)
	bltB_badrx <= bltB_badr;
always @(posedge m_clk_i)
	bltB_modx <= bltB_mod;
always @(posedge m_clk_i)
	bltB_cntx <= bltB_cnt;
always @(posedge m_clk_i)
	bltC_badrx <= bltC_badr;
always @(posedge m_clk_i)
	bltC_modx <= bltC_mod;
always @(posedge m_clk_i)
	bltC_cntx <= bltC_cnt;
always @(posedge m_clk_i)
	bltSrcWidx <= bltSrcWid;
always @(posedge m_clk_i)
	blt_opx <= blt_op;
always @(posedge m_clk_i)
	bltPipedepthx <= bltPipedepth;

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
// RGB output display side
// clk clock domain
// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

// Register hctr,vctr onto the m_clk_i domain
always @(posedge m_clk_i)
	m_hctr <= hctr;
always @(posedge m_clk_i)
	m_vctr <= vctr;

// widen vertical blank interrupt pulse
always @(posedge vclk)
	if (vbl_int)
		vbl_reg <= 10'h3FF;
	else
		vbl_reg <= {vbl_reg[8:0],1'b0};

always @(posedge vclk)
	if (eol)
		hpos <= hstart;
	else
		hpos <= hpos + 12'd1;

always @(posedge vclk)
	if (eol & eof) begin
		fpos <= fpos + 5'd1;
		flashcnt <= flashcnt + 6'd1;
	end

always @(posedge m_clk_i)
	if (bpp)
		cyPPL <= gcy * {TargetWidth,2'b0};
	else
		cyPPL <= gcy * {TargetWidth,1'b0};
always @(posedge m_clk_i)
	if (bpp)
		offset <= cyPPL + {gcx,2'b0};
	else
		offset <= cyPPL + {gcx,1'b0};
always @(posedge m_clk_i)
	ma <= TargetBase + offset;

// Memory access state machine
always @(posedge m_clk_i)
if (rst_i) begin
	goto(ST_IDLE);
	bltCtrlx[13] <= 1'b1;	// Blitter is "done" to begin with.
	zorder <= `FALSE;
	aa <= fixedOne;
	ab <= 32'h0;
	ac <= 32'h0;
	at <= 32'h0;
	ba <= 32'h0;
	bb <= fixedOne;
	bc <= 32'h0;
	bt <= 32'h0;
	ca <= 32'h0;
	cb <= 32'h0;
	cc <= fixedOne;
	ct <= 32'h0;
	// Triangle
	tri_shade <= 1'b0;
  diff_x1x0 <= 16'd0;
  diff_y2y0 <= 16'd0;
  diff_x2x0 <= 16'd0;
  diff_y1y0 <= 16'd0;
  triangle_area0        <= 1'b0;
  triangle_area1        <= 1'b0;

  triangle_edge0_y2y1   <= 1'b0;
  triangle_edge0_xx1    <= 1'b0;
  triangle_edge0_x2x1   <= 1'b0;
  triangle_edge0_yy1    <= 1'b0;

  triangle_edge1_y0y2   <= 1'b0;
  triangle_edge1_xx2    <= 1'b0;
  triangle_edge1_x0x2   <= 1'b0;
  triangle_edge1_yy2    <= 1'b0;

  triangle_edge2_y1y0   <= 1'b0;
  triangle_edge2_xx0    <= 1'b0;
  triangle_edge2_x1x0   <= 1'b0;
  triangle_edge2_yy0    <= 1'b0;
end
else begin

rst_cmdq <= `FALSE;

if (peBltCtrl)
	bltCtrlx <= dat_ix;
if (peBltAdatx)
	bltA_datx <= dat_ix;
if (peBltBdatx)
	bltB_datx <= dat_ix;
if (peBltCdatx)
	bltC_datx <= dat_ix;
if (peBltDdatx)
	bltD_datx <= dat_ix;
if (peBltDbadrx)
	bltD_badrx <= dat_ix;
if (peBltDmodx)
	bltD_modx <= dat_ix;
if (peBltDcntx)
	bltD_cntx <= dat_ix;
if (peBltDstWidx)
	bltDstWidx <= dat_ix;

//p0x <= up0x;
//p0y <= up0y;
//p1x <= up1x;
//p1y <= up1y;

	// Pipeline the vertical calc.
	vpos <= m_vctr - vstart;
	if (bpp)
		vndx <= (vpos >> lowres) * {TargetWidth,2'b0};
	else
		vndx <= (vpos >> lowres) * {TargetWidth,1'b0};
	charndx <= (charcode << font_width[4:3]) * (font_height + 6'd1);



// -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -
// -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -
case(state)
ST_IDLE:
	call(OTHERS,ST_IDLE);
	
DELAY4: goto(DELAY3);
DELAY3:	goto(DELAY2);
DELAY2:	goto(DELAY1);
DELAY1:	return();

OTHERS:
	if (tblit_active)
		goto(tblit_state);
 
	else if (bltCtrlx[14]) begin
		if ((bltCtrlx[7:0] & 8'hAA)!=8'h00)
			case(blt_nch)
			2'd0:	goto(ST_BLTDMA2);
			2'd1:	goto(ST_BLTDMA4);
			2'd2:	goto(ST_BLTDMA6);
			2'd3:	goto(ST_BLTDMA8);
			endcase
		else begin // no channels are enabled
			bltCtrlx[14] <= 1'b0;
			bltCtrlx[13] <= 1'b1;
			return();
		end
	end
	else if (bltCtrlx[15]) begin
		bltCtrlx[15] <= 1'b0;
		bltCtrlx[14] <= 1'b1;
		bltCtrlx[13] <= 1'b0;
		bltA_wadr <= bltA_badrx;
		bltB_wadr <= bltB_badrx;
		bltC_wadr <= bltC_badrx;
		bltD_wadr <= bltD_badrx;
		bltA_wcnt <= 32'd1;
		bltB_wcnt <= 32'd1;
		bltC_wcnt <= 32'd1;
		bltD_wcnt <= 32'd1;
		bltA_dcnt <= 32'd1;
		bltB_dcnt <= 32'd1;
		bltC_dcnt <= 32'd1;
		bltA_hcnt <= 32'd1;
		bltB_hcnt <= 32'd1;
		bltC_hcnt <= 32'd1;
		bltD_hcnt <= 32'd1;
		if (bltCtrlx[1])
			blt_nch <= 2'b00;
		else if (bltCtrlx[3])
			blt_nch <= 2'b01;
		else if (bltCtrlx[5])
			blt_nch <= 2'b10;
		else if (bltCtrlx[7])
			blt_nch <= 2'b11;
		else begin
			bltCtrlx[15] <= 1'b0;
			bltCtrlx[14] <= 1'b0;
			bltCtrlx[13] <= 1'b1;
		end
		return();
	end

 	else if (ctrl[14])
 		goto(ngs);

	else if (!cmdq_empty)
		call(DELAY3,ST_CMD);
	
	else
		return();

ST_CMD:
	begin
/*		if (!cmdq_valid) begin
			$display("Command not valid.");
			return();
		end
		else
*/		begin
		ctrl[7:0] <= cmdq_out[39:32];
//		ctrl[14] <= 1'b0;
		case(cmdq_out[39:32])
		8'd0:	begin
				$display("Text blitting");
				tblit_active <= `TRUE;
				charcode <= cmdq_out[15:0];
				char_upd_xpos <= cmdq_out[31];
				tblit_state <= ST_READ_FONT_TBL;	// draw character
				return();
				end
		8'd1:	begin
				$display("Point plot");
				ctrl[11:8] <= cmdq_out[7:4];	// raster op
				goto(ST_PLOT);
				end
		8'd2:	begin
				ctrl[11:8] <= cmdq_out[7:4];	// raster op
				goto(DL_PRECALC);				// draw line
				end
		8'd3:	begin
				ctrl[11:8] <= cmdq_out[7:4];	// raster op
				goto(ST_FILLRECT);
				end
/*
		8'd4:	begin
				wrtx <= 1'b1;
				hwTexture <= cmdq_out[`TXHANDLE];
				state <= OTHERS;
				end
		8'd5:	begin
				hrTexture <= cmdq_out[`TXHANDLE];
				ctrl[11:8] <= cmdq_out[7:4];	// raster op
				state <= ST_TILERECT;
				end
*/
		8'd6:	begin	// Draw triangle
				ctrl[11:8] <= cmdq_out[7:4];	// raster op
				goto(DT_START);
				end
`ifdef BEZIER_CURVE
		8'd8:	begin	// Bezier Curve
				ctrl[11:8] <= cmdq_out[7:4];	// raster op
				fillCurve <= cmdq_out[1:0];
				goto(BC0);
				end
`else
		8'd8:	return();
`endif
`ifdef FLOOD_FILL
		8'd9:	goto(FF1);
`else
		8'd9:	return();
`endif
/*
		8'd11:	transform <= cmdq_out[0];
*/
		8'd12:	begin penColor <= cmdq_out[`CMDDAT]; return(); $display("Set pen color"); end
		8'd13:	begin fillColor <= cmdq_out[`CMDDAT]; return(); $display("Set fill color"); end
		8'd14:	begin alpha <= cmdq_out[`CMDDAT]; return(); end
		8'd16:	begin up0x <= cmdq_out[`CMDDAT]; return(); $display ("Set X0=%h", cmdq_out[`CMDDAT]); end
		8'd17:	begin up0y <= cmdq_out[`CMDDAT]; return(); $display ("Set Y0=%h", cmdq_out[`CMDDAT]); end
		8'd18:	begin up0z <= cmdq_out[`CMDDAT]; return(); end
		8'd19:	begin up1x <= cmdq_out[`CMDDAT]; return(); end
		8'd20:	begin up1y <= cmdq_out[`CMDDAT]; return(); end
		8'd21:	begin up1z <= cmdq_out[`CMDDAT]; return(); end
		8'd22:	begin up2x <= cmdq_out[`CMDDAT]; return(); end
		8'd23:	begin up2y <= cmdq_out[`CMDDAT]; return(); end
		8'd24:	begin up2z <= cmdq_out[`CMDDAT]; return(); end
		
		8'd25:	begin clipX0 <= cmdq_out[15:0]; return(); end
		8'd26:	begin clipY0 <= cmdq_out[15:0]; return(); end
		8'd27:	begin clipX1 <= cmdq_out[15:0]; return(); end
		8'd28:	begin clipY1 <= cmdq_out[15:0]; return(); end
		8'd29:	begin clipEnable <= cmdq_out[0]; return(); end

		8'd32:	begin aa <= cmdq_out[`CMDDAT]; return(); end
		8'd33:	begin ab <= cmdq_out[`CMDDAT]; return(); end
		8'd34:	begin ac <= cmdq_out[`CMDDAT]; return(); end
		8'd35:	begin at <= cmdq_out[`CMDDAT]; return(); end
		8'd36:	begin ba <= cmdq_out[`CMDDAT]; return(); end
		8'd37:	begin bb <= cmdq_out[`CMDDAT]; return(); end
		8'd38:	begin bc <= cmdq_out[`CMDDAT]; return(); end
		8'd39:	begin bt <= cmdq_out[`CMDDAT]; return(); end
		8'd40:	begin ca <= cmdq_out[`CMDDAT]; return(); end
		8'd41:	begin cb <= cmdq_out[`CMDDAT]; return(); end
		8'd42:	begin cc <= cmdq_out[`CMDDAT]; return(); end
		8'd43:	begin ct <= cmdq_out[`CMDDAT]; return(); end

		8'd254:	begin rst_cmdq <= `TRUE; return(); end
		8'd255:	return();	// NOP
		default:	return();
		endcase
		end
	end

// -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -
// Generic data latching state.
// Implemented as a subroutine.
// -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -

ST_LATCH_DATA:
	begin
		tocnt <= tocnt - 8'd1;
		if (m_ack_i)
			latched_data <= m_dat_i;
		else if (bpp)
			latched_data <= {4{32'h00FF0000}};	// red
		else
			latched_data <= {8{16'h7C00}};	// red
		if (m_ack_i||tocnt==8'd1||!m_cyc_o) begin
			m_cyc_o <= `LOW;
			m_we_o <= `LOW;
			m_sel_o <= 16'h0000;
			return();
		end
	end

ST_WAIT_ACK:
	begin
		tocnt <= tocnt - 8'd1;
		if (m_ack_i||tocnt==8'd1||!m_cyc_o) begin
			m_cyc_o <= `LOW;
			m_we_o <= `LOW;
			m_sel_o <= 16'h0000;
			return();
		end
	end
ST_WAIT_NACK:
	if (~m_ack_i) begin
		return();
	end

// -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -
// Character draw acceleration states
//
// Font Table - An entry for each font
// fwwwwwhhhhh-aaaa		- width and height
// aaaaaaaaaaaaaaaa		- char bitmap address
// ------------aaaa		- address offset of gylph width table
// aaaaaaaaaaaaaaaa		- low order address offset bits
//
// Glyph Table Entry
// ---wwwww---wwwww		- width
// ---wwwww---wwwww
// ---wwwww---wwwww
// ---wwwww---wwwww
// -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -

ST_READ_FONT_TBL:
	begin
		pixhc <= 5'd0;
		pixvc <= 5'd0;
    m_cyc_o <= `HIGH;
    m_sel_o <= 16'hFFFF;
		m_adr_o <= {font_tbl_adr[31:4],4'b0} + {font_id,4'b00};
		tocnt <= busto;
		tblit_adr <= {font_tbl_adr[31:4],4'b0} + {font_id,4'b00};
		call(ST_LATCH_DATA,ST_READ_FONT_TBL_NACK);
	end
ST_READ_FONT_TBL_NACK:
	if (~m_ack_i) begin
		font_fixed <= latched_data[127];
		font_width <= latched_data[125:120];
		font_height <= latched_data[117:112];
		charBmpBase <= latched_data[63:32];
		glyph_tbl_adr <= latched_data[31:0];
		tblit_state <= ST_READ_GLYPH_ENTRY;
		goto(ST_READ_GLYPH_ENTRY);
		//return();
	end
ST_READ_GLYPH_ENTRY:
	begin
		charBoxX0 <= p0x;
		charBoxY0 <= p0y;
		charBmpBase <= charBmpBase + charndx;
		if (font_fixed) begin
			tblit_state <= ST_READ_CHAR_BITMAP;
			goto(ST_READ_CHAR_BITMAP);
			//return();
		end
		else begin
			m_cyc_o <= `HIGH;
		  m_sel_o <= 16'hFFFF;
			m_adr_o <= {glyph_tbl_adr[31:4],4'h0} + {charcode[8:4],4'h0};
			tocnt <= busto;
			call(ST_LATCH_DATA,ST_READ_GLYPH_ENTRY_NACK);
		end
	end
ST_READ_GLYPH_ENTRY_NACK:
	if (~m_ack_i) begin
		font_width <= latched_data >> {charcode[3:0],3'b0};
		tblit_state <= ST_READ_CHAR_BITMAP;
		goto(ST_READ_CHAR_BITMAP);
		//return();
	end
ST_READ_CHAR_BITMAP:
	begin
		m_cyc_o <= `HIGH;
	  m_sel_o <= 16'hFFFF;
		m_adr_o <= charBmpBase + (pixvc << font_width[4:3]);
		tocnt <= busto;
		call(ST_LATCH_DATA,ST_READ_CHAR_BITMAP_NACK);
	end
ST_READ_CHAR_BITMAP_NACK:
	if (~m_ack_i) begin
		case(font_width[4:3])
		2'd0:	charbmp <= (latched_data >> {m_adr_o[3:0],3'b0}) & 32'h0ff;
		2'd1:	charbmp <= (latched_data >> {m_adr_o[3:1],4'b0}) & 32'h0ffff;
		2'd2:	charbmp <= latched_data >> {m_adr_o[3:2],5'b0};
		2'd3:	charbmp <= latched_data >> {m_adr_o[3],6'b0};
		endcase
		if (bpp) begin
			tgtaddr <= {8'h00,fixToInt(charBoxY0)} * {4'h00,TargetWidth,2'b0} + TargetBase + {fixToInt(charBoxX0),2'b0};
			tgtindex <= {14'h00,pixvc} * {4'h00,TargetWidth,2'b0};
		end
		else begin
			tgtaddr <= {8'h00,fixToInt(charBoxY0)} * {4'h00,TargetWidth,1'b0} + TargetBase + {fixToInt(charBoxX0),1'b0};
			tgtindex <= {14'h00,pixvc} * {4'h00,TargetWidth,1'b0};
		end
		tblit_state <= ST_WRITE_CHAR;
		goto(ST_WRITE_CHAR);
		//return();
	end
ST_WRITE_CHAR:
	goto(ST_WRITE_CHAR1);
ST_WRITE_CHAR1:
	begin
		if (bpp)
			tgtadr <= tgtaddr + tgtindex + {13'h00,pixhc,2'b0};
		else
			tgtadr <= tgtaddr + tgtindex + {14'h00,pixhc,1'b0};
		goto(ST_WRITE_CHAR2);
	end
ST_WRITE_CHAR2:
	begin
		if (~fillColor[`A]) begin
			if ((clipEnable && (fixToInt(charBoxX0) + pixhc < clipX0) || (fixToInt(charBoxX0) + pixhc >= clipX1) || (fixToInt(charBoxY0) + pixvc < clipY0)))
				;
			else if (fixToInt(charBoxX0) + pixhc >= TargetWidth)
				;
			else begin
				m_cyc_o <= `HIGH;
				m_we_o <= `HIGH;
				if (bpp)
					m_sel_o <= 16'd15 << {tgtadr[3:2],2'b0};
				else
					m_sel_o <= 16'd3 << {tgtadr[3:1],1'b0};
				m_adr_o <= tgtadr;
				if (bpp)
					m_dat_o <= {4{charbmp[0] ? penColor : fillColor}};
				else
					m_dat_o <= {8{charbmp[0] ? penColor[15:0] : fillColor[15:0]}};
				tocnt <= busto;
			end
		end
		else begin
			if (charbmp[0]) begin
				if (zbuf) begin
					if (clipEnable && (fixToInt(charBoxX0) + pixhc < clipX0 || fixToInt(charBoxX0) + pixhc >= clipX1 || fixToInt(charBoxY0) + pixvc < clipY0))
						;
					else if (fixToInt(charBoxX0) + pixhc >= TargetWidth)
						;
					else begin
						m_cyc_o <= `HIGH;
						if (bpp)
							m_sel_o <= 16'hF << {tgtadr[3:2],2'b0};
						else
							m_sel_o <= 16'd3 << {tgtadr[3:1],1'b0};
/*
						m_we_o <= `HIGH;
						m_adr_o <= tgtadr;
						m_dat_o <= {32{zlayer}};
*/				
						tocnt <= busto;
					end
				end
				else begin
					if (clipEnable && (fixToInt(charBoxX0) + pixhc < clipX0 || fixToInt(charBoxX0) + pixhc >= clipX1 || fixToInt(charBoxY0) + pixvc < clipY0))
						;
					else if (fixToInt(charBoxX0) + pixhc >= TargetWidth)
						;
					else begin
						m_cyc_o <= `HIGH;
						if (bpp)
							m_sel_o <= 16'hF << {tgtadr[3:2],2'b0};
						else
							m_sel_o <= 16'd3 << {tgtadr[3:1],1'b0};
						m_we_o <= `HIGH;
						m_adr_o <= tgtadr;
						m_dat_o <= bpp ? {4{penColor}} : {8{penColor[15:0]}};
						tocnt <= busto;
					end
				end
			end
		end
		charbmp <= {1'b0,charbmp[31:1]};
		pixhc <= pixhc + 5'd1;
		if (pixhc==font_width) begin
			tblit_state <= ST_READ_CHAR_BITMAP;
		    pixhc <= 5'd0;
		    pixvc <= pixvc + 5'd1;
		    if (clipEnable && (fixToInt(charBoxY0) + pixvc + 16'd1 >= clipY1))
		    	tblit_active <= `FALSE;
		    else if (fixToInt(charBoxY0) + pixvc + 16'd1 >= TargetHeight)
		    	tblit_active <= `FALSE;
		    else if (pixvc==font_height)
		    	tblit_active <= `FALSE;
		end
		else
			tblit_state <= ST_WRITE_CHAR;
		call(ST_LATCH_DATA,ST_WRITE_CHAR2_NACK);
	end
ST_WRITE_CHAR2_NACK:
	if (~m_ack_i) begin
		goto(tblit_state);
		if (!tblit_active) begin
			if (char_upd_xpos)
				up0x[31:16] <= up0x[31:16] + font_width;
			tblit_state <= OTHERS;
			return();
		end
		//return();
	end

// -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -
// Pixel plot acceleration states
// For binary raster operations a back-to-back read then write is performed.
// -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -

ST_PLOT:
	begin
		gcx <= fixToInt(p0x);
		gcy <= fixToInt(p0y);
		if (IsBinaryROP(ctrl[11:8]))
			call(DELAY3,ST_PLOT_READ);
		else
			call(DELAY3,ST_PLOT_WRITE);
	end
ST_PLOT_READ:
    begin
	    m_cyc_o <= `HIGH;
		m_adr_o <= ma;
		tocnt <= busto;
		// The memory address doesn't change from read to write so
		// there's no need to wait for it to update, it's already
		// correct.
		call(ST_LATCH_DATA,ST_PLOT_WRITE);
    end
ST_PLOT_WRITE:
	begin
		tocnt <= busto;
		set_pixel(penColor,alpha,ctrl[11:8],4'd1);
		goto(ST_WAIT_ACK);
	end

// -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -
// Line draw states
// Line drawing may also be done by the blitter.
// -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -

// State to setup invariants for DRAWLINE
DL_PRECALC:
	if (!ctrl[14]) begin
		ctrl[14] <= 1'b1;
		gcx <= fixToInt(p0x);
		gcy <= fixToInt(p0y);
		dx <= fixToInt(absx1mx0);
		dy <= fixToInt(absy1my0);
		if (p0x < p1x) sx <= 16'h0001; else sx <= 16'hFFFF;
		if (p0y < p1y) sy <= 16'h0001; else sy <= 16'hFFFF;
		err <= fixToInt(absx1mx0-absy1my0);
	end
	else if (IsBinaryROP(ctrl[11:8]) || zbuf)
		call(DELAY3,DL_GETPIXEL);
	else
		call(DELAY3,DL_SETPIXEL);
DL_GETPIXEL:
	begin
		m_cyc_o <= `HIGH;
		m_sel_o <= 16'hFFFF;
		m_adr_o <= zbuf ? ma[19:3] : ma;
		tocnt <= busto;
		call(ST_LATCH_DATA,DL_SETPIXEL);
	end
DL_SETPIXEL:
	begin
		tocnt <= busto;
		set_pixel(penColor,alpha,ctrl[11:8],4'd1);
		if (gcx==fixToInt(p1x) && gcy==fixToInt(p1y)) begin
			if (ctrl[7:0]==8'd2)	// drawline
				ctrl[14] <= 1'b0;
			call(ST_WAIT_ACK,DL_RET);
		end
		else
			call(ST_WAIT_ACK,DL_TEST);
	end
DL_TEST:
	if (~m_ack_i) begin
		tocnt <= busto;
		err <= err - ((e2 > -dy) ? dy : 16'd0) + ((e2 < dx) ? dx : 16'd0);
		if (e2 > -dy)
			gcx <= gcx + sx;
		if (e2 <  dx)
			gcy <= gcy + sy;
		if (IsBinaryROP(ctrl[11:8]) || zbuf)
			call(DELAY3,DL_GETPIXEL);
		else
			call(DELAY3,DL_SETPIXEL);
//		pause(DL_PRECALC);
	end
DL_RET:
	if (~m_ack_i) begin
		return();
		//pause(OTHERS);
	end

// -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -
// Draw horizontal line
//
// Used by the filled triangle draw. Sometimes draws eight pixels at a time
// to display memory under the right conditions which makes it much faster
// than the regular line draw.
// -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -

// Swap the x-coordinate so that the line is always drawn left to right.
HL_LINE:
	begin
		if (curx0 <= curx1) begin
			if (fixToInt(curx0) < clipX0 && clipEnable)
				gcx <= clipX0;
			else if (curx0[31])
				gcx <= 16'd0;
			else
				gcx <= fixToInt(curx0);
			if (fixToInt(curx1) > clipX1 && clipEnable)
				endx <= clipX1;
			else if (fixToInt(curx1) > TargetWidth)
				endx <= TargetWidth;
			else
  			endx <= fixToInt(curx1);
  	end
  	else begin
  		if (fixToInt(curx1) < clipX0 && clipEnable)
  			gcx <= clipX0;
  		else if (curx1[31])
  			gcx <= 16'd0;
  		else
  			gcx <= fixToInt(curx1);
  		if (fixToInt(curx0) > clipX1 && clipEnable)
  			endx <= clipX1;
  		else if (curx0 > TargetWidth)
  			endx <= TargetWidth;
  		else
	    	endx <= fixToInt(curx0);
  	end
		if (IsBinaryROP(ctrl[11:8]))
      call(DELAY3,HL_GETPIXEL);
    else
      call(DELAY3,HL_SETPIXEL);
	end
HL_GETPIXEL:
  begin
    triangle_edge0_xx1  <= $signed(gcx) - v1x;
    triangle_edge0_yy1  <= $signed(gcy) - v1y;
    triangle_edge1_xx2  <= $signed(gcx) - v2x;
    triangle_edge1_yy2  <= $signed(gcy) - v2y;
    triangle_edge2_xx0  <= $signed(gcx) - v0x;
    triangle_edge2_yy0  <= $signed(gcy) - v0y;
  	m_cyc_o <= `HIGH;
  	if (ma[3:1]==3'b000 && endx-gcx > (bpp ? 16'd4 : 16'd8) && !tri_shade)
  		m_sel_o <= 16'hFFFF;
  	else if (bpp)
    	m_sel_o <= 16'h000F << {ma[3:2],2'b0};
  	else
    	m_sel_o <= 16'h0003 << {ma[3:1],1'b0};
    m_adr_o <= ma;
    call(ST_LATCH_DATA,HL_GETPIXEL_NACK);
  end
HL_GETPIXEL_NACK:
	if (~m_ack_i)
		goto(HL_SETPIXEL);
HL_SETPIXEL:
	begin
	  if (ma[3:1]==3'b000 && endx-gcx > (bpp ? 16'd4 : 16'd8) && !tri_shade) begin
			set_pixel(fillColor,0,ctrl[11:8],bpp ? 4'd4 : 4'd8);
			if (bpp)
				gcx <= gcx + 16'd4;
			else
				gcx <= gcx + 16'd4;
		end
	  else begin
			set_pixel(fillColor,0,ctrl[11:8],4'd1);
			gcx <= gcx + 16'd1;
		end
		call(ST_WAIT_ACK,HL_SETPIXEL_NACK);
	end
HL_SETPIXEL_NACK:
	if (~m_ack_i) begin
		if (gcx>=endx)
			return();
		else begin
      if (IsBinaryROP(ctrl[11:8]))
        //pause(HL_GETPIXEL);
        goto(HL_GETPIXEL);
      else
      	//pause(HL_SETPIXEL);
      	goto(HL_SETPIXEL);
		end
	end

// -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -
// Filled Triangle drawing
// Uses the standard method for drawing filled triangles.
// Requires some fixed point math and division / multiplication.
// -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -

// Save off the original set of points defining the triangle. The points are
// manipulated later by the anti-aliasing outline draw.

DT_START:								// allows p?? to update
  begin
    up0xs <= up0x;
    up0ys <= up0y;
    up0zs <= up0z;
    up1xs <= up1x;
    up1ys <= up1y;
    up1zs <= up1z;
    up2xs <= up2x;
    up2ys <= up2y;
    up2zs <= up2z;
		goto(DT_SORT);
	end

// First step - sort vertices
// Sort points in order of Y coordinate. Also find the minimum and maximum
// extent of the triangle.
DT_SORT:
	begin
		ctrl[14] <= 1'b1;				// set busy indicator

    diff_x1x0 <= p1x - p0x;
    diff_y2y0 <= p2y - p0y;
    diff_x2x0 <= p2x - p0x;
    diff_y1y0 <= p1y - p0y;
		
		// Just draw a horizontal line if all vertices have the same y co-ord.
		if (p0y == p1y && p0y == p2y) begin
		   if (p0x < p1x && p0x < p2x)
		       curx0 <= p0x;
		   else if (p1x < p2x)
		       curx0 <= p1x;
		   else
		       curx0 <= p2x;
		   if (p0x > p1x && p0x > p2x)
		       curx1 <= p0x;
		   else if (p1x > p2x)
		       curx1 <= p1x;
		   else
		       curx1 <= p2x;
		   gcy <= fixToInt(p0y);
       goto(HL_LINE);
		end
		else if (p0y <= p1y && p0y <= p2y) begin
		  minY <= p0y;
			v0x <= p0x;
			v0y <= p0y;
			if (p1y <= p2y) begin
				v1x <= p1x;
				v1y <= p1y;
				v2x <= p2x;
				v2y <= p2y;
				maxY <= p2y;
			end
			else begin
				v1x <= p2x;
				v1y <= p2y;
				v2x <= p1x;
				v2y <= p1y;
				maxY <= p1y;
			end
		end
		else if (p1y <= p2y) begin
		  minY <= p1y;
			v0y <= p1y;
			v0x <= p1x;
			if (p0y <= p2y) begin
				v1y <= p0y;
				v1x <= p0x;
				v2y <= p2y;
				v2x <= p2x;
				maxY <= p2y;
			end
			else begin
				v1y <= p2y;
				v1x <= p2x;
				v2y <= p0y;
				v2x <= p0x;
				maxY <= p0y;
			end
		end
		// y2 < y0 && y2 < y1
		else begin
			v0y <= p2y;
			v0x <= p2x;
			minY <= p2y;
			if (p0y <= p1y) begin
				v1y <= p0y;
				v1x <= p0x;
				v2y <= p1y;
				v2x <= p1x;
				maxY <= p1y;
			end
			else begin
				v1y <= p1y;
				v1x <= p1x;
				v2y <= p0y;
				v2x <= p0x;
				maxY <= p0y;
			end
		end
		// Determine minium and maximum X coord.
		if (p0x <= p1x && p0x <= p2x) begin
		    minX <= p0x;
		    if (p1x <= p2x)
		        maxX <= p2x;
		    else
		        maxX <= p1x;
		end
		else if (p1x <= p2x) begin
		    minX <= p1x;
		    if (p0x <= p2x)
		        maxX <= p2x;
		    else
		        maxX <= p0x;
		end
		else begin
		    minX <= p2x;
		    if (p0x < p1x)
		        maxX <= p1x;
		    else
		        maxX <= p0x;
		end
		    
		goto(DT1);
	end

// Flat bottom (FB) or flat top (FT) triangle drawing
// Calc inv slopes
DT_SLOPE1:
	begin
		div_ld <= `TRUE;
		if (fbt) begin
			div_a <= w1x - w0x;
			div_b <= w1y - w0y;
		end
		else begin
			div_a <= w2x - w0x;
			div_b <= w2y - w0y;
		end
    triangle_area <= triangle_area0 - triangle_area1;
		//pause(DT_SLOPE1a);
		goto(DT_SLOPE1a);
	end
DT_SLOPE1a:
	if (div_idle) begin
		invslope0 <= div_qo[31:0];
		if (fbt) begin
			div_a <= w2x - w0x;
			div_b <= w2y - w0y;
		end
		else begin
			div_a <= w2x - w1x;
			div_b <= w2y - w1y;
		end
		div_ld <= `TRUE;
		//pause(DT_SLOPE2);
		goto(DT_SLOPE2);
	end
DT_SLOPE2:
	if (div_idle) begin
		invslope1 <= div_qo[31:0];
    if (fbt) begin
	    curx0 <= w0x;
 	    curx1 <= w0x;
			gcy <= fixToInt(w0y);
			call(HL_LINE,DT_INCY);
		end
		else begin
	    curx0 <= w2x;
      curx1 <= w2x;
      gcy <= fixToInt(w2y);
			call(HL_LINE,DT_INCY);
		end
	end
DT_INCY:
		if (fbt) begin
	    if (curx0 + invslope0 < minX)
        curx0 <= minX;
	    else if (curx0 + invslope0 > maxX)
        curx0 <= maxX;
	    else
		    curx0 <= curx0 + invslope0;
			if (curx1 + invslope1 < minX)
		    curx1 <= minX;
			else if (curx1 + invslope1 > maxX)
		    curx1 <= maxX;
			else
		    curx1 <= curx1 + invslope1;
			gcy <= gcy + 16'd1;
			if (gcy>=fixToInt(w1y))
				return();
			else
				call(HL_LINE,DT_INCY);
		end
		else begin
	    if (curx0 - invslope0 < minX)
        curx0 <= minX;
      else if (curx0 - invslope0 > maxX)
        curx0 <= maxX;
      else
        curx0 <= curx0 - invslope0;
      if (curx1 - invslope1 < minX)
        curx1 <= minX;
      else if (curx1 - invslope1 > maxX)
        curx1 <= maxX;
      else
        curx1 <= curx1 - invslope1;
			gcy <= gcy - 16'd1;
			if (gcy<fixToInt(w0y))
				return();
			else
				call(HL_LINE,DT_INCY);
		end

DT1:
	begin
    triangle_area0 <= diff_x1x0_int * diff_y2y0_int;
    triangle_area1 <= diff_x2x0_int * diff_y1y0_int;
    triangle_edge0_y2y1 <= v2y - v1y;
    triangle_edge0_x2x1 <= v2x - v1x;
    triangle_edge1_y0y2 <= v0y - v2y;
    triangle_edge1_x0x2 <= v0x - v2x;
    triangle_edge2_y1y0 <= v1y - v0y;
    triangle_edge2_x1x0 <= v1x - v0x;

		// Simple case of flat bottom
		if (v1y==v2y) begin
			fbt <= 1'b1;
			w0x <= v0x;
			w0y <= v0y;
			w1x <= v1x;
			w1y <= v1y;
			w2x <= v2x;
			w2y <= v2y;
			call(DT_SLOPE1,DT6);
		end
		// Simple case of flat top
		else if (v0y==v1y) begin
			fbt <= 1'b0;
			w0x <= v0x;
			w0y <= v0y;
			w1x <= v1x;
			w1y <= v1y;
			w2x <= v2x;
			w2y <= v2y;
			call(DT_SLOPE1,DT6);
		end
		// Need to calculte 4th vertice
		else begin
			div_ld <= `TRUE;
			div_a <= v1y - v0y;
			div_b <= v2y - v0y;
			//pause(DT2);
			goto(DT2);
		end
	end
DT2:
	if (div_idle) begin
		trimd <= 8'b11111111;
		v3y <= v1y;
		goto(DT3);
	end
DT3:
	begin
		trimd <= {trimd[6:0],1'b0};
		if (trimd==8'h00) begin
			v3x <= v0x + trimult[47:16];
			v3x[15:0] <= 16'h0000;
			goto(DT4);
		end
	end
DT4:
	begin
		fbt <= 1'b1;
		w0x <= v0x;
		w0y <= v0y;
		w1x <= v1x;
		w1y <= v1y;
		w2x <= v3x;
		w2y <= v3y;
		call(DT_SLOPE1,DT5);
	end
DT5:
	begin
		fbt <= 1'b0;
		w0x <= v1x;
		w0y <= v1y;
		w1x <= v3x;
		w1y <= v3y;
		w2x <= v2x;
		w2y <= v2y;
		call(DT_SLOPE1,DT6);
	end
DT6:
	begin
		ngs <= OTHERS;
		if (stkstate[0]==OTHERS || stkstate[0]==ST_IDLE) begin
      ctrl[14] <= 1'b0;
      return();
	    //goto(DT7);
		end
		else
	    return();
	end

// -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -
// Bezier Curve
// B(t) = (1-t)[(1-t)P0+tP1] + t[(1-t)P1 + tP2], 0 <= t <= 1.
// -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -

BC0:
	begin
	ctrl[14] <= 1'b1;
	bv0x <= p0x;
	bv0y <= p0y;
	bv1x <= p1x;
	bv1y <= p1y;
	bv2x <= p2x;
	bv2y <= p2y;
	bezierT <= bezierInc;
	otransform <= transform;
	transform <= `FALSE;
	up0x <= p0x;
	up0y <= p0y;
	goto(BC1);
	end
BC1:
	begin
	bezier1mT <= fixedOne - bezierT;
	goto(BC2);
	end
BC2:
	begin
	bezier1mTP0xw <= bezier1mT * bv0x;
	bezier1mTP1xw <= bezier1mT * bv1x;
	bezierTP1x <= bezierT * bv1x;
	bezierTP2x <= bezierT * bv2x;
	bezier1mTP0yw <= bezier1mT * bv0y;
	bezier1mTP1yw <= bezier1mT * bv1y;
	bezierTP1y <= bezierT * bv1y;
	bezierTP2y <= bezierT * bv2y;
	goto(BC3);
	end
BC3:
	begin
	bezierP0plusP1x <= bezier1mTP0xw[47:16] + bezierTP1x[47:16];
	bezierP1plusP2x <= bezier1mTP1xw[47:16] + bezierTP2x[47:16];
	bezierP0plusP1y <= bezier1mTP0yw[47:16] + bezierTP1y[47:16];
	bezierP1plusP2y <= bezier1mTP1yw[47:16] + bezierTP2y[47:16];
	goto(BC4);
	end
BC4:
	begin
	bezierBxw <= bezier1mT * bezierP0plusP1x + bezierT * bezierP1plusP2x;
	bezierByw <= bezier1mT * bezierP0plusP1y + bezierT * bezierP1plusP2y;
	call(DELAY2,BC5);
	end
BC5:
	begin
	up1x <= bezierBxw[47:16];
	up1y <= bezierByw[47:16];
  if (fillCurve[1]) begin
    up2x <= bv1x;
    up2y <= bv1y;
  end
	goto(BC5a);
	end
BC5a:
	begin
	ctrl[14] <= 1'b0;
	call(DL_PRECALC,|fillCurve ? BC6 : BC7);
	end
BC6:
  begin
	ctrl[14] <= 1'b0;
	call(DT_START,BC7);
  end
BC7:
	begin
	goto(BC1);
  up0x <= up1x;
  up0y <= up1y;
  bezierT <= bezierT + bezierInc;
  if (bezierT >= fixedOne) begin
  	up1x <= up2x;
  	up1y <= up2y;
		ctrl[14] <= 1'b0;
  	call(|fillCurve ? DT_START : DL_PRECALC,BC8);
  	//goto(BC8);
  end
	end
BC8:
	begin
    ctrl[14] <= 1'b0;
    //call(BC9,DL_PRECALC);
    goto(BC9);
    end
BC9:
	begin
    ctrl[14] <= 1'b0;
    transform <= otransform;
    return();
	end

// -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -
// Flood filling.
// The flood fill is called recursively. The caller saves the current point
// on a stack, the called routine pops the current point from the stack.
// -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -
`ifdef FLOOD_FILL
FF1:
	begin
		ctrl[14] <= 1'b1;		// indicate we're busy
		push_point(gcx,gcy);	// save old graphics cursor position
		gcx <= fixToInt(p0x);	// convert fixed point point spec to int coord
		gcy <= fixToInt(p0y);
		call(FLOOD_FILL,FF_EXIT);	// call flood fill routine
	end
FLOOD_FILL:
		call(DELAY3,FF2);	// addidtional delay needed for ma to settle
FF2:
	// If the point is outside of clipping region, just return.
	if (gcx >= TargetWidth || gcy >= TargetHeight) begin
		pop_point(gcx,gcy);
		return();
	end
	else if (clipEnable==`TRUE && (gcx < clipX0 || gcx >= clipX1 || gcy < clipY0 || gcy >= clipY1)) begin
		pop_point(gcx,gcy);
		return();
	end
	// Point is inside clipping region, so a fetch has to take place
	else begin
		m_cyc_o <= `HIGH;
		m_sel_o <= 16'hFFFF;
		m_adr_o <= zbuf ? ma[19:3] : ma;
		tocnt <= busto;
		call(ST_LATCH_DATA,FF3);
	end
FF3:
	// Color already filled ? -> return
	if (fillColor==pixel_i) begin
		pop_point(gcx,gcy);
		return();
	end
	// Border hit ? -> return
	else if (penColor==pixel_i) begin
		pop_point(gcx,gcy);
		return();
	end
	// Set the pixel color then check the surrounding points.
	else begin
		set_pixel(fillColor,alpha,4'd1,4'd1);
		goto(FF4);
	end
FF4:	// check to the "south"
	begin
//		zbram_we <= 2'b00;
		push_point(gcx,gcy);			// save the point off
		gcy <= gcy + 1;
		call(FLOOD_FILL,FF5);		// call flood fill
	end
FF5:	// check to the "north"
	if (gcy==16'h0)
		goto(FF6);
	else begin
		push_point(gcx,gcy);		// save the point off
		gcy <= gcy - 1;
		call(FLOOD_FILL,FF6);	// call flood fill
	end
FF6:	// check to the "west"
	if (gcx==16'd0)
		goto(FF7);
	else begin
		push_point(gcx,gcy);		// save the point off
		gcx <= gcx - 1;
		call(FLOOD_FILL,FF7);	// call flood fill
	end
FF7:	// Check to the "east"
	begin
		push_point(gcx,gcy);			// save the point off
		gcx <= gcx + 1;				// next horiz. pos.
		call(FLOOD_FILL,FF8);		// call flood fill
	end
FF8:	// return
	begin
		pop_point(gcx,gcy);
		return();
	end
FF_EXIT:
	begin
		ctrl[14] <= 1'b0;	// signal graphics operation done (not busy)
		return();
	end
`endif

// -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -
// Blitter DMA
// Blitter has four DMA channels, three source channels and one destination
// channel.
// -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -

	// Blit channel A
ST_BLTDMA2:
	begin
	  m_cyc_o <= `HIGH;
		m_adr_o <= bltA_wadr;
		if (bpp) begin
			m_sel_o <= 16'h000F << {bltB_wadr[3:2],2'b0};
			bltinc <= bltCtrl[8] ? 32'hFFFFFFFC : 32'd4;
		end
		else begin
			m_sel_o <= 16'h0003 << {bltB_wadr[3:1],1'b0};
			bltinc <= bltCtrl[8] ? 32'hFFFFFFFE : 32'd2;
		end
		call(ST_LATCH_DATA,ST_BLTDMA2_NACK);
    end
ST_BLTDMA2_NACK:
	if (~m_ack_i) begin
		if (bpp)
			bltA_datx <= (latched_data >> {bltA_wadr[3:2],5'h0}) & 32'hFFFFFFFF;
		else
			bltA_datx <= (latched_data >> {bltA_wadr[3:1],4'h0}) & 32'h0000FFFF;
		bltA_wadr <= bltA_wadr + bltinc;
    bltA_hcnt <= bltA_hcnt + 32'd1;
    if (bltA_hcnt==bltSrcWid) begin
	    bltA_hcnt <= 32'd1;
	    if (bpp)
	    	bltA_wadr <= bltA_wadr + {bltA_modx[31:2],2'b0} + bltinc;
	    else
	    	bltA_wadr <= bltA_wadr + {bltA_modx[31:1],1'b0} + bltinc;
		end
    bltA_wcnt <= bltA_wcnt + 32'd1;
    bltA_dcnt <= bltA_dcnt + 32'd1;
    if (bltA_wcnt>=bltA_cntx) begin
      bltA_wadr <= bltA_badrx;
      bltA_wcnt <= 32'd1;
      bltA_hcnt <= 32'd1;
    end
		if (bltA_dcnt>=bltD_cntx)
			bltCtrlx[1] <= 1'b0;
		if (bltCtrlx[3])
			blt_nch <= 2'b01;
		else if (bltCtrlx[5])
			blt_nch <= 2'b10;
		else if (bltCtrlx[7])
			blt_nch <= 2'b11;
		else
			blt_nch <= 2'b00;
		return();
	end

	// Blit channel B
ST_BLTDMA4:
	begin
		m_cyc_o <= `HIGH;
		m_adr_o <= bltB_wadr;
		if (bpp) begin
			m_sel_o <= 16'h000F << {bltB_wadr[3:2],2'b0};
			bltinc <= bltCtrlx[9] ? 32'hFFFFFFFC : 32'd4;
		end
		else begin
			m_sel_o <= 16'h0003 << {bltB_wadr[3:1],1'b0};
			bltinc <= bltCtrlx[9] ? 32'hFFFFFFFE : 32'd2;
		end
		call(ST_LATCH_DATA,ST_BLTDMA4_NACK);
	end
ST_BLTDMA4_NACK:
	if (~m_ack_i) begin
		if (bpp)
			bltB_datx <= (latched_data >> {bltB_wadr[3:2],5'h0}) & 32'hFFFFFFFF;
		else
			bltB_datx <= (latched_data >> {bltB_wadr[3:1],4'h0}) & 32'h0000FFFF;
    bltB_wadr <= bltB_wadr + bltinc;
    bltB_hcnt <= bltB_hcnt + 32'd1;
    if (bltB_hcnt>=bltSrcWidx) begin
      bltB_hcnt <= 32'd1;
      if (bpp)
      	bltB_wadr <= bltB_wadr + {bltB_modx[31:2],2'b0} + bltinc;
      else
      	bltB_wadr <= bltB_wadr + {bltB_modx[31:1],1'b0} + bltinc;
    end
    bltB_wcnt <= bltB_wcnt + 32'd1;
    bltB_dcnt <= bltB_dcnt + 32'd1;
    if (bltB_wcnt>=bltB_cntx) begin
      bltB_wadr <= bltB_badrx;
      bltB_wcnt <= 32'd1;
      bltB_hcnt <= 32'd1;
    end
		if (bltB_dcnt==bltD_cntx)
			bltCtrlx[3] <= 1'b0;
		if (bltCtrlx[5])
			blt_nch <= 2'b10;
		else if (bltCtrlx[7])
			blt_nch <= 2'b11;
		else if (bltCtrlx[1])
			blt_nch <= 2'b00;
		else
			blt_nch <= 2'b01;
		return();
	end

	// Blit channel C
ST_BLTDMA6:
	begin
		m_cyc_o <= `HIGH;
		m_adr_o <= bltC_wadr;
		if (bpp) begin
			m_sel_o <= 16'hF << {bltC_wadr[3:2],2'b0};
			bltinc <= bltCtrlx[10] ? 32'hFFFFFFFC : 32'd4;
		end
		else begin
			m_sel_o <= 16'h3 << {bltC_wadr[3:1],1'b0};
			bltinc <= bltCtrlx[10] ? 32'hFFFFFFFE : 32'd2;
		end
		call(ST_LATCH_DATA,ST_BLTDMA6_NACK);		
	end
ST_BLTDMA6_NACK:
	if (~m_ack_i) begin
		if (bpp)
			bltC_datx <= (latched_data >> {bltC_wadr[3:2],5'h0}) & 32'hFFFFFFFF;
		else
			bltC_datx <= (latched_data >> {bltC_wadr[3:1],4'h0}) & 32'h0000FFFF;
    bltC_wadr <= bltC_wadr + bltinc;
    bltC_hcnt <= bltC_hcnt + 32'd1;
    if (bltC_hcnt==bltSrcWidx) begin
      bltC_hcnt <= 32'd1;
      if (bpp)
      	bltC_wadr <= bltC_wadr + {bltC_modx[31:2],2'b0} + bltinc;
      else
      	bltC_wadr <= bltC_wadr + {bltC_modx[31:1],1'b0} + bltinc;
    end
    bltC_wcnt <= bltC_wcnt + 32'd1;
    bltC_dcnt <= bltC_dcnt + 32'd1;
    if (bltC_wcnt>=bltC_cntx) begin
      bltC_wadr <= bltC_badrx;
      bltC_wcnt <= 32'd1;
      bltC_hcnt <= 32'd1;
    end
		if (bltC_dcnt>=bltD_cntx)
			bltCtrlx[5] <= 1'b0;
		if (bltCtrlx[7])
			blt_nch <= 2'b11;
		else if (bltCtrlx[1])
			blt_nch <= 2'b00;
		else if (bltCtrlx[3])
			blt_nch <= 2'b01;
		else
			blt_nch <= 2'b10;
		return();
	end

	// Blit channel D
ST_BLTDMA8:
	begin
		m_cyc_o <= `HIGH;
		m_we_o <= `HIGH;
		m_adr_o <= bltD_wadr;
		// If there's no source then a fill operation must be taking place.
		if (bpp) begin
			m_sel_o <= 16'h000F << {bltD_wadr[3:2],2'b0};
			if (bltCtrlx[1]|bltCtrlx[3]|bltCtrlx[5])
				m_dat_o <= {4{bltabc}};
			else
				m_dat_o <= {4{bltD_datx}};	// fill color
			bltinc <= bltCtrlx[11] ? 32'hFFFFFFFC : 32'd4;
		end
		else begin
			m_sel_o <= 16'h0003 << {bltD_wadr[3:1],1'b0};
			if (bltCtrlx[1]|bltCtrlx[3]|bltCtrlx[5])
				m_dat_o <= {8{bltabc[15:0]}};
			else
				m_dat_o <= {8{bltD_datx[15:0]}};	// fill color
			bltinc <= bltCtrlx[11] ? 32'hFFFFFFFE : 32'd2;
		end
		call(ST_WAIT_ACK,ST_BLTDMA8_NACK);
	end
ST_BLTDMA8_NACK:
	if (~m_ack_i) begin
		bltD_wadr <= bltD_wadr + bltinc;
		bltD_wcnt <= bltD_wcnt + 32'd1;
		bltD_hcnt <= bltD_hcnt + 32'd1;
		if (bltD_hcnt>=bltDstWidx) begin
			bltD_hcnt <= 32'd1;
			if (bpp)
				bltD_wadr <= bltD_wadr + {bltD_modx[31:2],2'b0} + bltinc;
			else 
				bltD_wadr <= bltD_wadr + {bltD_modx[31:1],1'b0} + bltinc;
		end
		if (bltD_wcnt>=bltD_cntx) begin
			bltCtrlx[14] <= 1'b0;
			bltCtrlx[13] <= 1'b1;
			bltCtrlx[7] <= 1'b0;
		end
		if (bltCtrlx[1])
			blt_nch <= 2'b00;
		else if (bltCtrlx[3])
			blt_nch <= 2'b01;
		else if (bltCtrlx[5])
			blt_nch <= 2'b10;
		else
			blt_nch <= 2'b11;
		return();
	end

// -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -
// Draw a filled rectangle, uses the blitter.
// -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -

ST_FILLRECT:
	begin
		// Switching the points around will have the side effect
		// of switching the transformed points around as well.
		if (p1y < p0y) up0y <= up1y;
		if (p1x < p0x) up0x <= up1x;
		dx <= fixToInt(absx1mx0) + 16'd1;	// Order of points doesn't matter here.
		dy <= fixToInt(absy1my0) + 16'd1;
		// Wait for previous blit to finish
		// then delay 1 cycle for point switching
		if (bltCtrlx[13]||!(bltCtrlx[15]||bltCtrlx[14]))
			call(DELAY1,ST_FILLRECT_CLIP);
	end
ST_FILLRECT_CLIP:
	begin
		if (fixToInt(p0x) + dx > TargetWidth)
			dx <= TargetWidth - fixToInt(p0x);
		if (fixToInt(p0y) + dy > TargetHeight)
			dy <= TargetHeight - fixToInt(p0y);
		goto(ST_FILLRECT2);
	end
ST_FILLRECT2:
	begin
		bltD_badrx <= {8'h00,fixToInt(p0y)} * {TargetWidth,1'b0} + TargetBase + {fixToInt(p0x),1'b0};
		bltD_modx <= {TargetWidth - dx,1'b0};
		bltD_cntx <= dx * dy;
		bltDstWidx <= dx;
		bltD_datx <= fillColor;
		bltCtrlx[15:0] <= 16'h8080;
		return();
	end

default:    goto(WAIT_RESET);
endcase

// -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -
// Support tasks
// -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -

task set_pixel;
input [31:0] color;
input [15:0] alpha;
input [3:0] rop;
input [3:0] cnt;
begin
	m_cyc_o <= `LOW;
	m_we_o <= `LOW;
	m_sel_o <= 1'b0;
	if (fnClip(gcx,gcy) && cnt==4'd1)
		;
/*
	else if (zbuf) begin
		m_cyc_o <= `HIGH;
		m_we_o <= `HIGH;
		m_sel_o <= 16'hFFFF;
		m_adr_o <= ma[31:1];
		m_dat_o <= latched_data & ~{128'b1111 << {ma[4:0],2'b0}} | ({124'b0,zlayer} << {ma[4:0],2'b0});
	end
*/
	else begin
		// The same operation is performed on all pixels, however the
		// data mask is set so that only the desired pixel is updated
		// in memory.
		// The same operation is performed on all pixels, however the
		// data mask is set so that only the desired pixel is updated
		// in memory.
		m_cyc_o <= `HIGH;
		m_we_o <= `HIGH;
		if (bpp) begin // 32bpp
			if (cnt==4) begin
				for (n = 0; n < 4; n = n + 1) begin
					if (fnClip(gcx+n,gcy)) begin
						m_sel_o[n*4] <= 1'b0;
						m_sel_o[n*4+1] <= 1'b0;
						m_sel_o[n*4+2] <= 1'b0;
						m_sel_o[n*4+3] <= 1'b0;
					end
					else begin
						m_sel_o[n*4] <= 1'b1;
						m_sel_o[n*4+1] <= 1'b1;
						m_sel_o[n*4+2] <= 1'b1;
						m_sel_o[n*4+3] <= 1'b1;
					end
				end
			end
			else
				m_sel_o <= 16'h000F << {ma[3:2],2'b0};
			m_adr_o <= ma;
			case(rop)
			4'd0:	m_dat_o <= {4{32'h00000000}};
			4'd1:	m_dat_o <= {4{color}};
			4'd3:	m_dat_o <= {
				blend8(color,latched_data[127:96],alpha),
				blend8(color,latched_data[ 95:64],alpha),
				blend8(color,latched_data[ 63:32],alpha),
				blend8(color,latched_data[ 31: 0],alpha)
				};
			4'd4:	m_dat_o <= {4{color}} & latched_data;
			4'd5:	m_dat_o <= {4{color}} | latched_data;
			4'd6:	m_dat_o <= {4{color}} ^ latched_data;
			4'd7:	m_dat_o <= {4{color}} & ~latched_data;
			4'hF:	m_dat_o <= {4{32'h00FFFFFF}};
			default:	m_dat_o <= {4{32'h00000000}};
			endcase
		end
		else begin
			if (cnt==8) begin
				for (n = 0; n < 8; n = n + 1) begin
					if (fnClip(gcx+n,gcy)) begin
						m_sel_o[n*2] <= 1'b0;
						m_sel_o[n*2+1] <= 1'b0;
					end
					else begin
						m_sel_o[n*2] <= 1'b1;
						m_sel_o[n*2+1] <= 1'b1;
					end
				end
			end
			else
				m_sel_o <= 16'b11 << {ma[3:1],1'b0};
			m_adr_o <= ma;
			case(rop)
			4'd0:	m_dat_o <= {8{16'h0000}};
			4'd1:	m_dat_o <= {8{color[15:0]}};
			4'd3:	m_dat_o <= {
				blend(color[15:0],latched_data[127:112],alpha),
				blend(color[15:0],latched_data[111: 96],alpha),
				blend(color[15:0],latched_data[ 95: 80],alpha),
				blend(color[15:0],latched_data[ 79: 64],alpha),
				blend(color[15:0],latched_data[ 63: 48],alpha),
				blend(color[15:0],latched_data[ 47: 32],alpha),
				blend(color[15:0],latched_data[ 31: 16],alpha),
				blend(color[15:0],latched_data[ 15:  0],alpha)
				};
			4'd4:	m_dat_o <= {8{color[15:0]}} & latched_data;
			4'd5:	m_dat_o <= {8{color[15:0]}} | latched_data;
			4'd6:	m_dat_o <= {8{color[15:0]}} ^ latched_data;
			4'd7:	m_dat_o <= {8{color[15:0]}} & ~latched_data;
			4'hF:	m_dat_o <= {8{16'h7FFF}};
			default:	m_dat_o <= {8{16'h0000}};
			endcase
		end
	end
end
endtask

task goto;
input [7:0] st;
begin
	state <= st;
end
endtask

`ifdef FLOOD_FILL
task call;
input [7:0] st;
input [7:0] nst;
begin
	if (retsp==12'd1) begin	// stack overflow ?
    rstst <= `TRUE;
		ctrl[14] <= 1'b0;
		state <= ST_IDLE;	// abort operation, go back to idle
	end
	else begin
    pushstate <= st;
    pushst <= `TRUE;
		goto(nst);
	end
end
endtask

task return;
begin
	state <= retstacko;
	popst <= `TRUE;
end
endtask
`else
task call;
input [7:0] st;
input [7:0] nst;
begin
	for (n = 0; n < 7; n = n + 1)
		stkstate[n+1] <= stkstate[n];
	stkstate[0] <= st;
	state <= nst;
end
endtask

task return;
begin
	for (n = 0; n < 7; n = n + 1)
		stkstate[n] <= stkstate[n+1];
	stkstate[7] <= ST_IDLE;
	state <= stkstate[0];
end
endtask

`endif

`ifdef FLOOD_FILL
task push_point;
input [15:0] px;
input [15:0] py;
begin
	if (pointsp==12'd1) begin
		rstpt <= `TRUE;
		rstst <= `TRUE;
		ctrl[14] <= 1'b0;
		state <= ST_IDLE;
	end
	else begin
		pointToPush <= {px,py};
		pushpt <= `TRUE;
	end
end
endtask

task pop_point;
output [15:0] px;
output [15:0] py;
begin
	px = pointstacko[31:16];
	py = pointstacko[15:0];
	poppt <= `TRUE;
end
endtask
`endif

endmodule
