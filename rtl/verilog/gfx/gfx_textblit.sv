import gfx_pkg::*;

module gfx_textblit(rst_i, clk_i, clip_ack_i,
	char_i, char_code, char_pos_x_i, char_pos_y_i,
	char_x_o, char_y_o, char_write_o, char_ack_o,
	font_table_adr_i, font_id_i, read_request_o,
	textblit_ack_i, textblit_sel_o, textblit_adr_o, textblit_dat_i);
parameter point_width = 16;
parameter MDW=256;
parameter ALOW = MDW==256 ? 5 : MDW==128 ? 4 : MDW==64 ? 3 : 2;
input rst_i;
input clk_i;
input clip_ack_i;
input char_i;
input [15:0] char_code;
input [point_width-1:0] char_pos_x_i;
input [point_width-1:0] char_pos_y_i;
output reg [point_width-1:0] char_x_o;
output reg [point_width-1:0] char_y_o;
output reg char_write_o;
output reg char_ack_o;
input [31:0] font_table_adr_i;
input [15:0] font_id_i;
output reg read_request_o;
input textblit_ack_i;
output reg [31:0] textblit_sel_o;
output reg [31:0] textblit_adr_o;
input [MDW-1:0] textblit_dat_i;

reg [3:0] state;
reg [5:0] pixhc, pixvc;
reg [31:0] font_addr;
reg font_fixed;
reg [5:0] font_width;
reg [5:0] font_height;
reg [31:0] char_bmp_adr;
reg [63:0] char_bmp;
reg [31:0] char_ndx;
reg [31:0] glyph_table_adr;
reg [7:0] glyph_entry;
reg [ALOW-1:0] alsb;
reg signed [7:0] read_cnt;
reg [MDW*8:0] read_buf;
reg [4:0] readno;

parameter TRUE = 1'b1;
parameter FALSE = 1'b0;
parameter ST_IDLE = 4'd0;
parameter ST_READ_FONTTBL1 = 4'd1;
parameter ST_READ_FONTTBL1_ACK = 4'd2;
parameter ST_READ_FONTTBL2 = 4'd3;
parameter ST_READ_FONTTBL2_ACK = 4'd4;
parameter ST_READ_GLYPH_ENTRY = 4'd5;
parameter ST_READ_GLYPH_ENTRY_ACK = 4'd6;
parameter ST_READ_GLYPH_ENTRY2 = 4'd7;
parameter ST_READ_CHAR_BITMAP = 4'd8;
parameter ST_READ_CHAR_BITMAP_ACK = 4'd9;
parameter ST_READ_CHAR_BITMAP2 = 4'd10;
parameter ST_WRITE_CHAR = 4'd11;
parameter ST_WAIT_ACK = 4'd12;
parameter ST_WAIT = 4'd13;
reg [3:0] ret_state;

reg [3:0] ret_stat;

typedef enum logic [1:0] {
	ST_READ_IDLE = 2'd0,
	ST_READ1,
	ST_READ1_ACK
} read_state_e;
read_state_e read_state;

always_ff @(posedge clk_i)
begin
case(state)
ST_IDLE:
	if (char_i) begin
		state <= ST_READ_FONTTBL1;
		read_state <= ST_READ1;
	end
ST_READ_FONTTBL1:
	state <= ST_WAIT;
ST_READ_FONTTBL1_ACK:
	state <= ST_READ_GLYPH_ENTRY;
ST_READ_GLYPH_ENTRY:
	if (font_fixed)
		state <= ST_READ_CHAR_BITMAP;
	else begin
		read_state <= ST_READ1;
		state <= ST_WAIT;
	end
ST_READ_GLYPH_ENTRY_ACK:
	state <= ST_READ_CHAR_BITMAP;
ST_READ_CHAR_BITMAP:
	begin
		state <= ST_READ_CHAR_BITMAP_ACK;
		read_state <= ST_READ1;
	end
ST_READ_CHAR_BITMAP_ACK:
	state <= ST_READ_CHAR_BITMAP2;
ST_READ_CHAR_BITMAP2:
	state <= ST_WRITE_CHAR;
ST_WRITE_CHAR:
	begin
		state <= ST_WAIT_ACK;
		if (pixhc==font_width) begin
			state <= ST_READ_CHAR_BITMAP;
	    if (pixvc==font_height)
	    	state <= ST_IDLE;
		end
	end
ST_WAIT_ACK:
	if (clip_ack_i)
		state <= ST_WRITE_CHAR;

endcase

case(read_state)
ST_READ_IDLE:	;
ST_READ1:
	read_state <= ST_READ1_ACK;
ST_READ1_ACK:
	if (!(read_cnt - $signed(MDW/32)) > 0 && read_request_o) begin
		read_state <= ST_READ_IDLE;
		state <= ret_state;
	end
default:
	state <= ST_READ_IDLE;
endcase
end

always @(posedge clk_i)
	char_ndx <= (char_code << font_width[4:3]) * (font_height + 6'd1);

always @(posedge clk_i)
	textblit_sel_o <= {MDW/8{1'b1}};

// Font Table - An entry for each font
// 0 aaaaaaaaaaaaaaaa_aaaaaaaaaaaaaaaa		- char bitmap address
// 4 fwwwwwhhhhh-----_aaaaaaaaaaaaaaaa		- width and height
// 8 aaaaaaaaaaaaaaaa_aaaaaaaaaaaaaaaa		- low order address offset bits
// C ----------------_aaaaaaaaaaaaaaaa		- address offset of gylph width table
//
// Glyph Table Entry
// ---wwwww---wwwww_---wwwww---wwwww		- width
// ---wwwww---wwwww_---wwwww---wwwww
// ...

always_ff @(posedge clk_i)
begin
	char_write_o <= 1'b0;
	char_ack_o <= 1'b0;
case(state)
ST_WAIT:	;
ST_READ_FONTTBL1:
	begin
		read_cnt <= 3'd3;
		read_request_o <= 1'b1;
		textblit_adr_o <= {font_table_adr_i[31:ALOW],{ALOW{1'b0}}} + {font_id_i,4'b0};
		ret_state <= ST_READ_FONTTBL1_ACK;
	end
ST_READ_FONTTBL1_ACK:
	begin
		char_bmp_adr <= {read_buf[31:2],{2{1'b0}}};
		font_fixed <= read_buf[63];
		font_width <= read_buf[62:58];
		font_height <= read_buf[57:53];
		glyph_table_adr <= {read_buf[95:69],5'd0};
	end
ST_READ_GLYPH_ENTRY:
	begin
		char_bmp_adr <= char_bmp_adr + char_ndx;
		if (!font_fixed) begin
			read_cnt <= 3'd1;
			read_request_o <= 1'b1;
			textblit_adr_o <= glyph_table_adr + {char_code[15:2],{2{1'b0}}};
			ret_state <= ST_READ_GLYPH_ENTRY_ACK;
		end
	end
ST_READ_GLYPH_ENTRY_ACK:
	begin
		case(MDW)
		32:	font_width <= read_buf >> {char_code[1:0],3'b0};
		64: font_width <= read_buf >> {textblit_adr_o[2],char_code[1:0],3'b0};
		128: font_width <= read_buf >> {textblit_adr_o[3:2],char_code[1:0],3'b0};
		256: font_width <= read_buf >> {textblit_adr_o[4:2],char_code[1:0],3'b0};
		512: font_width <= read_buf >> {textblit_adr_o[5:2],char_code[1:0],3'b0};
		default:	;
		endcase
	end
ST_READ_CHAR_BITMAP:
	begin
		casez(font_width[5:3]+|font_width[2:0])
		3'b001:	read_cnt <= 3'd1;
		3'b01?:	read_cnt <= 3'd1;
		3'b1??:	read_cnt <= 3'd2;
		endcase
		alsb <= char_bmp_adr + (pixvc << font_width[5:4]);
		textblit_adr_o <= char_bmp_adr + (pixvc << font_width[5:4]);
		textblit_adr_o[31:ALOW] <= {ALOW{1'd0}};
		ret_state <= ST_READ_CHAR_BITMAP_ACK;
	end
ST_READ_CHAR_BITMAP_ACK:
	case(MDW)
	32:	char_bmp <= read_buf >> {alsb[1:0],3'd0};
	64:	char_bmp <= read_buf >> {alsb[2:0],3'b0};
	128:	char_bmp <= read_buf >> {alsb[3:0],5'b0};
	256:	char_bmp <= read_buf >> {alsb[4:0],5'b0};
	512:	char_bmp <= read_buf >> {alsb[5:0],5'b0};
	endcase
ST_READ_CHAR_BITMAP2:
	begin
		casez(font_width[5:3])
		3'b000:	char_bmp <= char_bmp & 64'hff;
		3'b001:	char_bmp <= char_bmp & 64'hffff;
		3'b01?:	char_bmp <= char_bmp & 64'hffffffff;
		3'b1??:	char_bmp <= char_bmp;
		endcase
	end
ST_WRITE_CHAR:
	begin
		char_x_o <= char_pos_x_i + pixhc;
		char_y_o <= char_pos_y_i + pixvc;
		if (pixhc != font_width || pixvc != font_height)
			char_write_o <= char_bmp[0];
		char_bmp <= {1'b0,char_bmp[63:1]};
		pixhc <= pixhc + 5'd1;
		if (pixhc==font_width) begin
		  pixhc <= 5'd0;
		  pixvc <= pixvc + 5'd1;
	    if (pixvc==font_height)
	    	char_ack_o <= 1'b1;
		end
	end
default:	;
endcase

case(read_state)
ST_READ_IDLE:	;

ST_READ1:
	begin
		read_request_o <= 1'b1;
		readno <= 5'd0;
	end	
ST_READ1_ACK:
	if (textblit_ack_i) begin
		read_request_o <= 1'b0;
		case(readno)
		5'd0:	read_buf[MDW-1:0] <= textblit_dat_i;
		5'd1:	read_buf[MDW*2-1:MDW] <= textblit_dat_i;
		5'd2:	read_buf[MDW*3-1:MDW*2] <= textblit_dat_i;
		5'd3:	read_buf[MDW*4-1:MDW*3] <= textblit_dat_i;
		5'd4:	read_buf[MDW*5-1:MDW*4] <= textblit_dat_i;
		5'd5:	read_buf[MDW*6-1:MDW*5] <= textblit_dat_i;
		5'd6:	read_buf[MDW*7-1:MDW*6] <= textblit_dat_i;
		5'd7:	read_buf[MDW*8-1:MDW*7] <= textblit_dat_i;
		endcase
		if ((read_cnt - $signed(MDW/32)) > 0 && read_request_o)
			read_cnt <= read_cnt - $signed(MDW/32);
	end	
	else begin
		if (read_request_o==1'b0 && read_cnt!= 3'd0) begin
			readno <= readno + 5'd1;
			read_request_o <= 1'b1;
			textblit_adr_o <= textblit_adr_o + (MDW/8);
		end
	end
default:	;
endcase
end

endmodule
