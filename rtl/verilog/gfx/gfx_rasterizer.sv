/*
ORSoC GFX accelerator core
Copyright 2012, ORSoC, Per Lenander, Anton Fosselius.

RASTERIZER MODULE

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
This module takes a rect write or line write request and generates pixels in the span given by dest_pixel0-1.
Triangles can be declared by dest_pixel0-2, they are handled by the triangle module

The operation is clipped to the span given by clip_pixel0-1. Pixels outside the span are discarded.

If texturing is enabled, texture coordinates u (horizontal) and v (vertical) are emitted, offset and clipped by the span given by src_pixel0-1.

When all pixels have been generated and acked, the rasterizer acks the operation and returns to wait raster_state.
*/
module gfx_rasterizer (clk_i, rst_i, pps_i,
  clip_ack_i, interp_ack_i, ack_o, point_write_i,
  rect_write_i, line_write_i, triangle_write_i, interpolate_i, texture_enable_i,
  floodfill_i,
  //source pixel 0 and pixel 1
  src_pixel0_x_i, src_pixel0_y_i, src_pixel1_x_i, src_pixel1_y_i,
  //destination point 0, 1, 2
  dest_pixel0_x_i, dest_pixel0_y_i,
  dest_pixel1_x_i, dest_pixel1_y_i,
  dest_pixel2_x_i, dest_pixel2_y_i,
  clipping_enable_i,
  //clip pixel 0 and pixel 1
  clip_pixel0_x_i, clip_pixel0_y_i, clip_pixel1_x_i, clip_pixel1_y_i,
  target_base_i,
  target_size_x_i, target_size_y_i, 
  target_x0_i, target_y0_i, target_x1_i, target_y1_i,
  x_counter_o, y_counter_o, u_o,v_o,
  clip_write_o, interp_write_o,
  triangle_edge0_o, triangle_edge1_o, triangle_area_o,
  strip_o,
  // character
  char_x_i, char_y_i, char_write_i, char_ack_i,
  // flood fill
  color0_i, color1_i,
  bpp_i, cbpp_i, coeff1_i, coeff2_i, rmw_i,
  floodfill_write_i,
  floodfill_read_request_o, floodfill_adr_o, floodfill_sel_o, floodfill_data_i,
  floodfill_ack_i
);

parameter point_width    = 16;
parameter subpixel_width = 16;
parameter delay_width    = 7;
parameter MDW = 256;

input clk_i;
input rst_i;

input [9:0] pps_i;		// pixels per strip

input clip_ack_i;
input interp_ack_i;
output reg ack_o;

input point_write_i;
input rect_write_i;
input line_write_i;
input triangle_write_i;
input floodfill_i;
input interpolate_i;
input texture_enable_i;

//src pixels
input [point_width-1:0] src_pixel0_x_i;
input [point_width-1:0] src_pixel0_y_i;
input [point_width-1:0] src_pixel1_x_i;
input [point_width-1:0] src_pixel1_y_i;

//dest pixels
input signed [point_width-1:-subpixel_width] dest_pixel0_x_i;
input signed [point_width-1:-subpixel_width] dest_pixel0_y_i;
input signed [point_width-1:-subpixel_width] dest_pixel1_x_i;
input signed [point_width-1:-subpixel_width] dest_pixel1_y_i;
input signed [point_width-1:-subpixel_width] dest_pixel2_x_i;
input signed [point_width-1:-subpixel_width] dest_pixel2_y_i;

wire signed [point_width-1:0] p0_x = $signed(dest_pixel0_x_i[point_width-1:0]);
wire signed [point_width-1:0] p0_y = $signed(dest_pixel0_y_i[point_width-1:0]);
wire signed [point_width-1:0] p1_x = $signed(dest_pixel1_x_i[point_width-1:0]);
wire signed [point_width-1:0] p1_y = $signed(dest_pixel1_y_i[point_width-1:0]);

//clip pixels
input clipping_enable_i;
input [point_width-1:0] clip_pixel0_x_i;
input [point_width-1:0] clip_pixel0_y_i;
input [point_width-1:0] clip_pixel1_x_i;
input [point_width-1:0] clip_pixel1_y_i;

input [31:0] target_base_i;
input [point_width-1:0] target_size_x_i;
input [point_width-1:0] target_size_y_i;
input [point_width-1:0] target_x0_i;
input [point_width-1:0] target_y0_i;
input [point_width-1:0] target_x1_i;
input [point_width-1:0] target_y1_i;

// Generated pixel coordinates
output reg [point_width-1:0] x_counter_o;
output reg [point_width-1:0] y_counter_o;
// Generated texture coordinates
output reg [point_width-1:0] u_o;
output reg [point_width-1:0] v_o;
// Write pixel output signals
output reg clip_write_o;
output reg interp_write_o;
output reg strip_o;

output [2*point_width-1:0] triangle_edge0_o;
output [2*point_width-1:0] triangle_edge1_o;
output [2*point_width-1:0] triangle_area_o;

input [point_width-1:0] char_x_i;
input [point_width-1:0] char_y_i;
input char_write_i;
input char_ack_i;

input [31:0] color0_i;
input [31:0] color1_i;
input [5:0] bpp_i;
input [5:0] cbpp_i;
input [19:0] coeff1_i;
input [9:0] coeff2_i;
input rmw_i;
input floodfill_write_i;
output floodfill_read_request_o;
output [MDW/8-1:0] floodfill_sel_o;
output [31:0] floodfill_adr_o;
input [MDW-1:0] floodfill_data_i;
input floodfill_ack_i;

wire ack_i = interpolate_i ? interp_ack_i : clip_ack_i;

// Variables used in rect drawing
reg [point_width-1:0] rect_p0_x;
reg [point_width-1:0] rect_p0_y;
reg [point_width-1:0] rect_p1_x;
reg [point_width-1:0] rect_p1_y;

//line drawing reg & wires
wire raster_line_busy; // busy, drawing a line.
wire x_major; // is true if x is the major axis
wire valid_out;
reg draw_line;	// trigger the line drawing.

wire [point_width-1:0] major_out; // the major axis
wire [point_width-1:0] minor_out; // the minor axis
wire request_next_pixel;

// triangle
wire triangle_ack;
wire [point_width-1:0] triangle_x_o;
wire [point_width-1:0] triangle_y_o;
wire triangle_write_o;

// Flood fill
reg floodfill;
wire floodfill_ack;
wire floodfill_write_o;
wire [point_width-1:0] floodfill_x_o;
wire [point_width-1:0] floodfill_y_o;

// State machine
typedef enum logic [7:0] 
{
	wait_state = 8'd1,
	point_state = 8'd2,
	rect_state = 8'd4,
	line_state = 8'd8,
	triangle_state = 8'd16,
	triangle_final_state = 8'd32,
	char_state = 8'd64,
	floodfill_state = 8'd128
} rasterizer_state_e;
rasterizer_state_e raster_state;

// Write/ack counter
reg [delay_width-1:0] ack_counter;

always_ff @(posedge clk_i)
if(rst_i)
  ack_counter <= 1'b0;
else if(interpolate_i & ack_i & ~triangle_write_o)
  ack_counter <= ack_counter - 1'b1;
else if(interpolate_i & triangle_write_o & ~ack_i)
  ack_counter <= ack_counter + 1'b1;

// Rect drawing variables
always_ff @(posedge clk_i)
begin
  if(rst_i)
  begin
    rect_p0_x <= 16'b0;
    rect_p0_y <= 16'b0;
    rect_p1_x <= 16'b0;
    rect_p1_y <= 16'b0;
  end
  else
  begin
    if(clipping_enable_i)
    begin
    // pixel0 x
    if(p0_x < $signed(clip_pixel0_x_i)) // check if pixel is left of screen
      rect_p0_x <= clip_pixel0_x_i;
    else if(p0_x > $signed(clip_pixel1_x_i)) // check if pixel is right of screen
      rect_p0_x <= clip_pixel1_x_i;
    else
      rect_p0_x <= p0_x;

    // pixel0 y
    if(p0_y < $signed(clip_pixel0_y_i)) // check if pixel is above the screen
      rect_p0_y <= clip_pixel0_y_i;
    else if(p0_y > $signed(clip_pixel1_y_i)) // check if pixel is below the screen
      rect_p0_y <= clip_pixel1_y_i;
    else
      rect_p0_y <= p0_y;

    // pixel1 x
    if(p1_x < $signed(clip_pixel0_x_i)) // check if pixel is left of screen
      rect_p1_x <= clip_pixel0_x_i;
    else if(p1_x > $signed(clip_pixel1_x_i -1)) // check if pixel is right of screen
      rect_p1_x <= clip_pixel1_x_i -1'b1;
    else
      rect_p1_x <= dest_pixel1_x_i[point_width-1:0] - 1;

    // pixel1 y
    if(p1_y < $signed(clip_pixel0_y_i)) // check if pixel is above the screen
      rect_p1_y <= clip_pixel0_y_i;
    else if(p1_y > $signed(clip_pixel1_y_i -1)) // check if pixel is below the screen
      rect_p1_y <= clip_pixel1_y_i -1'b1;
    else
      rect_p1_y <= p1_y - 1;
    end
    else
    begin
      rect_p0_x <= p0_x       >= 0 ? p0_x : 16'b0;
      rect_p0_y <= p0_y       >= 0 ? p0_y : 16'b0;
      rect_p1_x <= (p1_x - 1) >= 0 ? p1_x - 1 : 16'b0;
      rect_p1_y <= (p1_y - 1) >= 0 ? p1_y - 1 : 16'b0;
    end
  end
end

// Checks if the current line in the rect being drawn is complete
wire raster_rect_line_done = (x_counter_o >= rect_p1_x) | (texture_enable_i && (u_o >= src_pixel1_x_i-1));
// Checks if the current rect is completely drawn
// TODO: ugly fix to prevent the an extra pixel being written when texturing is enabled. Ugly.
//wire raster_rect_done = ack_i & (x_counter_o >= rect_p1_x) & ((y_counter_o >= rect_p1_y) | (texture_enable_i && (v_o >= src_pixel1_y_i-1)));
wire raster_rect_done = (ack_i | texture_enable_i) &
                        (x_counter_o >= rect_p1_x) &
                        ((y_counter_o >= rect_p1_y) | (texture_enable_i && (v_o >= src_pixel1_y_i-1)));
// Special check if there are no pixels to draw at all (send ack immediately)
wire empty_raster = (rect_p0_x > rect_p1_x) | (rect_p0_y > rect_p1_y);

wire triangle_finished = ~interpolate_i | (ack_counter == 1'b0);

// Manage states
always_ff @(posedge clk_i)
if(rst_i)
  raster_state <= wait_state;
else
  case (raster_state)

  wait_state:
  	case(1'b1)
  	point_write_i:
  		raster_state <= point_state;
    triangle_write_i:
    	raster_state <= triangle_state;
    rect_write_i & !empty_raster: // if request for drawing a rect, go to rect drawing raster_state
      raster_state <= rect_state;
    line_write_i:
      raster_state <= line_state; // if request for drawing a line, go to line drawing raster_state
    char_write_i:
    	raster_state <= char_state;
    floodfill_write_i:
    	raster_state <= floodfill_state;
    default: 
    	raster_state <= wait_state;
  	endcase

	point_state:
		if (clip_ack_i)
			raster_state <= wait_state;
		else
			raster_state <= point_state;

  rect_state:
    if(raster_rect_done) // if we are done drawing a rect, go to wait raster_state
      raster_state <= wait_state;
    else
    	raster_state <= rect_state;

  line_state:
    if(!raster_line_busy & !draw_line)  // if we are done drawing a line, go to wait raster_state
      raster_state <= wait_state;
    else
    	raster_state <= line_state;

  triangle_state:
    if(triangle_ack & triangle_finished)
      raster_state <= wait_state;
    else if(triangle_ack)
      raster_state <= triangle_final_state;
    else
    	raster_state <= triangle_state;

  triangle_final_state:
    if(triangle_finished)
      raster_state <= wait_state;
    else
      raster_state <= triangle_final_state;

  char_state:
  	if (char_ack_i)
  		raster_state <= wait_state;
  	else
			raster_state <= char_state;

	floodfill_state:
		if (floodfill_ack)
			raster_state <= wait_state;
		else
			raster_state <= floodfill_state;
		
	default:
		raster_state <= wait_state;
  endcase

// If interpolation is active, only write to interp module if queue is not full. 
wire interp_ready   = interpolate_i ? (ack_counter <= point_width)   & ~interp_write_o : ack_i;
wire triangle_ready = interpolate_i ? (ack_counter <= point_width-1) & ~interp_write_o : ack_i;

// Calculate when it is possible to use a strip.
always_comb
begin
	strip_o = 1'b0;
	/*
	if (x_counter_o != rect_p1_x && raster_state==rect_state)
		case(color_depth_i)
		2'b00:	if (x_counter_o[4:0]==5'd0 && x_counter_o+6'd32 <= rect_p1_x) strip_o = 1'b1;
		2'b01:	
			if (BPP12) begin
				if (x_counter_o % 21==16'd0 && x_counter_o+6'd21 <= rect_p1_x) strip_o = 1'b1;
			end
			else begin
				if (x_counter_o[3:0]==4'd0 && x_counter_o+6'd16 <= rect_p1_x) strip_o = 1'b1;
			end
		2'b10:	if (x_counter_o % 10==16'd0 && x_counter_o+6'd10 <= rect_p1_x) strip_o = 1'b1;
		2'b11:	if (x_counter_o[2:0]==3'd0 && x_counter_o+6'd8 <= rect_p1_x) strip_o = 1'b1;
		endcase
	*/
end

// Manage outputs (mealy machine)
always_ff @(posedge clk_i)
begin
  // Reset
  if(rst_i)
  begin
    ack_o          <= 1'b0;
    x_counter_o    <= 16'b0;
    y_counter_o    <= 16'b0;
    clip_write_o   <= 1'b0;
    interp_write_o <= 1'b0;
    u_o            <= 1'b0;
    v_o            <= 1'b0;

    //reset line regs
    draw_line <= 1'b0;
  end
  else
  begin
  	ack_o <= 1'b0;
    case (raster_state)

    // Wait for incoming instructions
    wait_state:
    
    	if (point_write_i) begin
				x_counter_o <= p0_x;
				y_counter_o <= p0_y;
				clip_write_o <= 1'b1;
			end

      else if(rect_write_i & !empty_raster) // Start a raster rectangle operation
      begin
        ack_o <= 1'b0;
        clip_write_o <= 1'b1;
        // Generate pixel coordinates
        x_counter_o <= rect_p0_x;
        y_counter_o <= rect_p0_y;
        // Generate texture coordinates
        u_o <= (($signed(clip_pixel0_x_i) < p0_x) ? 1'b0 :
                 $signed(clip_pixel0_x_i) - p0_x) + src_pixel0_x_i;
        v_o <= (($signed(clip_pixel0_y_i) < p0_y) ? 1'b0 :
                 $signed(clip_pixel0_y_i) - p0_y) + src_pixel0_y_i;
      end

      else if(rect_write_i & empty_raster & !ack_o) // Start a raster rectangle operation
        ack_o <= 1'b1;

      // Start a raster line operation
      else if(line_write_i) begin
        draw_line <= 1'b1;
        ack_o <= 1'b0;
      end
      else if (floodfill_write_i) begin
      	floodfill <= 1'b1;
      	ack_o <= 1'b0;
      end
      else
        ack_o <= 1'b0;

		point_state:
			if (clip_ack_i) begin
				clip_write_o <= 1'b0;
				//ack_o <= 1'b1; No ack sent back for point, the transform module already sent one.
			end

    // Rasterize a rectangle between p0 and p1 (rasterize = generate the pixels)
    rect_state:
      begin
        if(ack_i) // If our last coordinate was acknowledged by a fragment processor
        begin
          if(raster_rect_line_done) // iterate through width of rect
          begin
            x_counter_o <= rect_p0_x;
            y_counter_o <= y_counter_o + 1'b1;
            u_o <= ($signed(clip_pixel0_x_i) < p0_x ? 1'b0 :
                    $signed(clip_pixel0_x_i) - p0_x) + $signed(src_pixel0_x_i);
            v_o <= v_o + 1'b1;
          end
          else begin
          	if (strip_o) begin
          		x_counter_o <= x_counter_o + pps_i;
          		u_o <= u_o + pps_i;
          	end
          	else begin
            	x_counter_o <= x_counter_o + 1'b1;
            	u_o <= u_o + 1'b1;
            end
          end
        end

        if (raster_rect_done) begin // iterate through height of rect (are we done?)
          clip_write_o <= 1'b0; // Only send ack when we get ack_i (see wait raster_state)
          ack_o <= 1'b1;
        end
      end

      // Rasterize a line between dest_pixel0 and dest_pixel1 (rasterize = generate the pixels)
    line_state:
      begin
        draw_line <= 1'b0;
        clip_write_o <= raster_line_busy & valid_out;
        x_counter_o <= x_major ? major_out : minor_out;
        y_counter_o <= x_major ? minor_out : major_out;
        ack_o <= !raster_line_busy & !draw_line;
      end

    triangle_state:
      if(triangle_ack) begin
        interp_write_o <= 1'b0;
        clip_write_o <= 1'b0;
        if(triangle_finished)
          ack_o <= 1'b1;
      end
      else if(~interpolate_i) begin
        x_counter_o <= triangle_x_o;
        y_counter_o <= triangle_y_o;
        clip_write_o <= triangle_write_o ;
      end
      else if(interpolate_i & interp_ready) begin
        x_counter_o <= triangle_x_o;
        y_counter_o <= triangle_y_o;
        // edge0, edge1 and area are set by the triangle module
        interp_write_o <= triangle_write_o;
      end
      else begin
        interp_write_o <= 1'b0;
        clip_write_o <= 1'b0;
      end

    triangle_final_state:
      if(triangle_finished)
        ack_o <= 1'b1;

		char_state:
			if (char_ack_i)
				ack_o <= 1'b1;
			else begin
				x_counter_o <= char_x_i;
				y_counter_o <= char_y_i;
				clip_write_o <= char_write_i;
			end
	
		floodfill_state:
			if (floodfill_ack) begin
        interp_write_o <= 1'b0;
        clip_write_o <= 1'b0;
        ack_o <= 1'b1;
			end
			else if (~interpolate_i) begin
				x_counter_o <= floodfill_x_o;
				y_counter_o <= floodfill_y_o;
				clip_write_o <= floodfill_write_o;
			end
			else if (interpolate_i & interp_ready) begin
				x_counter_o <= floodfill_x_o;
				y_counter_o <= floodfill_y_o;
				interp_write_o <= floodfill_write_o;
			end

		default:	;
    endcase
  end
end

// Request wire for line drawing module
assign request_next_pixel = ack_i & raster_line_busy;

// Instansiation of bresenham line drawing module
bresenham_line bresenham(
.clk_i        ( clk_i                ),  //clock
.rst_i        ( rst_i                ),  //rest
.pixel0_x_i   ( dest_pixel0_x_i      ),  // left pixel x
.pixel0_y_i   ( dest_pixel0_y_i      ),  // left pixel y
.pixel1_x_i   ( dest_pixel1_x_i      ),  // right pixel x
.pixel1_y_i   ( dest_pixel1_y_i      ),  // right pixel y
.draw_line_i  ( draw_line            ), // trigger for drawing a line
.read_pixel_i ( request_next_pixel   ), // request next pixel
.busy_o       ( raster_line_busy     ), // is true while line is drawn
.x_major_o    ( x_major              ), // is true if x is the major axis
.major_o      ( major_out            ), // the major axis pixel coordinate
.minor_o      ( minor_out            ), // the minor axis pixel coordinate
.valid_o      ( valid_out            )
);

defparam bresenham.point_width = point_width;
defparam bresenham.subpixel_width = subpixel_width;

// Triangle module instanciated
gfx_triangle triangle(
.clk_i            (clk_i),
.rst_i            (rst_i),
.ack_i            (triangle_ready),
.ack_o            (triangle_ack),
.triangle_write_i (triangle_write_i),
.texture_enable_i (texture_enable_i),
.dest_pixel0_x_i  (dest_pixel0_x_i),
.dest_pixel0_y_i  (dest_pixel0_y_i),
.dest_pixel1_x_i  (dest_pixel1_x_i),
.dest_pixel1_y_i  (dest_pixel1_y_i),
.dest_pixel2_x_i  (dest_pixel2_x_i),
.dest_pixel2_y_i  (dest_pixel2_y_i),
.x_counter_o      (triangle_x_o),
.y_counter_o      (triangle_y_o),
.triangle_edge0_o (triangle_edge0_o),
.triangle_edge1_o (triangle_edge1_o),
.triangle_area_o  (triangle_area_o),
.write_o          (triangle_write_o)
);

defparam triangle.point_width    = point_width;
defparam triangle.subpixel_width = subpixel_width;

gfx_floodfill #(.MDW(MDW)) ufloodfill1 (
	.rst_i(rst_i),
	.clk_i(clk_i),
	.floodfill_i(floodfill),
	.floodfill_ack_o(floodfill_ack),
	.fill_color(color0_i),
	.border_color(color1_i),
	.floodfill_write_o(floodfill_write_o),
	.target_base_i(target_base_i),
	.target_size_x_i(target_size_x_i),
	.target_x0_i(target_x0_i),
	.target_y0_i(target_y0_i),
	.target_x1_i(target_x1_i),
	.target_y1_i(target_y1_i),
	.clip_enable_i(clipping_enable_i),
	.clip_x0_i(clip_pixel0_x_i),
	.clip_y0_i(clip_pixel0_y_i),
	.clip_x1_i(clip_pixel1_x_i),
	.clip_y1_i(clip_pixel1_y_i),
	.dest_pixel0_x_i(dest_pixel0_x_i),
	.dest_pixel0_y_i(dest_pixel0_y_i),
	.floodfill_x_o(floodfill_x_o),
	.floodfill_y_o(floodfill_y_o),
	.bpp_i(bpp_i),
	.cbpp_i(cbpp_i),
	.coeff1_i(coeff1_i),
	.coeff2_i(coeff2_i),
	.rmw_i(rmw_i),
	.floodfill_adr_o(floodfill_adr_o),
	.floodfill_sel_o(floodfill_sel_o),
	.floodfill_data_i(floodfill_data_i),
	.floodfill_ack_i(floodfill_ack_i)
);

endmodule
