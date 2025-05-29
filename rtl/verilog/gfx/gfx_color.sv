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

module color_to_memory(rmw_i, bpp_i, color_i, mb_i, mem_i, mem_o, sel_o);
parameter MDW=256;
input rmw_i;
input [5:0] bpp_i;
input [31:0] color_i;
input [7:0] mb_i;
input [MDW-1:0] mem_i;
output [MDW-1:0] mem_o;
output reg [MDW/8-1:0] sel_o;

integer n1;

reg [3:0] sel1;
always_comb
	case (bpp_i[5:3]+|bpp_i[2:0])
	3'd1:	sel1 = 4'h1;
	3'd2:	sel1 = 4'h3;
	3'd3:	sel1 = 4'h7;
	3'd4:	sel1 = 4'hF;
	default:	sel1 = 4'hF;
	endcase

always_comb
if (rmw_i)
	sel_o = {MDW/8{1'b1}};
else
	sel_o = {{MDW/8{1'd0}},sel1} << mb_i[7:3];

reg [31:0] mask;
always_comb
	for (n1 = 0; n1 < 32; n1 = n1 + 1)
		if (n1 < bpp_i)
			mask[n1] = 1'b1;
		else
			mask[n1] = 1'b0;

reg [MDW-1:0] maskshftd;

always_comb
	maskshftd = mask << mb_i;

assign mem_o = ({{MDW{1'd0}},color_i & mask} << mb_i) | (mem_i & ~maskshftd);

endmodule

module memory_to_color(rmw_i, bpp_i, mem_i, mb_i, color_o, sel_o);
parameter MDW=256;
input rmw_i;
input [5:0] bpp_i;
input [MDW-1:0] mem_i;
input [7:0] mb_i;
output reg [31:0] color_o;
output reg [MDW/8-1:0]  sel_o;

integer n1;
reg [3:0] sel1;
always_comb
	case (bpp_i[5:3]+|bpp_i[2:0])
	3'd1:	sel1 = 4'h1;
	3'd2:	sel1 = 4'h3;
	3'd3:	sel1 = 4'h7;
	3'd4:	sel1 = 4'hF;
	default: sel1 = 4'hF;
	endcase

always_comb
if (rmw_i)
	sel_o = {MDW{1'b1}};
else
	sel_o = {{MDW/8{1'd0}},sel1} << mb_i[7:3];

reg [31:0] mask;
always_comb
	for (n1 = 0; n1 < 32; n1 = n1 + 1)
		if (n1 < bpp_i)
			mask[n1] = 1'b1;
		else
			mask[n1] = 1'b0;

always_comb
	color_o = (mem_i >> mb_i) & mask;

endmodule
