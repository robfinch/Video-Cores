// ============================================================================
//        __
//   \\__/ o\    (C) 2023-2025  Robert Finch, Waterloo
//    \  __ /    All rights reserved.
//     \/_//     robfinch<remove>@finitron.ca
//       ||
//
//	gfx128_wbm_rw.sv
//	- asynchronous bus interface
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

//synopsys translate_off
`include "timescale.v"
//synopsys translate_on
import wishbone_pkg::*;
import gfx128_pkg::*;

module gfx128_wbm_rw (clk_i, rst_i, wbm_req, wbm_resp, sint_o,
  read_request_i, write_request_i,
  texture_addr_i, texture_sel_i, texture_dat_o, texture_dat_i, texture_data_ack);
parameter CID = 4'd5;
parameter BUF_ENTRIES = 4'd3;

// wishbone signals
input clk_i;    // master clock input
input rst_i;    // asynchronous active high reset
output wb_cmd_request128_t wbm_req;
input wb_cmd_response128_t wbm_resp;

output sint_o;     // non recoverable error, interrupt host

// Request stuff
input read_request_i;
input write_request_i;

input [31:4] texture_addr_i;
input [15:0] texture_sel_i;
output reg [127:0] texture_dat_o;
input [127:0] texture_dat_i;
output reg texture_data_ack;

//
// variable declarations
//

integer nn;
reg [BUF_ENTRIES-1:0] cmdv;
reg [BUF_ENTRIES-1:0] cmdact;
reg [BUF_ENTRIES-1:0] cmdposted;
wb_cmd_request128_t [BUF_ENTRIES-1:0] cmdout;

// Detect if the request matches one already in the buffer.

function fnMatch;
input [3:0] nn;
input rw;
input [15:0] sel;
input [31:4] adr;
input [127:0] dat;
begin
	fnMatch = 'd0;
	if (cmdv[nn]) begin
		if (rw == cmdout[nn].we) begin
			if (adr==cmdout[nn].vadr[31:4]) begin
				if (rw) begin
					// Check only the lanes that are being accessed.
					casez(sel)
					16'b0000000000000001:	fnMatch = dat[7:0]==cmdout[nn].data1[7:0];
					16'b0000000000000010:	fnMatch = dat[15:8]==cmdout[nn].data1[15:8];
					16'b0000000000000100:	fnMatch = dat[23:16]==cmdout[nn].data1[23:16];
					16'b0000000000001000:	fnMatch = dat[31:24]==cmdout[nn].data1[31:24];
					16'b0000000000010000:	fnMatch = dat[39:32]==cmdout[nn].data1[39:32];
					16'b0000000000100000:	fnMatch = dat[47:40]==cmdout[nn].data1[47:40];
					16'b0000000001000000:	fnMatch = dat[55:48]==cmdout[nn].data1[55:48];
					16'b0000000010000000:	fnMatch = dat[63:56]==cmdout[nn].data1[63:56];
					16'b0000000100000000:	fnMatch = dat[71:64]==cmdout[nn].data1[71:64];
					16'b0000001000000000:	fnMatch = dat[79:72]==cmdout[nn].data1[79:72];
					16'b0000010000000000:	fnMatch = dat[87:80]==cmdout[nn].data1[87:80];
					16'b0000100000000000:	fnMatch = dat[95:88]==cmdout[nn].data1[95:88];
					16'b0001000000000000:	fnMatch = dat[103:96]==cmdout[nn].data1[103:96];
					16'b0010000000000000:	fnMatch = dat[111:104]==cmdout[nn].data1[111:104];
					16'b0100000000000000:	fnMatch = dat[119:112]==cmdout[nn].data1[119:112];
					16'b1000000000000000:	fnMatch = dat[127:120]==cmdout[nn].data1[127:120];
					16'b0000000000000011:	fnMatch = dat[15:0]==cmdout[nn].data1[15:0];
					16'b0000000000001100:	fnMatch = dat[31:16]==cmdout[nn].data1[31:16];
					16'b0000000000110000:	fnMatch = dat[47:32]==cmdout[nn].data1[47:32];
					16'b0000000011000000:	fnMatch = dat[63:48]==cmdout[nn].data1[63:48];
					16'b0000001100000000:	fnMatch = dat[79:64]==cmdout[nn].data1[79:64];
					16'b0000110000000000:	fnMatch = dat[95:80]==cmdout[nn].data1[95:80];
					16'b0011000000000000:	fnMatch = dat[111:96]==cmdout[nn].data1[111:96];
					16'b1100000000000000:	fnMatch = dat[127:112]==cmdout[nn].data1[127:112];
					16'b0000000000001111:	fnMatch = dat[31:0]==cmdout[nn].data1[31:0];
					16'b0000000011110000:	fnMatch = dat[63:32]==cmdout[nn].data1[63:32];
					16'b0000111100000000:	fnMatch = dat[95:64]==cmdout[nn].data1[95:64];
					16'b1111000000000000:	fnMatch = dat[127:96]==cmdout[nn].data1[127:96];
					16'b1111111111111111:	fnMatch = dat[127:0]==cmdout[nn].data1[127:0];
					default:	fnMatch = 1'b0;
					endcase
				end
				else
					fnMatch = 1'b1;
			end
		end
	end
end
endfunction


//
// module body
//

assign sint_o = wbm_resp.err;

always_ff @(posedge clk_i or posedge rst_i)
if (rst_i) // Reset
  begin
    texture_data_ack <= 1'b0;
    wbm_req.cyc <= 1'b0;
    wbm_req.sel <= 16'hFFFF;
    cmdv <= 'd0;
    cmdact <= 'd0;
    cmdposted <= 'd0;
    for (nn = 0; nn < BUF_ENTRIES; nn = nn + 1)
    	cmdout[nn] = 'd0;
  end
else
begin
	texture_data_ack <= 1'b0;
	if (!wbm_resp.rty)
		wbm_req.cyc <= 1'b0;

  // Buffer request
  if (read_request_i|write_request_i) begin
		for (nn = 0; nn < BUF_ENTRIES; nn = nn + 1) begin
			if (!fnMatch(nn,write_request_i,texture_sel_i,texture_addr_i,texture_dat_i)) begin
				cmdout[nn].cid <= CID;
				cmdout[nn].tid <= {CID,1'b0,nn[2:0]};
				cmdout[nn].bte <= wishbone_pkg::LINEAR;
				cmdout[nn].cti <= wishbone_pkg::CLASSIC;
	    	cmdout[nn].cyc <= 1'b1;
	    	cmdout[nn].stb <= 1'b1;
	    	cmdout[nn].we <= write_request_i;
		    cmdout[nn].sel <= 'd0;
	    	cmdout[nn].sel <= texture_sel_i;
	    	cmdout[nn].vadr <= {texture_addr_i[31:4],4'd0};
	    	cmdout[nn].data1 <= texture_dat_i;
	    	cmdv[nn] <= 1'b1;
			end
  	end
	end
	// Spit out requests
	for (nn = 0; nn < BUF_ENTRIES; nn = nn + 1) begin
		if (cmdv[nn] && !cmdposted[nn]) begin
			wbm_req <= cmdout[nn];
			if (!wbm_resp.rty)
				cmdposted[nn] <= 1'b1;
			else
				cmdact[nn] <= 1'b1;
		end   	
  end
  // Clear requests that have posted.
	for (nn = 0; nn < BUF_ENTRIES; nn = nn + 1) begin
		if (!wbm_resp.rty && cmdact[nn] && cmdv[nn] && !cmdposted[nn]) begin
			cmdposted[nn] <= 1'b1;
			cmdact[nn] <= 1'b0;
		end
	end
	// Search for completed requests
	if (wbm_resp.ack)
		for (nn = 0; nn < BUF_ENTRIES; nn = nn + 1)
	   	if (cmdv[nn] && cmdout[nn].tid == wbm_resp.tid) begin
	   		cmdv[nn] <= 1'b0;
	   		cmdact[nn] <= 'd0;
	   		cmdposted[nn] <= 1'b0;
	   		texture_data_ack <= 1'b1;
	   		texture_dat_o <= wbm_resp.dat;
	   	end
	  end

endmodule
