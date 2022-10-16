// ============================================================================
//        __
//   \\__/ o\    (C) 2018-2022  Robert Finch, Waterloo
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
module rfTextCharRam(clk_i, cs_i, we_i, sel_i, adr_i, dat_i, dat_o, dot_clk_i, ce_i,
  fontAddress_i, char_code_i, maxScanpix_i, maxscanline_i, scanline_i, bmp_o);
parameter pFontFile = "char_bitmaps_12x18.mem";
input clk_i;
input cs_i;
input we_i;
input [7:0] sel_i;
input [15:3] adr_i;
input [63:0] dat_i;
output [63:0] dat_o;
input dot_clk_i;
input ce_i;
input [15:0] fontAddress_i;
input [12:0] char_code_i;
input [5:0] maxScanpix_i;
input [5:0] maxscanline_i;
input [5:0] scanline_i;
output reg [63:0] bmp_o;

wire [63:0] memo;
reg [15:0] rcc, rcc0, rcc1, rcc2, rcc3;
reg [2:0] rcc200, rcc201, rcc202;
reg [1:0] bndx;
reg [63:0] bmp1;
//reg [7:0] bmp [0:7];

wire pe_cs;
edge_det ued1 (.rst(1'b0), .clk(clk_i), .ce(1'b1), .i(cs_i), .pe(pe_cs), .ne(), .ee());

reg [7:0] wea;
always_comb
	wea <= {8{we_i}} & sel_i;

// xpm_memory_tdpram: True Dual Port RAM
// Xilinx Parameterized Macro, version 2020.2
`ifdef VENDOR_XILINX

	xpm_memory_tdpram #(
	  .ADDR_WIDTH_A(13),
	  .ADDR_WIDTH_B(13),
	  .AUTO_SLEEP_TIME(0),
	  .BYTE_WRITE_WIDTH_A(8),
	  .BYTE_WRITE_WIDTH_B(8),
	  .CASCADE_HEIGHT(0),
	  .CLOCKING_MODE("independent_clock"), // String
	  .ECC_MODE("no_ecc"),            // String
	  .MEMORY_INIT_FILE(pFontFile),	  // String
	  .MEMORY_INIT_PARAM(""),        // String
	  .MEMORY_OPTIMIZATION("true"),   // String
	  .MEMORY_PRIMITIVE("block"),      // String
	  .MEMORY_SIZE(524288),
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

	  .douta(dat_o),                   // READ_DATA_WIDTH_A-bit output: Data output for port A read operations.
	  .doutb(memo),                    // READ_DATA_WIDTH_B-bit output: Data output for port B read operations.
	  .sbiterra(),             // 1-bit output: Status signal to indicate single bit error occurrence
	                                   // on the data output of port A.

	  .sbiterrb(),             // 1-bit output: Status signal to indicate single bit error occurrence
	                                   // on the data output of port B.

	  .addra(adr_i),                   // ADDR_WIDTH_A-bit input: Address for port A write and read operations.
	  .addrb(rcc3[15:3]),               // ADDR_WIDTH_B-bit input: Address for port B write and read operations.
	  .clka(clk_i),                     // 1-bit input: Clock signal for port A. Also clocks port B when
	                                   // parameter CLOCKING_MODE is "common_clock".

	  .clkb(~dot_clk_i),               // 1-bit input: Clock signal for port B when parameter CLOCKING_MODE is
	                                   // "independent_clock". Unused when parameter CLOCKING_MODE is
	                                   // "common_clock".

	  .dina(dat_i),                     // WRITE_DATA_WIDTH_A-bit input: Data input for port A write operations.
	  .dinb(64'h0),                     // WRITE_DATA_WIDTH_B-bit input: Data input for port B write operations.
	  .ena(cs_i),                       // 1-bit input: Memory enable signal for port A. Must be high on clock
	                                   // cycles when read or write operations are initiated. Pipelined
	                                   // internally.

	  .enb(~bndx[1]),                  // 1-bit input: Memory enable signal for port B. Must be high on clock
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

	  .regcea(cs_i),                 // 1-bit input: Clock Enable for the last register stage on the output
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
	  .wea(wea),         							// WRITE_DATA_WIDTH_A/BYTE_WRITE_WIDTH_A-bit input: Write enable vector
	                                   // for port A input data port dina. 1 bit wide when word-wide writes are
	                                   // used. In byte-wide write configurations, each bit controls the
	                                   // writing one byte of dina to address addra. For example, to
	                                   // synchronously write only bits [15-8] of dina when WRITE_DATA_WIDTH_A
	                                   // is 32, wea would be 4'b0010.

	  .web(8'h00)                      // WRITE_DATA_WIDTH_B/BYTE_WRITE_WIDTH_B-bit input: Write enable vector
	                                   // for port B input data port dinb. 1 bit wide when word-wide writes are
	                                   // used. In byte-wide write configurations, each bit controls the
	                                   // writing one byte of dinb to address addrb. For example, to
	                                   // synchronously write only bits [15-8] of dinb when WRITE_DATA_WIDTH_B
	                                   // is 32, web would be 4'b0010.

	);

`elsif VENDOR_ALTERA
	genvar g;
	generate begin : gAlteraRAM
		for (g = 0; g < 8; g = g + 1) begin
	    ALTSYNCRAM #(
	      .OPERATION_MODE("DUAL_PORT"),
	      .WIDTH_A(8),
	      .WIDTHAD_A(13),
	      .WIDTH_B(8),
	      .WIDTHAD_B(13),
	      .READ_DURING_WRITE_MIXED_PORTS("DONT_CARE")
	    ) charram0 (
	      .clock0(clk_i),
	      .clock1(clk_i),

	      // Write port
	      .wren_a(we_i & sel_i[g]),
	      .address_a(adr_i),
	      .data_a(dat_i[g*8+7:g*8]),
	      .q_a(),

	      // Read port
	      .rden_b(1'b1),
	      .address_b(adr_i),
	      .q_b(dat_o[g*8+7:g*8])
	    );
	    ALTSYNCRAM #(
	      .OPERATION_MODE("DUAL_PORT"),
	      .WIDTH_A(8),
	      .WIDTHAD_A(13),
	      .WIDTH_B(8),
	      .WIDTHAD_B(13),
	      .READ_DURING_WRITE_MIXED_PORTS("DONT_CARE")
	    ) charram1 (
	      .clock0(clk_i),
	      .clock1(~dot_clk_i),

	      // Write port
	      .wren_a(we_i & sel_i[g]),
	      .address_a(adr_i),
	      .data_a(dat_i[g*8+7:g*8]),
	      .q_a(),

	      // Read port
	      .rden_b(1'b1),
	      .address_b(rcc3[15:3]),
	      .q_b(memo[g*8+7:g*8])
	    );
	  end
	end
	endgenerate
`else
	/* ToDo: implement the rest of this */
	reg [63:0] mem [0:8191];
	always_ff @(posedge clk_i)
		begin
		end
	always_comb
	begin
		$display("No RAM vendor selected.");
		$finish();
	end
`endif

reg [3:0] scan_width;	// scan width in bytes rounded up
always_comb
	scan_width = maxScanpix_i[5:3] + |maxScanpix_i[2:0];
reg [9:0] char_size;	// character size in bytes
always_comb
	char_size = maxscanline_i * scan_width;
reg [6:0] char_size8;	// character size in octa-bytes
always_comb
	char_size8 = char_size[9:3] + |char_size[2:0];
	
// Char code is already delated two clocks relative to ce
// Assume that characters are always going to be at least four clocks wide.
// Clock #0
always_ff @(posedge dot_clk_i)
  if (ce_i)
    rcc <= char_code_i*{char_size8,3'b0}+scanline_i*scan_width;
// Provide some pipeline stages for the previous multiplies and adds
// Clock #1
always_ff @(posedge dot_clk_i)
	rcc0 <= rcc;
always_ff @(posedge dot_clk_i)
	rcc1 <= rcc0;
always_ff @(posedge dot_clk_i)
	rcc2 <= rcc1;
// Clock #2
always_ff @(posedge dot_clk_i)
  if (ce_i) begin
    rcc3 <= {fontAddress_i[15:3],3'b0}+rcc2;
    bndx <= 'd0;
  end
  else begin
  	case(bndx)
  	2'd0:	bmp1 <= memo >> {rcc3[2:0],3'b0};									// right half
  	2'd1:	bmp1 <= (memo << {4'd8-rcc3[2:0],3'b0}) | bmp1;		// left half
		default:	;
		endcase
		if (bndx < 2'd2)
			bndx <= bndx + 2'd1;
		rcc3 <= rcc3 + 4'd8;
  	/*
    if (bndx[2:0] <= maxScanpix_i[5:3]) begin
      bmp[bndx[2:0]] <= memo8;
      rcc1 <= rcc1 + 1'd1;
      bndx <= bndx + 1'd1;
    end
    */
  end
always @(posedge dot_clk_i)
  if (ce_i)
 	  bmp_o <= bmp1;//{bmp[7],bmp[6],bmp[5],bmp[4],bmp[3],bmp[2],bmp[1],bmp[0]};

endmodule
