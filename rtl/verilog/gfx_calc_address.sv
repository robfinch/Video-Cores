`timescale 1ns / 1ps
// ============================================================================
//        __
//   \\__/ o\    (C) 2015-2025  Robert Finch, Waterloo
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
// Latency of: 3 clocks
// ============================================================================
//
// Compute the graphics address
//
import gfx_pkg::*;

module gfx_calc_address(clk, base_address_i, coeff1_i, coeff2_i, bpp_i, cbpp_i, bmp_width_i, x_coord_i, y_coord_i,
	address_o, mb_o, me_o, ce_o);
parameter SW = 256;		// strip width in bits
parameter BN = $clog2(SW)-1;
parameter BPP12 = 1'b0;
input clk;
input [31:0] base_address_i;
input [15:0] coeff1_i;
input [9:0] coeff2_i;
input [5:0] bpp_i;
input [5:0] cbpp_i;
input [15:0] bmp_width_i;	// pixel per line
input [15:0] x_coord_i;
input [15:0] y_coord_i;
output reg [31:0] address_o;
output reg [BN:0] mb_o;			// mask begin
output reg [BN:0] me_o;			// mask end
output reg [BN:0] ce_o;			// color bits end

// Compute the fixed point horizonal strip number value. This has 16 binary
// point places.
reg [31:0] strip_num65k;
always_ff @(posedge clk)
	strip_num65k <= x_coord_i * coeff1_i;
// Truncate off the binary fraction to get the strip number. The strip
// number will be used to form part of the address.
wire [9:0] strip_num = strip_num65k[25:16];
// Calculate pixel position within strip using the fractional part of the
// horizontal strip number.
wire [15:0] strip_fract = strip_num65k[15:0]+(SW-1);  // +7F to round
// Pixel beginning bit is ratio of pixel # into all bits used by pixels
reg [17:0] ndx;
always_ff @(posedge clk)
begin
	case(SW)
	32:		ndx <= strip_fract[15:7] * {coeff2_i,3'b0};
	64:		ndx <= strip_fract[15:7] * {coeff2_i,2'b0};
	128:	ndx <= strip_fract[15:7] * {coeff2_i,1'b0};
	256:	ndx <= strip_fract[15:7] * coeff2_i;
	default:	ndx <= strip_fract[15:7] * coeff2_i;
	endcase
end
// Get whole pixel position (discard fraction)
always_comb
begin
	case(SW)
	32:	mb_o = ndx[17:12];
	64:	mb_o = ndx[17:11];
	128: mb_o = ndx[17:10];
	256: mb_o = ndx[17:9];
	default:	mb_o = ndx[17:9];
	endcase
end
always_comb me_o = mb_o + bpp_i; // Set high order position for mask
always_comb ce_o = mb_o + cbpp_i;
// num_strips is essentially a constant value unless the screen resolution changes.
// Gain performance here by regstering the multiply so that there aren't two
// cascaded multiplies when calculating the offset.
reg [31:0] num_strips65k;
always_ff @(posedge clk)
	num_strips65k <= bmp_width_i * coeff1_i;
wire [9:0] num_strips = num_strips65k[25:16];
reg [31:0] offset;
always_ff @(posedge clk)
begin
	case(SW)
	32:		offset <= {(({16'b0,num_strips} * y_coord_i) + strip_num),2'h0};
	64:		offset <= {(({16'b0,num_strips} * y_coord_i) + strip_num),3'h0};
	128:	offset <= {(({16'b0,num_strips} * y_coord_i) + strip_num),4'h0};
	256:	offset <= {(({16'b0,num_strips} * y_coord_i) + strip_num),5'h0};
	default:	offset <= {(({16'b0,num_strips} * y_coord_i) + strip_num),5'h0};
	endcase
end

always_comb
	address_o = base_address_i + offset;

endmodule
