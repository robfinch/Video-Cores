// ============================================================================
//        __
//   \\__/ o\    (C) 2018-2024  Robert Finch, Waterloo
//    \  __ /    All rights reserved.
//     \/_//     robfinch<remove>@finitron.ca
//       ||
//
//
// BSD 3-Clause License
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are met:
//
// 1. Redistributions of source code must retain the above copyright notice, this
//    list of conditions and the following disclaimer.
//
// 2. Redistributions in binary form must reproduce the above copyright notice,
//    this list of conditions and the following disclaimer in the documentation
//    and/or other materials provided with the distribution.
//
// 3. Neither the name of the copyright holder nor the names of its
//    contributors may be used to endorse or promote products derived from
//    this software without specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
// IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
// DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
// FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
// DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
// SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
// CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
// OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//                                                                          
// ============================================================================
//
`define VENDOR_XILINX

module rfTextScreenRam(rsta_i, clka_i, csa_i, wea_i, sela_i, adra_i, data_i, data_o,
	rstb_i, clkb_i, csb_i, web_i, selb_i, adrb_i, datb_i, datb_o);
input rsta_i;
input clka_i;
input csa_i;
input wea_i;
input [7:0] sela_i;
input [15:3] adra_i;
input [63:0] data_i;
output [63:0] data_o;
input rstb_i;
input clkb_i;
input csb_i;
input web_i;
input [7:0] selb_i;
input [15:3] adrb_i;
input [63:0] datb_i;
output [63:0] datb_o;
parameter TEXT_CELL_COUNT = 16384;
localparam AWID = $clog2(TEXT_CELL_COUNT);

wire rsta = rsta_i;
wire rstb = rstb_i;

// xpm_memory_tdpram: True Dual Port RAM
// Xilinx Parameterized Macro, version 2020.2
`ifdef VENDOR_XILINX

	xpm_memory_tdpram #(
	  .ADDR_WIDTH_A(AWID),
	  .ADDR_WIDTH_B(AWID),
	  .AUTO_SLEEP_TIME(0),
	  .BYTE_WRITE_WIDTH_A(8),
	  .BYTE_WRITE_WIDTH_B(8),
	  .CASCADE_HEIGHT(0),
	  .CLOCKING_MODE("independent_clock"), // String
	  .ECC_MODE("no_ecc"),            // String
	  .MEMORY_INIT_FILE("none"), 			// String
	  .MEMORY_INIT_PARAM("0"),        // String
	  .MEMORY_OPTIMIZATION("true"),   // String
	  .MEMORY_PRIMITIVE("block"),      // String
	  .MEMORY_SIZE(TEXT_CELL_COUNT*64),
	  .MESSAGE_CONTROL(0),
	  .READ_DATA_WIDTH_A(64),
	  .READ_DATA_WIDTH_B(64),
	  .READ_LATENCY_A(2),
	  .READ_LATENCY_B(1),
	  .READ_RESET_VALUE_A("0"),       // String
	  .READ_RESET_VALUE_B("0"),       // String
	  .RST_MODE_A("SYNC"),            // String
	  .RST_MODE_B("SYNC"),            // String
	  .SIM_ASSERT_CHK(0),             // DECIMAL; 0=disable simulation messages, 1=enable simulation messages
	  .USE_EMBEDDED_CONSTRAINT(0),    // DECIMAL
	  .USE_MEM_INIT(1),
	  .WAKEUP_TIME("disable_sleep"),  // String
	  .WRITE_DATA_WIDTH_A(64),
	  .WRITE_DATA_WIDTH_B(64),
	  .WRITE_MODE_A("no_change"),     // String
	  .WRITE_MODE_B("no_change")      // String
	)
	xpm_memory_tdpram_inst (
	  .dbiterra(),             // 1-bit output: Status signal to indicate double bit error occurrence
	                                   // on the data output of port A.

	  .dbiterrb(),             // 1-bit output: Status signal to indicate double bit error occurrence
	                                   // on the data output of port A.

	  .douta(data_o),          // READ_DATA_WIDTH_A-bit output: Data output for port A read operations.
	  .doutb(datb_o),          // READ_DATA_WIDTH_B-bit output: Data output for port B read operations.
	  .sbiterra(),             // 1-bit output: Status signal to indicate single bit error occurrence
	                                   // on the data output of port A.

	  .sbiterrb(),             // 1-bit output: Status signal to indicate single bit error occurrence
	                                   // on the data output of port B.

	  .addra(adra_i),                   // ADDR_WIDTH_A-bit input: Address for port A write and read operations.
	  .addrb(adrb_i),               // ADDR_WIDTH_B-bit input: Address for port B write and read operations.
	  .clka(clka_i),                   // 1-bit input: Clock signal for port A. Also clocks port B when
	                                   // parameter CLOCKING_MODE is "common_clock".

	  .clkb(clkb_i),               // 1-bit input: Clock signal for port B when parameter CLOCKING_MODE is
	                                   // "independent_clock". Unused when parameter CLOCKING_MODE is
	                                   // "common_clock".

	  .dina(data_i),                     // WRITE_DATA_WIDTH_A-bit input: Data input for port A write operations.
	  .dinb(datb_i),                  // WRITE_DATA_WIDTH_B-bit input: Data input for port B write operations.
	  .ena(csa_i),                       // 1-bit input: Memory enable signal for port A. Must be high on clock
	                                   // cycles when read or write operations are initiated. Pipelined
	                                   // internally.

	  .enb(csb_i),                       // 1-bit input: Memory enable signal for port B. Must be high on clock
	                                   // cycles when read or write operations are initiated. Pipelined
	                                   // internally.

	  .injectdbiterra(1'b0), // 1-bit input: Controls double bit error injection on input data when
	                                   // ECC enabled (Error injection capability is not available in
	                                   // "decode_only" mode).

	  .injectdbiterrb(1'b0), // 1-bit input: Controls double bit error injection on input data when
	                                   // ECC enabled (Error injection capability is not available in
	                                   // "decode_only" mode).

	  .injectsbiterra(1'b0), // 1-bit input: Controls single bit error injection on input data when
	                                   // ECC enabled (Error injection capability is not available in
	                                   // "decode_only" mode).

	  .injectsbiterrb(1'b0), // 1-bit input: Controls single bit error injection on input data when
	                                   // ECC enabled (Error injection capability is not available in
	                                   // "decode_only" mode).

	  .regcea(1'b1),                 // 1-bit input: Clock Enable for the last register stage on the output
	                                   // data path.

	  .regceb(1'b1),                 // 1-bit input: Clock Enable for the last register stage on the output
	                                   // data path.

	  .rsta(rsta),                     // 1-bit input: Reset signal for the final port A output register stage.
	                                   // Synchronously resets output port douta to the value specified by
	                                   // parameter READ_RESET_VALUE_A.

	  .rstb(rstb),                     // 1-bit input: Reset signal for the final port B output register stage.
	                                   // Synchronously resets output port doutb to the value specified by
	                                   // parameter READ_RESET_VALUE_B.

	  .sleep(1'b0),                   // 1-bit input: sleep signal to enable the dynamic power saving feature.
	  .wea({8{wea_i}} & sela_i),         							// WRITE_DATA_WIDTH_A/BYTE_WRITE_WIDTH_A-bit input: Write enable vector
	                                   // for port A input data port dina. 1 bit wide when word-wide writes are
	                                   // used. In byte-wide write configurations, each bit controls the
	                                   // writing one byte of dina to address addra. For example, to
	                                   // synchronously write only bits [15-8] of dina when WRITE_DATA_WIDTH_A
	                                   // is 32, wea would be 4'b0010.

	  .web({8{web_i}} & selb_i)        // WRITE_DATA_WIDTH_B/BYTE_WRITE_WIDTH_B-bit input: Write enable vector
	                                   // for port B input data port dinb. 1 bit wide when word-wide writes are
	                                   // used. In byte-wide write configurations, each bit controls the
	                                   // writing one byte of dinb to address addrb. For example, to
	                                   // synchronously write only bits [15-8] of dinb when WRITE_DATA_WIDTH_B
	                                   // is 32, web would be 4'b0010.

	);

`elsif VENDOR_ALTERA
	always_comb
	begin
		$display("ToDo: Add ALTERA RAM support.");
		$finish();
	end
`else
	always_comb
	begin
		$display("No RAM vendor selected.");
		$finish();
	end
`endif

endmodule
