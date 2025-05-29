/*
ORSoC GFX accelerator core
Copyright 2012, ORSoC, Per Lenander, Anton Fosselius.

The Wishbone slave component accepts incoming register accesses and puts them in a FIFO queue

Loosely based on the vga lcds wishbone slave (LGPL) in orpsocv2 by Julius Baxter, julius@opencores.org

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

//synopsys translate_off
`include "timescale.v"

//synopsys translate_on

import wishbone_pkg::*;
import gfx_pkg::*;
/*
This module acts as the main control interface of the orgfx core. It is built as a 32-bit wishbone slave interface with read and write capabilities.

The module has two states, wait and busy. The module enters busy state when a pipeline operation is triggered by a write to the control register.

In the busy state all incoming wishbone writes are queued up in a 64 item fifo. These will be processed in the order they were received when the module returns to wait state.

The module leaves the busy state and enters wait state when it receives an ack from the pipeline.
*/
module gfx_wbs(
  clk_i, rst_i, 
  wbs_clk_i, wbs_req, wbs_resp,
  cs_i, inta_o,
  //src pixels
  src_pixel0_x_o, src_pixel0_y_o, src_pixel1_x_o, src_pixel1_y_o,
  // dest pixels
  dest_pixel_x_o, dest_pixel_y_o, dest_pixel_z_o,
  dest_pixel_id_o,
  // matrix
  aa_o, ab_o, ac_o, tx_o,
  ba_o, bb_o, bc_o, ty_o,
  ca_o, cb_o, cc_o, tz_o,
  transform_point_o,
  forward_point_o,
  // clip pixels
  clip_pixel0_x_o, clip_pixel0_y_o, clip_pixel1_x_o, clip_pixel1_y_o,
  color0_o, color1_o, color2_o,
  u0_o, v0_o, u1_o, v1_o, u2_o, v2_o,
  a0_o, a1_o, a2_o,
  target_base_o, target_size_x_o, target_size_y_o,
  target_x0_o, target_y0_o, target_x1_o, target_y1_o,
  tex0_base_o, tex0_size_x_o, tex0_size_y_o,
  color_depth_o,
  rect_write_o, line_write_o, triangle_write_o, curve_write_o, interpolate_o,
  writer_sint_i, reader_sint_i,

  pipeline_ack_i,
  transform_ack_i,

  texture_enable_o,
  blending_enable_o,
  global_alpha_o,
  colorkey_enable_o,
  colorkey_o,
  clipping_enable_o,
  inside_o,
  zbuffer_enable_o,
  zbuffer_base_o,

	point_write_o,
 
  font_table_base_o,
  font_id_o,
  char_code_o,
  char_write_o,
  
  bpp_o,
  cbpp_o,
  coeff1_o,
  coeff2_o,
  pps_o,
  rmw_o,
  color_comp_o
);

  // Adjust these parameters in gfx_top!
  parameter REG_ADR_HIBIT = 7;
  parameter point_width = 16;
  parameter subpixel_width = 16;
  parameter fifo_depth = 11;
  parameter GR_WIDTH = 32'd1920;
  parameter GR_HEIGHT = 32'd1080;
  parameter MDW = 256;

  //
  // inputs & outputs
  //

  // wishbone slave interface
  input clk_i;
  input rst_i;
  input wbs_clk_i;
  input wb_cmd_request32_t wbs_req;
  output wb_cmd_response32_t wbs_resp;
  input cs_i;
  output reg inta_o;
  // source pixel
  output [point_width-1:0] src_pixel0_x_o;
  output [point_width-1:0] src_pixel0_y_o;
  output [point_width-1:0] src_pixel1_x_o;
  output [point_width-1:0] src_pixel1_y_o;
  // dest pixel
  output signed [point_width-1:-subpixel_width] dest_pixel_x_o;
  output signed [point_width-1:-subpixel_width] dest_pixel_y_o;
  output signed [point_width-1:-subpixel_width] dest_pixel_z_o;
  output [1:0] dest_pixel_id_o;
  // matrix
  output signed [point_width-1:-subpixel_width] aa_o;
  output signed [point_width-1:-subpixel_width] ab_o;
  output signed [point_width-1:-subpixel_width] ac_o;
  output signed [point_width-1:-subpixel_width] tx_o;
  output signed [point_width-1:-subpixel_width] ba_o;
  output signed [point_width-1:-subpixel_width] bb_o;
  output signed [point_width-1:-subpixel_width] bc_o;
  output signed [point_width-1:-subpixel_width] ty_o;
  output signed [point_width-1:-subpixel_width] ca_o;
  output signed [point_width-1:-subpixel_width] cb_o;
  output signed [point_width-1:-subpixel_width] cc_o;
  output signed [point_width-1:-subpixel_width] tz_o;
  output transform_point_o;
  output forward_point_o;
  // clip pixel
  output [point_width-1:0] clip_pixel0_x_o;
  output [point_width-1:0] clip_pixel0_y_o;
  output [point_width-1:0] clip_pixel1_x_o;
  output [point_width-1:0] clip_pixel1_y_o;

  output [31:0] color0_o;
  output [31:0] color1_o;
  output [31:0] color2_o;

  output [point_width-1:0] u0_o;
  output [point_width-1:0] v0_o;
  output [point_width-1:0] u1_o;
  output [point_width-1:0] v1_o;
  output [point_width-1:0] u2_o;
  output [point_width-1:0] v2_o;

  output [7:0] a0_o;
  output [7:0] a1_o;
  output [7:0] a2_o;

  output            [31:0] target_base_o;
  output [point_width-1:0] target_size_x_o;
  output [point_width-1:0] target_size_y_o;
  output [point_width-1:0] target_x0_o;
  output [point_width-1:0] target_y0_o;
  output [point_width-1:0] target_x1_o;
  output [point_width-1:0] target_y1_o;
  output            [31:0] tex0_base_o;
  output [point_width-1:0] tex0_size_x_o;
  output [point_width-1:0] tex0_size_y_o;

  output [1:0]  color_depth_o;
	
  output        rect_write_o;
  output        line_write_o;
  output        triangle_write_o;
  output        curve_write_o;
  output        interpolate_o;

  // status register inputs
  input         writer_sint_i;       // system error interrupt request
  input         reader_sint_i;       // system error interrupt request

  // Pipeline feedback
  input         pipeline_ack_i;             // operation done
  input         transform_ack_i;            // transformation done

  // fragment 
  output        texture_enable_o;
  // blender
  output        blending_enable_o;
  output  [7:0] global_alpha_o;
  output        colorkey_enable_o;
  output [31:0] colorkey_o;

  output        clipping_enable_o;
  output        inside_o;
  output        zbuffer_enable_o;

  output [31:0] zbuffer_base_o;

	output point_write_o;

  output [31:0] font_table_base_o;
  output [15:0] font_id_o;
  output [15:0] char_code_o;
  output char_write_o;

output reg [5:0] bpp_o;
output reg [5:0] cbpp_o;
output reg [15:0] coeff1_o;
output reg [9:0] coeff2_o;
output reg [9:0] pps_o;
output reg rmw_o;
output reg [15:0] color_comp_o;
  //
  // variable declarations
  //

	reg [31:0] dato;
  wire [REG_ADR_HIBIT:0] REG_ADR  = {wbs_req.padr[REG_ADR_HIBIT : 2], 2'b00};

  // Declaration of local registers
  reg        [31:0] control_reg, status_reg, target_base_reg, tex0_base_reg;
  reg        [31:0] target_size_x_reg, target_size_y_reg, tex0_size_x_reg, tex0_size_y_reg;
  reg        [31:0] target_x0_reg, target_y0_reg, target_x1_reg, target_y1_reg;
  reg        [31:0] src_pixel_pos_0_x_reg, src_pixel_pos_0_y_reg, src_pixel_pos_1_x_reg, src_pixel_pos_1_y_reg;
  reg        [31:0] clip_pixel_pos_0_x_reg, clip_pixel_pos_0_y_reg, clip_pixel_pos_1_x_reg, clip_pixel_pos_1_y_reg;
  reg signed [31:0] dest_pixel_pos_x_reg, dest_pixel_pos_y_reg, dest_pixel_pos_z_reg;
  reg signed [31:0] aa_reg, ab_reg, ac_reg, tx_reg;
  reg signed [31:0] ba_reg, bb_reg, bc_reg, ty_reg;
  reg signed [31:0] ca_reg, cb_reg, cc_reg, tz_reg;
  reg        [31:0] color0_reg, color1_reg, color2_reg;
  reg        [31:0] u0_reg, v0_reg, u1_reg, v1_reg, u2_reg, v2_reg; 
  reg        [31:0] alpha_reg;
  reg        [31:0] colorkey_reg;
  reg        [31:0] zbuffer_base_reg;
	reg        [31:0] font_table_base_reg;
	reg        [31:0] font_id_reg;
	reg        [31:0] char_code_reg;
  wire        [1:0] active_point;
  reg [31:0] color_comp_reg;
  reg [3:0] red_comp,green_comp,blue_comp,pad_comp;

	always_ff @(posedge wbs_clk_i) pad_comp <= color_comp_reg[15:12];
	always_ff @(posedge wbs_clk_i) red_comp <= color_comp_reg[11:8];
	always_ff @(posedge wbs_clk_i) green_comp <= color_comp_reg[7:4];
	always_ff @(posedge wbs_clk_i) blue_comp <= color_comp_reg[3:0];
	always_ff @(posedge wbs_clk_i) color_comp_o <= color_comp_reg[15:0];

  /* Instruction fifo */
  wire instruction_fifo_wreq;
  wire [31:0] instruction_fifo_q_data;
  wire instruction_fifo_rreq;
  wire instruction_fifo_valid_out;
  reg fifo_read_ack;
  reg was_fifo_rd;
  wire [REG_ADR_HIBIT:0] instruction_fifo_q_adr;
  wire [fifo_depth-1:0] instruction_fifo_count;

  // Wishbone access wires
  wb_cmd_request32_t [15:0] tran_in;

  wire acc, acc32, reg_acc, reg_wacc;

  // State machine variables
  typedef enum logic [1:0] 
  {
  	wait_state = 2'd0,
  	busy_state = 2'd1
  } wbs_state_e;
  wbs_state_e state;

  //
  // Module body
  //

	wire full, empty;
	wire wr_ack;

  // wishbone access signals
  assign acc = cs_i & wbs_req.cyc & wbs_req.stb;
  assign acc32 = (wbs_req.sel[3:0] == 4'b1111);
  assign reg_acc = acc & acc32;
  assign reg_wacc = reg_acc & wbs_req.we;

  // Generate wishbone ack
  wire rdy3, rdy3pe;
  delay2 #(.WID(1)) udly1 (.clk(wbs_clk_i), .ce(1'b1), .i(acc), .o(rdy3));
	edge_det ued10 (.rst(rst_i), .clk(wbs_clk_i), .ce(1'b1), .i(rdy3), .pe(rdy3pe), .ne(), .ee());
  always_comb
  begin
  	wbs_resp = {$bits(wb_cmd_response32_t){1'b0}};
  	wbs_resp.tid = wbs_req.tid;
  	wbs_resp.ack = (acc & wbs_req.we) ? wr_ack : acc & rdy3pe;
  	wbs_resp.rty = 1'b0;
  	wbs_resp.err = acc & ~acc32 ? wishbone_pkg::ERR : wishbone_pkg::OKAY;
  	wbs_resp.dat = acc ? dato : 32'd0;
	end

  // generate interrupt request signal
  always_ff @(posedge wbs_clk_i)
  if(rst_i)
    inta_o <= 1'b0;
  else
    inta_o <= writer_sint_i | reader_sint_i; // | other_int | (int_enable & int) | ...

  // generate registers
  always_ff @(posedge clk_i)
  begin : gen_regs
    /* To prevent entering an infinite write cycle, the bits that start pipeline operations are cleared here */
    control_reg[GFX_CTRL_RECT]  <= 1'b0; // Reset rect write
    control_reg[GFX_CTRL_LINE]  <= 1'b0; // Reset line write
    control_reg[GFX_CTRL_TRI]   <= 1'b0; // Reset triangle write
    control_reg[GFX_CTRL_CHAR]  <= 1'b0; // Reset char blit write
    control_reg[GFX_CTRL_POINT] <= 1'b0; // Reset point write
    // Reset matrix transformation bits
    control_reg[GFX_CTRL_FORWARD_POINT]   <= 1'b0;
    control_reg[GFX_CTRL_TRANSFORM_POINT] <= 1'b0;
    if (rst_i) begin
      control_reg             <= 32'h00000001;
      target_base_reg         <= 32'h00000000;
      target_size_x_reg       <= GR_WIDTH;
      target_size_y_reg       <= GR_HEIGHT;
      target_x0_reg           <= 32'h00000000;
      target_y0_reg           <= 32'h00000000;
      target_x1_reg           <= GR_WIDTH;
      target_y1_reg           <= GR_HEIGHT;
      tex0_base_reg           <= 32'h00000000;
      tex0_size_x_reg         <= 32'h00000000;
      tex0_size_y_reg         <= 32'h00000000;
      src_pixel_pos_0_x_reg   <= 32'h00000000;
      src_pixel_pos_0_y_reg   <= 32'h00000000;
      src_pixel_pos_1_x_reg   <= 32'h00000000;
      src_pixel_pos_1_y_reg   <= 32'h00000000;
      dest_pixel_pos_x_reg    <= 32'h00000000;
      dest_pixel_pos_y_reg    <= 32'h00000000;
      dest_pixel_pos_z_reg    <= 32'h00000000;
      aa_reg                  <= $signed(1'b1 << subpixel_width);
      ab_reg                  <= 32'h00000000;
      ac_reg                  <= 32'h00000000;
      tx_reg                  <= 32'h00000000;
      ba_reg                  <= 32'h00000000;
      bb_reg                  <= $signed(1'b1 << subpixel_width);
      bc_reg                  <= 32'h00000000;
      ty_reg                  <= 32'h00000000;
      ca_reg                  <= 32'h00000000;
      cb_reg                  <= 32'h00000000;
      cc_reg                  <= $signed(1'b1 << subpixel_width);
      tz_reg                  <= 32'h00000000;
      clip_pixel_pos_0_x_reg  <= 32'h00000000;
      clip_pixel_pos_0_y_reg  <= 32'h00000000;
      clip_pixel_pos_1_x_reg  <= GR_WIDTH;
      clip_pixel_pos_1_y_reg  <= GR_HEIGHT;
      color0_reg              <= 32'h00000000;
      color1_reg              <= 32'h00000000;
      color2_reg              <= 32'h00000000;
      u0_reg                  <= 32'h00000000;
      v0_reg                  <= 32'h00000000;
      u1_reg                  <= 32'h00000000;
      v1_reg                  <= 32'h00000000;
      u2_reg                  <= 32'h00000000;
      v2_reg                  <= 32'h00000000;
      alpha_reg	              <= 32'hffffffff;
      colorkey_reg            <= 32'h00000000;
      zbuffer_base_reg        <= 32'h00000000;
      font_table_base_reg			<= 32'h0;
      font_id_reg             <= 32'h0;
      char_code_reg					  <= 32'h0;
      color_comp_reg 					<= 32'h00001555;
    end
    // Read fifo to write to registers
    else if (was_fifo_rd & instruction_fifo_valid_out) begin
      case (instruction_fifo_q_adr) // synopsis full_case parallel_case
      GFX_CONTROL          : control_reg            <= instruction_fifo_q_data;
      GFX_TARGET_BASE      : target_base_reg        <= instruction_fifo_q_data;
      GFX_TARGET_SIZE_X    : target_size_x_reg      <= instruction_fifo_q_data;
      GFX_TARGET_SIZE_Y    : target_size_y_reg      <= instruction_fifo_q_data;
      GFX_TARGET_X0				 : target_x0_reg          <= instruction_fifo_q_data;
      GFX_TARGET_X1				 : target_x0_reg          <= instruction_fifo_q_data;
      GFX_TARGET_Y0				 : target_y0_reg          <= instruction_fifo_q_data;
      GFX_TARGET_Y1				 : target_y1_reg          <= instruction_fifo_q_data;
      GFX_TEX0_BASE        : tex0_base_reg          <= instruction_fifo_q_data;
      GFX_TEX0_SIZE_X      : tex0_size_x_reg        <= instruction_fifo_q_data;
      GFX_TEX0_SIZE_Y      : tex0_size_y_reg        <= instruction_fifo_q_data;
      GFX_SRC_PIXEL0_X     : src_pixel_pos_0_x_reg  <= instruction_fifo_q_data;
      GFX_SRC_PIXEL0_Y     : src_pixel_pos_0_y_reg  <= instruction_fifo_q_data;
      GFX_SRC_PIXEL1_X     : src_pixel_pos_1_x_reg  <= instruction_fifo_q_data;
      GFX_SRC_PIXEL1_Y     : src_pixel_pos_1_y_reg  <= instruction_fifo_q_data;
      GFX_DEST_PIXEL_X     : dest_pixel_pos_x_reg   <= $signed(instruction_fifo_q_data);
      GFX_DEST_PIXEL_Y     : dest_pixel_pos_y_reg   <= $signed(instruction_fifo_q_data);
      GFX_DEST_PIXEL_Z     : dest_pixel_pos_z_reg   <= $signed(instruction_fifo_q_data);
      GFX_AA               : aa_reg                 <= $signed(instruction_fifo_q_data);
      GFX_AB               : ab_reg                 <= $signed(instruction_fifo_q_data);
      GFX_AC               : ac_reg                 <= $signed(instruction_fifo_q_data);
      GFX_TX               : tx_reg                 <= $signed(instruction_fifo_q_data);
      GFX_BA               : ba_reg                 <= $signed(instruction_fifo_q_data);
      GFX_BB               : bb_reg                 <= $signed(instruction_fifo_q_data);
      GFX_BC               : bc_reg                 <= $signed(instruction_fifo_q_data);
      GFX_TY               : ty_reg                 <= $signed(instruction_fifo_q_data);
      GFX_CA               : ca_reg                 <= $signed(instruction_fifo_q_data);
      GFX_CB               : cb_reg                 <= $signed(instruction_fifo_q_data);
      GFX_CC               : cc_reg                 <= $signed(instruction_fifo_q_data);
      GFX_TZ               : tz_reg                 <= $signed(instruction_fifo_q_data);
      GFX_CLIP_PIXEL0_X    : clip_pixel_pos_0_x_reg <= instruction_fifo_q_data;
      GFX_CLIP_PIXEL0_Y    : clip_pixel_pos_0_y_reg <= instruction_fifo_q_data;
      GFX_CLIP_PIXEL1_X    : clip_pixel_pos_1_x_reg <= instruction_fifo_q_data;
      GFX_CLIP_PIXEL1_Y    : clip_pixel_pos_1_y_reg <= instruction_fifo_q_data;
      GFX_COLOR0           : color0_reg             <= instruction_fifo_q_data;
      GFX_COLOR1           : color1_reg             <= instruction_fifo_q_data;
      GFX_COLOR2           : color2_reg             <= instruction_fifo_q_data;
      GFX_U0               : u0_reg                 <= instruction_fifo_q_data;
      GFX_V0               : v0_reg                 <= instruction_fifo_q_data;
      GFX_U1               : u1_reg                 <= instruction_fifo_q_data;
      GFX_V1               : v1_reg                 <= instruction_fifo_q_data;
      GFX_U2               : u2_reg                 <= instruction_fifo_q_data;
      GFX_V2               : v2_reg                 <= instruction_fifo_q_data;
      GFX_ALPHA            : alpha_reg              <= instruction_fifo_q_data;
      GFX_COLORKEY         : colorkey_reg           <= instruction_fifo_q_data;
      GFX_ZBUFFER_BASE     : zbuffer_base_reg       <= instruction_fifo_q_data;
      GFX_FONT_TABLE_BASE	 : font_table_base_reg    <= instruction_fifo_q_data;
      GFX_FONT_ID					 : font_id_reg            <= instruction_fifo_q_data;
      GFX_CHAR_CODE				 : char_code_reg					<= instruction_fifo_q_data;
      GFX_COLOR_COMP			 : color_comp_reg         <= instruction_fifo_q_data;
      default:	;
      endcase
    end
  end

  // generate status register
  always_ff @(posedge clk_i)
  if (rst_i)
    status_reg <= 32'h00000000;
  else begin
    status_reg[GFX_STAT_BUSY] <= (state != wait_state);
    status_reg[31:16] <= instruction_fifo_count;
  end

  // Assign target and texture signals
  assign target_base_o = target_base_reg[31:0];
  assign target_size_x_o = target_size_x_reg[point_width-1:0];
  assign target_size_y_o = target_size_y_reg[point_width-1:0];
  assign target_x0_o = target_x0_reg[point_width-1:0];
  assign target_y0_o = target_y0_reg[point_width-1:0];
  assign target_x1_o = target_x1_reg[point_width-1:0];
  assign target_y1_o = target_y1_reg[point_width-1:0];
  assign tex0_base_o = tex0_base_reg[31:0];
  assign tex0_size_x_o = tex0_size_x_reg[point_width-1:0];
  assign tex0_size_y_o = tex0_size_y_reg[point_width-1:0];

  // Assign source pixel signals
  assign src_pixel0_x_o = src_pixel_pos_0_x_reg[point_width-1:0];
  assign src_pixel0_y_o = src_pixel_pos_0_y_reg[point_width-1:0];
  assign src_pixel1_x_o = src_pixel_pos_1_x_reg[point_width-1:0];
  assign src_pixel1_y_o = src_pixel_pos_1_y_reg[point_width-1:0];
  // Assign clipping pixel signals
  assign clip_pixel0_x_o = clip_pixel_pos_0_x_reg[point_width-1:0];
  assign clip_pixel0_y_o = clip_pixel_pos_0_y_reg[point_width-1:0];
  assign clip_pixel1_x_o = clip_pixel_pos_1_x_reg[point_width-1:0];
  assign clip_pixel1_y_o = clip_pixel_pos_1_y_reg[point_width-1:0];
  // Assign destination pixel signals
  assign dest_pixel_x_o[point_width-1:-subpixel_width] = $signed(dest_pixel_pos_x_reg);
  assign dest_pixel_y_o[point_width-1:-subpixel_width] = $signed(dest_pixel_pos_y_reg);
  assign dest_pixel_z_o[point_width-1:-subpixel_width] = $signed(dest_pixel_pos_z_reg);
  assign dest_pixel_id_o = active_point;

  // Assign matrix signals
  assign aa_o = $signed(aa_reg);
  assign ab_o = $signed(ab_reg);
  assign ac_o = $signed(ac_reg);
  assign tx_o = $signed(tx_reg);
  assign ba_o = $signed(ba_reg);
  assign bb_o = $signed(bb_reg);
  assign bc_o = $signed(bc_reg);
  assign ty_o = $signed(ty_reg);
  assign ca_o = $signed(ca_reg);
  assign cb_o = $signed(cb_reg);
  assign cc_o = $signed(cc_reg);
  assign tz_o = $signed(tz_reg);

  // Assign color signals
  assign color0_o = color0_reg;
  assign color1_o = color1_reg;
  assign color2_o = color2_reg;

  assign u0_o = u0_reg[point_width-1:0];
  assign v0_o = v0_reg[point_width-1:0];
  assign u1_o = u1_reg[point_width-1:0];
  assign v1_o = v1_reg[point_width-1:0];
  assign u2_o = u2_reg[point_width-1:0];
  assign v2_o = v2_reg[point_width-1:0];

  assign a0_o = alpha_reg[31:24];
  assign a1_o = alpha_reg[23:16];
  assign a2_o = alpha_reg[15:8];
  assign global_alpha_o = alpha_reg[7:0];
  assign colorkey_o = colorkey_reg;
  assign zbuffer_base_o = zbuffer_base_reg[31:3];


  // decode control register
  assign color_depth_o = control_reg[GFX_CTRL_COLOR_DEPTH+1:GFX_CTRL_COLOR_DEPTH];

  assign texture_enable_o = control_reg[GFX_CTRL_TEXTURE ];
  assign blending_enable_o = control_reg[GFX_CTRL_BLENDING];
  assign colorkey_enable_o = control_reg[GFX_CTRL_COLORKEY];
  assign clipping_enable_o = control_reg[GFX_CTRL_CLIPPING];
  assign zbuffer_enable_o = control_reg[GFX_CTRL_ZBUFFER ];

  assign interpolate_o = control_reg[GFX_CTRL_INTERP  ];
  assign inside_o = control_reg[GFX_CTRL_INSIDE  ];

  assign active_point = control_reg[GFX_CTRL_ACTIVE_POINT+1:GFX_CTRL_ACTIVE_POINT];
  
  assign font_table_base_o = font_table_base_reg;
  assign font_id_o = font_id_reg;
  assign char_code_o = char_code_reg;

	// The following signals pulse for just one controller clock cycle.
	assign point_write_o = control_reg[GFX_CTRL_POINT];
	assign rect_write_o = control_reg[GFX_CTRL_RECT];
	assign line_write_o = control_reg[GFX_CTRL_LINE];
	assign triangle_write_o = control_reg[GFX_CTRL_TRI];
	assign curve_write_o = control_reg[GFX_CTRL_CURVE];
	assign char_write_o = control_reg[GFX_CTRL_CHAR];
	assign forward_point_o = control_reg[GFX_CTRL_FORWARD_POINT];
	assign transform_point_o = control_reg[GFX_CTRL_TRANSFORM_POINT];
	
// Bits per pixel minus one.
always_ff @(posedge wbs_clk_i)
	bpp_o <= pad_comp+red_comp+green_comp+blue_comp-1'd1;

// Color bits per pixel minus one.
always_ff @(posedge wbs_clk_i)
	cbpp_o <= red_comp+green_comp+blue_comp-1'd1;

// Bytes per pixel.
//always_ff @(posedge clk)
//	bytpp  (bpp + 3'd7) >> 2'd3;

// This coefficient is a fixed point fraction representing the inverse of the
// number of pixels per strip. The inverse (reciprocal) is used for a high
// speed divide operation.
always_ff @(posedge wbs_clk_i)
	coeff1_o <= bpp_o * (65536/MDW);	// 9x6 multiply - could use a lookup table

// This coefficient is the number of bits used by all pixels in the strip. 
// Used to determine pixel placement in the strip.
reg [9:0] coeff2a [0:63];
genvar g;

generate begin : gCoeff2
	for (g = 0; g < 64; g = g + 1)
always_ff @(posedge wbs_clk_i)
	coeff2a[g] <= (MDW/g) * g;
end
endgenerate

always_ff @(posedge wbs_clk_i)
	coeff2_o <= coeff2a[bpp_o];

// Whether a read-modify-write is needed
always_ff @(posedge wbs_clk_i)
	rmw_o <= |bpp_o[2:0];

// Pixels per strip
always_ff @(posedge wbs_clk_i)
	pps_o <= (coeff1_o * MDW) >> 5'd16;

	// The following signals should just pulse for one controller clock cycle.
	// This works assuming the controller clock is at least as fast as the slave bus clock.
	// With a slow slave bus clock, the output of the control reg cannot be used directly,
	// it would take too long to reset.
	/*
	edge_det ued1 (.rst(rst_i), .clk(clk_i), .ce(1'b1), .i(control_reg[GFX_CTRL_RECT]), .pe(rect_write_o), .ne(), .ee());
	edge_det ued2 (.rst(rst_i), .clk(clk_i), .ce(1'b1), .i(control_reg[GFX_CTRL_LINE]), .pe(line_write_o), .ne(), .ee());
	edge_det ued3 (.rst(rst_i), .clk(clk_i), .ce(1'b1), .i(control_reg[GFX_CTRL_TRI]), .pe(triangle_write_o), .ne(), .ee());
	edge_det ued4 (.rst(rst_i), .clk(clk_i), .ce(1'b1), .i(control_reg[GFX_CTRL_CURVE]), .pe(curve_write_o), .ne(), .ee());
	edge_det ued5 (.rst(rst_i), .clk(clk_i), .ce(1'b1), .i(control_reg[GFX_CTRL_CHAR]), .pe(char_write_o), .ne(), .ee());
	edge_det ued6 (.rst(rst_i), .clk(clk_i), .ce(1'b1), .i(control_reg[GFX_CTRL_FORWARD_POINT]), .pe(forward_point_o), .ne(), .ee());
	edge_det ued7 (.rst(rst_i), .clk(clk_i), .ce(1'b1), .i(control_reg[GFX_CTRL_TRANSFORM_POINT]), .pe(transform_point_o), .ne(), .ee());
	edge_det ued8 (.rst(rst_i), .clk(clk_i), .ce(1'b1), .i(control_reg[GFX_CTRL_POINT]), .pe(point_write_o), .ne(), .ee());
	*/

  // decode status register TODO

  // assign output from wishbone reads. Note that this does not account for pending writes in the fifo!
  always_ff @(posedge wbs_clk_i)
    if(rst_i)
      dato <= 32'd0;
    else
      case (REG_ADR) // synopsis full_case parallel_case
      GFX_CONTROL       : dato <= {{control_reg}};
      GFX_STATUS        : dato <= {{status_reg}};
      GFX_TARGET_BASE   : dato <= {{target_base_reg}};
      GFX_TARGET_SIZE_X : dato <= {{target_size_x_reg}};
      GFX_TARGET_SIZE_Y : dato <= {{target_size_y_reg}};
      GFX_TARGET_X0     : dato <= {{target_x0_reg}};
      GFX_TARGET_Y0     : dato <= {{target_y0_reg}};
      GFX_TARGET_X1     : dato <= {{target_x1_reg}};
      GFX_TARGET_Y1     : dato <= {{target_y1_reg}};
      GFX_TEX0_BASE     : dato <= {{tex0_base_reg}};
      GFX_TEX0_SIZE_X   : dato <= {{tex0_size_x_reg}};
      GFX_TEX0_SIZE_Y   : dato <= {{tex0_size_y_reg}};
      GFX_SRC_PIXEL0_X  : dato <= {{src_pixel_pos_0_x_reg}};
      GFX_SRC_PIXEL0_Y  : dato <= {{src_pixel_pos_0_y_reg}};
      GFX_SRC_PIXEL1_X  : dato <= {{src_pixel_pos_1_x_reg}};
      GFX_SRC_PIXEL1_Y  : dato <= {{src_pixel_pos_1_y_reg}};
      GFX_DEST_PIXEL_X  : dato <= {{dest_pixel_pos_x_reg}};
      GFX_DEST_PIXEL_Y  : dato <= {{dest_pixel_pos_y_reg}};
      GFX_DEST_PIXEL_Z  : dato <= {{dest_pixel_pos_z_reg}};
      GFX_AA            : dato <= {{aa_reg}};
      GFX_AB            : dato <= {{ab_reg}};
      GFX_AC            : dato <= {{ac_reg}};
      GFX_TX            : dato <= {{tx_reg}};
      GFX_BA            : dato <= {{ba_reg}};
      GFX_BB            : dato <= {{bb_reg}};
      GFX_BC            : dato <= {{bc_reg}};
      GFX_TY            : dato <= {{ty_reg}};
      GFX_CA            : dato <= {{ca_reg}};
      GFX_CB            : dato <= {{cb_reg}};
      GFX_CC            : dato <= {{cc_reg}};
      GFX_TZ            : dato <= {{tz_reg}};
      GFX_CLIP_PIXEL0_X : dato <= {{clip_pixel_pos_0_x_reg}};
      GFX_CLIP_PIXEL0_Y : dato <= {{clip_pixel_pos_0_y_reg}};
      GFX_CLIP_PIXEL1_X : dato <= {{clip_pixel_pos_1_x_reg}};
      GFX_CLIP_PIXEL1_Y : dato <= {{clip_pixel_pos_1_y_reg}};
      GFX_COLOR0        : dato <= {{color0_reg}};
      GFX_COLOR1        : dato <= {{color1_reg}};
      GFX_COLOR2        : dato <= {{color2_reg}};
      GFX_U0            : dato <= {{u0_reg}};
      GFX_V0            : dato <= {{v0_reg}};
      GFX_U1            : dato <= {{u1_reg}};
      GFX_V1            : dato <= {{v1_reg}};
      GFX_U2            : dato <= {{u2_reg}};
      GFX_V2            : dato <= {{v2_reg}};
      GFX_ALPHA         : dato <= {{alpha_reg}};
      GFX_COLORKEY      : dato <= {{colorkey_reg}};
      GFX_ZBUFFER_BASE  : dato <= {{zbuffer_base_reg}};
      GFX_FONT_TABLE_BASE: dato <= {{font_table_base_reg}};
      GFX_FONT_ID				: dato <= {{font_id_reg}};
      GFX_CHAR_CODE			: dato <= {{char_code_reg}};
      GFX_COLOR_COMP		: dato <= color_comp_reg;
      default           : dato <= 32'd0;
      endcase

  // State machine
  always_ff @(posedge clk_i)
  if(rst_i)
    state <= wait_state;
  else
    case (state)
      wait_state:
        // Signals that trigger pipeline operations 
        if(rect_write_o | line_write_o | triangle_write_o | char_write_o | point_write_o |
           forward_point_o | transform_point_o)
          state <= busy_state;

      busy_state:
      	begin
	        // If a pipeline operation is finished, go back to wait state
	        if(pipeline_ack_i | transform_ack_i)
	          state <= wait_state;
        end
    endcase

  wire ready_next_cycle = (state == wait_state) &
  	~rect_write_o &
  	~line_write_o &
  	~triangle_write_o &
  	~char_write_o &
  	~point_write_o &
  	~forward_point_o &
  	~transform_point_o
  	;

	wire fifo_wr_req;
	wire wr_rst_busy;
	wire rd_rst_busy;
  assign instruction_fifo_rreq = ready_next_cycle && !rd_rst_busy && !empty;
  always_ff @(posedge clk_i)
  	was_fifo_rd <= instruction_fifo_rreq;
//	edge_det ued9 (.rst(rst_i), .clk(wbs_clk_i), .ce(1'b1), .i(reg_wacc && !full), .pe(fifo_wr_req), .ne(), .ee());
	assign instruction_fifo_wreq = reg_wacc && !full && !rst_i && !wr_rst_busy && !rd_rst_busy && !wr_ack;

	localparam FIFO_WID = 32 + REG_ADR_HIBIT + 1;

// +---------------------------------------------------------------------------------------------------------------------+
// | USE_ADV_FEATURES     | String             | Default value = 0707.                                                   |
// |---------------------------------------------------------------------------------------------------------------------|
// | Enables data_valid, almost_empty, rd_data_count, prog_empty, underflow, wr_ack, almost_full, wr_data_count,         |
// | prog_full, overflow features.                                                                                       |
// |                                                                                                                     |
// |   Setting USE_ADV_FEATURES[0] to 1 enables overflow flag; Default value of this bit is 1                            |
// |   Setting USE_ADV_FEATURES[1] to 1 enables prog_full flag; Default value of this bit is 1                           |
// |   Setting USE_ADV_FEATURES[2] to 1 enables wr_data_count; Default value of this bit is 1                            |
// |   Setting USE_ADV_FEATURES[3] to 1 enables almost_full flag; Default value of this bit is 0                         |
// |   Setting USE_ADV_FEATURES[4] to 1 enables wr_ack flag; Default value of this bit is 0                              |
// |   Setting USE_ADV_FEATURES[8] to 1 enables underflow flag; Default value of this bit is 1                           |
// |   Setting USE_ADV_FEATURES[9] to 1 enables prog_empty flag; Default value of this bit is 1                          |
// |   Setting USE_ADV_FEATURES[10] to 1 enables rd_data_count; Default value of this bit is 1                           |
// |   Setting USE_ADV_FEATURES[11] to 1 enables almost_empty flag; Default value of this bit is 0                       |
// |   Setting USE_ADV_FEATURES[12] to 1 enables data_valid flag; Default value of this bit is 0                         |
// +---------------------------------------------------------------------------------------------------------------------+

   // xpm_fifo_async: Asynchronous FIFO
   // Xilinx Parameterized Macro, version 2024.2

   xpm_fifo_async #(
      .CASCADE_HEIGHT(0),            // DECIMAL
      .CDC_SYNC_STAGES(2),           // DECIMAL
      .DOUT_RESET_VALUE("0"),        // String
      .ECC_MODE("no_ecc"),           // String
      .EN_SIM_ASSERT_ERR("warning"), // String
      .FIFO_MEMORY_TYPE("auto"),     // String
      .FIFO_READ_LATENCY(1),         // DECIMAL
      .FIFO_WRITE_DEPTH(2048),       // DECIMAL
      .FULL_RESET_VALUE(0),          // DECIMAL
      .PROG_EMPTY_THRESH(10),        // DECIMAL
      .PROG_FULL_THRESH(2040),        // DECIMAL
      .RD_DATA_COUNT_WIDTH(11),      // DECIMAL
      .READ_DATA_WIDTH(FIFO_WID),    // DECIMAL
      .READ_MODE("std"),             // String
      .RELATED_CLOCKS(0),            // DECIMAL
      .SIM_ASSERT_CHK(0),            // DECIMAL; 0=disable simulation messages, 1=enable simulation messages
      .USE_ADV_FEATURES("1014"),     // String
      .WAKEUP_TIME(0),               // DECIMAL
      .WRITE_DATA_WIDTH(FIFO_WID),   // DECIMAL
      .WR_DATA_COUNT_WIDTH(11)       // DECIMAL
   )
   xpm_fifo_async_inst (
      .almost_empty(),
      .almost_full(),
      .data_valid(instruction_fifo_valid_out),
      .dbiterr(),
      .dout({instruction_fifo_q_adr, instruction_fifo_q_data}),
      .empty(empty),
      .full(full),
      .overflow(),
      .prog_empty(),
      .prog_full(),
      .rd_data_count(),
      .rd_rst_busy(rd_rst_busy),
      .sbiterr(),
      .underflow(),
      .wr_ack(wr_ack),
      .wr_data_count(instruction_fifo_count),
      .wr_rst_busy(wr_rst_busy),
      .din({REG_ADR, wbs_req.dat}),
      .injectdbiterr(1'b0),
      .injectsbiterr(1'b0),
      .rd_clk(clk_i),
      .rd_en(instruction_fifo_rreq),
      .rst(rst_i),
      .sleep(1'b0),
      .wr_clk(wbs_clk_i),
      .wr_en(instruction_fifo_wreq)
   );
				
endmodule
