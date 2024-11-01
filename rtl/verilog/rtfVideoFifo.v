`timescale 1ns / 1ps
// ============================================================================
//        __
//   \\__/ o\    (C) 2008-2024  Robert Finch, Stratford
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
//	Verilog 1995
//
// ============================================================================
//
module rtfVideoFifo(rst, wclk, wr, di, rclk, rd, do, cnt);
input rst;
input wclk;
input wr;
input [31:0] di;
input rclk;
input rd;
output [31:0] do;
output [8:0] cnt;
reg [8:0] cnt;

reg [8:0] wr_ptr;
reg [8:0] rd_ptr,rrd_ptr;
reg [31:0] mem [0:511];

always @(posedge wclk)
	if (rst)
		wr_ptr <= 9'd0;
	else if (wr) begin
		mem[wr_ptr] <= di;
		wr_ptr <= wr_ptr + 9'd1;
	end

always @(posedge rclk)
	if (rst)
		rd_ptr <= 9'd0;
	else if (rd)
		rd_ptr <= rd_ptr + 9'd1;
always @(posedge rclk)
	rrd_ptr <= rd_ptr;

assign do = mem[rrd_ptr];

always @(wr_ptr or rd_ptr)
	if (rd_ptr > wr_ptr)
		cnt <= wr_ptr + (10'd512 - rd_ptr);
	else
		cnt <= wr_ptr - rd_ptr;

endmodule
