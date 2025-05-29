/*
ORSoC GFX accelerator core
Copyright 2012, ORSoC, Per Lenander, Anton Fosselius.

PER-PIXEL COLORING MODULE, alpha blending


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
This module performs alpha blending by fetching the pixel from the target and mixing it with the texel based on the current alpha value.

The exact formula is:
alpha = global_alpha_i * alpha_i
color_out = color_in * alpha + color_target * (1-alpha)       , where alpha is defined from 0 to 1 

alpha_i[7:0] is used, so the actual span is 0 (transparent) to 255 (opaque)

If alpha blending is disabled (blending_enable_i == 1'b0) the module just passes on the input pixel.
*/
import gfx_pkg::*;

module gfx_blender(clk_i, rst_i, color_comp_i,
  blending_enable_i, target_base_i, target_size_x_i, target_size_y_i, bpp_i, cbpp_i, coeff1_i, coeff2_i, rmw_i,
  x_counter_i, y_counter_i, z_i, alpha_i, global_alpha_i, write_i, ack_o, strip_i,        // from fragment
  target_ack_i, target_addr_o, target_data_i, target_sel_o, target_request_o, wbm_busy_i, // from/to wbm reader
  pixel_x_o, pixel_y_o, pixel_z_o, pixel_color_i, pixel_color_o, strip_color_o, strip_o, write_o, ack_i    // to render
);

parameter point_width = 16;
parameter MDW = 256;

input clk_i;
input rst_i;

input [15:0] color_comp_i;
input blending_enable_i;
input [31:0] target_base_i;
input [point_width-1:0] target_size_x_i;
input [point_width-1:0] target_size_y_i;
input rmw_i;
input [5:0] bpp_i;
input [5:0] cbpp_i;
input [15:0] coeff1_i;
input [9:0] coeff2_i;

// from fragment
input [point_width-1:0] x_counter_i;
input [point_width-1:0] y_counter_i;
input signed [point_width-1:0] z_i;
input [7:0] alpha_i;
input [7:0] global_alpha_i;
input [31:0] pixel_color_i;
input write_i;
input strip_i;
output reg ack_o;

// Interface against wishbone master (reader)
input target_ack_i;
output [31:0] target_addr_o;
input [MDW-1:0] target_data_i;
output reg [31:0] target_sel_o;
output reg target_request_o;
input wbm_busy_i;

//to render
output reg [point_width-1:0] pixel_x_o;
output reg [point_width-1:0] pixel_y_o;
output reg signed [point_width-1:0] pixel_z_o;
output reg [31:0] pixel_color_o;
output write_o;
output reg strip_o;
output reg [MDW-1:0] strip_color_o;
input ack_i;

reg write1;

// State machine
typedef enum logic [2:0] {
	wait_state = 3'd0,
	delay1_state,
	delay2_state,
	delay3_state,
	target_read_state,
	target_read_ack_state,
	write_pixel_state,
	write_pixel_ack_state
} blender_state_e;

blender_state_e state;

// Calculate alpha
reg [15:0] combined_alpha_reg;
wire [7:0] alpha = combined_alpha_reg[15:8];

// Calculate address of target pixel
// Addr[31:2] = Base + (Y*width + X) * ppb
//reg [31:0] pixel_offset;
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
	.x_coord_i(x_counter_i),
	.y_coord_i(y_counter_i),
	.address_o(target_addr_o),
	.mb_o(mb),
	.me_o(),
	.ce_o()
);

wire [31:0] dest_color;
// Memory to color converter
memory_to_color #(.MDW(MDW)) memory_proc(
	.rmw_i(rmw),
	.bpp_i(bpp_i),
	.mem_i (target_data_i),
	.mb_i(mb),
	.color_o (dest_color),
	.sel_o ()
);

//always_comb
//	pixel_offset = fnPixelOffset(color_depth_i,(target_size_x_i*y_counter_i + {16'h0, x_counter_i}));

//assign target_addr_o = target_base_i + pixel_offset[31:4];
integer nr,ng,nb;
reg [9:0] red_mask,green_mask,blue_mask;
reg [4:0] red_shift;
reg [4:0] green_shift;
always_ff @(posedge clk_i)
	for (nr = 0; nr < 10; nr = nr + 1)
		red_mask[nr] <= nr < color_comp_i[11:8];
always_ff @(posedge clk_i)
	for (ng = 0; ng < 10; ng = ng + 1)
		green_mask[ng] <= ng < color_comp_i[7:4];
always_ff @(posedge clk_i)
	for (nb = 0; nb < 10; nb = nb + 1)
		blue_mask[nb] <= nb < color_comp_i[3:0];
always_ff @(posedge clk_i)
	red_shift <= color_comp_i[3:0] + color_comp_i[7:4];		
always_ff @(posedge clk_i)
	green_shift <= {1'b0,color_comp_i[3:0]};	


function [9:0] C;
input [9:0] mask;
input [4:0] shift;
input [31:0] pixel_color;
	C = (pixel_color >> shift) & mask;
endfunction

// Split colors for alpha blending (render color)
wire [9:0] blend_color_r = C(red_mask,red_shift,pixel_color_i);
wire [9:0] blend_color_g = C(green_mask,green_shift,pixel_color_i);
wire [9:0] blend_color_b = C(blue_mask,5'd0,pixel_color_i);

// Split colors for alpha blending (from target surface)
wire [9:0] target_color_r = C(red_mask,red_shift,dest_color);
wire [9:0] target_color_g = C(green_mask,green_shift,dest_color);
wire [9:0] target_color_b = C(blue_mask,5'd0,dest_color);

// Alpha blending (per color channel):
// rgb = (alpha1)(rgb1) + (1-alpha1)(rgb2)
wire [17:0] alpha_color_r = blend_color_r * alpha + target_color_r * ~alpha;
wire [17:0] alpha_color_g = blend_color_g * alpha + target_color_g * ~alpha;
wire [17:0] alpha_color_b = blend_color_b * alpha + target_color_b * ~alpha;

assign write_o = write1;

// Acknowledge when a command has completed
always_ff @(posedge clk_i)
begin
  // reset, init component
  if(rst_i)
  begin
    ack_o <= 1'b0;
    write1 <= 1'b0;
    pixel_x_o <= 16'b0;
    pixel_y_o <= 16'b0;
    pixel_z_o <= 16'b0;
    pixel_color_o <= 32'b0;
    target_request_o <= 1'b0;
    target_sel_o <= 32'hFFFFFFFF;
    strip_o <= 1'b0;
  end
  // Else, set outputs for next cycle
  else
  begin
    strip_o <= 1'b0;
    case (state)

    wait_state:
      begin
        ack_o <= 1'b0;

        if(write_i)
        begin
          if(!blending_enable_i)
          begin
            pixel_x_o <= x_counter_i;
            pixel_y_o <= y_counter_i;
            pixel_z_o <= z_i;
            pixel_color_o <= pixel_color_i;
            strip_o <= strip_i;
            case(bpp_i)
            32:	strip_color_o <= {8{pixel_color_i[31:0]}};
            31:	strip_color_o <= {8{pixel_color_i[30:0]}};
            30:	strip_color_o <= {8{pixel_color_i[29:0]}};
            29:	strip_color_o <= {8{pixel_color_i[28:0]}};
            28:	strip_color_o <= {9{pixel_color_i[27:0]}};
            27:	strip_color_o <= {9{pixel_color_i[26:0]}};
            26:	strip_color_o <= {9{pixel_color_i[25:0]}};
            25:	strip_color_o <= {10{pixel_color_i[24:0]}};
            24:	strip_color_o <= {10{pixel_color_i[23:0]}};
            23:	strip_color_o <= {11{pixel_color_i[22:0]}};
            22:	strip_color_o <= {11{pixel_color_i[21:0]}};
            21:	strip_color_o <= {12{pixel_color_i[20:0]}};
            20:	strip_color_o <= {12{pixel_color_i[19:0]}};
            19:	strip_color_o <= {13{pixel_color_i[18:0]}};
            18:	strip_color_o <= {14{pixel_color_i[17:0]}};
            17:	strip_color_o <= {15{pixel_color_i[16:0]}};
            16:	strip_color_o <= {16{pixel_color_i[15:0]}};
            15:	strip_color_o <= {17{pixel_color_i[14:0]}};
            14:	strip_color_o <= {18{pixel_color_i[13:0]}};
            13:	strip_color_o <= {19{pixel_color_i[12:0]}};
            12:	strip_color_o <= {21{pixel_color_i[11:0]}};
            11:	strip_color_o <= {23{pixel_color_i[10:0]}};
            10:	strip_color_o <= {25{pixel_color_i[9:0]}};
            9:	strip_color_o <= {28{pixel_color_i[8:0]}};
            8:	strip_color_o <= {32{pixel_color_i[7:0]}};
            7:	strip_color_o <= {36{pixel_color_i[6:0]}};
            6:	strip_color_o <= {42{pixel_color_i[5:0]}};
            5:	strip_color_o <= {51{pixel_color_i[4:0]}};
            4:	strip_color_o <= {64{pixel_color_i[3:0]}};
            3:	strip_color_o <= {85{pixel_color_i[2:0]}};
            2:	strip_color_o <= {128{pixel_color_i[1:0]}};
            1:	strip_color_o <= {256{pixel_color_i[0]}};
            0:	strip_color_o <= {256{1'b0}};
          	endcase
            write1 <= 1'b1;
          end
          else
          begin
            target_request_o   <= !wbm_busy_i;
            combined_alpha_reg <= alpha_i * global_alpha_i;
          end
        end
      end

      // Read pixel color at target (request is sent through the wbm reader arbiter).
      target_read_state:
        if(target_ack_i)
        begin
          // When we receive an ack from memory, calculate the combined color and send the pixel forward in the pipeline (go to write state)
          write1 <= 1'b1;
          pixel_x_o <= x_counter_i;
          pixel_y_o <= y_counter_i;
          pixel_z_o <= z_i;
          target_request_o <= 1'b0;

      	  // Recombine colors
      	  pixel_color_o <= {(((alpha_color_r >> 4'd8) & red_mask) << red_shift) |
      	  									(((alpha_color_g >> 4'd8) & green_mask) << green_shift) |
      	  									((alpha_color_b >> 4'd8) & blue_mask)
      	  								 };
        end
        else
          target_request_o <= !wbm_busy_i | target_request_o;

      // Ack and return to wait state
    write_pixel_ack_state:
  	  begin
        if(ack_i) begin
	        write1 <= 1'b0;
          ack_o <= 1'b1;
        end    
      end

		default:	;
    endcase
  end
end

// State machine
always_ff @(posedge clk_i)
begin
  // reset, init component
  if(rst_i)
    state <= wait_state;
  // Move in statemachine
  else
    case (state)

    wait_state:
      if(write_i & blending_enable_i)
        state <= delay1_state;
      else if(write_i)
        state <= write_pixel_ack_state;
        
    delay1_state:
    	state <= delay2_state;
//    delay2_state:
//    	state <= delay3_state;
    delay2_state:
      state <= target_read_state;

		target_read_state:
      if(target_ack_i)
        state <= write_pixel_ack_state;
//			state <= target_read_ack_state;

//    target_read_ack_state:
//      if(target_ack_i)
//        state <= write_pixel_ack_state;

    write_pixel_ack_state:
      if(ack_i)
        state <= wait_state;

		default:
			state <= wait_state;
    endcase
end

endmodule

