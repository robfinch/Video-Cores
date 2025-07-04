
package gfx_pkg;

// Declarations of register addresses:
parameter GFX_CONTROL        = 8'h00;
parameter GFX_STATUS         = 8'h04;
parameter GFX_ALPHA          = 8'h08;
parameter GFX_COLORKEY       = 8'h0c;

parameter GFX_TARGET_BASE    = 8'h10;
parameter GFX_TARGET_SIZE_X  = 8'h14;
parameter GFX_TARGET_SIZE_Y  = 8'h18;

parameter GFX_TEX0_BASE      = 8'h1c;
parameter GFX_TEX0_SIZE_X    = 8'h20;
parameter GFX_TEX0_SIZE_Y    = 8'h24;

parameter GFX_SRC_PIXEL0_X   = 8'h28;
parameter GFX_SRC_PIXEL0_Y   = 8'h2c;
parameter GFX_SRC_PIXEL1_X   = 8'h30;
parameter GFX_SRC_PIXEL1_Y   = 8'h34;

parameter GFX_DEST_PIXEL_X   = 8'h38;
parameter GFX_DEST_PIXEL_Y   = 8'h3c;
parameter GFX_DEST_PIXEL_Z   = 8'h40;

parameter GFX_AA             = 8'h44;
parameter GFX_AB             = 8'h48;
parameter GFX_AC             = 8'h4c;
parameter GFX_TX             = 8'h50;
parameter GFX_BA             = 8'h54;
parameter GFX_BB             = 8'h58;
parameter GFX_BC             = 8'h5c;
parameter GFX_TY             = 8'h60;
parameter GFX_CA             = 8'h64;
parameter GFX_CB             = 8'h68;
parameter GFX_CC             = 8'h6c;
parameter GFX_TZ             = 8'h70;

parameter GFX_CLIP_PIXEL0_X  = 8'h74;
parameter GFX_CLIP_PIXEL0_Y  = 8'h78;
parameter GFX_CLIP_PIXEL1_X  = 8'h7c;
parameter GFX_CLIP_PIXEL1_Y  = 8'h80;

parameter GFX_COLOR0         = 8'h84;
parameter GFX_COLOR1         = 8'h88;
parameter GFX_COLOR2         = 8'h8c;

parameter GFX_U0             = 8'h90;
parameter GFX_V0             = 8'h94;
parameter GFX_U1             = 8'h98;
parameter GFX_V1             = 8'h9c;
parameter GFX_U2             = 8'ha0;
parameter GFX_V2             = 8'ha4;

parameter GFX_ZBUFFER_BASE   = 8'ha8;

parameter GFX_TARGET_X0			 = 8'hb0;
parameter GFX_TARGET_Y0			 = 8'hb4;
parameter GFX_TARGET_X1			 = 8'hb8;
parameter GFX_TARGET_Y1			 = 8'hbc;
parameter GFX_FONT_TABLE_BASE= 8'hc0;
parameter GFX_FONT_ID				 = 8'hc8;
parameter GFX_CHAR_CODE			 = 8'hcc;
parameter GFX_COLOR_COMP		 = 8'hd0;
parameter GFX_PPS						 = 8'hd4;

// Declare control register bits
parameter GFX_CTRL_COLOR_DEPTH = 0;
parameter GFX_CTRL_TEXTURE  = 2;
parameter GFX_CTRL_BLENDING = 3;
parameter GFX_CTRL_COLORKEY = 4;
parameter GFX_CTRL_CLIPPING = 5;
parameter GFX_CTRL_ZBUFFER  = 6;
parameter GFX_CTRL_POINT		= 7;
parameter GFX_CTRL_RECT     = 8;
parameter GFX_CTRL_LINE     = 9;
parameter GFX_CTRL_TRI      = 10;
parameter GFX_CTRL_CURVE    = 11;
parameter GFX_CTRL_INTERP   = 12;
parameter GFX_CTRL_INSIDE   = 13;
parameter GFX_CTRL_CHAR		  = 20;
parameter GFX_CTRL_FLOODFILL = 21;

parameter GFX_CTRL_ACTIVE_POINT    = 16;
parameter GFX_CTRL_FORWARD_POINT   = 18;
parameter GFX_CTRL_TRANSFORM_POINT = 19;

// Declare status register bits
parameter GFX_STAT_BUSY     = 0;

parameter point_width = 16;
parameter address_width = 32;

// Calculate the memory address of the texel to read 
function [31:0] fnPixelOffset;
input [1:0] color_depth;
input [31:0] offs;
begin
case(color_depth)
2'b00:	fnPixelOffset = offs;
2'b01:	fnPixelOffset = offs << 1;
2'b11:	fnPixelOffset = offs << 2;
default:	fnPixelOffset = 32'd0;
endcase
end
endfunction

endpackage
