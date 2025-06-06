// ============================================================================
//        __
//   \\__/ o\    (C) 2023-2025  Robert Finch, Waterloo
//    \  __ /    All rights reserved.
//     \/_//     robfinch<remove>@finitron.ca
//       ||
//
//
// fb_palram.sv
// - Palette RAM for frame buffer
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

module fb_palram(clka, ena, wea, addra, dina, douta, clkb, enb, web, addrb, dinb, doutb);
parameter XILINX = 1;
input clka;
input ena;
input [7:0] wea;
input [9:0] addra;
input [63:0] dina;
output [63:0] douta;
input clkb;
input enb;
input web;
input [10:0] addrb;
input [31:0] dinb;
output [31:0] doutb;


generate begin : gPalram
	if (XILINX) 
	   // xpm_memory_tdpram: True Dual Port RAM
	   // Xilinx Parameterized Macro, version 2022.2

	   xpm_memory_tdpram #(
	      .ADDR_WIDTH_A(10),              // DECIMAL
	      .ADDR_WIDTH_B(11),               // DECIMAL
	      .AUTO_SLEEP_TIME(0),            // DECIMAL
	      .BYTE_WRITE_WIDTH_A(8),         // DECIMAL
	      .BYTE_WRITE_WIDTH_B(32),        // DECIMAL
	      .CASCADE_HEIGHT(0),             // DECIMAL
	      .CLOCKING_MODE("independent_clock"), // String
	      .ECC_MODE("no_ecc"),            // String
	      .MEMORY_INIT_FILE("none"),      // String
	      .MEMORY_INIT_PARAM("0"),        // String
	      .MEMORY_OPTIMIZATION("true"),   // String
	      .MEMORY_PRIMITIVE("auto"),      // String
	      .MEMORY_SIZE(1024*64),          // DECIMAL
	      .MESSAGE_CONTROL(0),            // DECIMAL
	      .READ_DATA_WIDTH_A(64),         // DECIMAL
	      .READ_DATA_WIDTH_B(32),         // DECIMAL
	      .READ_LATENCY_A(2),             // DECIMAL
	      .READ_LATENCY_B(2),             // DECIMAL
	      .READ_RESET_VALUE_A("0"),       // String
	      .READ_RESET_VALUE_B("0"),       // String
	      .RST_MODE_A("SYNC"),            // String
	      .RST_MODE_B("SYNC"),            // String
	      .SIM_ASSERT_CHK(0),             // DECIMAL; 0=disable simulation messages, 1=enable simulation messages
	      .USE_EMBEDDED_CONSTRAINT(0),    // DECIMAL
	      .USE_MEM_INIT(1),               // DECIMAL
	      .USE_MEM_INIT_MMI(0),           // DECIMAL
	      .WAKEUP_TIME("disable_sleep"),  // String
	      .WRITE_DATA_WIDTH_A(64),        // DECIMAL
	      .WRITE_DATA_WIDTH_B(32),        // DECIMAL
	      .WRITE_MODE_A("no_change"),     // String
	      .WRITE_MODE_B("no_change"),     // String
	      .WRITE_PROTECT(1)               // DECIMAL
	   )
	   xpm_memory_tdpram_inst (
	      .dbiterra(),             // 1-bit output: Status signal to indicate double bit error occurrence
	                                       // on the data output of port A.

	      .dbiterrb(),             // 1-bit output: Status signal to indicate double bit error occurrence
	                                       // on the data output of port A.

	      .douta(douta),                   // READ_DATA_WIDTH_A-bit output: Data output for port A read operations.
	      .doutb(doutb),                   // READ_DATA_WIDTH_B-bit output: Data output for port B read operations.
	      .sbiterra(),             // 1-bit output: Status signal to indicate single bit error occurrence
	                                       // on the data output of port A.

	      .sbiterrb(),             // 1-bit output: Status signal to indicate single bit error occurrence
	                                       // on the data output of port B.

	      .addra(addra[9:0]),                   // ADDR_WIDTH_A-bit input: Address for port A write and read operations.
	      .addrb(addrb[10:0]),                   // ADDR_WIDTH_B-bit input: Address for port B write and read operations.
	      .clka(clka),                     // 1-bit input: Clock signal for port A. Also clocks port B when
	                                       // parameter CLOCKING_MODE is "common_clock".

	      .clkb(clkb),                     // 1-bit input: Clock signal for port B when parameter CLOCKING_MODE is
	                                       // "independent_clock". Unused when parameter CLOCKING_MODE is
	                                       // "common_clock".

	      .dina(dina),                     // WRITE_DATA_WIDTH_A-bit input: Data input for port A write operations.
	      .dinb(dinb),                     // WRITE_DATA_WIDTH_B-bit input: Data input for port B write operations.
	      .ena(ena),                       // 1-bit input: Memory enable signal for port A. Must be high on clock
	                                       // cycles when read or write operations are initiated. Pipelined
	                                       // internally.

	      .enb(enb),                       // 1-bit input: Memory enable signal for port B. Must be high on clock
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

	      .rsta(1'b0),                     // 1-bit input: Reset signal for the final port A output register stage.
	                                       // Synchronously resets output port douta to the value specified by
	                                       // parameter READ_RESET_VALUE_A.

	      .rstb(1'b0),                     // 1-bit input: Reset signal for the final port B output register stage.
	                                       // Synchronously resets output port doutb to the value specified by
	                                       // parameter READ_RESET_VALUE_B.

	      .sleep(1'b0),                   // 1-bit input: sleep signal to enable the dynamic power saving feature.
	      .wea(wea),                       // WRITE_DATA_WIDTH_A/BYTE_WRITE_WIDTH_A-bit input: Write enable vector
	                                       // for port A input data port dina. 1 bit wide when word-wide writes are
	                                       // used. In byte-wide write configurations, each bit controls the
	                                       // writing one byte of dina to address addra. For example, to
	                                       // synchronously write only bits [15-8] of dina when WRITE_DATA_WIDTH_A
	                                       // is 32, wea would be 4'b0010.

	      .web(web)                        // WRITE_DATA_WIDTH_B/BYTE_WRITE_WIDTH_B-bit input: Write enable vector
	                                       // for port B input data port dinb. 1 bit wide when word-wide writes are
	                                       // used. In byte-wide write configurations, each bit controls the
	                                       // writing one byte of dinb to address addrb. For example, to
	                                       // synchronously write only bits [15-8] of dinb when WRITE_DATA_WIDTH_B
	                                       // is 32, web would be 4'b0010.

	   );

	   // End of xpm_memory_tdpram_inst instantiation
end
endgenerate
				
endmodule
