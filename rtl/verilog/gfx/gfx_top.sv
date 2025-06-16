/*
ORSoC GFX accelerator core
Copyright 2012, ORSoC, Per Lenander, Anton Fosselius.

TOP MODULE

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
import wishbone_pkg::*;
import gfx_pkg::*;

module gfx_top (wb_clk_i, wb_rst_i, wb_inta_o, wbs_cs_i,
  // Wishbone master signals (interfaces with video memory, write)
  wbm_req, wbm_resp,
  // Wishbone slave signals (interfaces with main bus/CPU)
  wbs_clk_i, wbs_req, wbs_resp
);
parameter CID = 4'd5;
// Set default parameters
parameter point_width    = 16;
parameter subpixel_width = 16;
parameter fifo_depth     = 11;

parameter REG_ADR_HIBIT = 8;
parameter MDW = 256;

// Common wishbone signals
input wb_clk_i;    // master clock input
input wb_rst_i;    // Asynchronous active high reset
output wb_inta_o;   // interrupt

// Wishbone slave signals
input wbs_clk_i;
input wb_cmd_request32_t wbs_req;
output wb_cmd_response32_t wbs_resp;
input wbs_cs_i;			// circuit select

// Wishbone master signals (write)
output wb_cmd_request256_t wbm_req;
input wb_cmd_response256_t wbm_resp;

// Wires and variables

wire wbmwriter_sint; // connect to slave interface
wire wbmreader_sint;

wire vector_wbs_ack;
wire transform_wbs_ack;

wire            [31:0] target_base_reg;
wire [point_width-1:0] target_size_x_reg;
wire [point_width-1:0] target_size_y_reg;
wire [point_width-1:0] target_x0_reg;
wire [point_width-1:0] target_y0_reg;
wire [point_width-1:0] target_x1_reg;
wire [point_width-1:0] target_y1_reg;

wire            [31:0] wbs_fragment_tex0_base;
wire [point_width-1:0] wbs_fragment_tex0_size_x;
wire [point_width-1:0] wbs_fragment_tex0_size_y;

wire [31:0] render_wbmwriter_addr;
wire [MDW/8-1:0] render_wbmwriter_sel;
wire [MDW-1:0] render_wbmwriter_dat;
wire [MDW-1:0] render_wbmwriter_dati;

wire [1:0] color_depth_reg;

wire render_wbmwriter_memory_pixel_write;
wire render_wbmwriter_memory_pixel_read;
wire wbs_raster_point_write;
wire wbs_raster_rect_write;
wire wbs_raster_line_write;
wire wbs_raster_triangle_write;
wire wbs_raster_interpolate;
wire wbs_char_write;
wire wbs_raster_floodfill_write;

wire wbs_fragment_curve_write;

wire wbmwriter_render_ack;

// src pixel
wire [point_width-1:0] wbs_raster_src_pixel0_x;
wire [point_width-1:0] wbs_raster_src_pixel0_y;
wire [point_width-1:0] wbs_raster_src_pixel1_x;
wire [point_width-1:0] wbs_raster_src_pixel1_y;

// dest pixel
wire signed [point_width-1:-subpixel_width] wbs_transform_dest_pixel_x;
wire signed [point_width-1:-subpixel_width] wbs_transform_dest_pixel_y;
wire signed [point_width-1:-subpixel_width] wbs_transform_dest_pixel_z;
wire                           [1:0] wbs_transform_dest_pixel_id;

// transformation matrix
wire signed [point_width-1:-subpixel_width] wbs_transform_aa;
wire signed [point_width-1:-subpixel_width] wbs_transform_ab;
wire signed [point_width-1:-subpixel_width] wbs_transform_ac;
wire signed [point_width-1:-subpixel_width] wbs_transform_tx;
wire signed [point_width-1:-subpixel_width] wbs_transform_ba;
wire signed [point_width-1:-subpixel_width] wbs_transform_bb;
wire signed [point_width-1:-subpixel_width] wbs_transform_bc;
wire signed [point_width-1:-subpixel_width] wbs_transform_ty;
wire signed [point_width-1:-subpixel_width] wbs_transform_ca;
wire signed [point_width-1:-subpixel_width] wbs_transform_cb;
wire signed [point_width-1:-subpixel_width] wbs_transform_cc;
wire signed [point_width-1:-subpixel_width] wbs_transform_tz;

// clip pixel
wire [point_width-1:0] clip_pixel0_x_reg;
wire [point_width-1:0] clip_pixel0_y_reg;
wire [point_width-1:0] clip_pixel1_x_reg;
wire [point_width-1:0] clip_pixel1_y_reg;

wire [31:0] color0_reg;
wire [31:0] color1_reg;
wire [31:0] color2_reg;

wire [point_width-1:0] u0_reg;
wire [point_width-1:0] v0_reg;
wire [point_width-1:0] u1_reg;
wire [point_width-1:0] v1_reg;
wire [point_width-1:0] u2_reg;
wire [point_width-1:0] v2_reg;

wire [7:0] alpha0_reg;
wire [7:0] alpha1_reg;
wire [7:0] alpha2_reg;

wire texture_enable_reg;

wire        blending_enable_reg;
wire  [7:0] global_alpha_reg;
wire        colorkey_enable_reg;
wire [31:0] colorkey_reg;
wire        clipping_enable_reg;
wire        inside_reg;
wire        zbuffer_enable_reg;
wire [31:0] zbuffer_base_reg;

wire        wbs_transform_transform;
wire        wbs_transform_forward;

wire        raster_wbs_ack;

wire [31:0] font_table_base_reg;
wire [15:0] font_id_reg;
wire [15:0] char_code_reg;

wire [5:0] bpp;
wire [5:0] cbpp;
wire [19:0] coeff1;
wire [9:0] coeff2;
wire [9:0] pps;
wire rmw;
wire [15:0] color_comp;

// Slave wishbone interface. Reads wishbone bus and fills registers
gfx_wbs wb_databus (
  .clk_i (wb_clk_i),
  .wbs_clk_i (wbs_clk_i),
  .rst_i (wb_rst_i),
  .cs_i(wbs_cs_i),
  .wbs_req(wbs_req),
  .wbs_resp(wbs_resp),
  .inta_o (wb_inta_o),

  //source pixel
  .src_pixel0_x_o (wbs_raster_src_pixel0_x),
  .src_pixel0_y_o (wbs_raster_src_pixel0_y),
  .src_pixel1_x_o (wbs_raster_src_pixel1_x),
  .src_pixel1_y_o (wbs_raster_src_pixel1_y),
  //destination pixel
  .dest_pixel_x_o (wbs_transform_dest_pixel_x),
  .dest_pixel_y_o (wbs_transform_dest_pixel_y),
  .dest_pixel_z_o (wbs_transform_dest_pixel_z),
  .dest_pixel_id_o (wbs_transform_dest_pixel_id),
  //matrix
  .aa_o (wbs_transform_aa),
  .ab_o (wbs_transform_ab),
  .ac_o (wbs_transform_ac),
  .tx_o (wbs_transform_tx),
  .ba_o (wbs_transform_ba),
  .bb_o (wbs_transform_bb),
  .bc_o (wbs_transform_bc),
  .ty_o (wbs_transform_ty),
  .ca_o (wbs_transform_ca),
  .cb_o (wbs_transform_cb),
  .cc_o (wbs_transform_cc),
  .tz_o (wbs_transform_tz),
  .transform_point_o (wbs_transform_transform),
  .forward_point_o (wbs_transform_forward),
  //clip pixel
  .clip_pixel0_x_o (clip_pixel0_x_reg),
  .clip_pixel0_y_o (clip_pixel0_y_reg),
  .clip_pixel1_x_o (clip_pixel1_x_reg),
  .clip_pixel1_y_o (clip_pixel1_y_reg),

  .color0_o (color0_reg),
  .color1_o (color1_reg),
  .color2_o (color2_reg),

  .u0_o (u0_reg),
  .v0_o (v0_reg),
  .u1_o (u1_reg),
  .v1_o (v1_reg),
  .u2_o (u2_reg),
  .v2_o (v2_reg),

  .a0_o (alpha0_reg),
  .a1_o (alpha1_reg),
  .a2_o (alpha2_reg),
  .global_alpha_o (global_alpha_reg),

  .target_base_o (target_base_reg),
  .target_size_x_o (target_size_x_reg),
  .target_size_y_o (target_size_y_reg),
  .target_x0_o (target_x0_reg),
  .target_y0_o (target_y0_reg),
  .target_x1_o (target_x1_reg),
  .target_y1_o (target_y1_reg),
  .tex0_base_o (wbs_fragment_tex0_base),
  .tex0_size_x_o (wbs_fragment_tex0_size_x),
  .tex0_size_y_o (wbs_fragment_tex0_size_y),

  .color_depth_o (color_depth_reg),

	.point_write_o (wbs_raster_point_write),
  .rect_write_o (wbs_raster_rect_write),
  .line_write_o (wbs_raster_line_write),
  .triangle_write_o (wbs_raster_triangle_write),
  .curve_write_o (wbs_fragment_curve_write),
  .char_write_o	(wbs_char_write),
  .floodfill_write_o (wbs_raster_floodfill_write),
  .interpolate_o (wbs_raster_interpolate),

  .writer_sint_i (wbmwriter_sint),
  .reader_sint_i (wbmreader_sint),

  .pipeline_ack_i (raster_wbs_ack),
  .transform_ack_i (transform_wbs_ack),

  .texture_enable_o (texture_enable_reg),
  .blending_enable_o (blending_enable_reg),
  .colorkey_enable_o (colorkey_enable_reg),
  .colorkey_o (colorkey_reg),
  .clipping_enable_o (clipping_enable_reg),
  .inside_o (inside_reg),
  .zbuffer_enable_o (zbuffer_enable_reg),
  .zbuffer_base_o (zbuffer_base_reg),
  .char_code_o (char_code_reg),
  .font_table_base_o (font_table_base_reg),
  .font_id_o (font_id_reg),
  
  .bpp_o(bpp),
  .cbpp_o(cbpp),
  .coeff1_o(coeff1),
  .coeff2_o(coeff2),
  .pps_o(pps),
  .rmw_o(rmw),
	.color_comp_o(color_comp)  
);

defparam wb_databus.point_width    = point_width;
defparam wb_databus.subpixel_width = subpixel_width;
defparam wb_databus.fifo_depth     = fifo_depth;
defparam wb_databus.REG_ADR_HIBIT  = REG_ADR_HIBIT;
defparam wb_databus.MDW = MDW;

wire signed [point_width-1:-subpixel_width] transform_raster_dest_pixel0_x;
wire signed [point_width-1:-subpixel_width] transform_raster_dest_pixel0_y;
wire signed [point_width-1:-subpixel_width] transform_raster_dest_pixel1_x;
wire signed [point_width-1:-subpixel_width] transform_raster_dest_pixel1_y;
wire signed [point_width-1:-subpixel_width] transform_raster_dest_pixel2_x;
wire signed [point_width-1:-subpixel_width] transform_raster_dest_pixel2_y;

wire signed [point_width-1:0] transform_cuvz_dest_pixel0_z;
wire signed [point_width-1:0] transform_cuvz_dest_pixel1_z;
wire signed [point_width-1:0] transform_cuvz_dest_pixel2_z;

// Apply transforms to points
gfx_transform transform(
	.clk_i (wb_clk_i),
	.rst_i (wb_rst_i),
	.x_i (wbs_transform_dest_pixel_x),
	.y_i (wbs_transform_dest_pixel_y),
	.z_i (wbs_transform_dest_pixel_z),
	.point_id_i (wbs_transform_dest_pixel_id),
	// Matrix
	.aa (wbs_transform_aa),
	.ab (wbs_transform_ab),
	.ac (wbs_transform_ac),
	.tx (wbs_transform_tx),
	.ba (wbs_transform_ba),
	.bb (wbs_transform_bb),
	.bc (wbs_transform_bc),
	.ty (wbs_transform_ty),
	.ca (wbs_transform_ca),
	.cb (wbs_transform_cb),
	.cc (wbs_transform_cc),
	.tz (wbs_transform_tz),
	// Output points
	.p0_x_o (transform_raster_dest_pixel0_x),
	.p0_y_o (transform_raster_dest_pixel0_y),
	.p0_z_o (transform_cuvz_dest_pixel0_z),
	.p1_x_o (transform_raster_dest_pixel1_x),
	.p1_y_o (transform_raster_dest_pixel1_y),
	.p1_z_o (transform_cuvz_dest_pixel1_z),
	.p2_x_o (transform_raster_dest_pixel2_x),
	.p2_y_o (transform_raster_dest_pixel2_y),
	.p2_z_o (transform_cuvz_dest_pixel2_z),
	.transform_i (wbs_transform_transform),
	.forward_i (wbs_transform_forward),
	.ack_o (transform_wbs_ack)
);

defparam transform.point_width = point_width;
defparam transform.subpixel_width = subpixel_width;

wire raster_clip_write;
wire [point_width-1:0] raster_x_pixel;
wire [point_width-1:0] raster_y_pixel;
wire clip_ack;
wire raster_interp_write;
wire interp_raster_ack;
wire [point_width-1:0] raster_clip_u;
wire [point_width-1:0] raster_clip_v;

wire [2*point_width-1:0] raster_interp_edge0;
wire [2*point_width-1:0] raster_interp_edge1;
wire [2*point_width-1:0] raster_interp_area;

wire [point_width-1:0] char_x_o;
wire [point_width-1:0] char_y_o;
wire char_write_o;
wire char_ack_o;
wire raster_strip;

wire floodfill_read_request;
wire [31:0] floodfill_adr;
wire [MDW/8-1:0] floodfill_sel;
wire [MDW-1:0] floodfill_data;

// Rasterizer generates pixels to calculate
gfx_rasterizer #(.MDW(MDW)) rasterizer0 (
  .clk_i            (wb_clk_i),
  .rst_i            (wb_rst_i),

	.pps_i(pps),
  .clip_ack_i       (clip_ack),
  .interp_ack_i     (interp_raster_ack),
  .ack_o            (raster_wbs_ack),

	.point_write_i	  (wbs_raster_point_write),
  .rect_write_i	    (wbs_raster_rect_write),
  .line_write_i     (wbs_raster_line_write),
  .triangle_write_i (wbs_raster_triangle_write),
  .floodfill_write_i(wbs_raster_floodfill_write),
  .interpolate_i    (wbs_raster_interpolate),

  .texture_enable_i (texture_enable_reg),
  // source pixel coordinates
  .src_pixel0_x_i   (wbs_raster_src_pixel0_x),
  .src_pixel0_y_i   (wbs_raster_src_pixel0_y),
  .src_pixel1_x_i   (wbs_raster_src_pixel1_x),
  .src_pixel1_y_i   (wbs_raster_src_pixel1_y),

  // destination pixel coordinates
  .dest_pixel0_x_i  (transform_raster_dest_pixel0_x),
  .dest_pixel0_y_i  (transform_raster_dest_pixel0_y),
  .dest_pixel1_x_i  (transform_raster_dest_pixel1_x),
  .dest_pixel1_y_i  (transform_raster_dest_pixel1_y),
  .dest_pixel2_x_i  (transform_raster_dest_pixel2_x),
  .dest_pixel2_y_i  (transform_raster_dest_pixel2_y),

  // clip pixel coordinates
  .clipping_enable_i (clipping_enable_reg),
  .clip_pixel0_x_i (clip_pixel0_x_reg),
  .clip_pixel0_y_i (clip_pixel0_y_reg),
  .clip_pixel1_x_i (clip_pixel1_x_reg),
  .clip_pixel1_y_i (clip_pixel1_y_reg),	

  // Screen size
  .target_base_i(target_base_reg),
  .target_size_x_i (target_size_x_reg),
  .target_size_y_i (target_size_y_reg),
  .target_x0_i (target_x0_reg),
  .target_y0_i (target_y0_reg),
  .target_x1_i (target_x1_reg),
  .target_y1_i (target_y1_reg),

  // Output pixel
  .x_counter_o 	    (raster_x_pixel),
  .y_counter_o 	    (raster_y_pixel),
  .u_o              (raster_clip_u),
  .v_o              (raster_clip_v),
  .clip_write_o     (raster_clip_write),
  .strip_o (raster_strip),
  // To interp
  .triangle_edge0_o (raster_interp_edge0),
  .triangle_edge1_o (raster_interp_edge1),
  .triangle_area_o  (raster_interp_area),
  .interp_write_o   (raster_interp_write),
  // char blitting
  .char_x_i(char_x_o),
  .char_y_i(char_y_o),
  .char_write_i(char_write_o),
  .char_ack_i(char_ack_o),
  // flood filling
  .color0_i(color0_reg),
  .color1_i(color1_reg),
  .bpp_i(bpp),
  .cbpp_i(cbpp),
  .coeff1_i(coeff1),
  .coeff2_i(coeff2),
  .rmw_i(rmw),
  .floodfill_read_request_o(floodfill_read_request),
  .floodfill_sel_o(floodfill_sel),
  .floodfill_adr_o(floodfill_adr),
  .floodfill_data_i(floodfill_data)
);

defparam rasterizer0.point_width = point_width;
defparam rasterizer0.subpixel_width = subpixel_width;
defparam rasterizer0.delay_width  = 5; // log2(point_width+1)

wire [point_width-1:0] interp_cuvz_x;
wire [point_width-1:0] interp_cuvz_y;

wire [point_width-1:0] interp_cuvz_factor0;
wire [point_width-1:0] interp_cuvz_factor1;

wire                   interp_cuvz_write;

wire                   cuvz_interp_ack;

gfx_interp interp(
.clk_i     (wb_clk_i),
.rst_i     (wb_rst_i),
.ack_i     (cuvz_interp_ack),
.ack_o     (interp_raster_ack),
.write_i   (raster_interp_write),
.edge0_i   (raster_interp_edge0),
.edge1_i   (raster_interp_edge1),
.area_i    (raster_interp_area),
.x_i       (raster_x_pixel),
.y_i       (raster_y_pixel),
.x_o       (interp_cuvz_x),
.y_o       (interp_cuvz_y),
.factor0_o (interp_cuvz_factor0),
.factor1_o (interp_cuvz_factor1),
.write_o   (interp_cuvz_write)
);

defparam interp.point_width  = point_width;
defparam interp.delay_width  = 5; // log2(point_width+1)
defparam interp.result_width = 4; // 16 pipeline slots

wire [point_width-1:0] cuvz_clip_x;
wire [point_width-1:0] cuvz_clip_y;
wire signed [point_width-1:0] cuvz_clip_z;
wire [point_width-1:0] cuvz_clip_u;
wire [point_width-1:0] cuvz_clip_v;
wire             [7:0] cuvz_clip_alpha;
wire [point_width-1:0] cuvz_clip_bezier_factor0;
wire [point_width-1:0] cuvz_clip_bezier_factor1;
wire                   cuvz_clip_write;

wire            [31:0] cuvz_clip_color;

gfx_cuvz cuvz(
	.clk_i     (wb_clk_i),
	.rst_i     (wb_rst_i),
	.ack_i     (clip_ack),
	.ack_o     (cuvz_interp_ack),
	.write_i   (interp_cuvz_write),
	// Variables needed for interpolation
	.factor0_i (interp_cuvz_factor0),
	.factor1_i (interp_cuvz_factor1),
	// Color
	.color0_i  (color0_reg),
	.color1_i  (color1_reg),
	.color2_i  (color2_reg),
	.color_o   (cuvz_clip_color),
	.color_comp_i(color_comp),
	// Depth
	.z0_i      (transform_cuvz_dest_pixel0_z),
	.z1_i      (transform_cuvz_dest_pixel1_z),
	.z2_i      (transform_cuvz_dest_pixel2_z),
	.z_o       (cuvz_clip_z),
	// Alpha
	.a0_i      (alpha0_reg),
	.a1_i      (alpha1_reg),
	.a2_i      (alpha2_reg),
	.a_o       (cuvz_clip_alpha),
	// Texture coordinates
	.u0_i      (u0_reg),
	.v0_i      (v0_reg),
	.u1_i      (u1_reg),
	.v1_i      (v1_reg),
	.u2_i      (u2_reg),
	.v2_i      (v2_reg),
	.u_o       (cuvz_clip_u),
	.v_o       (cuvz_clip_v),
	// Bezier calculations
	.bezier_factor0_o (cuvz_clip_bezier_factor0),
	.bezier_factor1_o (cuvz_clip_bezier_factor1),
	// Raster position
	.x_i       (interp_cuvz_x),
	.y_i       (interp_cuvz_y),
	.x_o       (cuvz_clip_x),
	.y_o       (cuvz_clip_y),

	.write_o   (cuvz_clip_write)
);

defparam cuvz.point_width     = point_width;

wire                   clip_fragment_write_enable;
wire [point_width-1:0] clip_fragment_x_pixel;
wire [point_width-1:0] clip_fragment_y_pixel;
wire signed [point_width-1:0] clip_fragment_z_pixel;
wire                   fragment_clip_ack;
wire [point_width-1:0] clip_fragment_u;
wire [point_width-1:0] clip_fragment_v;
wire             [7:0] clip_fragment_a;
wire [point_width-1:0] clip_fragment_bezier_factor0;
wire [point_width-1:0] clip_fragment_bezier_factor1;

wire            [31:0] clip_fragment_color;

wire                   wbmreader_busy;

wire textblit_read_request;
wire [MDW/8-1:0] textblit_sel_o;
wire [31:0] textblit_adr_o;
wire [MDW-1:0] textblit_dat_i;
wire textblit_ack_i;

gfx_textblit #(.MDW(MDW)) textblit
(
	.rst_i(wb_rst_i),
	.clk_i(wb_clk_i),
	.clip_ack_i(clip_ack),
	.char_i(wbs_char_write),
	.char_code(char_code_reg),
  .char_pos_x_i(transform_raster_dest_pixel0_x[15:0]),
  .char_pos_y_i(transform_raster_dest_pixel0_y[15:0]),
	.char_x_o(char_x_o),
	.char_y_o(char_y_o),
	.char_write_o(char_write_o),
	.char_ack_o(char_ack_o),
	.font_table_adr_i(font_table_base_reg),
	.font_id_i(font_id_reg),
	.read_request_o(textblit_read_request),
	.textblit_ack_i(textblit_ack_i),
	.textblit_sel_o(textblit_sel_o),
	.textblit_adr_o(textblit_adr_o),
	.textblit_dat_i(textblit_dat_i)
);

// Connected through arbiter
wire wbmreader_clip_z_ack;
wire [31:0] clip_wbmreader_z_addr;
wire [MDW-1:0] wbmreader_clip_z_data;
wire [MDW/8-1:0] clip_wbmreader_z_sel;
wire clip_wbmreader_z_request;
wire clip_fragment_strip;

// Apply clipping
gfx_clip #(.MDW(MDW)) clip (
	.clk_i (wb_clk_i),
	.rst_i (wb_rst_i),
	.clipping_enable_i(clipping_enable_reg),
	.rmw_i(rmw),
  .bpp_i(bpp),
  .cbpp_i(cbpp),
  .coeff1_i(coeff1),
  .coeff2_i(coeff2),
  .pps_i(pps),
	.zbuffer_enable_i (zbuffer_enable_reg),
	.zbuffer_base_i (zbuffer_base_reg),
	.target_size_x_i (target_size_x_reg),
	.target_size_y_i (target_size_y_reg),
	.target_x0_i (target_x0_reg),
	.target_y0_i (target_y0_reg),
	.target_x1_i (target_x1_reg),
	.target_y1_i (target_y1_reg),
	.clip_pixel0_x_i (clip_pixel0_x_reg),
	.clip_pixel0_y_i (clip_pixel0_y_reg),
	.clip_pixel1_x_i (clip_pixel1_x_reg),
	.clip_pixel1_y_i (clip_pixel1_y_reg),
	.raster_pixel_x_i (raster_x_pixel),
	.raster_pixel_y_i (raster_y_pixel),
	.raster_u_i (raster_clip_u),
	.raster_v_i (raster_clip_v),
	.raster_strip_i (raster_strip),
	.flat_color_i (color0_reg),
	.raster_write_i (raster_clip_write),
	.cuvz_pixel_x_i (cuvz_clip_x),
	.cuvz_pixel_y_i (cuvz_clip_y),
	.cuvz_pixel_z_i (cuvz_clip_z),
	.cuvz_u_i (cuvz_clip_u),
	.cuvz_v_i (cuvz_clip_v),
	.cuvz_a_i (cuvz_clip_alpha),
	.cuvz_color_i (cuvz_clip_color),
	.cuvz_write_i (cuvz_clip_write),
	.ack_o (clip_ack),
	.z_ack_i (wbmreader_clip_z_ack),
	.z_addr_o (clip_wbmreader_z_addr),
	.z_data_i (wbmreader_clip_z_data),
	.z_sel_o (clip_wbmreader_z_sel),
	.z_request_o (clip_wbmreader_z_request),
	.wbm_busy_i (wbmreader_busy),
	.pixel_x_o (clip_fragment_x_pixel),
	.pixel_y_o (clip_fragment_y_pixel),
	.pixel_z_o (clip_fragment_z_pixel),
	.strip_o (clip_fragment_strip),
	.u_o (clip_fragment_u),
	.v_o (clip_fragment_v),
	.a_o (clip_fragment_a),
	.bezier_factor0_i (cuvz_clip_bezier_factor0),
	.bezier_factor1_i (cuvz_clip_bezier_factor1),
	.bezier_factor0_o (clip_fragment_bezier_factor0),
	.bezier_factor1_o (clip_fragment_bezier_factor1),
	.color_o (clip_fragment_color),
	.write_o (clip_fragment_write_enable),
	.ack_i (fragment_clip_ack)
);

defparam clip.point_width = point_width;

wire fragment_blender_write_enable;
wire [point_width-1:0] fragment_blender_x_pixel;
wire [point_width-1:0] fragment_blender_y_pixel;
wire signed [point_width-1:0] fragment_blender_z_pixel;
wire blender_fragment_ack;
wire [31:0] fragment_blender_color;
wire [7:0] fragment_blender_alpha;

wire wbmreader_fragment_texture_ack;
wire [MDW-1:0] wbmreader_fragment_texture_data;
wire [31:0] fragment_wbmreader_texture_addr;
wire [MDW/8-1:0] fragment_wbmreader_texture_sel;
wire fragment_wbmreader_texture_request;
wire fragement_blender_strip;


// Fragment processor generates color of pixel (requires RAM read for textures)
gfx_fragment_processor #(.MDW(MDW)) fp0 (
  .clk_i (wb_clk_i),
  .rst_i (wb_rst_i),
  .pixel_alpha_i (clip_fragment_a),
  .x_counter_i (clip_fragment_x_pixel),
  .y_counter_i (clip_fragment_y_pixel),
  .z_i (clip_fragment_z_pixel),
  .u_i (clip_fragment_u),
  .v_i (clip_fragment_v),
  .strip_i(clip_fragment_strip),
  .bezier_factor0_i (clip_fragment_bezier_factor0),
  .bezier_factor1_i (clip_fragment_bezier_factor1),
  .bezier_inside_i (inside_reg),
  .ack_i (blender_fragment_ack),
  .write_i (clip_fragment_write_enable),
  .curve_write_i (wbs_fragment_curve_write),
  .pixel_x_o (fragment_blender_x_pixel),
  .pixel_y_o (fragment_blender_y_pixel),
  .pixel_z_o (fragment_blender_z_pixel),
  .pixel_color_i (clip_fragment_color),
  .pixel_color_o (fragment_blender_color),
  .pixel_alpha_o (fragment_blender_alpha),
  .strip_o(fragment_blender_strip),
  .write_o (fragment_blender_write_enable),
  .ack_o (fragment_clip_ack),
  .texture_ack_i (wbmreader_fragment_texture_ack), 
  .texture_data_i (wbmreader_fragment_texture_data), 
  .texture_addr_o (fragment_wbmreader_texture_addr), 
  .texture_sel_o (fragment_wbmreader_texture_sel), 
  .texture_request_o (fragment_wbmreader_texture_request),
  .texture_enable_i (texture_enable_reg),
  .tex0_base_i (wbs_fragment_tex0_base), 
  .tex0_size_x_i (wbs_fragment_tex0_size_x), 
  .tex0_size_y_i (wbs_fragment_tex0_size_y),
  .rmw_i(rmw),
  .bpp_i(bpp),
  .cbpp_i(cbpp),
  .coeff1_i(coeff1),
  .coeff2_i(coeff2),
  .colorkey_enable_i (colorkey_enable_reg),
  .colorkey_i (colorkey_reg)
  );

defparam fp0.point_width = point_width;

wire blender_render_write_enable;
wire [point_width-1:0] blender_render_x_pixel;
wire [point_width-1:0] blender_render_y_pixel;
wire signed [point_width-1:0] blender_render_z_pixel;
wire render_blender_ack;
wire [31:0] blender_render_color;

// Connected through arbiter
wire wbmreader_blender_target_ack;
wire [31:0] blender_wbmreader_target_addr;
wire [MDW-1:0] wbmreader_blender_target_data;
wire [MDW/8-1:0] blender_wbmreader_target_sel;
wire blender_wbmreader_target_request;
wire blender_render_strip;
wire [MDW-1:0] blender_render_strip_color;

// Applies alpha blending if enabled (requires RAM read to get target pixel color)
// Fragment processor generates color of pixel (requires RAM read for textures)
gfx_blender #(.MDW(MDW)) blender0 (
  .clk_i (wb_clk_i),
  .rst_i (wb_rst_i),
  .blending_enable_i (blending_enable_reg),
  // Render target information
  .target_base_i (target_base_reg),
  .target_size_x_i (target_size_x_reg),
  .target_size_y_i (target_size_y_reg),
  .rmw_i(rmw),
  .color_comp_i(color_comp),
  .bpp_i(bpp),
  .cbpp_i(cbpp),
  .coeff1_i(coeff1),
  .coeff2_i(coeff2),
  .x_counter_i (fragment_blender_x_pixel),
  .y_counter_i (fragment_blender_y_pixel),
  .z_i (fragment_blender_z_pixel),
  .strip_i (fragment_blender_strip),
  .alpha_i (fragment_blender_alpha),
  .global_alpha_i (global_alpha_reg),
  .ack_i (render_blender_ack),
  .target_ack_i (wbmreader_blender_target_ack),
  .target_addr_o (blender_wbmreader_target_addr),
  .target_data_i (wbmreader_blender_target_data),
  .target_sel_o (blender_wbmreader_target_sel),
  .target_request_o (blender_wbmreader_target_request),
  .wbm_busy_i (wbmreader_busy),
  .write_i (fragment_blender_write_enable),
  .pixel_x_o (blender_render_x_pixel),
  .pixel_y_o (blender_render_y_pixel),
  .pixel_z_o (blender_render_z_pixel),
  .pixel_color_i (fragment_blender_color),
  .pixel_color_o (blender_render_color),
  .strip_o (blender_render_strip),
  .strip_color_o (blender_render_strip_color),
  .write_o (blender_render_write_enable),
  .ack_o (blender_fragment_ack)
);

defparam blender0.point_width = point_width;

// Write pixel to target (check for out of bounds)
gfx_renderer #(.MDW(MDW)) renderer (
  .clk_i (wb_clk_i),
  .rst_i (wb_rst_i),
  // Render target information
  .target_base_i (target_base_reg),
  .zbuffer_base_i (zbuffer_base_reg),
  .target_size_x_i (target_size_x_reg),
  .target_size_y_i (target_size_y_reg),
	.target_x0_i (target_x0_reg),
	.target_y0_i (target_y0_reg),
  .bpp_i(bpp),
  .cbpp_i(cbpp),
  .coeff1_i(coeff1),
  .coeff2_i(coeff2),
  .rmw_i(rmw),
  // Input pixel
  .pixel_x_i (blender_render_x_pixel),
  .pixel_y_i (blender_render_y_pixel),
  .pixel_z_i (blender_render_z_pixel),
  .zbuffer_enable_i(zbuffer_enable_reg),
  .color_i (blender_render_color),
  .strip_i(blender_render_strip),
  .strip_color_i(blender_render_strip_color),

  .render_addr_o (render_wbmwriter_addr),
  .render_sel_o (render_wbmwriter_sel),
  .render_dat_o (render_wbmwriter_dat),
  .render_dat_i (render_wbmwriter_dati),
  .ack_o (render_blender_ack),
  .ack_i (wbmwriter_render_ack),
  .write_i (blender_render_write_enable),
  .write_o (render_wbmwriter_memory_pixel_write),
  .read_o (render_wbmwriter_memory_pixel_read)
);

defparam renderer.point_width = point_width;

wire wbmreader_arbiter_ack;
wire [31:0] arbiter_wbmreader_addr;
wire [MDW-1:0] wbmreader_arbiter_data;
wire [MDW-1:0] wbmwriter_arbiter_data;
wire arbiter_wbmreader_we;
wire [MDW/8-1:0] arbiter_wbmreader_sel;
wire arbiter_wbmreader_request;
wire arbiter_wbmwriter_request;

// Instansiate wbm arbiter
gfx_wbm_readwrite_arbiter #(.MDW(MDW)) wbm_arbiter (
  .master_busy_o (wbmreader_busy),
  // Interface against the wbm module
  .read_request_o (arbiter_wbmreader_request),
  .write_request_o (arbiter_wbmwriter_request),
  .addr_o (arbiter_wbmreader_addr),
  .we_o (arbiter_wbmreader_we),
  .sel_o (arbiter_wbmreader_sel),
  .dat_i (wbmreader_arbiter_data),
  .dat_o (wbmwriter_arbiter_data),
  .ack_i (wbmreader_arbiter_ack),
  // Interface against masters (render)
  .mw_write_request_i(render_wbmwriter_memory_pixel_write),
  .mw_read_request_i(render_wbmwriter_memory_pixel_read),
  .mw_we_i(render_wbmwriter_memory_pixel_write),
  .mw_addr_i (render_wbmwriter_addr),
  .mw_sel_i (render_wbmwriter_sel),
  .mw_dat_i (render_wbmwriter_dat),
  .mw_dat_o (render_wbmwriter_dati),
  .mw_ack_o (wbmwriter_render_ack),
  // Interface against masters (clip)
  .m0_read_request_i (clip_wbmreader_z_request),
  .m0_addr_i (clip_wbmreader_z_addr),
  .m0_sel_i (clip_wbmreader_z_sel),
  .m0_dat_o (wbmreader_clip_z_data),
  .m0_ack_o (wbmreader_clip_z_ack),
  // Interface against masters (fragment processor)
  .m1_read_request_i (fragment_wbmreader_texture_request),
  .m1_addr_i (fragment_wbmreader_texture_addr),
  .m1_sel_i (fragment_wbmreader_texture_sel),
  .m1_dat_o (wbmreader_fragment_texture_data),
  .m1_ack_o (wbmreader_fragment_texture_ack),
  // Interface against masters (blender)
  .m2_read_request_i (blender_wbmreader_target_request),
  .m2_addr_i (blender_wbmreader_target_addr),
  .m2_sel_i (blender_wbmreader_target_sel),
  .m2_dat_o (wbmreader_blender_target_data),
  .m2_ack_o (wbmreader_blender_target_ack),
  // Interface against masters (textblit)
  .m3_read_request_i(textblit_read_request),
  .m3_addr_i (textblit_adr_o[31:0]),
  .m3_sel_i	(textblit_sel_o),
  .m3_dat_o	(textblit_dat_i),
  .m3_ack_o	(textblit_ack_i),
  // Floodfill
  .m4_read_request_i(floodfill_read_request),
  .m4_addr_i (floodfill_adr),
  .m4_sel_i	(floodfill_sel),
  .m4_dat_o	(floodfill_data),
  .m4_ack_o	(floodfill_ack)
);

// Instansiate wishbone master interface (read only for textures)
gfx256_wbm_rw  #(.CID(CID), .MDW(MDW)) wbm_rw
(
  .clk_i (wb_clk_i),
  .rst_i (wb_rst_i),
  .wbm_req(wbm_req),
  .wbm_resp(wbm_resp),
  .sint_o (wbmreader_sint),

  // send ack to renderer when done writing to memory.
  .read_request_i (arbiter_wbmreader_request),
  .write_request_i (arbiter_wbmwriter_request),
  .texture_addr_i (arbiter_wbmreader_addr),
  .texture_sel_i (arbiter_wbmreader_sel),
  .texture_dat_o (wbmreader_arbiter_data),
  .texture_dat_i (wbmwriter_arbiter_data),
  .texture_data_ack (wbmreader_arbiter_ack)
);

endmodule

