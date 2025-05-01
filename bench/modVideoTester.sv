import const_pkg::*;
import fta_bus_pkg::*;

module modVideoTester(btnu, btnd, vtm);
input btnu;
input btnd;
fta_bus_interface.master vtm;

typedef enum logic [4:0] {
	IDLE = 5'd0,
	CLS1 = 5'd1,
	CLS2,
	CLS3,
	READBMP1,
	READBMP2,
	READBMP3,
	READBMP4,
	READBMP5
} state_t;

state_t state;
wire [5:0] cnt;
wire rsta = vtm.rst;
wire rstb = vtm.rst;
wire clka = vtm.clk;
wire clkb = vtm.clk;
wire ena = 1'b0;
reg enb;
wire wea = 1'b0;
wire [19:0] addra = 20'h0;
reg [19:0] addrb;
wire [255:0] dina = 256'd0;
wire [255:0] doutb;
reg sleep;
reg rnd;
reg [15:0] color;

wire [26:0] lfsr1_o;
lfsr27 #(.WID(27)) ulfsr1(vtm.rst, vtm.clk, 1'b1, 1'b0, lfsr1_o);

counter #(6) ucnt1 (.rst(vtm.rst||state==CLS1||state==READBMP3), .clk(vtm.clk), .ce(state==CLS2||state==READBMP4), .ld(1'b0), .d(6'd0), .q(cnt), .tc());

always_ff @(posedge vtm.clk)
if (vtm.rst) begin
	vtm.req.blen = 6'd0;
	vtm.req.bte <= fta_bus_pkg::LINEAR;
	vtm.req.cti <= fta_bus_pkg::CLASSIC;
	vtm.req.cmd <= fta_bus_pkg::CMD_NONE;
	vtm.req.we <= LOW;
	vtm.req.sel <= 32'h0;
	vtm.req.pv <= 1'b0;
	vtm.req.adr <= 32'h0;
	addrb <= 20'd0;
	enb <= 1'b0;
	rnd <= 1'b1;
	sleep <= 1'b1;
	state <= IDLE;
end
else begin
	vtm.req.cmd <= fta_bus_pkg::CMD_NONE;
	vtm.req.cyc <= LOW;
	vtm.req.we <= LOW;
	vtm.req.sel <= 32'h0;
	case(state)
	IDLE:
		if (btnu) begin
//			vtm.req.vadr <= 32'h001000;
			vtm.req.pv <= 1'b0;
			vtm.req.adr <= 32'h201000;
			color <= 16'h000F;
			rnd <= 1'b0;
			state <= CLS1;
		end
		else if (btnd) begin
//			vtm.req.vadr <= 32'h001000;
			vtm.req.pv <= 1'b0;
			vtm.req.adr <= 32'h201000;
			sleep <= 1'b0;
			rnd <= 1'b1;
			color <= lfsr1_o[15:0];
			state <= CLS1;
		end
	CLS1:
		begin
			vtm.req.cmd <= fta_bus_pkg::CMD_STORE;
			vtm.req.cyc <= HIGH;
			vtm.req.we <= HIGH;
			vtm.req.sel <= 32'hFFFFFFFF;
			if (rnd)
				color <= lfsr1_o[15:0];
			vtm.req.data1 <= {16{color}};
			state <= CLS2;
		end
	// Delay so that the fifo is not overflowed.
	CLS2:
		begin
			if (cnt>=6'd51)
				state <= CLS3;
		end
	CLS3:
		begin
			vtm.req.adr <= vtm.req.adr + 6'd32;
			if (vtm.req.adr < 32'h300000)
				state <= CLS1;
			else
				state <= IDLE;
		end
	READBMP1:
		begin
			vtm.req.adr <= 32'h200000;
			enb <= 1'b1;
			addrb <= doutb[111:80];
			state <= READBMP2;
		end
	READBMP2:
		begin
			state <= READBMP3;
		end
	READBMP3:
		begin
			vtm.req.cmd <= fta_bus_pkg::CMD_STORE;
			vtm.req.cyc <= HIGH;
			vtm.req.we <= HIGH;
			vtm.req.sel <= 32'hFFFFFFFF;
			vtm.req.data1 <= doutb;
			addrb <= addrb + 6'd32;
			state <= READBMP4;
		end
	READBMP4:
		if (cnt >= 6'd51)
			state <= READBMP5;
	READBMP5:
		begin
			vtm.req.adr <= vtm.req.adr + 6'd32;
			if (addrb < 32'h100000)
				state <= READBMP3;
			else begin
				sleep <= 1'b1;
				state <= IDLE;
			end
		end
	default:
		state <= IDLE;
	endcase
end

/*
   // xpm_memory_sdpram: Simple Dual Port RAM
   // Xilinx Parameterized Macro, version 2024.1

   xpm_memory_sdpram #(
      .ADDR_WIDTH_A(15),               // DECIMAL
      .ADDR_WIDTH_B(15),               // DECIMAL
      .AUTO_SLEEP_TIME(0),            // DECIMAL
      .BYTE_WRITE_WIDTH_A(256),        // DECIMAL
      .CASCADE_HEIGHT(0),             // DECIMAL
      .CLOCKING_MODE("common_clock"), // String
      .ECC_BIT_RANGE("7:0"),          // String
      .ECC_MODE("no_ecc"),            // String
      .ECC_TYPE("none"),              // String
      .IGNORE_INIT_SYNTH(0),          // DECIMAL
      .MEMORY_INIT_FILE("teacup.bmp"),    // String
      .MEMORY_INIT_PARAM("0"),        // String
      .MEMORY_OPTIMIZATION("true"),   // String
      .MEMORY_PRIMITIVE("auto"),      // String
      .MEMORY_SIZE(32768*32*8),             // DECIMAL
      .MESSAGE_CONTROL(0),            // DECIMAL
      .RAM_DECOMP("auto"),            // String
      .READ_DATA_WIDTH_B(256),        // DECIMAL
      .READ_LATENCY_B(2),             // DECIMAL
      .READ_RESET_VALUE_B("0"),       // String
      .RST_MODE_A("SYNC"),            // String
      .RST_MODE_B("SYNC"),            // String
      .SIM_ASSERT_CHK(0),             // DECIMAL; 0=disable simulation messages, 1=enable simulation messages
      .USE_EMBEDDED_CONSTRAINT(0),    // DECIMAL
      .USE_MEM_INIT(1),               // DECIMAL
      .USE_MEM_INIT_MMI(0),           // DECIMAL
      .WAKEUP_TIME("disable_sleep"),  // String
      .WRITE_DATA_WIDTH_A(256),       // DECIMAL
      .WRITE_MODE_B("no_change"),     // String
      .WRITE_PROTECT(1)               // DECIMAL
   )
   xpm_memory_sdpram_inst (
      .dbiterrb(),             // 1-bit output: Status signal to indicate double bit error occurrence
                                       // on the data output of port B.

      .doutb(doutb),                   // READ_DATA_WIDTH_B-bit output: Data output for port B read operations.
      .sbiterrb(),             // 1-bit output: Status signal to indicate single bit error occurrence
                                       // on the data output of port B.

      .addra(addra),                   // ADDR_WIDTH_A-bit input: Address for port A write operations.
      .addrb(addrb),                   // ADDR_WIDTH_B-bit input: Address for port B read operations.
      .clka(clka),                     // 1-bit input: Clock signal for port A. Also clocks port B when
                                       // parameter CLOCKING_MODE is "common_clock".

      .clkb(clkb),                     // 1-bit input: Clock signal for port B when parameter CLOCKING_MODE is
                                       // "independent_clock". Unused when parameter CLOCKING_MODE is
                                       // "common_clock".

      .dina(dina),                     // WRITE_DATA_WIDTH_A-bit input: Data input for port A write operations.
      .ena(ena),                       // 1-bit input: Memory enable signal for port A. Must be high on clock
                                       // cycles when write operations are initiated. Pipelined internally.

      .enb(enb),                       // 1-bit input: Memory enable signal for port B. Must be high on clock
                                       // cycles when read operations are initiated. Pipelined internally.

      .injectdbiterra(1'b0), // 1-bit input: Controls double bit error injection on input data when
                                       // ECC enabled (Error injection capability is not available in
                                       // "decode_only" mode).

      .injectsbiterra(1'b0), // 1-bit input: Controls single bit error injection on input data when
                                       // ECC enabled (Error injection capability is not available in
                                       // "decode_only" mode).

      .regceb(1'b1),                 // 1-bit input: Clock Enable for the last register stage on the output
                                       // data path.

      .rstb(rstb),                     // 1-bit input: Reset signal for the final port B output register stage.
                                       // Synchronously resets output port doutb to the value specified by
                                       // parameter READ_RESET_VALUE_B.

      .sleep(sleep),                   // 1-bit input: sleep signal to enable the dynamic power saving feature.
      .wea(wea)                        // WRITE_DATA_WIDTH_A/BYTE_WRITE_WIDTH_A-bit input: Write enable vector
                                       // for port A input data port dina. 1 bit wide when word-wide writes are
                                       // used. In byte-wide write configurations, each bit controls the
                                       // writing one byte of dina to address addra. For example, to
                                       // synchronously write only bits [15-8] of dina when WRITE_DATA_WIDTH_A
                                       // is 32, wea would be 4'b0010.

   );
*/			
				
endmodule
