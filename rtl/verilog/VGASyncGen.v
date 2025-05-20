// ============================================================================
//        __
//   \\__/ o\    (C) 2012-2025  Robert Finch, Waterloo
//    \  __ /    All rights reserved.
//     \/_//     robfinch<remove>@finitron.ca
//       ||
//
//	VGASyncGen.v
//		VGA sync generator
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
//	VGA video sync generator.
//
//	This module generates the basic sync timing signals required for a
//	VGA display.
//
// ============================================================================

module VGASyncGen(rst, clk, eol, eof, hSync, vSync, hCtr, vCtr,
    blank, vblank, vbl_int, border,
    hTotal_i, vTotal_i,
    hSyncOn_i, hSyncOff_i, vSyncOn_i, vSyncOff_i,
    hBlankOn_i, hBlankOff_i, vBlankOn_i, vBlankOff_i,
    hBorderOn_i, vBorderOn_i, hBorderOff_i, vBorderOff_i);
input rst;			// reset
input clk;			// video clock
output reg eol;
output reg eof;
output reg hSync, vSync;	// sync outputs
output [11:0] hCtr;
output [11:0] vCtr;
output reg blank;		// blanking output
output reg vblank;
output reg vbl_int;
output border;
input [11:0] hTotal_i;
input [11:0] vTotal_i;
input [11:0] hSyncOn_i;
input [11:0] hSyncOff_i;
input [11:0] vSyncOn_i;
input [11:0] vSyncOff_i;
input [11:0] hBlankOn_i;
input [11:0] hBlankOff_i;
input [11:0] vBlankOn_i;
input [11:0] vBlankOff_i;
input [11:0] hBorderOn_i;
input [11:0] hBorderOff_i;
input [11:0] vBorderOn_i;
input [11:0] vBorderOff_i;

//---------------------------------------------------------------------
//---------------------------------------------------------------------

reg hBlank1;
wire vBlank1;
wire vBorder,hBorder;
wire hSync1,vSync1;
reg border;

wire eol1 = hCtr==hTotal_i;
wire eof1 = vCtr==vTotal_i;

assign vSync1 = vCtr >= vSyncOn_i && vCtr < vSyncOff_i;
assign hSync1 = hCtr >= hSyncOn_i && hCtr < hSyncOff_i;
assign vBlank1 = ~(vCtr < vBlankOn_i && vCtr >= vBlankOff_i);
assign vBorder = ~(vCtr < vBorderOn_i && vCtr >= vBorderOff_i);
assign hBorder = ~(hCtr < hBorderOn_i && hCtr >= hBorderOff_i);

counter #(12) u1 (.rst(rst), .clk(clk), .ce(1'b1), .ld(eol1), .d(12'd1), .q(hCtr), .tc() );
counter #(12) u2 (.rst(rst), .clk(clk), .ce(eol1),  .ld(eof1), .d(12'd1), .q(vCtr), .tc() );

always @(posedge clk)
if (rst)
  hBlank1 <= 1'b0;
else begin
  if (hCtr==hBlankOn_i)
    hBlank1 <= 1'b1;
  else if (hCtr==hBlankOff_i)
    hBlank1 <= 1'b0;
end

always @(posedge clk)
    blank <= #1 hBlank1|vBlank1;
always @(posedge clk)
    vblank <= #1 vBlank1;
always @(posedge clk)
    border <= #1 hBorder|vBorder;
always @(posedge clk)
	hSync <= #1 hSync1;
always @(posedge clk)
	vSync <= #1 vSync1;
always @(posedge clk)
    eof <= eof1;
always @(posedge clk)
    eol <= eol1;
always @(posedge clk)
    vbl_int <= hCtr==12'd8 && vCtr==12'd1;

endmodule

