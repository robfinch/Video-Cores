`timescale 1ns / 1ps
// ============================================================================
//        __
//   \\__/ o\    (C) 2012-2022  Robert Finch, Waterloo
//    \  __ /    All rights reserved.
//     \/_//     robfinch<remove>@finitron.ca
//       ||
//
//	WXGASyncGen1366x768_60.sv
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
// ============================================================================
//
//	WXGA video sync generator.
//
//	Input clock:     85.86 MHz (50 MHz * 12/7) (85.7142)
//	Horizontal freq: 47.7 kHz	(generated) (47.619KHz)
//	Vertical freq:   60.00  Hz (generated)  (59.89 Hz)
//
//	This module generates the basic sync timing signals required for a
//	WXGA display.
//
// ============================================================================

module WXGASyncGen1366x768_60Hz(rst, clk, hSync, vSync, blank, border);
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
// 60 Hz
// 1366x768
input rst;			// reset
input clk;			// video clock
output reg hSync, vSync;	// sync outputs
output blank;			// blanking output
output border;

//---------------------------------------------------------------------
//---------------------------------------------------------------------

wire [11:0] hCtr;	// count from 1 to 1800
wire [11:0] vCtr;	// count from 1 to 795

wire vBlank, hBlank;
wire vBorder,hBorder;
wire hSync1,vSync1;
reg blank;
reg border;

wire eol = hCtr==phTotal;
wire eof = vCtr==pvTotal && eol;

assign vSync1 = vCtr >= pvSyncOn && vCtr < pvSyncOff;
assign hSync1 = !(hCtr >= phSyncOn && hCtr < phSyncOff);
assign vBlank = vCtr >= pvBlankOn || vCtr < pvBlankOff;
assign hBlank = hCtr >= phBlankOn || hCtr < phBlankOff;
assign vBorder = vCtr >= pvBorderOn || vCtr < pvBorderOff;
assign hBorder = hCtr >= phBorderOn || hCtr < phBorderOff;

counter #(12) u1 (.rst(rst), .clk(clk), .ce(1'b1), .ld(eol), .d(12'd1), .q(hCtr), .tc() );
counter #(12) u2 (.rst(rst), .clk(clk), .ce(eol),  .ld(eof), .d(12'd1), .q(vCtr), .tc() );

always @(posedge clk)
    blank <= #1 hBlank|vBlank;
always @(posedge clk)
    border <= #1 hBorder|vBorder;
always @(posedge clk)
	hSync <= #1 hSync1;
always @(posedge clk)
	vSync <= #1 vSync1;

endmodule

