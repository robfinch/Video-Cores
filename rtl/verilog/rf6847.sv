`timescale 1ns / 1ps
// ============================================================================
//        __
//   \\__/ o\    (C) 2024  Robert Finch, Waterloo
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
// Features:
//	50x25 alphanumeric display	(8x12 char bitmaps)
//	100x100, 200x100, 200x150, 200x300, 400x300	(full graphics mode)
// ============================================================================

import const_pkg::*;

//`define VGA_800x600	1
`define WXGA_1366x768	1
//`define vga640x480	1

module rf6847(rst, clk, dot_clk, css, ag, as, inv, intext, gm0, gm1, gm2,
	leg, s_cs, s_rw, s_adr, s_dat_i, s_dat_o, m_adr, m_charrom_adr, m_dat_i,
	rst_busy, frame_cnt, hsync, vsync, blank, rgb, vbl_irq);
input rst;
input clk;							// CPU bus clock
input dot_clk;					// pixel clock	(21.4286 MHz)
input css;							// color set select
input ag;								// alpha(0)/graphics(1)
input as;								// alpha(0)/semi-graphics(1)
input inv;							// invert alphanumerics
input intext;						// internal(0) / external char rom(1)
input gm0;							// graphics mode select
input gm1;
input gm2;
input leg;							// legacy operation
input s_cs;							// circuit select
input s_rw;							// read(1)/write(0)
input [13:0] s_adr;
input [7:0] s_dat_i;
output reg [7:0] s_dat_o;
output reg [13:0] m_adr;
output reg [11:0] m_charrom_adr;
input [7:0] m_dat_i;		// external char ROM input
output reg rst_busy;		// device is busy resetting
output [5:0] frame_cnt;	// frame counter
output reg hsync;
output reg vsync;
output reg blank;
output reg [23:0] rgb;
output reg vbl_irq;			// vertical blank

reg iinv;
reg iag;
reg ias;
reg iintext;

reg por;
reg [7:0] ctrl_adr;
reg [7:0] ctrl_map;
reg [13:0] ma,ma2;
reg [3:0] ra;						// scan line (row address)
reg [7:0] mem [0:16383];
reg [7:0] charrom [0:4095];
reg [7:0] charno;				// character number
reg [11:0] charrom_adr;
reg dots16;
reg char_en;

wire clka = dot_clk;
wire clkb = dot_clk;
wire rsta = rst;
wire rstb = rst;
wire [7:0] dispmem_outa;
wire [7:0] dispmem_outb;
wire [7:0] charrom_outa;
wire [7:0] charrom_outb;
wire [26:0] lfsr1_o;
lfsr27 #(.WID(27)) ulfsr1(rst, dot_clk, 1'b1, 1'b0, lfsr1_o);
wire [7:0] dispmem_dinb = lfsr1_o[6:0];

reg border,border2;
wire [11:0] hCtr, vCtr;

always_comb
	iinv = inv;
always_comb
	iag = ag;
always_comb
	ias = as;
always_comb
	iintext = intext;
always_comb
	m_adr = ma;
always_comb
	m_charrom_adr = charrom_adr;
always_comb
	rst_busy = por;

// XPM_MEMORY instantiation template for True Dual Port RAM configurations
// Refer to the targeted device family architecture libraries guide for XPM_MEMORY documentation
// =======================================================================================================================

// Parameter usage table, organized as follows:
// +---------------------------------------------------------------------------------------------------------------------+
// | Parameter name       | Data type          | Restrictions, if applicable                                             |
// |---------------------------------------------------------------------------------------------------------------------|
// | Description                                                                                                         |
// +---------------------------------------------------------------------------------------------------------------------+
// +---------------------------------------------------------------------------------------------------------------------+
// | ADDR_WIDTH_A         | Integer            | Range: 1 - 20. Default value = 6.                                       |
// |---------------------------------------------------------------------------------------------------------------------|
// | Specify the width of the port A address port addra, in bits.                                                        |
// | Must be large enough to access the entire memory from port A, i.e. &gt;= $clog2(MEMORY_SIZE/[WRITE|READ]_DATA_WIDTH_A).|
// +---------------------------------------------------------------------------------------------------------------------+
// | ADDR_WIDTH_B         | Integer            | Range: 1 - 20. Default value = 6.                                       |
// |---------------------------------------------------------------------------------------------------------------------|
// | Specify the width of the port B address port addrb, in bits.                                                        |
// | Must be large enough to access the entire memory from port B, i.e. &gt;= $clog2(MEMORY_SIZE/[WRITE|READ]_DATA_WIDTH_B).|
// +---------------------------------------------------------------------------------------------------------------------+
// | AUTO_SLEEP_TIME      | Integer            | Range: 0 - 15. Default value = 0.                                       |
// |---------------------------------------------------------------------------------------------------------------------|
// | Number of clk[a|b] cycles to auto-sleep, if feature is available in architecture                                    |
// | 0 - Disable auto-sleep feature                                                                                      |
// | 3-15 - Number of auto-sleep latency cycles                                                                          |
// | Do not change from the value provided in the template instantiation                                                 |
// +---------------------------------------------------------------------------------------------------------------------+
// | BYTE_WRITE_WIDTH_A   | Integer            | Range: 1 - 4608. Default value = 32.                                    |
// |---------------------------------------------------------------------------------------------------------------------|
// | To enable byte-wide writes on port A, specify the byte width, in bits-                                              |
// | 8- 8-bit byte-wide writes, legal when WRITE_DATA_WIDTH_A is an integer multiple of 8                                |
// | 9- 9-bit byte-wide writes, legal when WRITE_DATA_WIDTH_A is an integer multiple of 9                                |
// | Or to enable word-wide writes on port A, specify the same value as for WRITE_DATA_WIDTH_A.                          |
// +---------------------------------------------------------------------------------------------------------------------+
// | BYTE_WRITE_WIDTH_B   | Integer            | Range: 1 - 4608. Default value = 32.                                    |
// |---------------------------------------------------------------------------------------------------------------------|
// | To enable byte-wide writes on port B, specify the byte width, in bits-                                              |
// | 8- 8-bit byte-wide writes, legal when WRITE_DATA_WIDTH_B is an integer multiple of 8                                |
// | 9- 9-bit byte-wide writes, legal when WRITE_DATA_WIDTH_B is an integer multiple of 9                                |
// | Or to enable word-wide writes on port B, specify the same value as for WRITE_DATA_WIDTH_B.                          |
// +---------------------------------------------------------------------------------------------------------------------+
// | CASCADE_HEIGHT       | Integer            | Range: 0 - 64. Default value = 0.                                       |
// |---------------------------------------------------------------------------------------------------------------------|
// | 0- No Cascade Height, Allow Vivado Synthesis to choose.                                                             |
// | 1 or more - Vivado Synthesis sets the specified value as Cascade Height.                                            |
// +---------------------------------------------------------------------------------------------------------------------+
// | CLOCKING_MODE        | String             | Allowed values: common_clock, independent_clock. Default value = common_clock.|
// |---------------------------------------------------------------------------------------------------------------------|
// | Designate whether port A and port B are clocked with a common clock or with independent clocks-                     |
// | "common_clock"- Common clocking; clock both port A and port B with clka                                             |
// | "independent_clock"- Independent clocking; clock port A with clka and port B with clkb                              |
// +---------------------------------------------------------------------------------------------------------------------+
// | ECC_MODE             | String             | Allowed values: no_ecc, both_encode_and_decode, decode_only, encode_only. Default value = no_ecc.|
// |---------------------------------------------------------------------------------------------------------------------|
// |                                                                                                                     |
// |   "no_ecc" - Disables ECC                                                                                           |
// |   "encode_only" - Enables ECC Encoder only                                                                          |
// |   "decode_only" - Enables ECC Decoder only                                                                          |
// |   "both_encode_and_decode" - Enables both ECC Encoder and Decoder                                                   |
// +---------------------------------------------------------------------------------------------------------------------+
// | MEMORY_INIT_FILE     | String             | Default value = none.                                                   |
// |---------------------------------------------------------------------------------------------------------------------|
// | Specify "none" (including quotes) for no memory initialization, or specify the name of a memory initialization file-|
// | Enter only the name of the file with .mem extension, including quotes but without path (e.g. "my_file.mem").        |
// | File format must be ASCII and consist of only hexadecimal values organized into the specified depth by              |
// | narrowest data width generic value of the memory. Initialization of memory happens through the file name specified only when parameter|
// | MEMORY_INIT_PARAM value is equal to "". |                                                                           |
// | When using XPM_MEMORY in a project, add the specified file to the Vivado project as a design source.                |
// +---------------------------------------------------------------------------------------------------------------------+
// | MEMORY_INIT_PARAM    | String             | Default value = 0.                                                      |
// |---------------------------------------------------------------------------------------------------------------------|
// | Specify "" or "0" (including quotes) for no memory initialization through parameter, or specify the string          |
// | containing the hex characters. Enter only hex characters with each location separated by delimiter (,).             |
// | Parameter format must be ASCII and consist of only hexadecimal values organized into the specified depth by         |
// | narrowest data width generic value of the memory.For example, if the narrowest data width is 8, and the depth of    |
// | memory is 8 locations, then the parameter value should be passed as shown below.                                    |
// | parameter MEMORY_INIT_PARAM = "AB,CD,EF,1,2,34,56,78"                                                               |
// | Where "AB" is the 0th location and "78" is the 7th location.                                                        |
// +---------------------------------------------------------------------------------------------------------------------+
// | MEMORY_OPTIMIZATION  | String             | Allowed values: true, false. Default value = true.                      |
// |---------------------------------------------------------------------------------------------------------------------|
// | Specify "true" to enable the optimization of unused memory or bits in the memory structure. Specify "false" to      |
// | disable the optimization of unused memory or bits in the memory structure.                                          |
// +---------------------------------------------------------------------------------------------------------------------+
// | MEMORY_PRIMITIVE     | String             | Allowed values: auto, block, distributed, mixed, ultra. Default value = auto.|
// |---------------------------------------------------------------------------------------------------------------------|
// | Designate the memory primitive (resource type) to use-                                                              |
// | "auto"- Allow Vivado Synthesis to choose                                                                            |
// | "distributed"- Distributed memory                                                                                   |
// | "block"- Block memory                                                                                               |
// | "ultra"- Ultra RAM memory                                                                                           |
// | "mixed"- Mixed memory                                                                                               |
// | NOTE: There may be a behavior mismatch if Block RAM or Ultra RAM specific features, like ECC or Asymmetry, are selected with MEMORY_PRIMITIVE set to "auto".|
// +---------------------------------------------------------------------------------------------------------------------+
// | MEMORY_SIZE          | Integer            | Range: 2 - 150994944. Default value = 2048.                             |
// |---------------------------------------------------------------------------------------------------------------------|
// | Specify the total memory array size, in bits.                                                                       |
// | For example, enter 65536 for a 2kx32 RAM.                                                                           |
// | When ECC is enabled and set to "encode_only", then the memory size has to be multiples of READ_DATA_WIDTH_[A|B]     |
// | When ECC is enabled and set to "decode_only", then the memory size has to be multiples of WRITE_DATA_WIDTH_[A|B].   |
// +---------------------------------------------------------------------------------------------------------------------+
// | MESSAGE_CONTROL      | Integer            | Range: 0 - 1. Default value = 0.                                        |
// |---------------------------------------------------------------------------------------------------------------------|
// | Specify 1 to enable the dynamic message reporting such as collision warnings, and 0 to disable the message reporting|
// +---------------------------------------------------------------------------------------------------------------------+
// | READ_DATA_WIDTH_A    | Integer            | Range: 1 - 4608. Default value = 32.                                    |
// |---------------------------------------------------------------------------------------------------------------------|
// | Specify the width of the port A read data output port douta, in bits.                                               |
// | The values of READ_DATA_WIDTH_A and WRITE_DATA_WIDTH_A must be equal.                                               |
// | When ECC is enabled and set to "encode_only", then READ_DATA_WIDTH_A has to be multiples of 72-bits                 |
// | When ECC is enabled and set to "decode_only" or "both_encode_and_decode", then READ_DATA_WIDTH_A has to be          |
// | multiples of 64-bits.                                                                                               |
// +---------------------------------------------------------------------------------------------------------------------+
// | READ_DATA_WIDTH_B    | Integer            | Range: 1 - 4608. Default value = 32.                                    |
// |---------------------------------------------------------------------------------------------------------------------|
// | Specify the width of the port B read data output port doutb, in bits.                                               |
// | The values of READ_DATA_WIDTH_B and WRITE_DATA_WIDTH_B must be equal.                                               |
// | When ECC is enabled and set to "encode_only", then READ_DATA_WIDTH_B has to be multiples of 72-bits                 |
// | When ECC is enabled and set to "decode_only" or "both_encode_and_decode", then READ_DATA_WIDTH_B has to be          |
// | multiples of 64-bits.                                                                                               |
// +---------------------------------------------------------------------------------------------------------------------+
// | READ_LATENCY_A       | Integer            | Range: 0 - 100. Default value = 2.                                      |
// |---------------------------------------------------------------------------------------------------------------------|
// | Specify the number of register stages in the port A read data pipeline. Read data output to port douta takes this   |
// | number of clka cycles.                                                                                              |
// | To target block memory, a value of 1 or larger is required- 1 causes use of memory latch only; 2 causes use of      |
// | output register. To target distributed memory, a value of 0 or larger is required- 0 indicates combinatorial output.|
// | Values larger than 2 synthesize additional flip-flops that are not retimed into memory primitives.                  |
// +---------------------------------------------------------------------------------------------------------------------+
// | READ_LATENCY_B       | Integer            | Range: 0 - 100. Default value = 2.                                      |
// |---------------------------------------------------------------------------------------------------------------------|
// | Specify the number of register stages in the port B read data pipeline. Read data output to port doutb takes this   |
// | number of clkb cycles (clka when CLOCKING_MODE is "common_clock").                                                  |
// | To target block memory, a value of 1 or larger is required- 1 causes use of memory latch only; 2 causes use of      |
// | output register. To target distributed memory, a value of 0 or larger is required- 0 indicates combinatorial output.|
// | Values larger than 2 synthesize additional flip-flops that are not retimed into memory primitives.                  |
// +---------------------------------------------------------------------------------------------------------------------+
// | READ_RESET_VALUE_A   | String             | Default value = 0.                                                      |
// |---------------------------------------------------------------------------------------------------------------------|
// | Specify the reset value of the port A final output register stage in response to rsta input port is assertion.      |
// | As this parameter is a string, please specify the hex values inside double quotes. As an example,                   |
// | If the read data width is 8, then specify READ_RESET_VALUE_A = "EA";                                                |
// | When ECC is enabled, then reset value is not supported.                                                             |
// +---------------------------------------------------------------------------------------------------------------------+
// | READ_RESET_VALUE_B   | String             | Default value = 0.                                                      |
// |---------------------------------------------------------------------------------------------------------------------|
// | Specify the reset value of the port B final output register stage in response to rstb input port is assertion.      |
// | As this parameter is a string, please specify the hex values inside double quotes. As an example,                   |
// | If the read data width is 8, then specify READ_RESET_VALUE_B = "EA";                                                |
// | When ECC is enabled, then reset value is not supported.                                                             |
// +---------------------------------------------------------------------------------------------------------------------+
// | RST_MODE_A           | String             | Allowed values: SYNC, ASYNC. Default value = SYNC.                      |
// |---------------------------------------------------------------------------------------------------------------------|
// | Describes the behaviour of the reset                                                                                |
// |                                                                                                                     |
// |   "SYNC" - when reset is applied, synchronously resets output port douta to the value specified by parameter READ_RESET_VALUE_A|
// |   "ASYNC" - when reset is applied, asynchronously resets output port douta to zero                                  |
// +---------------------------------------------------------------------------------------------------------------------+
// | RST_MODE_B           | String             | Allowed values: SYNC, ASYNC. Default value = SYNC.                      |
// |---------------------------------------------------------------------------------------------------------------------|
// | Describes the behaviour of the reset                                                                                |
// |                                                                                                                     |
// |   "SYNC" - when reset is applied, synchronously resets output port doutb to the value specified by parameter READ_RESET_VALUE_B|
// |   "ASYNC" - when reset is applied, asynchronously resets output port doutb to zero                                  |
// +---------------------------------------------------------------------------------------------------------------------+
// | SIM_ASSERT_CHK       | Integer            | Range: 0 - 1. Default value = 0.                                        |
// |---------------------------------------------------------------------------------------------------------------------|
// | 0- Disable simulation message reporting. Messages related to potential misuse will not be reported.                 |
// | 1- Enable simulation message reporting. Messages related to potential misuse will be reported.                      |
// +---------------------------------------------------------------------------------------------------------------------+
// | USE_EMBEDDED_CONSTRAINT| Integer            | Range: 0 - 1. Default value = 0.                                        |
// |---------------------------------------------------------------------------------------------------------------------|
// | Specify 1 to enable the set_false_path constraint addition between clka of Distributed RAM and doutb_reg on clkb    |
// +---------------------------------------------------------------------------------------------------------------------+
// | USE_MEM_INIT         | Integer            | Range: 0 - 1. Default value = 1.                                        |
// |---------------------------------------------------------------------------------------------------------------------|
// | Specify 1 to enable the generation of below message and 0 to disable generation of the following message completely.|
// | "INFO - MEMORY_INIT_FILE and MEMORY_INIT_PARAM together specifies no memory initialization.                         |
// | Initial memory contents will be all 0s."                                                                            |
// | NOTE: This message gets generated only when there is no Memory Initialization specified either through file or      |
// | Parameter.                                                                                                          |
// +---------------------------------------------------------------------------------------------------------------------+
// | USE_MEM_INIT_MMI     | Integer            | Range: 0 - 1. Default value = 0.                                        |
// |---------------------------------------------------------------------------------------------------------------------|
// | Specify 1 to expose this memory information to be written out in the MMI file.                                      |
// +---------------------------------------------------------------------------------------------------------------------+
// | WAKEUP_TIME          | String             | Allowed values: disable_sleep, use_sleep_pin. Default value = disable_sleep.|
// |---------------------------------------------------------------------------------------------------------------------|
// | Specify "disable_sleep" to disable dynamic power saving option, and specify "use_sleep_pin" to enable the           |
// | dynamic power saving option                                                                                         |
// +---------------------------------------------------------------------------------------------------------------------+
// | WRITE_DATA_WIDTH_A   | Integer            | Range: 1 - 4608. Default value = 32.                                    |
// |---------------------------------------------------------------------------------------------------------------------|
// | Specify the width of the port A write data input port dina, in bits.                                                |
// | The values of WRITE_DATA_WIDTH_A and READ_DATA_WIDTH_A must be equal.                                               |
// | When ECC is enabled and set to "encode_only" or "both_encode_and_decode", then WRITE_DATA_WIDTH_A has to be         |
// | multiples of 64-bits                                                                                                |
// | When ECC is enabled and set to "decode_only", then WRITE_DATA_WIDTH_A has to be multiples of 72-bits.               |
// +---------------------------------------------------------------------------------------------------------------------+
// | WRITE_DATA_WIDTH_B   | Integer            | Range: 1 - 4608. Default value = 32.                                    |
// |---------------------------------------------------------------------------------------------------------------------|
// | Specify the width of the port B write data input port dinb, in bits.                                                |
// | The values of WRITE_DATA_WIDTH_B and READ_DATA_WIDTH_B must be equal.                                               |
// | When ECC is enabled and set to "encode_only" or "both_encode_and_decode", then WRITE_DATA_WIDTH_B has to be         |
// | multiples of 64-bits                                                                                                |
// | When ECC is enabled and set to "decode_only", then WRITE_DATA_WIDTH_B has to be multiples of 72-bits.               |
// +---------------------------------------------------------------------------------------------------------------------+
// | WRITE_MODE_A         | String             | Allowed values: no_change, read_first, write_first. Default value = no_change.|
// |---------------------------------------------------------------------------------------------------------------------|
// | Write mode behavior for port A output data port, douta.                                                             |
// +---------------------------------------------------------------------------------------------------------------------+
// | WRITE_MODE_B         | String             | Allowed values: no_change, read_first, write_first. Default value = no_change.|
// |---------------------------------------------------------------------------------------------------------------------|
// | Write mode behavior for port B output data port, doutb.                                                             |
// +---------------------------------------------------------------------------------------------------------------------+
// | WRITE_PROTECT        | Integer            | Range: 0 - 1. Default value = 1.                                        |
// |---------------------------------------------------------------------------------------------------------------------|
// | Default value is 1, means write is protected through enable and write enable and hence the LUT is placed before the memory. This is the default behaviour to access memory.|
// | When 0, disables write protection. Write enable (WE) directly connected to memory.                                  |
// | NOTE: Disable this option only if the advanced users can guarantee that the write enable (WE) cannot be given without enable (EN).|
// +---------------------------------------------------------------------------------------------------------------------+

// Port usage table, organized as follows:
// +---------------------------------------------------------------------------------------------------------------------+
// | Port name      | Direction | Size, in bits                         | Domain  | Sense       | Handling if unused     |
// |---------------------------------------------------------------------------------------------------------------------|
// | Description                                                                                                         |
// +---------------------------------------------------------------------------------------------------------------------+
// +---------------------------------------------------------------------------------------------------------------------+
// | addra          | Input     | ADDR_WIDTH_A                          | clka    | NA          | Required               |
// |---------------------------------------------------------------------------------------------------------------------|
// | Address for port A write and read operations.                                                                       |
// +---------------------------------------------------------------------------------------------------------------------+
// | addrb          | Input     | ADDR_WIDTH_B                          | clkb    | NA          | Required               |
// |---------------------------------------------------------------------------------------------------------------------|
// | Address for port B write and read operations.                                                                       |
// +---------------------------------------------------------------------------------------------------------------------+
// | clka           | Input     | 1                                     | NA      | Rising edge | Required               |
// |---------------------------------------------------------------------------------------------------------------------|
// | Clock signal for port A. Also clocks port B when parameter CLOCKING_MODE is "common_clock".                         |
// +---------------------------------------------------------------------------------------------------------------------+
// | clkb           | Input     | 1                                     | NA      | Rising edge | Required               |
// |---------------------------------------------------------------------------------------------------------------------|
// | Clock signal for port B when parameter CLOCKING_MODE is "independent_clock".                                        |
// | Unused when parameter CLOCKING_MODE is "common_clock".                                                              |
// +---------------------------------------------------------------------------------------------------------------------+
// | dbiterra       | Output    | 1                                     | clka    | Active-high | DoNotCare              |
// |---------------------------------------------------------------------------------------------------------------------|
// | Status signal to indicate double bit error occurrence on the data output of port A.                                 |
// +---------------------------------------------------------------------------------------------------------------------+
// | dbiterrb       | Output    | 1                                     | clkb    | Active-high | DoNotCare              |
// |---------------------------------------------------------------------------------------------------------------------|
// | Status signal to indicate double bit error occurrence on the data output of port A.                                 |
// +---------------------------------------------------------------------------------------------------------------------+
// | dina           | Input     | WRITE_DATA_WIDTH_A                    | clka    | NA          | Required               |
// |---------------------------------------------------------------------------------------------------------------------|
// | Data input for port A write operations.                                                                             |
// +---------------------------------------------------------------------------------------------------------------------+
// | dinb           | Input     | WRITE_DATA_WIDTH_B                    | clkb    | NA          | Required               |
// |---------------------------------------------------------------------------------------------------------------------|
// | Data input for port B write operations.                                                                             |
// +---------------------------------------------------------------------------------------------------------------------+
// | douta          | Output    | READ_DATA_WIDTH_A                     | clka    | NA          | Required               |
// |---------------------------------------------------------------------------------------------------------------------|
// | Data output for port A read operations.                                                                             |
// +---------------------------------------------------------------------------------------------------------------------+
// | doutb          | Output    | READ_DATA_WIDTH_B                     | clkb    | NA          | Required               |
// |---------------------------------------------------------------------------------------------------------------------|
// | Data output for port B read operations.                                                                             |
// +---------------------------------------------------------------------------------------------------------------------+
// | ena            | Input     | 1                                     | clka    | Active-high | Required               |
// |---------------------------------------------------------------------------------------------------------------------|
// | Memory enable signal for port A.                                                                                    |
// | Must be high on clock cycles when read or write operations are initiated. Pipelined internally.                     |
// +---------------------------------------------------------------------------------------------------------------------+
// | enb            | Input     | 1                                     | clkb    | Active-high | Required               |
// |---------------------------------------------------------------------------------------------------------------------|
// | Memory enable signal for port B.                                                                                    |
// | Must be high on clock cycles when read or write operations are initiated. Pipelined internally.                     |
// +---------------------------------------------------------------------------------------------------------------------+
// | injectdbiterra | Input     | 1                                     | clka    | Active-high | Tie to 1'b0            |
// |---------------------------------------------------------------------------------------------------------------------|
// | Controls double bit error injection on input data when ECC enabled (Error injection capability is not available in  |
// | "decode_only" mode).                                                                                                |
// +---------------------------------------------------------------------------------------------------------------------+
// | injectdbiterrb | Input     | 1                                     | clkb    | Active-high | Tie to 1'b0            |
// |---------------------------------------------------------------------------------------------------------------------|
// | Controls double bit error injection on input data when ECC enabled (Error injection capability is not available in  |
// | "decode_only" mode).                                                                                                |
// +---------------------------------------------------------------------------------------------------------------------+
// | injectsbiterra | Input     | 1                                     | clka    | Active-high | Tie to 1'b0            |
// |---------------------------------------------------------------------------------------------------------------------|
// | Controls single bit error injection on input data when ECC enabled (Error injection capability is not available in  |
// | "decode_only" mode).                                                                                                |
// +---------------------------------------------------------------------------------------------------------------------+
// | injectsbiterrb | Input     | 1                                     | clkb    | Active-high | Tie to 1'b0            |
// |---------------------------------------------------------------------------------------------------------------------|
// | Controls single bit error injection on input data when ECC enabled (Error injection capability is not available in  |
// | "decode_only" mode).                                                                                                |
// +---------------------------------------------------------------------------------------------------------------------+
// | regcea         | Input     | 1                                     | clka    | Active-high | Tie to 1'b1            |
// |---------------------------------------------------------------------------------------------------------------------|
// | Clock Enable for the last register stage on the output data path.                                                   |
// +---------------------------------------------------------------------------------------------------------------------+
// | regceb         | Input     | 1                                     | clkb    | Active-high | Tie to 1'b1            |
// |---------------------------------------------------------------------------------------------------------------------|
// | Clock Enable for the last register stage on the output data path.                                                   |
// +---------------------------------------------------------------------------------------------------------------------+
// | rsta           | Input     | 1                                     | clka    | Active-high | Required               |
// |---------------------------------------------------------------------------------------------------------------------|
// | Reset signal for the final port A output register stage.                                                            |
// | Synchronously resets output port douta to the value specified by parameter READ_RESET_VALUE_A.                      |
// +---------------------------------------------------------------------------------------------------------------------+
// | rstb           | Input     | 1                                     | clkb    | Active-high | Required               |
// |---------------------------------------------------------------------------------------------------------------------|
// | Reset signal for the final port B output register stage.                                                            |
// | Synchronously resets output port doutb to the value specified by parameter READ_RESET_VALUE_B.                      |
// +---------------------------------------------------------------------------------------------------------------------+
// | sbiterra       | Output    | 1                                     | clka    | Active-high | DoNotCare              |
// |---------------------------------------------------------------------------------------------------------------------|
// | Status signal to indicate single bit error occurrence on the data output of port A.                                 |
// +---------------------------------------------------------------------------------------------------------------------+
// | sbiterrb       | Output    | 1                                     | clkb    | Active-high | DoNotCare              |
// |---------------------------------------------------------------------------------------------------------------------|
// | Status signal to indicate single bit error occurrence on the data output of port B.                                 |
// +---------------------------------------------------------------------------------------------------------------------+
// | sleep          | Input     | 1                                     | NA      | Active-high | Tie to 1'b0            |
// |---------------------------------------------------------------------------------------------------------------------|
// | sleep signal to enable the dynamic power saving feature.                                                            |
// +---------------------------------------------------------------------------------------------------------------------+
// | wea            | Input     | WRITE_DATA_WIDTH_A/BYTE_WRITE_WIDTH_A | clka    | Active-high | Required               |
// |---------------------------------------------------------------------------------------------------------------------|
// | Write enable vector for port A input data port dina. 1 bit wide when word-wide writes are used.                     |
// | In byte-wide write configurations, each bit controls the writing one byte of dina to address addra.                 |
// | For example, to synchronously write only bits [15-8] of dina when WRITE_DATA_WIDTH_A is 32, wea would be 4'b0010.   |
// +---------------------------------------------------------------------------------------------------------------------+
// | web            | Input     | WRITE_DATA_WIDTH_B/BYTE_WRITE_WIDTH_B | clkb    | Active-high | Required               |
// |---------------------------------------------------------------------------------------------------------------------|
// | Write enable vector for port B input data port dinb. 1 bit wide when word-wide writes are used.                     |
// | In byte-wide write configurations, each bit controls the writing one byte of dinb to address addrb.                 |
// | For example, to synchronously write only bits [15-8] of dinb when WRITE_DATA_WIDTH_B is 32, web would be 4'b0010.   |
// +---------------------------------------------------------------------------------------------------------------------+


// xpm_memory_tdpram : In order to incorporate this function into the design,
//      Verilog      : the following instance declaration needs to be placed
//     instance      : in the body of the design code.  The instance name
//    declaration    : (xpm_memory_tdpram_inst) and/or the port declarations within the
//       code        : parenthesis may be changed to properly reference and
//                   : connect this function to the design.  All inputs
//                   : and outputs must be connected.

//  Please reference the appropriate libraries guide for additional information on the XPM modules.

//  <-----Cut code below this line---->

   // xpm_memory_tdpram: True Dual Port RAM
   // Xilinx Parameterized Macro, version 2022.2

   xpm_memory_tdpram #(
      .ADDR_WIDTH_A(14),               // DECIMAL
      .ADDR_WIDTH_B(14),               // DECIMAL
      .AUTO_SLEEP_TIME(0),            // DECIMAL
      .BYTE_WRITE_WIDTH_A(8),        // DECIMAL
      .BYTE_WRITE_WIDTH_B(8),        // DECIMAL
      .CASCADE_HEIGHT(0),             // DECIMAL
      .CLOCKING_MODE("common_clock"), // String
      .ECC_MODE("no_ecc"),            // String
      .MEMORY_INIT_FILE("none"),      // String
      .MEMORY_INIT_PARAM("0"),        // String
      .MEMORY_OPTIMIZATION("true"),   // String
      .MEMORY_PRIMITIVE("auto"),      // String
      .MEMORY_SIZE(8*16384),          // DECIMAL
      .MESSAGE_CONTROL(0),            // DECIMAL
      .READ_DATA_WIDTH_A(8),         // DECIMAL
      .READ_DATA_WIDTH_B(8),         // DECIMAL
      .READ_LATENCY_A(1),             // DECIMAL
      .READ_LATENCY_B(1),             // DECIMAL
      .READ_RESET_VALUE_A("0"),       // String
      .READ_RESET_VALUE_B("0"),       // String
      .RST_MODE_A("SYNC"),            // String
      .RST_MODE_B("SYNC"),            // String
      .SIM_ASSERT_CHK(0),             // DECIMAL; 0=disable simulation messages, 1=enable simulation messages
      .USE_EMBEDDED_CONSTRAINT(0),    // DECIMAL
      .USE_MEM_INIT(1),               // DECIMAL
      .USE_MEM_INIT_MMI(0),           // DECIMAL
      .WAKEUP_TIME("disable_sleep"),  // String
      .WRITE_DATA_WIDTH_A(8),        // DECIMAL
      .WRITE_DATA_WIDTH_B(8),        // DECIMAL
      .WRITE_MODE_A("no_change"),     // String
      .WRITE_MODE_B("no_change"),     // String
      .WRITE_PROTECT(1)               // DECIMAL
   )
   udispmem1 (
      .dbiterra(),             // 1-bit output: Status signal to indicate double bit error occurrence
                                       // on the data output of port A.

      .dbiterrb(),             // 1-bit output: Status signal to indicate double bit error occurrence
                                       // on the data output of port A.

      .douta(dispmem_outa),                   // READ_DATA_WIDTH_A-bit output: Data output for port A read operations.
      .doutb(dispmem_outb),                   // READ_DATA_WIDTH_B-bit output: Data output for port B read operations.
      .sbiterra(),             // 1-bit output: Status signal to indicate single bit error occurrence
                                       // on the data output of port A.

      .sbiterrb(),             // 1-bit output: Status signal to indicate single bit error occurrence
                                       // on the data output of port B.

      .addra(s_adr[13:0]),                   // ADDR_WIDTH_A-bit input: Address for port A write and read operations.
      .addrb(ma[13:0]),                   // ADDR_WIDTH_B-bit input: Address for port B write and read operations.
      .clka(clka),                     // 1-bit input: Clock signal for port A. Also clocks port B when
                                       // parameter CLOCKING_MODE is "common_clock".

      .clkb(clkb),                     // 1-bit input: Clock signal for port B when parameter CLOCKING_MODE is
                                       // "independent_clock". Unused when parameter CLOCKING_MODE is
                                       // "common_clock".

      .dina(s_dat_i),                     // WRITE_DATA_WIDTH_A-bit input: Data input for port A write operations.
      .dinb(dispmem_dinb),                // WRITE_DATA_WIDTH_B-bit input: Data input for port B write operations.
      .ena(s_cs && !ctrl_map[0]),  	 // 1-bit input: Memory enable signal for port A. Must be high on clock
                                       // cycles when read or write operations are initiated. Pipelined
                                       // internally.

      .enb(1'b1),                       // 1-bit input: Memory enable signal for port B. Must be high on clock
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
      .wea(~s_rw),                       // WRITE_DATA_WIDTH_A/BYTE_WRITE_WIDTH_A-bit input: Write enable vector
                                       // for port A input data port dina. 1 bit wide when word-wide writes are
                                       // used. In byte-wide write configurations, each bit controls the
                                       // writing one byte of dina to address addra. For example, to
                                       // synchronously write only bits [15-8] of dina when WRITE_DATA_WIDTH_A
                                       // is 32, wea would be 4'b0010.

      .web(por)                        // WRITE_DATA_WIDTH_B/BYTE_WRITE_WIDTH_B-bit input: Write enable vector
                                       // for port B input data port dinb. 1 bit wide when word-wide writes are
                                       // used. In byte-wide write configurations, each bit controls the
                                       // writing one byte of dinb to address addrb. For example, to
                                       // synchronously write only bits [15-8] of dinb when WRITE_DATA_WIDTH_B
                                       // is 32, web would be 4'b0010.

   );

   // End of xpm_memory_tdpram_inst instantiation
				


// XPM_MEMORY instantiation template for True Dual Port RAM configurations
// Refer to the targeted device family architecture libraries guide for XPM_MEMORY documentation
// =======================================================================================================================

   // xpm_memory_tdpram: True Dual Port RAM
   // Xilinx Parameterized Macro, version 2022.2

   xpm_memory_tdpram #(
      .ADDR_WIDTH_A(12),               // DECIMAL
      .ADDR_WIDTH_B(12),               // DECIMAL
      .AUTO_SLEEP_TIME(0),            // DECIMAL
      .BYTE_WRITE_WIDTH_A(8),        // DECIMAL
      .BYTE_WRITE_WIDTH_B(8),        // DECIMAL
      .CASCADE_HEIGHT(0),             // DECIMAL
      .CLOCKING_MODE("common_clock"), // String
      .ECC_MODE("no_ecc"),            // String
      .MEMORY_INIT_FILE("char_bitmaps_8x12.mem"),	// String
      .MEMORY_INIT_PARAM("0"),        // String
      .MEMORY_OPTIMIZATION("true"),   // String
      .MEMORY_PRIMITIVE("auto"),      // String
      .MEMORY_SIZE(12*256*8),         // DECIMAL
      .MESSAGE_CONTROL(0),            // DECIMAL
      .READ_DATA_WIDTH_A(8),         // DECIMAL
      .READ_DATA_WIDTH_B(8),         // DECIMAL
      .READ_LATENCY_A(1),             // DECIMAL
      .READ_LATENCY_B(1),             // DECIMAL
      .READ_RESET_VALUE_A("0"),       // String
      .READ_RESET_VALUE_B("0"),       // String
      .RST_MODE_A("SYNC"),            // String
      .RST_MODE_B("SYNC"),            // String
      .SIM_ASSERT_CHK(0),             // DECIMAL; 0=disable simulation messages, 1=enable simulation messages
      .USE_EMBEDDED_CONSTRAINT(0),    // DECIMAL
      .USE_MEM_INIT(1),               // DECIMAL
      .USE_MEM_INIT_MMI(0),           // DECIMAL
      .WAKEUP_TIME("disable_sleep"),  // String
      .WRITE_DATA_WIDTH_A(8),        // DECIMAL
      .WRITE_DATA_WIDTH_B(8),        // DECIMAL
      .WRITE_MODE_A("no_change"),     // String
      .WRITE_MODE_B("no_change"),     // String
      .WRITE_PROTECT(1)               // DECIMAL
   )
   ucharrom1 (
      .dbiterra(),             // 1-bit output: Status signal to indicate double bit error occurrence
                                       // on the data output of port A.

      .dbiterrb(),             // 1-bit output: Status signal to indicate double bit error occurrence
                                       // on the data output of port A.

      .douta(charrom_outa),                   // READ_DATA_WIDTH_A-bit output: Data output for port A read operations.
      .doutb(charrom_outb),                   // READ_DATA_WIDTH_B-bit output: Data output for port B read operations.
      .sbiterra(),             // 1-bit output: Status signal to indicate single bit error occurrence
                                       // on the data output of port A.

      .sbiterrb(),             // 1-bit output: Status signal to indicate single bit error occurrence
                                       // on the data output of port B.

      .addra(s_adr[11:0]),                   // ADDR_WIDTH_A-bit input: Address for port A write and read operations.
      .addrb(charrom_adr),                   // ADDR_WIDTH_B-bit input: Address for port B write and read operations.
      .clka(clka),                     // 1-bit input: Clock signal for port A. Also clocks port B when
                                       // parameter CLOCKING_MODE is "common_clock".

      .clkb(clkb),                     // 1-bit input: Clock signal for port B when parameter CLOCKING_MODE is
                                       // "independent_clock". Unused when parameter CLOCKING_MODE is
                                       // "common_clock".

      .dina(s_dat_i),                     // WRITE_DATA_WIDTH_A-bit input: Data input for port A write operations.
      .dinb(8'h00),                     // WRITE_DATA_WIDTH_B-bit input: Data input for port B write operations.
      .ena(s_cs && ctrl_map[0]), 				// 1-bit input: Memory enable signal for port A. Must be high on clock
                                       // cycles when read or write operations are initiated. Pipelined
                                       // internally.

      .enb(1'b1),                       // 1-bit input: Memory enable signal for port B. Must be high on clock
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
      .wea(~s_rw),                       // WRITE_DATA_WIDTH_A/BYTE_WRITE_WIDTH_A-bit input: Write enable vector
                                       // for port A input data port dina. 1 bit wide when word-wide writes are
                                       // used. In byte-wide write configurations, each bit controls the
                                       // writing one byte of dina to address addra. For example, to
                                       // synchronously write only bits [15-8] of dina when WRITE_DATA_WIDTH_A
                                       // is 32, wea would be 4'b0010.

      .web(1'b0)                        // WRITE_DATA_WIDTH_B/BYTE_WRITE_WIDTH_B-bit input: Write enable vector
                                       // for port B input data port dinb. 1 bit wide when word-wide writes are
                                       // used. In byte-wide write configurations, each bit controls the
                                       // writing one byte of dinb to address addrb. For example, to
                                       // synchronously write only bits [15-8] of dinb when WRITE_DATA_WIDTH_B
                                       // is 32, web would be 4'b0010.

   );

   // End of xpm_memory_tdpram_inst instantiation
				
`ifdef VGA_800x600			
parameter phSyncOn  = 20;		//   40 front porch
parameter phSyncOff = 84;		//  128 sync
parameter phBlankOff = 126;	//256	//   88 back porch
//parameter phBorderOff = 336;	//   80 border
parameter phBorderOff = 128;	//   80 border
//parameter phBorderOn = 976;		//  640 display
parameter phBorderOn = 528;		//  800 display
parameter phBlankOn = 526;		//   4 border
parameter phTotal = 528;		// 1056 total clocks
parameter pvSyncOn  = 1;		//    1 front porch
parameter pvSyncOff = 5;		//    4 vertical sync
parameter pvBlankOff = 28;		//   23 back porch
parameter pvBorderOff = 28;		//   44 border	0
//parameter pvBorderOff = 72;		//   44 border	0
parameter pvBorderOn = 628;		//  600 display
//parameter pvBorderOn = 584;		//  512 display
parameter pvBlankOn = 628;  	//   44 border	0
parameter pvTotal = 628;		//  628 total scan lines

parameter pleghBorderOff = 198;
parameter pleghBorderOn = 454;
parameter plegvBorderOff = 136;
parameter plegvBorderOn = 520;
`endif

`ifdef WXGA_1366x768
// Needs 
//	Input clock:     85.86 MHz/4 (50 MHz * 12/7) (85.7142)/4
//	Input clock:     21.4286 MHz (100 MHz * 3/14)
//	Horizontal freq: 47.7 kHz	(generated) (47.619KHz)
//	Vertical freq:   60.00  Hz (generated)  (59.89 Hz)
parameter phSyncOn  = 18;		//   72 front porch
parameter phSyncOff = 54;		//  144 sync
parameter phBlankOff = 107;		//  212 back porch
parameter phBorderOff = 119;	//    0 border
parameter phBorderOn = 439;	// 1366 display
parameter phBlankOn = 450;		//    0 border
parameter phTotal = 450;		// 1800 total clocks
// 47.7 = 60 * 795 kHz
parameter pvSyncOn  = 2;		//    1 front porch
parameter pvSyncOff = 5;		//    3 vertical sync
parameter pvBlankOff = 27;		//   23 back porch
parameter pvBorderOff = 27;		//    2 border	0
parameter pvBorderOn = 795;		//  768 display
parameter pvBlankOn = 795;  	//    1 border	0
parameter pvTotal = 795;		//  795 total scan lines

parameter pleghBorderOff = 151;
parameter pleghBorderOn = 407;
parameter plegvBorderOff = 27;
parameter plegvBorderOn = 795;
`endif

always @(posedge dot_clk)
if (rst)
	por <= 1'b1;
else begin
	if (frame_cnt > 6'd10)
		por <= 1'b0;
end

always_ff @(posedge clk)
if (rst)
	ctrl_adr <= 8'h00;
else begin
	if (s_cs && !s_rw && s_adr==14'h3FFE)
		ctrl_adr <= s_dat_i;
end

always_ff @(posedge clk)
if (rst) begin
	ctrl_map <= 8'h00;
end
else begin
	if (s_cs && !s_rw && s_adr==14'h3FFF) begin
		case(ctrl_adr)
		8'h00:	ctrl_map <= s_dat_i;
		default:	;
		endcase
	end
end

always_comb
if (s_cs & s_rw) begin
	case(ctrl_map[0])
	1'b0:	s_dat_o = dispmem_outa;
	1'b1:	s_dat_o = charrom_outa;
	default:	s_dat_o = 8'h00;
	endcase
end
else
	s_dat_o = 8'h00;

reg [7:0] char_bitmap, char_bitmap1;
reg [7:0] bitmap,bitmap1;
wire L;
wire c0,c1,c2;
wire [23:0] border_color, pixel_color;

reg hBlank1;
wire vBlank1;
wire hSync1,vSync1;
reg hBorder1,vBorder1,hBorder2;
reg vblank;
reg eof;
reg eol;

wire eol1 = hCtr==phTotal;
wire eof1 = vCtr==pvTotal;

assign vSync1 = vCtr >= pvSyncOn && vCtr < pvSyncOff;
assign hSync1 = hCtr >= phSyncOn && hCtr < phSyncOff;
assign vBlank1 = vCtr >= pvBlankOn || vCtr < pvBlankOff;
assign vBorder1 = leg ? vCtr >= plegvBorderOn || vCtr < plegvBorderOff :
												vCtr >= pvBorderOn || vCtr < pvBorderOff;

counter #(12) u1 (.rst(rst), .clk(dot_clk), .ce(1'b1), .ld(eol1), .d(12'd1), .q(hCtr), .tc() );
counter #(12) u2 (.rst(rst), .clk(dot_clk), .ce(eol1), .ld(eof1), .d(12'd1), .q(vCtr), .tc() );
counter #(6)  u3 (.rst(rst), .clk(dot_clk), .ce(eof1), .ld(1'b0), .d(6'd1), .q(frame_cnt), .tc() );

// Decode modes

wire int_alpha;
wire ext_alpha;
wire sg4;
wire sg6;
wire cg1;
wire rg1;
wire cg2;
wire rg2;
wire cg3;
wire rg3;
wire cg6;
wire rg6;

rf6847_mode_decode umd1
(
	.clk(clk),
	.ag(iag),
	.as(ias),
	.intext(iintext),
	.gm0(gm0),
	.gm1(gm1),
	.gm2(gm2), 
	.int_alpha(int_alpha),
	.ext_alpha(ext_alpha),
	.sg4(sg4),
	.sg6(sg6),
	.cg1(cg1),
	.cg2(cg2),
	.cg3(cg3),
	.cg6(cg6),
	.rg1(rg1),
	.rg2(rg2),
	.rg3(rg3),
	.rg6(rg6)
);

// There are 8 or 16 dot clocks per character row.

always_comb
	dots16 = cg1|rg1|rg2|rg3;

always @(posedge dot_clk)
if (rst)
	char_en <= 1'b0;
else begin
	if (dots16)
		char_en <= hCtr[3:0]==4'd15;
	else	
		char_en <= hCtr[2:0]==3'd7;
end

rf6947_row_address_gen ura1
(
	.rst(rst),
	.dot_clk(dot_clk),
	.div2(leg ? 1'b0 : 1'b1),
	.eol(eol),
	.vborder(vBorder1),
	.ra(ra)
);

// Memory address generation

rf6847_address_gen uagen1
(
	.rst(rst),
	.dot_clk(dot_clk),
	.en(char_en),
	.eol(eol),
	.eof(eof),
	.blank(blank),
	.border(border2),
	.ra(ra),
	.text(int_alpha|ext_alpha),
	.sg(sg4|sg6),
	.scan3(cg1|rg1|cg2),
	.scan2(rg2|cg3),
	.ma(ma)
);

// Character ROM address generation

always @(posedge dot_clk)
if (char_en)
	charrom_adr <= {8'h00,charno} * 4'd12 + ra;

reg [3:0] dot_cnt;
always_comb
	dot_cnt = hCtr[3:0];

always @(posedge dot_clk)
if (rst)
	charno <= 8'd0;
else begin
	charno <= dispmem_outb;
end

always @(posedge dot_clk)
if (rst)
	char_bitmap1 <= 8'd0;
else begin
	char_bitmap1 <= iintext ? m_dat_i : charrom_outb;
end

always @(posedge dot_clk)
if (rst)
	char_bitmap <= 8'd0;
else begin
	if (char_en)
		char_bitmap <= iinv ? ~char_bitmap1 : char_bitmap1;
	else
		char_bitmap <= char_bitmap << 2'd1;
end

always @(posedge dot_clk)
if (rst)
	bitmap1 <= 8'd0;
else
	bitmap1 <= charno;
always @(posedge dot_clk)
if (char_en)
	bitmap <= bitmap1;

rf6847_select_pixel usp1
(
	.ra(ra),
	.dot_cnt(dot_cnt),
	.css(css),
	.char_bitmap(char_bitmap),
	.bitmap(bitmap),
	.text(int_alpha|ext_alpha),
	.sg4(sg4),
	.sg6(sg6),
	.cg1(cg1),
	.cg2(cg2),
	.cg3(cg3),
	.cg6(cg6),
	.rg1(rg1),
	.rg2(rg2),
	.rg3(rg3),
	.rg6(rg6),
	.L(L),
	.c0(c0),
	.c1(c1),
	.c2(c2)
);

rf6847_select_color usc1
(
	.dot_clk(dot_clk),
	.text(int_alpha|ext_alpha),
	.sg4(sg4),
	.sg6(sg6),
	.cg(cg1|cg2|cg3|cg6),
	.rg(rg1|rg2|rg3|rg6),
	.css(css),
	.L(L),
	.c2(c2),
	.c1(c1),
	.c0(c0),
	.pixel_color(pixel_color),
	.border_color(border_color)
);

always @(posedge dot_clk)
if (rst)
  hBlank1 <= 1'b0;
else begin
  if (hCtr==phBlankOn)
    hBlank1 <= 1'b1;
  else if (hCtr==phBlankOff)
    hBlank1 <= 1'b0;
end

rf6847_hborder uhb1
(
	.rst(rst),
	.dot_clk(dot_clk),
	.leg(leg),
	.hCtr(hCtr), 
	.leg_border_on(pleghBorderOn+4'd2),
	.leg_border_off(pleghBorderOff+4'd2),
	.border_on(phBorderOn+4'd2),
	.border_off(phBorderOff+4'd2),
	.border(hBorder1)
);

rf6847_hborder uhb2
(
	.rst(rst),
	.dot_clk(dot_clk),
	.leg(leg),
	.hCtr(hCtr), 
	.leg_border_on(pleghBorderOn-(dots16 ? 6'd48 : 6'd24)),
	.leg_border_off(pleghBorderOff-(dots16 ? 6'd48 : 6'd24)),
	.border_on(phBorderOn-(dots16 ? 6'd48 : 6'd24)),
	.border_off(phBorderOff-(dots16 ? 6'd48 : 6'd24)),
	.border(hBorder2)
);

// Output stage
// Register signals.

always @(posedge dot_clk)
  border <= #1 hBorder1|vBorder1;
always @(posedge dot_clk)
  border2 <= #1 hBorder2|vBorder1;
always @(posedge dot_clk)
  blank <= #1 hBlank1|vBlank1;
always @(posedge dot_clk)
  vblank <= #1 vBlank1;
always @(posedge dot_clk)
	hsync <= #1 hSync1;
always @(posedge dot_clk)
	vsync <= #1 vSync1;
always @(posedge dot_clk)
  eof <= eof1;
always @(posedge dot_clk)
  eol <= eol1;
always @(posedge dot_clk)
  vbl_irq <= hCtr==8'd1 && vCtr==pvBlankOn;

always_ff @(posedge dot_clk)
case({blank,border})
2'b00:	rgb = pixel_color;
2'b01:	rgb = border_color;
2'b10:	rgb = 6'd0;
2'b11:	rgb = 6'd0;
endcase

endmodule

module rf6847_mode_decode(clk,
	ag, as, intext, gm0, gm1, gm2, 
	int_alpha, ext_alpha, sg4, sg6, cg1, cg2, cg3, cg6,
	rg1, rg2, rg3, rg6
);
input clk;
input ag;
input as;
input intext;
input gm0;
input gm1;
input gm2;
output reg int_alpha;
output reg ext_alpha;
output reg sg4;
output reg sg6;
output reg cg1;
output reg cg2;
output reg cg3;
output reg cg6;
output reg rg1;
output reg rg2;
output reg rg3;
output reg rg6;

always_ff @(posedge clk)
begin
	int_alpha <= ag==1'b0 && intext==1'b0;
	ext_alpha <= ag==1'b0 && intext==1'b1;
	sg4 <= ag==1'b0 && as==1'b1 && intext==1'b0;
	sg6 <= ag==1'b0 && as==1'b1 && intext==1'b1;
	cg1 <= ag==1'b1 && {gm2,gm1,gm0}==3'b000;
	rg1 <= ag==1'b1 && {gm2,gm1,gm0}==3'b001;
	cg2 <= ag==1'b1 && {gm2,gm1,gm0}==3'b010;
	rg2 <= ag==1'b1 && {gm2,gm1,gm0}==3'b011;
	cg3 <= ag==1'b1 && {gm2,gm1,gm0}==3'b100;
	rg3 <= ag==1'b1 && {gm2,gm1,gm0}==3'b101;
	cg6 <= ag==1'b1 && {gm2,gm1,gm0}==3'b110;
	rg6 <= ag==1'b1 && {gm2,gm1,gm0}==3'b111;
end

endmodule

// Character row address generation

module rf6947_row_address_gen(rst, dot_clk, div2, eol, vborder, ra);
input rst;
input dot_clk;
input div2;
input eol;
input vborder;
output reg [3:0] ra;

reg [5:0] ra1;

always @(posedge dot_clk)
if (rst)
	ra1 <= 6'd0;
else begin
	if (vborder)
		ra1 <= 6'd0;
	else if (eol) begin
		if (ra1==(div2 ? 6'd23 : 6'd47))
			ra1 <= 6'd0;
		else
			ra1 <= ra1 + 2'd1;
	end
end

always @(posedge dot_clk)
if (rst)
	ra <= 4'd0;
else begin
	if (div2)
		ra <= ra1 >> 2'd1;
	else
		ra <= ra1 >> 2'd2;
end

endmodule

// Memory address generation
// Rescans the same set of addresses each scanline until the number of
// scanlines needed is reached.
// Note the border signal is three character times in advance of the displayed
// border to account for the pipeline.

module rf6847_address_gen(rst, dot_clk, en, eol, eof, blank, border,
	ra, text, sg, scan3, scan2, ma);
input rst;
input dot_clk;
input en;
input eol;
input eof;
input blank;
input border;
input [3:0] ra;
input text;
input sg;
input scan3;
input scan2;
output reg [13:0] ma;

reg [13:0] ma2;

always @(posedge dot_clk)
if (rst) begin
	ma <= 14'd0;
	ma2 <= 14'd0;
end
else begin
	if (eof) begin
		ma <= 14'd0;
		ma2 <= 14'd0;
	end
	else if (eol) begin
		case(1'b1)
		text,sg:
			if (ra!=4'd11)
				ma <= ma2;
			else
				ma2 <= ma;
		// 3 scan lines per pixel
		scan3:
			if (ra!=4'd2 && ra!=4'd5 && ra!=4'd8 && ra != 4'd11)
				ma <= ma2;
			else
				ma2 <= ma;
		// 2 scanline per pixel
		scan2:
			if (ra[0]!=1'd1)
				ma <= ma2;
			else
				ma2 <= ma;
		// 1 scanline per pixel
		default:
			;	//ma2 <= ma;
		endcase
	end
	else if ({blank,border}==2'b00 && en) begin
		ma <= ma + 2'd1;
	end
end
endmodule

// Horizontal border timing

module rf6847_hborder(rst, dot_clk, leg, hCtr, 
	leg_border_on, leg_border_off, border_on, border_off, border);
input rst;
input dot_clk;
input leg;
input [11:0] hCtr;
input [11:0] leg_border_on;
input [11:0] leg_border_off;
input [11:0] border_on;
input [11:0] border_off;
output reg border;

always @(posedge dot_clk)
if (rst)
  border <= 1'b0;
else begin
	if (leg) begin
	  if (hCtr==leg_border_on)
	    border <= 1'b1;
	  else if (hCtr==leg_border_off)
	    border <= 1'b0;
	end
	else begin
	  if (hCtr==border_on)
	    border <= 1'b1;
	  else if (hCtr==border_off)
	    border <= 1'b0;
  end
end
endmodule

// Select pixel from bitmap

module rf6847_select_pixel(ra, dot_cnt, css,
	char_bitmap, bitmap,
	text, sg4, sg6, cg1, rg1, cg2, rg2, cg3, rg3, cg6, rg6,
	L, c0, c1, c2
);
input [4:0] ra;
input [3:0] dot_cnt;
input css;
input [7:0] char_bitmap;
input [7:0] bitmap;
input text;
input sg4;
input sg6;
input cg1;
input cg2;
input cg3;
input cg6;
input rg1;
input rg2;
input rg3;
input rg6;
output reg L;
output reg c0;
output reg c1;
output reg c2;

always_comb
case (1'b1)
text:
	L <= char_bitmap[7];
sg4:
	begin
		case({ra>5'd11,dot_cnt[2:0]>3'd3})
		2'b00:	L <= bitmap[3];
		2'b01:	L <= bitmap[2];
		2'b10:	L <= bitmap[1];
		2'b11:	L <= bitmap[0];
		endcase
		{c2,c1,c0} <= bitmap[6:4];
	end
sg6:
	begin
		case({ra>5'd15,ra>5'd7,dot_cnt[2:0]>3'd3})
		3'b000:	L <= bitmap[5];
		3'b001:	L <= bitmap[4];
		3'b010:	L <= bitmap[3];
		3'b011:	L <= bitmap[2];
		3'b100:	L <= bitmap[1];
		3'b101:	L <= bitmap[0];
		default:	L <= 1'b0;
		endcase
		{c1,c0} <= bitmap[7:6];
	end
cg1:
	begin
		case(dot_cnt[3:2])
		2'd0:	{c1,c0} <= bitmap[7:6];
		2'd1:	{c1,c0} <= bitmap[5:4];
		2'd2:	{c1,c0} <= bitmap[3:2];
		2'd3:	{c1,c0} <= bitmap[1:0];
		endcase
	end
rg1:	L <= bitmap[dot_cnt[3:1]];
cg2,cg3,cg6:
		case(dot_cnt[2:1])
		2'd0:	{c1,c0} <= bitmap[7:6];
		2'd1:	{c1,c0} <= bitmap[5:4];
		2'd2:	{c1,c0} <= bitmap[3:2];
		2'd3:	{c1,c0} <= bitmap[1:0];
		endcase
rg2,rg3,rg6:	L <= bitmap[~dot_cnt[2:0]];
default:
	begin
		L <= 1'b0;
		{c2,c1,c0} <= 3'b000;
	end
endcase

endmodule

// Select color for pixel or border given graphics mode and select bits

module rf6847_select_color (dot_clk,
	text, sg4, sg6, cg, rg,
	css, L, c2, c1, c0, pixel_color, border_color
);
input dot_clk;
input text;
input sg4;
input sg6;
input cg;
input rg;
input css;
input L;
input c2;
input c1;
input c0;
output reg [23:0] pixel_color;
output reg [23:0] border_color;

// 6847 colors as RGB
wire [23:0] green = {8'h07, 8'hff, 8'h00};
wire [23:0] yellow = {8'hff,8'hff,8'h00};
wire [23:0] blue = {8'h3b,8'h08,8'hff};
wire [23:0] red = {8'hcc,8'h00,8'h3b};
wire [23:0] white = {8'hff,8'hff,8'hff};
wire [23:0] cyan = {8'h07,8'he3,8'h99};
wire [23:0] magenta = {8'hff, 8'h1c, 8'hff};
wire [23:0] orange = {8'hff, 8'h81, 8'h00};
wire [23:0] black = {8'h00, 8'h00, 8'h00};
wire [23:0] dark_green = {8'h00, 8'h7c, 8'h00};
wire [23:0] dark_orange = {8'h91,8'h00,8'h00};
wire [23:0] buff = {8'hff, 8'hff, 8'hff};

always_ff @(posedge dot_clk)
case(1'b1)
text:
	case({css,L})
	2'b00:	pixel_color <= black;
	2'b01:	pixel_color <= green;
	2'b10:	pixel_color <= black;
	2'b11:	pixel_color <= orange;
	endcase
sg4:
	case({L,c2,c1,c0})
	4'b1000:	pixel_color <= green;
	4'b1001:	pixel_color <= yellow;
	4'b1010:	pixel_color <= blue;
	4'b1011:	pixel_color <= red;
	4'b1100:	pixel_color <= white;
	4'b1101:	pixel_color <= cyan;
	4'b1110:	pixel_color <= magenta;
	4'b1111:	pixel_color <= orange;
	default:	pixel_color <= black;
	endcase
sg6:
	case({L,css,c1,c0})
	4'b1000:	pixel_color <= green;
	4'b1001:	pixel_color <= yellow;
	4'b1010:	pixel_color <= blue;
	4'b1011:	pixel_color <= red;
	4'b1100:	pixel_color <= white;
	4'b1101:	pixel_color <= cyan;
	4'b1110:	pixel_color <= magenta;
	4'b1111:	pixel_color <= orange;
	default:	pixel_color <= black;
	endcase
cg:
	case({css,c1,c0})
	3'b000:	pixel_color <= green;
	3'b001:	pixel_color <= yellow;
	3'b010:	pixel_color <= blue;
	3'b011:	pixel_color <= red;
	3'b100:	pixel_color <= white;
	3'b101:	pixel_color <= cyan;
	3'b110:	pixel_color <= magenta;
	3'b111:	pixel_color <= orange;
	endcase
rg:
	case({css,L})
	2'b00:	pixel_color <= black;
	2'b01:	pixel_color <= white;
	2'b10:	pixel_color <= black;
	2'b11:	pixel_color <= green;
	endcase
endcase

always_ff @(posedge dot_clk)
case(1'b1)
cg:	border_color <= css ? white : green;
rg:	border_color <= css ? white : green;
default:	border_color <= black;
endcase

endmodule
