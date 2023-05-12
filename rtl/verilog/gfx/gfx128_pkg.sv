
package gfx128_pkg;

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
