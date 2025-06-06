/*
ORSoC GFX accelerator core
Copyright 2012, ORSoC, Per Lenander, Anton Fosselius.

RENDERING MODULE

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
import gfx_pkg::*;

module gfx_renderer(clk_i, rst_i,
	target_base_i, zbuffer_base_i, target_size_x_i, target_size_y_i,
	target_x0_i, target_y0_i,
	bpp_i, cbpp_i, coeff1_i, coeff2_i, rmw_i,
	pixel_x_i, pixel_y_i, pixel_z_i, zbuffer_enable_i, color_i, strip_color_i, strip_i,
	render_addr_o, render_sel_o, render_dat_o, render_dat_i,
	ack_o, ack_i,
	write_i, write_o, read_o
	);

parameter point_width = 16;
parameter MDW = 256;

input clk_i;
input rst_i;

// Render target information, used for checking out of bounds and stride when writing pixels
input [31:0] target_base_i;
input [31:0] zbuffer_base_i;
input [point_width-1:0] target_size_x_i;
input [point_width-1:0] target_size_y_i;
input [point_width-1:0] target_x0_i;
input [point_width-1:0] target_y0_i;

input [5:0] bpp_i;
input [5:0] cbpp_i;
input [19:0] coeff1_i;
input [9:0] coeff2_i;
input rmw_i;

input [point_width-1:0] pixel_x_i;
input [point_width-1:0] pixel_y_i;
input [point_width-1:0] pixel_z_i;
input zbuffer_enable_i;
input [31:0] color_i;
input strip_i;
input [MDW-1:0] strip_color_i;

input write_i;
output reg write_o;
output reg read_o;

// Output registers connected to the wbm
output reg [31:0] render_addr_o;
output reg [31:0] render_sel_o;
output reg [MDW-1:0] render_dat_o;
input [MDW-1:0] render_dat_i;

wire [31:0] target_sel;
wire [MDW-1:0] target_dat;
wire [31:0] zbuffer_sel;
wire [MDW-1:0] zbuffer_dat;
reg [MDW-1:0] target_dati;

output reg ack_o;
input ack_i;

// TODO: Fifo for incoming pixel data?



// Define memory address
// Addr[31:2] = Base + (Y*width + X) * ppb
//reg [31:0] pixel_offset;
//always_comb
//	pixel_offset = fnPixelOffset(color_depth_i,(target_size_x_i*pixel_y_i + pixel_x_i));
wire [31:0] target_addr;
wire [31:0] zbuffer_addr;
wire [7:0] tmb;
gfx_calc_address #(.SW(MDW)) ugfxca1
(
	.clk(clk_i),
	.base_address_i(target_base_i),
	.bpp_i(bpp_i),
	.cbpp_i(cbpp_i),
	.coeff1_i(coeff1_i),
	.coeff2_i(coeff2_i),
	.bmp_width_i(target_size_x_i),
	.x_coord_i(pixel_x_i),
	.y_coord_i(pixel_y_i),
	.address_o(target_addr),
	.mb_o(tmb),
	.me_o(),
	.ce_o()
);
wire [7:0] zmb;
gfx_calc_address #(.SW(MDW)) ugfxca2
(
	.clk(clk_i),
	.base_address_i(zbuffer_base_i),
	.bpp_i(bpp_i),
	.cbpp_i(cbpp_i),
	.coeff1_i(coeff1_i),
	.coeff2_i(coeff2_i),
	.bmp_width_i(target_size_x_i),
	.x_coord_i(pixel_x_i),
	.y_coord_i(pixel_y_i),
	.address_o(zbuffer_addr),
	.mb_o(zmb),
	.me_o(),
	.ce_o()
);

//wire [31:5] target_addr = target_base_i + pixel_offset[31:5];
//wire [31:5] zbuffer_addr = zbuffer_base_i + pixel_offset[31:5];

// Color to memory converter
color_to_memory #(.MDW(MDW)) color_proc(
	.clk_i(clk_i),
	.rmw_i(rmw_i),
	.bpp_i(bpp_i),
	.color_i (color_i),
	.mb_i(tmb),
	.mem_i (target_dati),
	.mem_o (target_dat),
	.sel_o (target_sel)
);

// Color to memory converter
color_to_memory #(.MDW(MDW)) depth_proc(
	.clk_i(clk_i),
	.rmw_i(rmw_i),
	.bpp_i(6'd16),
	// Note: Padding because z_i is only [15:0]
	.color_i ({ {point_width{1'b0}}, pixel_z_i[point_width-1:0] }),
	.mb_i(zmb),
	.mem_i ({MDW{1'd0}}),
	.mem_o (zbuffer_dat),
	.sel_o (zbuffer_sel)
);

// State machine
typedef enum logic [2:0] {
	wait_state = 3'd0,
	delay1_state = 3'd1,
	delay2_state = 3'd2,
	delay3_state = 3'd3,
	read_pixel_state = 3'd4,
	write_pixel_state = 3'd5,
	write_z_state = 3'd6
} render_state_e;

reg [6:0] render_state;

// Acknowledge when a command has completed
always_ff @(posedge clk_i)
begin
  //  reset, init component
  if(rst_i)
  begin
    write_o <= 1'b0;
    ack_o <= 1'b0;
    render_addr_o <= 32'b0;
    render_sel_o <= 32'b0;
    render_dat_o <= 256'b0;
  end
  // Else, set outputs for next cycle
  else
  begin
 
    case (1'b1)

    render_state[wait_state]:
    	begin
    		target_dati <= 256'd0;
      	ack_o <= 1'b0;
      end
      
    render_state[read_pixel_state]:
      begin
        render_addr_o <= target_addr;
        render_sel_o <= target_sel;
        render_dat_o <= 256'd0;
        read_o <= 1'b1;
        if (ack_i) begin
        	target_dati <= render_dat_i;
        	read_o <= 1'b0;
        end
      end

    // Write pixel to memory. If depth buffering is enabled, write z value too
		render_state[write_pixel_state]:
      begin
	      if(ack_i) begin
	        render_addr_o <= zbuffer_addr;
	        render_sel_o <= zbuffer_sel;
	        render_dat_o <= zbuffer_dat;
	        write_o <= zbuffer_enable_i;
	        ack_o <= ~zbuffer_enable_i;
	      end
        else if (strip_i) begin
	        write_o <= 1'b1;
	        render_sel_o <= 32'hFFFFFFFF;
	        render_addr_o <= target_addr;
  	    	render_dat_o <= strip_color_i;
        end
        else begin
	        write_o <= 1'b1;
	        render_sel_o <= target_sel;
	        render_addr_o <= target_addr;
        	render_dat_o <= target_dat;
        end
      end

    render_state[write_z_state]:
    	begin
		    if (ack_i) begin
		      write_o <= 1'b0;
		      ack_o <= 1'b1;
		    end
		    else
        	write_o <= 1'b1;
	  	end

		default:	;
    endcase
  end
end

// State machine
always_ff @(posedge clk_i)
begin
	
	render_state <= 7'd0;

  // reset, init component
  if(rst_i)
    render_state[wait_state] <= 1'b1;
  // Move in statemachine
  else
    case (1'b1)

    render_state[wait_state]:
      if(write_i)
        render_state[delay1_state] <= 1'b1;
      else
      	render_state[wait_state] <= 1'b1;

    render_state[delay1_state]:
    	render_state[delay2_state] <= 1'b1;
//    delay2_state:
//    	render_state <= delay3_state;
    render_state[delay2_state]:
    	if (rmw_i)
    		render_state[read_pixel_state] <= 1'b1;
    	else
      	render_state[write_pixel_state] <= 1'b1;

		render_state[read_pixel_state]:
			if (ack_i)
				render_state[write_pixel_state] <= 1'b1;
			else
				render_state[read_pixel_state] <= 1'b1;

    render_state[write_pixel_state]:
      if(ack_i & zbuffer_enable_i)
        render_state[write_z_state] <= 1'b1;
      else if(ack_i)
        render_state[wait_state] <= 1'b1;
      else
      	render_state[write_pixel_state] <= 1'b1;

    render_state[write_z_state]:
      if(ack_i)
        render_state[wait_state] <= 1'b1;
      else
      	render_state[write_z_state] <= 1'b1;

		default:
			render_state[wait_state] <= 1'b1;
    endcase
end

endmodule

