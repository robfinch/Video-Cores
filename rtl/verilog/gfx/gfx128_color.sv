/*
ORSoC GFX accelerator core
Copyright 2012, ORSoC, Per Lenander, Anton Fosselius.

Components for aligning colored pixels to memory and the inverse

 This file is part of orgfx.

 orgfx is free software: you can redistribute it and/or modify
 it under the terms of the GNU Lesser General Public License as published by
 the Free Software Foundation, either version 3 of the License, or
 (at your option) any later version. 

 orgfx is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU Lesser General Public License for more details.

 You should have received a copy of the GNU Lesser General Public License
 along with orgfx.  If not, see <http://www.gnu.org/licenses/>.

*/

module color_to_memory128(color_depth_i, color_i, x_lsb_i, mem_o, sel_o);
input  [1:0]  color_depth_i;
input  [31:0] color_i;
input  [3:0]  x_lsb_i;
output [127:0] mem_o;
output reg [15:0]  sel_o;

reg [3:0] sel1;
always_comb
	case (color_depth_i)
	2'd0:	sel1 = 4'h1;
	2'd1:	sel1 = 4'h3;
	2'd3:	sel1 = 4'hF;
	default:	sel1 = 4'h3;
	endcase

always_comb
	sel_o = sel1 << x_lsb_i;

reg [5:0] shftcnt;
always_comb
	shftcnt = {x_lsb_i,3'd0};

reg [31:0] mask;
always @*
case(color_depth_i)
2'b00:	mask = 32'h000000FF;
2'b01:	mask = 32'h0000FFFF;
2'b11:	mask = 32'hFFFFFFFF;
default:	mask = 32'h00000000;
endcase

assign mem_o = {32'd0,color_i & mask} << shftcnt;

endmodule

module memory_to_color128(color_depth_i, mem_i, mem_lsb_i, color_o, sel_o);
input  [1:0]  color_depth_i;
input  [127:0] mem_i;
input  [3:0]  mem_lsb_i;
output reg [31:0] color_o;
output reg [15:0]  sel_o;

reg [3:0] sel1;
always_comb
	case (color_depth_i)
	2'd0:	sel1 = 4'h1;
	2'd1:	sel1 = 4'h3;
	2'd3:	sel1 = 4'hF;
	default:	sel1 = 4'h3;
	endcase

always_comb
	sel_o = sel1 << mem_lsb_i;

reg [5:0] shftcnt;
always_comb
	shftcnt = {mem_lsb_i,3'd0};

reg [31:0] mask;
always @*
case(color_depth_i)
2'b00:	mask = 32'h000000FF;
2'b01:	mask = 32'h0000FFFF;
2'b11:	mask = 32'hFFFFFFFF;
default:	mask = 32'h00000000;
endcase

always_comb
	color_o = (mem_i >> shftcnt) & mask;

endmodule

