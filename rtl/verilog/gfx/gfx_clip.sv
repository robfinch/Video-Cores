/*
ORSoC GFX accelerator core
Copyright 2012, ORSoC, Per Lenander, Anton Fosselius.

CLIPPING/SCISSORING MODULE

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

/*
This module performs clipping by applying the current cliprect and the target size.

This module also performs z-buffer culling (requires reading from memory)
*/
import gfx_pkg::*;

module gfx_clip(clk_i, rst_i, rmw_i,
  clipping_enable_i, zbuffer_enable_i, bpp_i, cbpp_i, coeff1_i, coeff2_i, pps_i,
  zbuffer_base_i, target_size_x_i, target_size_y_i, target_x0_i, target_y0_i, target_x1_i, target_y1_i,
  clip_pixel0_x_i, clip_pixel0_y_i, clip_pixel1_x_i, clip_pixel1_y_i,                              //clip pixel 0 and pixel 1
  raster_pixel_x_i, raster_pixel_y_i, raster_u_i, raster_v_i, flat_color_i, raster_write_i, ack_o, // from raster
  raster_strip_i, strip_o,
  cuvz_pixel_x_i, cuvz_pixel_y_i, cuvz_pixel_z_i, cuvz_u_i, cuvz_v_i, cuvz_color_i, cuvz_write_i,  // from cuvz
  cuvz_a_i,                                                                                        // from cuvz
  z_ack_i, z_addr_o, z_data_i, z_sel_o, z_request_o, wbm_busy_i,                                   // from/to wbm reader
  pixel_x_o, pixel_y_o, pixel_z_o, u_o, v_o, a_o,                                                  // to fragment
  bezier_factor0_i, bezier_factor1_i, bezier_factor0_o, bezier_factor1_o,                          // bezier calculations
  color_o, write_o, ack_i                                                                          // from/to fragment
  );

parameter point_width = 16;
parameter MDW = 256;

input clk_i;
input rst_i;

input clipping_enable_i;
input zbuffer_enable_i;
input [5:0] bpp_i;
input [5:0] cbpp_i;
input [19:0] coeff1_i;
input [9:0] coeff2_i;
input [9:0] pps_i;
input rmw_i;
input [31:0] zbuffer_base_i;
input [point_width-1:0] target_size_x_i;
input [point_width-1:0] target_size_y_i;
input [point_width-1:0] target_x0_i;
input [point_width-1:0] target_y0_i;
input [point_width-1:0] target_x1_i;
input [point_width-1:0] target_y1_i;
//clip pixels
input [point_width-1:0] clip_pixel0_x_i;
input [point_width-1:0] clip_pixel0_y_i;
input [point_width-1:0] clip_pixel1_x_i;
input [point_width-1:0] clip_pixel1_y_i;

// From cuvz
input [point_width-1:0] cuvz_pixel_x_i;
input [point_width-1:0] cuvz_pixel_y_i;
input signed [point_width-1:0] cuvz_pixel_z_i;
input [point_width-1:0] cuvz_u_i;
input [point_width-1:0] cuvz_v_i;
input [7:0] cuvz_a_i;
input [31:0] cuvz_color_i;
input cuvz_write_i;
// From raster
input [point_width-1:0] raster_pixel_x_i;
input [point_width-1:0] raster_pixel_y_i;
input [point_width-1:0] raster_u_i;
input [point_width-1:0] raster_v_i;
input raster_strip_i;
output reg strip_o;
input [31:0] flat_color_i;
input raster_write_i;
output reg ack_o;

// Interface against wishbone master (reader)
input z_ack_i;
output [31:0] z_addr_o;
input [MDW-1:0] z_data_i;
output reg [31:0] z_sel_o;
output reg z_request_o;
input wbm_busy_i;

// To fragment
output reg [point_width-1:0] pixel_x_o;
output reg [point_width-1:0] pixel_y_o;
output reg [point_width-1:0] pixel_z_o;
output reg [point_width-1:0] u_o;
output reg [point_width-1:0] v_o;
output reg [7:0] a_o;
input [point_width-1:0] bezier_factor0_i;
input [point_width-1:0] bezier_factor1_i;
output reg [point_width-1:0] bezier_factor0_o;
output reg [point_width-1:0] bezier_factor1_o;
output reg [31:0] color_o;
output write_o;
input ack_i;

// 
reg write1;
assign write_o = write1;

// State machine
typedef enum logic [3:0] {
	wait_state = 4'd0,
	delay1_state = 4'd1,
	delay2_state = 4'd2,
	delay3_state = 4'd3,
	z_read_state = 4'd4,
	write_pixel_state = 4'd5,
	z_value_state
} clip_state_e;
reg [6:0] clip_state;

// Calculate address of target pixel
// Addr[31:2] = Base + (Y*width + X) * ppb
//wire [31:0] pixel_offset;
wire [7:0] mb;
gfx_calc_address #(.SW(MDW)) ugfxca1
(
	.clk(clk_i),
	.base_address_i(zbuffer_base_i),
	.bpp_i(bpp_i),
	.cbpp_i(cbpp_i),
	.coeff1_i(coeff1_i),
	.coeff2_i(coeff2_i),
	.bmp_width_i(target_size_x_i),
	.x_coord_i(cuvz_pixel_x_i),
	.y_coord_i(cuvz_pixel_y_i),
	.address_o(z_addr_o),
	.mb_o(mb),
	.me_o(),
	.ce_o()
);
//always_comb
//	pixel_offset = fnPixelOffset(color_depth_i,(target_size_x_i*cuvz_pixel_y_i + {16'h0,cuvz_pixel_x_i}));
//assign z_addr_o = zbuffer_base_i + pixel_offset[31:5];

wire [31:0] z_value_at_target32;
wire signed [point_width-1:0] z_value_at_target = z_value_at_target32[point_width-1:0];

// Memory to color converter
memory_to_color #(.MDW(MDW)) memory_proc(
	.clk_i(clk_i),
	.rmw_i(rmw_i),
	.bpp_i(6'd16),
	.mem_i (z_data_i),
	.mb_i(mb),
	.color_o (z_value_at_target32),
	.sel_o ()
);

// Forward texture coordinates, color, alpha etc
always_ff @(posedge clk_i)
if(rst_i)
begin
  u_o <= 1'b0;
  v_o <= 1'b0;
  bezier_factor0_o <= 1'b0;
  bezier_factor1_o <= 1'b0;
  pixel_x_o <= 16'b0;
  pixel_y_o <= 16'b0;
  pixel_z_o <= 16'b0;
  color_o <= 32'b0;
  a_o <= 8'b0;
  z_sel_o <= 32'hFFFFFFFF;
end
else
begin
  // Implement a MUX, send data from either the raster or from the cuvz module to the fragment processor
  if(raster_write_i)
  begin
    u_o <= raster_u_i;
    v_o <= raster_v_i;
    a_o <= 8'hff;
    color_o <= flat_color_i;
    pixel_x_o <= raster_pixel_x_i;
    pixel_y_o <= raster_pixel_y_i;
    pixel_z_o <= 16'b0;
  end
  // If the cuvz module is being used, more parameters needs to be forwarded
  else if(cuvz_write_i)
  begin
    u_o <= cuvz_u_i;
    v_o <= cuvz_v_i;
    a_o <= cuvz_a_i;
    color_o <= cuvz_color_i;
    pixel_x_o <= cuvz_pixel_x_i;
    pixel_y_o <= cuvz_pixel_y_i;
    pixel_z_o <= cuvz_pixel_z_i;
    bezier_factor0_o <= bezier_factor0_i;
    bezier_factor1_o <= bezier_factor1_i;
  end
end

reg discard_strip;
reg [point_width-1:0] x_end;
always_comb
	x_end = raster_pixel_x_i + pps_i;

// Check if we should discard this pixel due to failing depth check
wire fail_z_check   = z_value_at_target > cuvz_pixel_z_i;

// Check if we should discard this pixel due to falling outside render target/clip rect
wire outside_target = raster_write_i
											 ? (raster_pixel_x_i >= target_size_x_i)
											 | (raster_pixel_y_i >= target_size_y_i)
											 : cuvz_write_i ? (cuvz_pixel_x_i >= target_size_x_i)
											 | (cuvz_pixel_y_i >= target_size_y_i)
											 : 1'b0;
wire outside_clip = raster_write_i
											 ? (raster_pixel_x_i < clip_pixel0_x_i) | (raster_pixel_y_i < clip_pixel0_y_i) | (raster_pixel_x_i >= clip_pixel1_x_i) | (raster_pixel_y_i >= clip_pixel1_y_i)
											 : cuvz_write_i ? (cuvz_pixel_x_i < clip_pixel0_x_i) | (cuvz_pixel_y_i < clip_pixel0_y_i) | (cuvz_pixel_x_i >= clip_pixel1_x_i) | (cuvz_pixel_y_i >= clip_pixel1_y_i) 
											 : 1'b0;
wire discard_pixel = outside_target | (clipping_enable_i & outside_clip);

wire outside_target2 = raster_write_i ? (x_end >= target_size_x_i) : 1'b1;
wire outside_clip2 = raster_write_i ? (x_end >= clip_pixel1_x_i) : 1'b1;

// Check if there is a write signal
wire write_i = raster_write_i | cuvz_write_i;

always_comb
	discard_strip = discard_pixel | outside_target2 | (clipping_enable_i & outside_clip2);

// Acknowledge when a command has completed
always_ff @(posedge clk_i)
// reset, init component
if(rst_i)
begin
  ack_o <= 1'b0;
  write1 <= 1'b0;
  z_request_o <= 1'b0;
  z_sel_o <= 32'hFFFFFFFF;
end
// Else, set outputs for next cycle
else
begin
  case (1'b1)

  clip_state[wait_state]:
	  begin
			ack_o <= 1'b0;
			strip_o <= raster_strip_i & ~discard_strip;
      if(write_i)
        ack_o <= discard_pixel;
      if(write_i & zbuffer_enable_i) begin
      	if (discard_pixel)
        	z_request_o <= 1'b0;
      end
      else if(write_i)
        write1 <= ~discard_pixel;
	  end

  clip_state[delay2_state]:
    z_request_o <= 1'b1;

  // Do a depth check. If it fails, discard pixel, ack and go back to wait. If it succeeds, go to write clip_state
  clip_state[z_read_state]:
    if(z_ack_i)
      z_request_o <= 1'b0;
    else
      z_request_o <= ~wbm_busy_i | z_request_o;

	clip_state[z_value_state]:
		begin
      write1 <= ~fail_z_check;
      ack_o <= fail_z_check;
      z_request_o <= 1'b0;
    end
		
  // ack, then go back to wait clip_state when the next module is ready
  clip_state[write_pixel_state]:
    if(ack_i) begin
	    write1 <= 1'b0;
      ack_o <= 1'b1;    
    end

	default:	;
  endcase

end

// State machine
always_ff @(posedge clk_i)
// reset, init component
if(rst_i) begin
  clip_state <= 7'd0;
  clip_state[wait_state] <= 1'b1;
// Move in statemachine
end
else begin
  clip_state <= 7'd0;
  case (1'b1)

  clip_state[wait_state]:
    if(write_i & ~discard_pixel) begin
    	if (zbuffer_enable_i)
    		clip_state[delay1_state] <= 1'b1;
    	else
    		clip_state[write_pixel_state] <= 1'b1;
    end
    else
			clip_state[wait_state] <= 1'b1;

	// Two cycle delay is for address calc. 
  clip_state[delay1_state]:
  	clip_state[delay2_state] <= 1'b1;
//  delay2_state:
//  	clip_state <= delay3_state;
  clip_state[delay2_state]:
    clip_state[z_read_state] <= 1'b1;

  clip_state[z_read_state]:
    if(z_ack_i)
    	clip_state[z_value_state] <= 1'b1;
    else
			clip_state[z_read_state] <= 1'b1;

	clip_state[z_value_state]:
  	if (fail_z_check)
  		clip_state[wait_state] <= 1'b1;
  	else
    	clip_state[write_pixel_state] <= 1'b1;
		
  clip_state[write_pixel_state]:
    if(ack_i)
      clip_state[wait_state] <= 1'b1;
    else
    	clip_state[write_pixel_state] <= 1'b1;

	default:
		clip_state[wait_state] <= 1'b1;
  endcase
end

endmodule
