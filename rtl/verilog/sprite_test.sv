`timescale 1ns / 1ps
// ============================================================================
//        __
//   \\__/ o\    (C) 2022  Robert Finch, Waterloo
//    \  __ /    All rights reserved.
//     \/_//     robfinch<remove>@finitron.ca
//       ||
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

import wishbone_pkg::*;

module sprite_test(rst, clk, cs, wb_req, wb_resp, state_o);
input rst;
input clk;
output reg cs;
output wb_write_request32_t wb_req;
input wb_read_response32_t wb_resp;
output [3:0] state_o;

reg [4:0] sprite_no;
reg [11:0] hpos [0:31];
reg [11:0] vpos [0:31];
reg [11:0] hdelta [0:31];
reg [11:0] vdelta [0:31];
reg [3:0] hcnt [0:31];
reg [3:0] vcnt [0:31];

typedef enum logic [3:0] {
	INIT0 = 4'd0,
	INIT1 = 4'd1,
	INIT2 = 4'd2,
	RUN1 = 4'd4,
	RUN2 = 4'd5,
	RUN3 = 4'd6,
	RUN4 = 4'd7,
	RUN5 = 4'd8,
	RUN6 = 4'd9
} state_t;
state_t state;
assign state_o = state;

wire [26:0] lfsr_o;
reg [23:0] count;
lfsr27 ulfsr1
(
	.rst(rst),
	.clk(clk),
	.ce(1'b1),
	.cyc(1'b0),
	.o(lfsr_o)
);


always_ff @(posedge clk)
if (rst) begin
	state <= INIT0;
	sprite_no <= 5'd0;
	count <= 'd0;
	cs <= 'd0;
	wb_req.bte <= LINEAR;
	wb_req.cti <= CLASSIC;
	wb_req.blen <= 6'd0;
	wb_req.cid <= 4'd7;
	wb_req.cyc <= 'd0;
	wb_req.stb <= 'd0;
	wb_req.we <= 'd0;
end
else begin
	case(state)
	// Time for the LFSR to randomize.
	INIT0:
		begin
			count <= count + 2'd1;
			if (count>=24'd100000)
				state <= INIT1;	
		end
	INIT1:
		if (~wb_resp.ack) begin
			cs <= 1'b1;
			wb_req.cyc <= 1'b1;
			wb_req.stb <= 1'b1;
			wb_req.we <= 1'b1;
			wb_req.sel <= 4'b1111;
			wb_req.adr <= {1'b0,sprite_no,2'b01,2'b00};	// SIZE register
			wb_req.dat <= {4'h8,4'd10,2'b00,lfsr_o[1:0],2'b00,lfsr_o[1:0],8'd21,8'd24};
//			wb_req.dat[15:0] <= lfsr_o[11:0];
		  hpos[sprite_no] <= 200 + (sprite_no & 7) * 70;
    	vpos[sprite_no] <= 100 + (sprite_no >> 3) * 100;
//			hpos[sprite_no] <= lfsr_o[11:0];
//			wb_req.dat[31:0] <= lfsr_o[23:12];
//			vpos[sprite_no] <= lfsr_o[23:12];
			hdelta[sprite_no] <= {{12{lfsr_o[26]}},lfsr_o[26:23]};
			vdelta[sprite_no] <= {{12{lfsr_o[11]}},lfsr_o[11:8]};
			hcnt[sprite_no] <= 'd0;
			vcnt[sprite_no] <= 'd0;
			state <= INIT2;
		end
	INIT2:
		begin
			cs <= 1'b0;
			wb_req.cyc <= 1'b0;
			wb_req.stb <= 1'b0;
			wb_req.we <= 1'b0;
			sprite_no <= sprite_no + 2'd1;
			if (sprite_no==5'd31)
				state <= RUN1;
			else
				state <= INIT1;
		end
	RUN1:
		if (~wb_resp.ack) begin
			cs <= 1'b1;
			wb_req.cyc <= 1'b1;
			wb_req.stb <= 1'b1;
			wb_req.we <= 1'b1;
			wb_req.adr <= {23'b0,sprite_no,2'b00,2'b00};	// POS register
			wb_req.dat[15: 0] <= hpos[sprite_no];
			wb_req.dat[31:16] <= vpos[sprite_no];
			state <= RUN2;
		end
	RUN2:
		if (wb_resp.ack) begin
			cs <= 1'b0;
			wb_req.cyc <= 1'b0;
			wb_req.stb <= 1'b0;
			wb_req.we <= 1'b0;
			state <= RUN3;
		end
	RUN3:
		begin	
			if (hcnt[sprite_no] != 4'd0)
				hcnt[sprite_no] <= hcnt[sprite_no] + 2'd1;
			if (vcnt[sprite_no] != 4'd0)
				vcnt[sprite_no] <= vcnt[sprite_no] + 2'd1;
			if ((hpos[sprite_no] < 12'd260 || hpos[sprite_no] > 12'd980) && hcnt[sprite_no]==4'd0) begin
				hdelta[sprite_no] <= -hdelta[sprite_no];
				hcnt[sprite_no] <= 4'd1;
			end
			if ((vpos[sprite_no] < 12'd50 || vpos[sprite_no] > 12'd580) && vcnt[sprite_no]==4'd0) begin
				vdelta[sprite_no] <= -vdelta[sprite_no];
				vcnt[sprite_no] <= 4'd1;
			end
			hpos[sprite_no] <= hpos[sprite_no] + hdelta[sprite_no];
			vpos[sprite_no] <= vpos[sprite_no] + vdelta[sprite_no];
			state <= RUN4;
		end
	RUN4:
		if (~wb_resp.ack) begin
			cs <= 1'b1;
			wb_req.cyc <= 1'b1;
			wb_req.stb <= 1'b1;
			wb_req.we <= 1'b1;
			wb_req.adr <= {23'b0,sprite_no,2'b10,2'b00};	// addr register
			if (hdelta[sprite_no][11])
				wb_req.dat <= 32'h00300000 + {sprite_no[4:0],13'h0000};
			else
				wb_req.dat <= 32'h00300000 + {sprite_no[4:0],13'h1000};
			state <= RUN5;
		end
	RUN5:
		if (wb_resp.ack) begin
			cs <= 1'b0;
			wb_req.cyc <= 1'b0;
			wb_req.stb <= 1'b0;
			wb_req.we <= 1'b0;
			sprite_no <= sprite_no + 2'd1;
			if (sprite_no==5'd31)
				state <= RUN6;
			else
				state <= RUN1;
		end
	RUN6:
		begin
			count <= count + 2'd1;
			if (count > 24'd1500000) begin
				state <= RUN1;
				count <= 'd0;
			end
		end
	default:	state <= INIT0;
	endcase
end

endmodule
