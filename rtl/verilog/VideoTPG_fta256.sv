// ============================================================================
//        __
//   \\__/ o\    (C) 2023-2024  Robert Finch, Waterloo
//    \  __ /    All rights reserved.
//     \/_//     robfinch<remove>@finitron.ca
//       ||
//
// VideoTPG.sv
// - video test pattern generator
// - Responds to video memory requests by supplying a fixed pattern.
// - Responds in a variable number of cycles to simulate memory latency. So, there
//   is jitter in the data supplied back to the frame buffer which should be able
//	 to display without the jitter.
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

import fta_bus_pkg::*;

module VideoTPG_fta256(rst, clk, en, vSync, s);
input rst;
input clk;
input en;
input vSync;
fta_bus_interface.slave s;

//input fta_cmd_request256_t req;
//output fta_cmd_response256_t resp;
//input fta_cmd_response256_t ex_resp;	// external response input

wire pe_vsync;
wire [30:0] lfsr31o;

edge_det uedvs1
(
	.rst(rst),
	.clk(clk),
	.ce(1'b1),
	.i(vSync),
	.pe(pe_vsync),
	.ne(),
	.ee()
);
	
lfsr31 ulfsr1
(
	.rst(pe_vsync),
	.clk(clk),
	.ce(s.req.cyc),
	.cyc(1'b0),
	.o(lfsr31o)
);

reg [11:0] p, m;
reg [19:0] q,d400;
reg [31:0] m400;
reg [15:0] c;
always_comb
	d400 = ({16'h0,s.req.padr} * 16'd2621) >> 20;
always_comb
	m400 = s.req.padr - ({10'd0,d400} * 10'd400);
always_comb
	p = m400 >> 5;
always_comb
	q = ({16'd0,s.req.padr} * 16'd78) >> 20;		// /(32*400)
always_comb
	c = {1'b0,5'h1F,q[4:0],p[4:0]};

vtdl #(.WID(1), .DEP(16)) urdyd2 (.clk(clk), .ce(1'b1), .a(lfsr31o[3:0]), .d(s.req.cyc), .q(s.resp.ack));
//vtdl #(.WID(6), .DEP(16)) urdyd3 (.clk(clk), .ce(1'b1), .a(lfsr31o[3:0]), .d(req.cid), .q(resp.cid));
vtdl #(.WID($bits(fta_tranid_t)), .DEP(16)) urdyd4 (.clk(clk), .ce(1'b1), .a(lfsr31o[3:0]), .d(s.req.tid), .q(s.resp.tid));
vtdl #(.WID($bits(s.resp.adr)), .DEP(16)) urdyd5 (.clk(clk), .ce(1'b1), .a(lfsr31o[3:0]), .d(s.req.padr), .q(s.resp.adr));
vtdl #(.WID($bits(s.resp.dat)), .DEP(16)) urdyd6 (.clk(clk), .ce(1'b1), .a(lfsr31o[3:0]), .d({16{c}}), .q(s.resp.dat));

always_ff @(posedge clk)
begin
	/*
	resp.tid <= req.tid;
	resp.cid <= req.cid;
	resp.ack <= req.cyc;
	*/
	s.resp.stall <= 1'b0;
	s.resp.next <= 1'b0;
	s.resp.err <= fta_bus_pkg::OKAY;
	s.resp.rty <= 1'b0;
	s.resp.pri <= 4'd7;
	/*
	resp.adr <= req.padr;
	resp.dat <= {8{c}};
	*/
	/*
	casez({~en,req.padr[11:8]})
	5'h00:	resp.dat <= {4{lfsr31o}};
	5'h02:	resp.dat <= ex_resp.dat;
	5'h1?:	resp.dat <= ex_resp.dat;
	default:	resp.dat <= {16{req.padr[15:8]}};
	endcase
	*/
end

endmodule
