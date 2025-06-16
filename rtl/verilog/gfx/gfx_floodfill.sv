`timescale 1ns / 1ps
// ============================================================================
//        __
//   \\__/ o\    (C) 2025  Robert Finch, Waterloo
//    \  __ /    All rights reserved.
//     \/_//     robfinch<remove>@opencores.org
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
//

module gfx_floodfill(rst_i, clk_i, floodfill_i, floodfill_ack_o, floodfill_write_o,
	fill_color, border_color, target_base_i, target_size_x_i,
	target_x0_i, target_y0_i, target_x1_i, target_y1_i,
	bpp_i, cbpp_i, coeff1_i, coeff2_i,
	clip_enable_i, clip_x0_i, clip_y0_i, clip_x1_i, clip_y1_i,
	dest_pixel0_x_i, dest_pixel0_y_i, floodfill_x_o, floodfill_y_o,
	rmw_i, floodfill_read_request_o, floodfill_ack_i, floodfill_adr_o,
	floodfill_sel_o, floodfill_data_i);
parameter MDW = 256;
input rst_i;
input clk_i;
input floodfill_i;
output reg floodfill_ack_o;
output reg floodfill_write_o;
input [31:0] fill_color;
input [31:0] border_color;
input [31:0] target_base_i;
input [5:0] bpp_i;
input [5:0] cbpp_i;
input [19:0] coeff1_i;
input [9:0] coeff2_i;
input [15:0] target_size_x_i;
input [15:0] target_x0_i;
input [15:0] target_y0_i;
input [15:0] target_x1_i;
input [15:0] target_y1_i;
input clip_enable_i;
input [15:0] clip_x0_i;
input [15:0] clip_y0_i;
input [15:0] clip_x1_i;
input [15:0] clip_y1_i;
input [15:0] dest_pixel0_x_i;
input [15:0] dest_pixel0_y_i;
output reg [15:0] floodfill_x_o;
output reg [15:0] floodfill_y_o;
input rmw_i;
output reg floodfill_read_request_o;
output [31:0] floodfill_adr_o;
output [MDW/8-1:0] floodfill_sel_o;
input [MDW-1:0] floodfill_data_i;
input floodfill_ack_i;

typedef enum logic [4:0]
{
	FF_INIT = 5'd0,
	FF_INIT1,
	FF_WAIT,
	FLOOD_FILL,
	FF1,
	FF2,
	FF3,
	FF4,
	FF5,
	FF6,
	FF7,
	FF8,
	ST_LATCH_DATA,
	DELAY1,
	DELAY2,
	DELAY3,
	FF_EXIT
} ff_state_e;
ff_state_e ff_state;

reg [15:0] gcx,gcy;
reg [4:0] loopcnt;
reg [11:0] retsp;
reg [11:0] pointsp;
ff_state_e pushstate;
ff_state_e retstack [0:4095];
reg [31:0] pointstack [0:4095];

reg [31:0] pointToPush;
reg rstst, pushst, popst;
reg rstpt, pushpt, poppt;

always_ff @(posedge clk_i)
  if (pushst)
    retstack[retsp-12'd1] <= pushstate;
ff_state_e retstacko = retstack[retsp];

always_ff @(posedge clk_i)
  if (pushpt)
    pointstack[pointsp-12'd1] <= pointToPush;
wire [31:0] pointstacko = pointstack[pointsp];
wire [15:0] lgcx = pointstacko[31:16];
wire [15:0] lgcy = pointstacko[15:0];

wire [7:0] mb;
gfx_calc_address #(.SW(MDW)) ugfxca1
(
	.clk(clk_i),
	.base_address_i(target_base_i),
	.bpp_i(bpp_i),
	.cbpp_i(cbpp_i),
	.coeff1_i(coeff1_i),
	.coeff2_i(coeff2_i),
	.bmp_width_i(target_size_x_i),
	.x_coord_i(gcx),
	.y_coord_i(gcy),
	.address_o(floodfill_adr_o),
	.mb_o(mb),
	.me_o(),
	.ce_o()
);

wire [31:0] dest_color;
reg [MDW-1:0] data;

// Memory to color converter
memory_to_color #(.MDW(MDW)) memory_proc(
	.clk_i(clk_i),
	.rmw_i(rmw_i),
	.bpp_i(bpp_i),
	.mem_i (data),
	.mb_i(mb),
	.color_o (dest_color),
	.sel_o ()
);

assign floodfill_sel_o = {MDW/8{1'b1}};

always_ff @(posedge clk_i)
  if (rstst)
    retsp <= 12'd0;
  else if (pushst)
    retsp <= retsp - 12'd1;
  else if (popst)
    retsp <= retsp + 12'd1;

always_ff @(posedge clk_i)
  if (rstpt)
    pointsp <= 12'd0;
  else if (pushpt)
    pointsp <= pointsp - 12'd1;
  else if (poppt)
    pointsp <= pointsp + 12'd1;

always_ff @(posedge clk_i)
if (rst_i) begin
	gcx <= 16'd0;
	gcy <= 16'd0;
	floodfill_ack_o <= 1'b0;
	floodfill_read_request_o <= 1'b0;
	floodfill_write_o <= 1'b0;
	floodfill_x_o <= 16'd0;
	floodfill_y_o <= 16'd0;
	ff_state <= FF_WAIT;
	rstpt <= 1'b1;
	rstst <= 1'b1;
end
else
case (ff_state)
// Reset the point and state stacks.
FF_INIT:
	begin
		floodfill_ack_o <= 1'b0;
		rstpt <= 1'b1;
		rstst <= 1'b1;
		goto (FF_INIT1);
	end
FF_INIT1:
	begin
		floodfill_ack_o <= 1'b0;
		rstpt <= 1'b0;
		rstst <= 1'b0;
		goto (FF_WAIT);
	end
// Wait for a flood fill request.
FF_WAIT:
	begin
		floodfill_ack_o <= 1'b0;
		if (floodfill_i) begin
			call(FF1,FF_INIT);
		end
	end
FF1:
	begin
		loopcnt <= 5'd31;
		push_point(gcx,gcy);	// save old graphics cursor position
		gcx <= dest_pixel0_x_i[15:0];	// convert fixed point point spec to int coord
		gcy <= dest_pixel0_y_i[15:0];
		call(FLOOD_FILL,FF_EXIT);	// call flood fill routine
	end
FLOOD_FILL:
	// If the point is outside of clipping region, just return.
	if (gcx < target_x0_i || gcy < target_y0_i || gcx >= target_x1_i || gcy >= target_y1_i) begin
		pop_point(gcx,gcy);
		tReturn();
	end
	else if (clip_enable_i && (gcx < clip_x0_i || gcx >= clip_x1_i || gcy < clip_y0_i || gcy >= clip_y1_i)) begin
		pop_point(gcx,gcy);
		tReturn();
	end
	// Point is inside clipping region, so a fetch has to take place
	else
		call(DELAY2,FF2);	// delay needed for address to settle
FF2:
	begin
		floodfill_read_request_o <= 1'b1;
		goto (ST_LATCH_DATA);
	end
ST_LATCH_DATA:
	if (floodfill_ack_i) begin
		floodfill_read_request_o <= 1'b0;
		data <= floodfill_data_i;
		goto (FF3);
	end
FF3:
	// Color already filled ? -> return
	if (fill_color==dest_color) begin
		pop_point(gcx,gcy);
		tReturn();
	end
	// Border hit ? -> return
	else if (border_color==dest_color) begin
		pop_point(gcx,gcy);
		tReturn();
	end
	// Set the pixel color then check the surrounding points.
	else begin
		floodfill_x_o <= gcx;
		floodfill_y_o <= gcy;
		floodfill_write_o <= 1'b1;
		goto(FF4);
	end
FF4:	// check to the "south"
	begin
		floodfill_write_o <= 1'b0;
		push_point(gcx,gcy);			// save the point off
		gcy <= gcy + 1;
		call(FLOOD_FILL,FF5);		// call flood fill
	end
FF5:	// check to the "north"
	if (gcy <= target_y0_i)
		goto(FF6);
	else begin
		push_point(gcx,gcy);		// save the point off
		gcy <= gcy - 1;
		call(FLOOD_FILL,FF6);	// call flood fill
	end
FF6:	// check to the "west"
	if (gcx <= target_x0_i)
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
		tReturn();
	end
FF_EXIT:
	begin
		floodfill_ack_o <= 1'b1;	// signal graphics operation done (not busy)
		tReturn();
	end
DELAY3:
	goto (DELAY2);
DELAY2:
	goto (DELAY1);
DELAY1:
	tReturn();
default:
	goto(FF_WAIT);
endcase

task goto;
input ff_state_e st;
begin
	ff_state <= st;
end
endtask

task call;
input ff_state_e st;
input ff_state_e nst;
begin
	if (retsp==12'd1) begin	// stack overflow ?
    rstst <= 1'b1;
		floodfill_ack_o <= 1'b1;
		ff_state <= FF_WAIT;		// abort operation, go back to idle
	end
	else begin
    pushstate <= st;
    pushst <= 1'b1;
		goto(nst);
	end
end
endtask

task tReturn;
begin
	ff_state <= retstacko;
	popst <= 1'b1;
end
endtask

task push_point;
input [15:0] px;
input [15:0] py;
begin
	if (pointsp==12'd1) begin
		rstpt <= 1'b1;
		rstst <= 1'b1;
		floodfill_ack_o <= 1'b1;
		ff_state <= FF_WAIT;
	end
	else begin
		pointToPush <= {px,py};
		pushpt <= 1'b1;
	end
end
endtask

task pop_point;
output [15:0] px;
output [15:0] py;
begin
	px = pointstacko[31:16];
	py = pointstacko[15:0];
	poppt <= 1'b1;
end
endtask

endmodule
