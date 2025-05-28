/*
ORSoC GFX accelerator core
Copyright 2012, ORSoC, Per Lenander, Anton Fosselius.

INTERPOLATION MODULE - Color, UV and Z calculator

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
This module uses the interpolation factors from the divider to calculate color, depth and texture coordinates
*/
import gfx256_pkg::*;

module gfx256_cuvz(
  clk_i, rst_i,
  ack_i, ack_o,
  write_i,
  // Variables needed for interpolation
  factor0_i, factor1_i,
  // Color
  color0_i, color1_i, color2_i,
  color_o,
  color_comp_i,
  // Depth
  z0_i, z1_i, z2_i,
  z_o,
  // Texture coordinates
  u0_i, v0_i, u1_i, v1_i, u2_i, v2_i,
  u_o, v_o,
  // Alpha
  a0_i, a1_i, a2_i,
  a_o,
  // Bezier shape calculation
  bezier_factor0_o, bezier_factor1_o,
  // Raster position
  x_i, y_i, x_o, y_o,

  write_o
  );

parameter point_width = 16;
parameter BPP12 = 1'b0;

input                        clk_i;
input                        rst_i;

input                        ack_i;
output reg                   ack_o;

input                        write_i;

// Input barycentric coordinates used to interpolate values
input      [point_width-1:0] factor0_i;
input      [point_width-1:0] factor1_i;

// Color for each point
input                 [31:0] color0_i;
input                 [31:0] color1_i;
input                 [31:0] color2_i;
input [15:0] color_comp_i;
// Interpolated color
output reg            [31:0] color_o;

// Depth for each point
input signed [point_width-1:0] z0_i;
input signed [point_width-1:0] z1_i;
input signed [point_width-1:0] z2_i;
// Interpolated depth
output reg signed [point_width-1:0] z_o;

// Alpha for each point
input      [7:0] a0_i;
input      [7:0] a1_i;
input      [7:0] a2_i;
// Interpolated alpha
output reg [7:0] a_o;

// Texture coordinates for each point
input      [point_width-1:0] u0_i;
input      [point_width-1:0] u1_i;
input      [point_width-1:0] u2_i;
input      [point_width-1:0] v0_i;
input      [point_width-1:0] v1_i;
input      [point_width-1:0] v2_i;
// Interpolated texture coordinates
output reg [point_width-1:0] u_o;
output reg [point_width-1:0] v_o;

// Bezier factors, used to draw bezier shapes
output reg [point_width-1:0] bezier_factor0_o;
output reg [point_width-1:0] bezier_factor1_o;

// Input and output pixel coordinate (passed on)
input      [point_width-1:0] x_i;
input      [point_width-1:0] y_i;
output reg [point_width-1:0] x_o;
output reg [point_width-1:0] y_o;

// Write pixel output signal
output write_o;

// Holds the barycentric coordinates for interpolation
reg        [point_width:0] factor0;
reg        [point_width:0] factor1;
reg        [point_width:0] factor2;

reg write1;
assign write_o = write1;

// State machine
reg [1:0] state;
parameter wait_state   = 2'b00,
          prep_state   = 2'b01,
          write_state  = 2'b10;

// Manage states
always_ff @(posedge clk_i)
if(rst_i)
  state <= wait_state;
else
  case (state)

    wait_state:
      if(write_i)
        state <= prep_state;

    prep_state:
      state <= write_state;

    write_state:
      if(ack_i)
        state <= wait_state;

  endcase

// Interpolate texture coordinates, depth and alpha
wire [point_width*2-1:0] u = factor0 * u0_i + factor1 * u1_i + factor2 * u2_i;
wire [point_width*2-1:0] v = factor0 * v0_i + factor1 * v1_i + factor2 * v2_i;
wire [point_width+8-1:0] a = factor0 * a0_i + factor1 * a1_i + factor2 * a2_i;

// Note: special case here since z is signed. To prevent incorrect multiplication, factor is treated as a signed value (with a 0 added in front)
wire signed [point_width*2-1:0] z = $signed({1'b0, factor0}) * z0_i + $signed({1'b0, factor1}) * z1_i + $signed({1'b0, factor2}) * z2_i;

// REF: Loop & Blinn, for rendering quadratic bezier shapes
wire [point_width-1:0] bezier_factor0 = (factor1/2) + factor2;
wire [point_width-1:0] bezier_factor1 = factor2;

// ***************** //
// Interpolate color //
// ***************** //

integer nr,ng,nb;
reg [9:0] red_mask,green_mask,blue_mask;
reg [4:0] red_shift;
reg [3:0] green_shift;
always_ff @(posedge clk_i)
	for (nr = 0; nr < 10; nr = nr + 1)
		red_mask <= nr < color_comp_i[11:8];
always_ff @(posedge clk_i)
	for (ng = 0; ng < 10; ng = ng + 1)
		green_mask <= ng < color_comp_i[7:4];
always_ff @(posedge clk_i)
	for (nb = 0; nb < 10; nb = nb + 1)
		blue_mask <= nb < color_comp_i[3:0];
always_ff @(posedge clk_i)
	red_shift <= color_comp_i[3:0] + color_comp_i[7:4];		
always_ff @(posedge clk_i)
	green_shift <= color_comp_i[3:0];	

// Split colors
wire [9:0] color0_r = (color0_i >> red_shift) & red_mask;
wire [9:0] color0_g = (color0_i >> green_shift) & green_mask;
wire [9:0] color0_b = color0_i & blue_mask;

wire [9:0] color1_r = (color1_i >> red_shift) & red_mask;
wire [9:0] color1_g = (color1_i >> green_shift) & green_mask;
wire [9:0] color1_b = color1_i & blue_mask;

wire [9:0] color2_r = (color2_i >> red_shift) & red_mask;
wire [9:0] color2_g = (color2_i >> green_shift) & green_mask;
wire [9:0] color2_b = color2_i & blue_mask;

// Interpolation
wire [10+point_width-1:0] color_r = factor0*color0_r +  factor1*color1_r +  factor2*color2_r;
wire [10+point_width-1:0] color_g = factor0*color0_g +  factor1*color1_g +  factor2*color2_g;
wire [10+point_width-1:0] color_b = factor0*color0_b +  factor1*color1_b +  factor2*color2_b;

always_ff @(posedge clk_i)
begin
  // Reset
  if(rst_i)
  begin
    ack_o       <= 1'b0;
    write1 <= 1'b0;
    x_o         <= 1'b0;
    y_o         <= 1'b0;
    color_o     <= 1'b0;
    z_o         <= 1'b0;
    u_o         <= 1'b0;
    v_o         <= 1'b0;
    a_o         <= 1'b0;
    factor0     <= 1'b0;
    factor1     <= 1'b0;
    factor2     <= 1'b0;
  end
  else
    case (state)

    wait_state:
      begin
        ack_o     <= 1'b0;
        if(write_i)
        begin
          x_o     <= x_i;
          y_o     <= y_i;
          factor0 <= factor0_i;
          factor1 <= factor1_i;
          factor2 <= (factor0_i + factor1_i >= (1 << point_width)) ? 1'b0 : (1 << point_width) - factor0_i - factor1_i;
        end
      end

    prep_state:
      begin
        // Assign outputs
        // --------------
        write1 <= 1'b1;
        // Texture coordinates
        u_o     <= u[point_width*2-1:point_width];
        v_o     <= v[point_width*2-1:point_width];
        // Bezier calculations
        bezier_factor0_o <= bezier_factor0;
        bezier_factor1_o <= bezier_factor1;
        // Depth
        z_o     <= z[point_width*2-1:point_width];
        // Alpha
        a_o     <= a[point_width+8-1:point_width];
        // Color
        color_o <= {((color_r >> point_width) & red_mask) << red_shift,
        					  ((color_g >> point_width) & green_mask) << green_shift,
        					  ((color_b >> point_width) & bluemask)
        					 };
      end

    write_state:
      if (ack_i) begin
        write1 <= 1'b0;
        ack_o <= 1'b1;
      end
    endcase
   
end

endmodule

