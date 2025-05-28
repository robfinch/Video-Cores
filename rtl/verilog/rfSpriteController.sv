`timescale 1ns / 1ps
// ============================================================================
//        __
//   \\__/ o\    (C) 2005-2025  Robert Finch, Waterloo
//    \  __ /    All rights reserved.
//     \/_//     robfinch<remove>@finitron.ca
//       ||
//
//	rfSpriteController.sv
//		sprite / hardware cursor controller
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
//
//	Sprite Controller
//
//	FEATURES
//	- parameterized number of sprites 1,2,4,6,8,14,16 or 32
//	- sprite image cache buffers
//		- each image cache is capable of holding multiple
//		  sprite images
//		- an embedded DMA controller is used for sprite reload
//	- programmable image offset within cache
//	- programmable sprite width,height, and pixel size
//		- sprite width and height may vary from 1 to 256 as long
//		  as the product doesn't exceed 4096.
//	    - pixels may be programmed to be 1,2,3 or 4 video clocks
//	      both height and width are programmable
//	- programmable sprite position
//	- programmable 8, 16 or 32 bits for color
//		eg 32k color + 1 bit alpha blending indicator (1,5,5,5)
//	- fixed display and DMA priority
//	    sprite 0 highest, sprite 31 lowest
//	- graphics plane control
//
//		This core requires an external timing generator to
//	provide horizontal and vertical sync signals, but
//	otherwise can be used as a display controller on it's
//	own. However, normally this core would be embedded
//	within another core such as a VGA controller. Sprite
//	positions are referenced to the rising edge of the
//	vertical and horizontal sync pulses.
//		The core includes an embedded dual port RAM to hold the
//	sprite images. The image RAM is updated using a built in DMA
//	controller. The DMA controller uses 32 bit accesses to fill
//	the sprite buffers. The circuit features an automatic bus
//  transaction timeout; if the system bus hasn't responded
//  within 20 clock cycles, the DMA controller moves onto the
//  next address.
//		The controller uses a ram underlay to cache the values
//	of the registers. This is a lot cheaper resource wise than
//	using a 32 to 1 multiplexor (well at least for an FPGA).
//
//	All registers are 32 bits wide
//
//	These registers repeat in incrementing block of four registers
//	and pertain to each sprite
//	00:	- position register
//		HPOS    [11: 0]	horizontal position (hctr value)
//	    VPOS	[27:16]	vertical position (vctr value)
//
//	04:	SZ	- size register
//			bits
//			[ 7: 0]	width of sprite in pixels - 1
//			[15: 8]	height of sprite in pixels -1
//			[19:16]	size of horizontal pixels - 1 in clock cycles
//			[23:20]	size of vertical pixels in scan-lines - 1
//				* the product of width * height cannot exceed 2048 !
//				if it does, the display will begin repeating
//			[27:24] output plane
//			[31:30] color depth 00=RGB332,01=RGB555+A,10=RGB888+A
//				
//	08: ADR	[31:12] 20 bits sprite image address bits
//			This registers contain the high order address bits of the
//          location of the sprite image in system memory.
//			The DMA controller will assign the low order 12 bits
//			during DMA.
//		    [11:0] image offset bits [11:0]
//			offset of the sprite image within the sprite image cache
//			typically zero
//	
//	0C: TC	[23:0]	transparent color
//			This register identifies which color of the sprite
//			is transparent
//
//
//
//	0C-1FC:	registers reserved for up to thirty-one other sprites
//
//	200:		DMA burst reg sprite 0
//				[8:0]  burst start
//				[24:16] burst end
//	...
//	27C:		DMA burst reg sprite 31
//
//  280:	[ 7: 0] Frame size, multiples of 16 pixels
//				[15: 8]	Number of frames of animation
//        [25:16] Animation Rate
//				[29:26] Frame size, LSBs 0 to 3
//				[30]		Auto repeat
//				[31]    Enable animation
//  ...
//	2FC:	Animation register sprite #31
//
//	Global status and control
//	3C0: EN [31:0] sprite enable register
//  3C4: IE	[31:0] sprite interrupt enable / status
//	3C8: SCOL	[31:0] sprite-sprite collision register
//	3CC: BCOL	[31:0] sprite-background collision register
//	3D0: DT		[31:0] sprite DMA trigger on
//	3D4: DT		[31:0] sprite DMA trigger off
//	3D8: VDT	[31:0] sprite vertical sync DMA trigger
//	3EC: BC	  [29:0] background color
//  3FC: ADDR	[31:0] sprite DMA address bits [63:32]
//
// 7200
//=============================================================================

import wishbone_pkg::*;

module rfSpriteController(
// Globals
//------------------------------
input cs_config_i,
input cs_io_i,

// Bus Slave interface
//------------------------------
// Slave signals
input rst_i,			// reset
input s_clk_i,		// clock
input	wb_write_request32_t wbs_req,
output wb_read_response32_t wbs_resp,
//------------------------------
// Bus Master Signals
fta_bus_interface.master m_bus,
output [4:0] m_spriteno_o,
//--------------------------
// interrupt
output [31:0] irq_o,
//--------------------------
// Video
video_bus.in video_i,
video_bus.out video_o,

input test,
input xonoff_i
);

reg m_soc_o;
reg [31:0] zrgb_o;
wire vclk = video_i.clk;
wire hSync = video_i.hsync;
wire vSync = video_i.vsync;
always_comb
begin
	video_o = video_i;
	video_o.data = zrgb_o;
end


//--------------------------------------------------------------------
// Core Parameters
//--------------------------------------------------------------------
parameter pnSpr = 32;		// number of sprites
parameter phBits = 12;		// number of bits in horizontal timing counter
parameter pvBits = 12;		// number of bits in vertical timing counter
localparam pnSprm = pnSpr-1;
parameter SPR_ADDR = 32'hFEDA0000;
parameter SPR_ADDR_MASK = 32'h00FF0000;

parameter CFG_BUS = 8'd0;
parameter CFG_DEVICE = 5'd2;
parameter CFG_FUNC = 3'd0;
parameter CFG_VENDOR_ID	=	16'h0;
parameter CFG_DEVICE_ID	=	16'h0;
parameter CFG_SUBSYSTEM_VENDOR_ID	= 16'h0;
parameter CFG_SUBSYSTEM_ID = 16'h0;
parameter CFG_ROM_ADDR = 32'hFFFFFFF0;

parameter CFG_REVISION_ID = 8'd0;
parameter CFG_PROGIF = 8'd1;
parameter CFG_SUBCLASS = 8'h80;					// 80 = Other
parameter CFG_CLASS = 8'h03;						// 03 = display controller
parameter CFG_CACHE_LINE_SIZE = 8'd8;		// 32-bit units
parameter CFG_MIN_GRANT = 8'h00;
parameter CFG_MAX_LATENCY = 8'h00;
parameter CFG_IRQ_LINE = 8'd5;

localparam CFG_HEADER_TYPE = 8'h00;			// 00 = a general device

parameter MSIX = 1'b0;
parameter IRQ_MSGADR = 64'h0EDA900E1;
parameter IRQ_MSGDAT = 64'h1;

always_comb
	if (pnSpr < 1 || pnSpr > 32) begin
		$display("Number of sprites must be between 1 and 32.");
		$finish;
	end

//--------------------------------------------------------------------
// Variable Declarations
//--------------------------------------------------------------------

reg ce;										// controller enable
wb_write_request32_t wb_reqs;	// synchronized request
reg [31:0] spr_addr;

wire [4:0] sprN = wb_reqs.adr[8:4];

reg [phBits-1:0] hctr;		// horizontal reference counter (counts dots since hSync)
reg [pvBits-1:0] vctr;		// vertical reference counter (counts scanlines since vSync)
reg sprSprIRQ;
reg sprBkIRQ;

reg [31:0] out;			// sprite output
reg outact;				// sprite output is active
reg [3:0] outplane;
reg [pnSprm:0] bkCollision;		// sprite-background collision
reg [29:0] bgTc;			// background transparent color
reg [29:0] bkColor;		// background color


reg [pnSprm:0] sprWe;	// block ram write enable for image cache update
reg [pnSprm:0] sprRe;	// block ram read enable for image cache update

// Global control registers
reg [31:0] sprEn;   	// enable sprite
reg [pnSprm:0] sprCollision;	    // sprite-sprite collision
reg sprSprIe;			// sprite-sprite interrupt enable
reg sprBkIe;            // sprite-background interrupt enable
reg sprSprIRQPending;   // sprite-sprite collision interrupt pending
reg sprBkIRQPending;    // sprite-background collision interrupt pending
reg sprSprIRQPending1;  // sprite-sprite collision interrupt pending
reg sprBkIRQPending1;   // sprite-background collision interrupt pending
reg sprSprIRQ1;			// vclk domain regs
reg sprBkIRQ1;

// Sprite control registers
reg [31:0] sprSprCollision;
reg [pnSprm:0] sprSprCollision1;
reg [31:0] sprBkCollision;
reg [pnSprm:0] sprBkCollision1;
reg [23:0] sprTc [pnSprm:0];		// sprite transparent color code
// How big the pixels are:
// 1 to 16 video clocks
reg [3:0] hSprRes [pnSprm:0];		// sprite horizontal resolution
reg [3:0] vSprRes [pnSprm:0];		// sprite vertical resolution
reg [7:0] sprWidth [pnSprm:0];		// number of pixels in X direction
reg [7:0] sprHeight [pnSprm:0];		// number of vertical pixels
reg [3:0] sprPlane [pnSprm:0];		// output plane sprite is in
reg [1:0] sprColorDepth [pnSprm:0];
reg [1:0] colorBits;
// Sprite DMA control
reg [8:0] sprBurstStart [pnSprm:0];
reg [8:0] sprBurstEnd	[pnSprm:0];
reg [31:0] vSyncT;								// DMA on vSync

// display and timing signals
reg [31:0] hSprReset;   // horizontal reset
reg [31:0] vSprReset;   // vertical reset
reg [31:0] hSprDe;		// sprite horizontal display enable
reg [31:0] vSprDe;		// sprite vertical display enable
reg [31:0] sprDe;			// display enable
reg [phBits-1:0] hSprPos [pnSprm:0];	// sprite horizontal position
reg [pvBits-1:0] vSprPos [pnSprm:0];	// sprite vertical position
reg [7:0] hSprCnt [pnSprm:0];	// sprite horizontal display counter
reg [7:0] vSprCnt [pnSprm:0];	// vertical display counter
reg [11:0] sprImageOffs [pnSprm:0];	// offset within sprite memory
reg [12:0] sprAddr [pnSprm:0];	// index into sprite memory (pixel number)
reg [9:0] sprAddr1 [pnSprm:0];	// index into sprite memory
reg [2:0] sprAddr2 [pnSprm:0];	// index into sprite memory
reg [2:0] sprAddr3 [pnSprm:0];	// index into sprite memory
reg [2:0] sprAddr4 [pnSprm:0];	// index into sprite memory
reg [2:0] sprAddr5 [pnSprm:0];	// index into sprite memory
reg [11:0] sprAddrB [pnSprm:0];	// backup address cache for rescan
wire [31:0] sprOut4 [pnSprm:0];	// sprite image data output
reg [31:0] sprOut [pnSprm:0];	// sprite image data output
reg [31:0] sprOut5 [pnSprm:0];	// sprite image data output
wire [5:0] actcnt;	// count of sprites active at a given pixel location of the screen

// Animation
reg [11:0] sprFrameSize [pnSprm:0];
reg [7:0] sprFrames [pnSprm:0];
reg [7:0] sprCurFrame [pnSprm:0];
reg [9:0] sprRate [pnSprm:0];
reg [9:0] sprCurRateCount [pnSprm:0];
reg [pnSprm:0] sprEnableAnimation;
reg [pnSprm:0] sprAutoRepeat;
reg [11:0] sprFrameProd [pnSprm:0];

// DMA access
reg [31:12] sprSysAddr [pnSprm:0];	// system memory address of sprite image (low bits)
reg [4:0] dmaOwner;			// which sprite has the DMA channel
reg [31:0] sprDt;		// DMA trigger register
reg dmaActive;				// this flag indicates that a block DMA transfer is active

genvar g;

//--------------------------------------------------------------------
// config
//--------------------------------------------------------------------

reg cs_config;
reg cs_io;
wire irq_en;

pci32_config #(
	.CFG_BUS(CFG_BUS),
	.CFG_DEVICE(CFG_DEVICE),
	.CFG_FUNC(CFG_FUNC),
	.CFG_VENDOR_ID(CFG_VENDOR_ID),
	.CFG_DEVICE_ID(CFG_DEVICE_ID),
	.CFG_BAR0(SPR_ADDR),
	.CFG_BAR0_ALLOC(SPR_ADDR_MASK),
	.CFG_SUBSYSTEM_VENDOR_ID(CFG_SUBSYSTEM_VENDOR_ID),
	.CFG_SUBSYSTEM_ID(CFG_SUBSYSTEM_ID),
	.CFG_ROM_ADDR(CFG_ROM_ADDR),
	.CFG_REVISION_ID(CFG_REVISION_ID),
	.CFG_PROGIF(CFG_PROGIF),
	.CFG_SUBCLASS(CFG_SUBCLASS),
	.CFG_CLASS(CFG_CLASS),
	.CFG_CACHE_LINE_SIZE(CFG_CACHE_LINE_SIZE),
	.CFG_MIN_GRANT(CFG_MIN_GRANT),
	.CFG_MAX_LATENCY(CFG_MAX_LATENCY),
	.CFG_IRQ_LINE(CFG_IRQ_LINE)
)
ucfg1
(
	.rst_i(rst_i),
	.clk_i(clk_i),
	.irq_i(irq),
	.irq_o(irq_o),
	.cs_config_i(cs_config), 
	.we_i(wbs_req.we),
	.sel_i(wbs_req.sel),
	.adr_i(wbs_req.adr),
	.dat_i(wbs_req.dat),
	.dat_o(cfg_out),
	.cs_bar0_o(cs_spr),
	.cs_bar1_o(),
	.cs_bar2_o(),
	.irq_en_o(irq_en)
);

always_ff @(posedge s_clk_i)
	cs_config <= wbs_req.cyc && wbs_req.stb && cs_config_i && 
							wbs_req.adr[27:20]==CFG_BUS &&
							wbs_req.adr[19:15]==CFG_DEVICE &&
							wbs_req.adr[14:12]==CFG_FUNC;

always_ff @(posedge s_clk_i)
	cs_io <= wbs_req.cyc && wbs_req.stb && cs_io_i && cs_spr;

//--------------------------------------------------------------------
// DMA control / bus interfacing
//--------------------------------------------------------------------
always_ff @(posedge s_clk_i)
	wb_reqs <= wbs_req;

wire s_ack_o;
ack_gen #(
	.READ_STAGES(3),
	.WRITE_STAGES(1),
	.REGISTER_OUTPUT(1)
)
uag1 (
	.clk_i(s_clk_i),
	.ce_i(1'b1),
	.i((cs_io|cs_config) & ~wb_reqs.we),
	.we_i((cs_io|cs_config) & wb_reqs.we),
	.o(s_ack_o),
	.rid_i(0),
	.wid_i(0),
	.rid_o(),
	.wid_o()
);
always_comb
begin
	wbs_resp.ack = s_ack_o & wbs_req.cyc & wbs_req.stb;
	wbs_resp.next = s_ack_o & wbs_req.cyc & wbs_req.stb;
end

//--------------------------------------------------------------------
// DMA control / bus interfacing
//--------------------------------------------------------------------

reg [5:0] dmaStart;
reg [8:0] cob;	// count of burst cycles
reg irq;
reg rst_irq;

assign m_bus_o.req.bte = LINEAR;
assign m_bus_o.req.cti = CLASSIC;
assign m_bus_o.req.blen = 6'd63;
assign m_bus_o.req.stb = wbm_req.cyc;
assign m_bus_o.req.sel = 32'hFFFFFFFF;
assign m_bus_o.req.cid = 4'd5;
assign m_spriteno_o = dmaOwner;

reg [2:0] mstate;
parameter IDLE = 3'd0;
parameter ACTIVE = 3'd1;
parameter ACK = 3'd2;
parameter NACK = 3'd3;

wire pe_m_ack_i;
edge_det ued2 (.rst(rst_i), .clk(m_clk_i), .ce(1'b1), .i(m_bus_o.resp.ack), .pe(pe_m_ack_i), .ne(), .ee());

always_ff @(posedge m_clk_i)
if (rst_i)
	irq <= 1'b0;
else begin
	if (MSIX) begin
		if (rst_irq)
			irq <= 1'b0;
		else if (sprSprIRQ|sprBkIRQ)
			irq <= irq_en;
	end
	else
		irq <= (sprSprIRQ|sprBkIRQ) & irq_en;
end

reg [11:0] tocnt;
always_ff @(posedge m_clk_i)
if (rst_i)
	tocnt <= 'd0;
else begin
	if (wbm_req.cyc)
		tocnt <= tocnt + 2'd1;
	else
		tocnt <= 'd0;
end

always_ff @(posedge m_clk_i)
if (rst_i)
	mstate <= IDLE;
else begin
	case(mstate)
	IDLE:
		if (irq & MSIX & irq_en)
			mstate <= IRQ;
		else if (|sprDt & ce)
			mstate <= ACTIVE;
	IRQ:
		mstate <= ACK;
	ACTIVE:
		mstate <= ACK;
	ACK:
		if (m_bus_o.resp.ack || (m_bus_o.resp.err!=fta_bus_pkg::OKAY) || tocnt[10])
			mstate <= NACK;
	NACK:
		if (~(m_bus_o.resp.ack||(m_bus_o.resp.err!=fta_bus_pkg::OKAY)))
			mstate <= cob==sprBurstEnd[dmaOwner] ? IDLE : ACTIVE;
	default:
		mstate <= IDLE;
	endcase
end

integer n30;
always_ff @(posedge m_clk_i)
begin
	case(mstate)
	IDLE:
		begin
			dmaOwner <= 5'd0;
			for (n30 = pnSprm; n30 >= 0; n30 = n30 - 1)
				if (sprDt[n30])
					dmaOwner <= n30;
		end
	default:	;
	endcase
end

always_ff @(posedge m_clk_i)
if (rst_i)
	dmaStart <= 6'b0;
else begin
	dmaStart <= {dmaStart[4:0],1'b0};
	case(mstate)
	IDLE:
		if (irq)
			;
		else if (|sprDt & ce)
			dmaStart <= 6'h3F;
	default:	;
	endcase
end

integer n32;
always_ff @(posedge m_clk_i)
begin
	case(mstate)
	IDLE:
		for (n32 = pnSprm; n32 >= 0; n32 = n32 - 1)
			if (sprDt[n32] & ce)
				cob <= sprBurstStart[n32];
	ACTIVE:
		cob <= cob + 2'd2;
	default:	;
	endcase
end

always_ff @(posedge m_clk_i)
if (rst_i)
	wb_m_nack();
else begin
	case(mstate)
	IDLE:
		wb_m_nack();
	IRQ:
		begin
			m_bus_o.req.cyc <= 1'b1;
			m_bus_o.req.we <= 1'b1;
			m_bus_o.req.sel <= irq_msgadr[3] ? 16'hFF00 : 16'h00FF;
			m_bus_o.req.adr <= irq_msg_adr;
			m_bus_o.req.data1 <= {48'h0,irq_msg_data};
		end
	ACTIVE:
		begin
			m_bus_o.req.cyc <= 1'b1;
			m_bus_o.req.sel <= 32'hFFFFFFFF;
			m_bus_o.req.adr <= {sprSysAddr[dmaOwner],cob[7:1],5'h0};
		end
	ACK:
		if (m_bus_o.resp.ack||(m_bus_o.resp.err!=fta_bus_pkg::OKAY)||tocnt[10])
			wb_m_nack();
	endcase
end

always_ff @(posedge m_clk_i)
if (rst_i)
	rst_irq <= 1'b1;
else begin
	rst_irq <= 1'b0;
	if (mstate==IRQ)
		rst_irq <= 1'b1;
end

task wb_m_nack;
begin
	m_bus_o.req.cyc <= 1'b0;
	m_bus_o.req.we <= 1'b0;
	m_bus_o.req.sel <= 32'h00000000;
end
endtask


// generate a write enable strobe for the sprite image memory
integer n1;
reg [8:0] m_adr_or;		// 64-bit value address
reg [127:0] m_dat_ir;
reg ack1;

always_ff @(posedge m_clk_i)
for (n1 = 0; n1 < pnSpr; n1 = n1 + 1)
	sprWe[n1] <= (dmaOwner==n1 && (pe_m_ack_i||ack1));

always_ff @(posedge m_clk_i)
	ack1 <= pe_m_ack_i;
always_ff @(posedge m_clk_i)
if (pe_m_ack_i|ack1)
	m_adr_or <= {wbm_req.adr[11:4],ack1};
always_ff @(posedge m_clk_i)
if (pe_m_ack_i) begin
	if (test)
		m_dat_ir <= {8{1'b0,dmaOwner,10'b0}};
	else
		m_dat_ir <= {wbm_resp.dat[63:0],wbm_resp.dat[127:64]};
end
else if (ack1)
	m_dat_ir <= {64'd0,m_dat_ir[127:64]};


//--------------------------------------------------------------------
//--------------------------------------------------------------------

reg [31:0] reg_shadow [0:255];
reg [7:0] radr;
always_ff @(posedge s_clk_i)
begin
    if (cs_io & wb_reqs.we & wb_reqs.sel[0])  reg_shadow[wb_reqs.adr[9:2]][7:0] <= wb_reqs.dat[7:0];
    if (cs_io & wb_reqs.we & wb_reqs.sel[1])  reg_shadow[wb_reqs.adr[9:2]][15:8] <= wb_reqs.dat[15:8];
    if (cs_io & wb_reqs.we & wb_reqs.sel[2])  reg_shadow[wb_reqs.adr[9:2]][23:16] <= wb_reqs.dat[23:16];
    if (cs_io & wb_reqs.we & wb_reqs.sel[3])  reg_shadow[wb_reqs.adr[9:2]][31:24] <= wb_reqs.dat[31:24];
end
always @(posedge s_clk_i)
  radr <= wb_reqs.adr[9:2];
wire [31:0] reg_shadow_o = reg_shadow[radr];

// register/sprite memory output mux
always_ff @(posedge s_clk_i)
	if (cs_config)
		wbs_resp.dat <= cfg_out;
	else if (cs_io)
		case (wb_reqs.adr[9:2])		// synopsys full_case parallel_case
		8'b11110000:	wbs_resp.dat <= sprEn;
		8'b11110001:	wbs_resp.dat <= {sprBkIRQPending|sprSprIRQPending,5'b0,sprBkIRQPending,sprSprIRQPending,6'b0,sprBkIe,sprSprIe};
		8'b11110010:	wbs_resp.dat <= sprSprCollision;
		8'b11110011:	wbs_resp.dat <= sprBkCollision;
		8'b11110100:	wbs_resp.dat <= sprDt;
		default:	wbs_resp.dat <= reg_shadow_o;
		endcase
	else
		wbs_resp.dat <= 32'h0;


// vclk -> clk_i
always_ff @(posedge s_clk_i)
begin
	sprSprIRQ <= sprSprIRQ1;
	sprBkIRQ <= sprBkIRQ1;
	sprSprIRQPending <= sprSprIRQPending1;
	sprBkIRQPending <= sprBkIRQPending1;
	sprSprCollision <= sprSprCollision1;
	sprBkCollision <= sprBkCollision1;
end


// register updates
// on the clk_i domain
reg vSync1;
integer n33;
always_ff @(posedge s_clk_i)
if (rst_i) begin
	vSyncT <= 32'hFFFFFFFF;//FFFFFFFF;
	sprEn <= 32'hFFFFFFFF;
	sprDt <= 0;
  for (n33 = 0; n33 < pnSpr; n33 = n33 + 1) begin
		sprSysAddr[n33] <= 20'b0000_0000_0011_0000_0000 + n33;	//0030_0000
	end
	sprSprIe <= 0;
	sprBkIe  <= 0;

  // Set reasonable starting positions on the screen
  // so that the sprites might be visible for testing
  for (n33 = 0; n33 < pnSpr; n33 = n33 + 1) begin
    hSprPos[n33] <= 200 + (n33 & 7) * 70;
    vSprPos[n33] <= 100 + (n33 >> 3) * 100;
    sprTc[n33] <= 24'h7FFF;		// White 16 bpp
		sprWidth[n33] <= 8'd24;  	// 16x16 sprites
		sprHeight[n33] <= 8'd21;
		hSprRes[n33] <= 2'd2;	// our standard display
		vSprRes[n33] <= 2'd2;
		sprImageOffs[n33] <= 12'h0;
		sprPlane[n33] <= 4'h7;//n[3:0];
		sprBurstStart[n33] <= 9'h000;
		sprBurstEnd[n33] <= 9'h1FE;
		sprColorDepth[n33] <= 2'b10;
		if (n33 >= 5'd29) begin
			sprFrameSize[n33] <= 12'd1936;
			sprFrames[n33] <= 8'd0;
		end
		else begin
			sprFrameSize[n33] <= 12'd504;
			sprFrames[n33] <= 8'd3;
		end
		sprRate[n33] <= 12'd10;
		sprEnableAnimation[n33] <= n33 < 5'd29;
		sprAutoRepeat[n33] <= 1'b1;
	end
  hSprPos[0] <= 210;
  vSprPos[0] <= 72;

  bgTc <= 24'h08_08_08;
  bkColor <= 24'hFF_FF_60;
end
else begin
	ce <= xonoff_i;
	vSync1 <= vSync;
	if (vSync & ~vSync1)
		sprDt <= sprDt | vSyncT;

	// clear DMA trigger bit once DMA is recognized
	if (dmaStart[5])
		sprDt[dmaOwner] <= 1'b0;

	// Disable animation after frame count expired, if not auto-repeat.
  for (n33 = 0; n33 < pnSpr; n33 = n33 + 1)
		if (sprCurFrame[n33] >= sprFrames[n33] && !sprAutoRepeat[n33])
			sprEnableAnimation[n33] <= 1'b0;

	if (cs_io & wb_reqs.we) begin

		casez (wb_reqs.adr[9:2])
		8'b100?????:
			begin
				if (&wb_reqs.sel[1:0]) sprBurstStart[wb_reqs.adr[6:2]] <= {wb_reqs.dat[8:1],1'b0};
				if (&wb_reqs.sel[3:2]) sprBurstEnd[wb_reqs.adr[6:2]] <= {wb_reqs.dat[24:17],1'b0};
			end
		8'b101?????:
			begin
				if (wb_reqs.sel[0]) sprFrameSize[wb_reqs.adr[6:2]][11:4] <= wb_reqs.dat[7:0];
				if (wb_reqs.sel[1]) sprFrames[wb_reqs.adr[6:2]] <= wb_reqs.dat[15:8];
				if (wb_reqs.sel[2]) sprRate[wb_reqs.adr[6:2]][7:0] <= wb_reqs.dat[23:16];
				if (wb_reqs.sel[3]) 
					begin
						sprRate[wb_reqs.adr[6:2]][9:8] <= wb_reqs.dat[25:24];
						sprFrameSize[wb_reqs.adr[6:2]][3:0] <= wb_reqs.dat[29:26];
						sprAutoRepeat[wb_reqs.adr[6:2]] <= wb_reqs.dat[30];
						sprEnableAnimation[wb_reqs.adr[6:2]] <= wb_reqs.dat[31];
					end
			end
		8'b11110000:	// 3C0
			begin
				if (wb_reqs.sel[0]) sprEn[7:0] <= wb_reqs.dat[7:0];
				if (wb_reqs.sel[1]) sprEn[15:8] <= wb_reqs.dat[15:8];
				if (wb_reqs.sel[2]) sprEn[23:16] <= wb_reqs.dat[23:16];
				if (wb_reqs.sel[3]) sprEn[31:24] <= wb_reqs.dat[31:24];
			end
		8'b11110001:	// 3C4
			if (wb_reqs.sel[0]) begin
				sprSprIe <= wb_reqs.dat[0];
				sprBkIe <= wb_reqs.dat[1];
			end
		// update DMA trigger
		// s_wb_reqs.dat[7:0] indicates which triggers to set  (1=set,0=ignore)
		// s_wb_reqs.dat[7:0] indicates which triggers to clear (1=clear,0=ignore)
		8'b11110100:	// 3D0
			begin
				if (wb_reqs.sel[0])	sprDt[7:0] <= sprDt[7:0] | wb_reqs.dat[7:0];
				if (wb_reqs.sel[1]) sprDt[15:8] <= sprDt[15:8] | wb_reqs.dat[15:8];
				if (wb_reqs.sel[2]) sprDt[23:16] <= sprDt[23:16] | wb_reqs.dat[23:16];
				if (wb_reqs.sel[3])	sprDt[31:24] <= sprDt[31:24] | wb_reqs.dat[31:24];
			end
		8'b11110101:	// 3D4
			begin
				if (wb_reqs.sel[0])	sprDt[7:0] <= sprDt[7:0] & ~wb_reqs.dat[7:0];
				if (wb_reqs.sel[1]) sprDt[15:8] <= sprDt[15:8] & ~wb_reqs.dat[15:8];
				if (wb_reqs.sel[2]) sprDt[23:16] <= sprDt[23:16] & ~wb_reqs.dat[23:16];
				if (wb_reqs.sel[3])	sprDt[31:24] <= sprDt[31:24] & ~wb_reqs.dat[31:24];
			end
		8'b11110110:	// 3D8
			begin
				if (wb_reqs.sel[0])	vSyncT[7:0] <= wb_reqs.dat[7:0];
				if (wb_reqs.sel[1]) vSyncT[15:8] <= wb_reqs.dat[15:8];
				if (wb_reqs.sel[2]) vSyncT[23:16] <= wb_reqs.dat[23:16];
				if (wb_reqs.sel[3])	vSyncT[31:24] <= wb_reqs.dat[31:24];
			end
		8'b11111010:	// 3E8
			begin
				if (wb_reqs.sel[0])	bgTc[7:0] <= wb_reqs.dat[7:0];
				if (wb_reqs.sel[1])	bgTc[15:8] <= wb_reqs.dat[15:8];
				if (wb_reqs.sel[2])	bgTc[23:16] <= wb_reqs.dat[23:16];
				if (wb_reqs.sel[3])	bgTc[29:24] <= wb_reqs.dat[29:24];
			end
		8'b11111011:	// 3EC
			begin
				if (wb_reqs.sel[0]) bkColor[7:0] <= wb_reqs.dat[7:0];
				if (wb_reqs.sel[1]) bkColor[15:8] <= wb_reqs.dat[15:8];
				if (wb_reqs.sel[2]) bkColor[23:16] <= wb_reqs.dat[23:16];
				if (wb_reqs.sel[3]) bkColor[29:24] <= wb_reqs.dat[29:24];
			end
//		8'b11111100:	// 3F0
//			if (wb_reqs.sel[0]) ce <= wb_reqs[0];
		8'b0?????00:
			 begin
	    		if (wb_reqs.sel[0]) hSprPos[sprN][ 7:0] <= wb_reqs.dat[ 7: 0];
	    		if (wb_reqs.sel[1]) hSprPos[sprN][11:8] <= wb_reqs.dat[11: 8];
	    		if (wb_reqs.sel[2]) vSprPos[sprN][ 7:0] <= wb_reqs.dat[23:16];
	    		if (wb_reqs.sel[3]) vSprPos[sprN][11:8] <= wb_reqs.dat[27:24];
    		end
    8'b0?????01:
			begin
    		if (wb_reqs.sel[0]) begin
					sprWidth[sprN] <= wb_reqs.dat[7:0];
        end
    		if (wb_reqs.sel[1]) begin
					sprHeight[sprN] <= wb_reqs.dat[15:8];
        end
				if (wb_reqs.sel[2]) begin
        	hSprRes[sprN] <= wb_reqs.dat[19:16];
        	vSprRes[sprN] <= wb_reqs.dat[23:20];
				end
				if (wb_reqs.sel[3]) begin
					sprPlane[sprN] <= wb_reqs.dat[27:24];
					sprColorDepth[sprN] <= wb_reqs.dat[31:30];
				end
			end
		8'b0?????10:
			begin	// DMA address set on clk_i domain
        if (wb_reqs.sel[0]) sprImageOffs[sprN][ 7:0] <= wb_reqs.dat[7:0];
        if (wb_reqs.sel[1]) sprImageOffs[sprN][11:8] <= wb_reqs.dat[11:8];
				if (wb_reqs.sel[1]) sprSysAddr[sprN][15:12] <= wb_reqs.dat[15:12];
				if (wb_reqs.sel[2]) sprSysAddr[sprN][23:16] <= wb_reqs.dat[23:16];
				if (wb_reqs.sel[3]) sprSysAddr[sprN][31:24] <= wb_reqs.dat[31:24];
			end
		8'b0?????11:
			begin
				if (wb_reqs.sel[0]) sprTc[sprN][ 7:0] <= wb_reqs.dat[ 7:0];
				if (wb_reqs.sel[1]) sprTc[sprN][15:8] <= wb_reqs.dat[15:8];
				if (wb_reqs.sel[2]) sprTc[sprN][23:16] <= wb_reqs.dat[23:16];
			end

		default:	;
		endcase
	
	end
end

//-------------------------------------------------------------
// Sprite Image Cache RAM
// This RAM is dual ported with an SoC side and a display
// controller side.
//-------------------------------------------------------------

integer n2;
always_ff @(posedge vclk)
for (n2 = 0; n2 < pnSpr; n2 = n2 + 1)
case(sprColorDepth[n2])
2'd1:	sprAddr1[n2] <= {sprAddr[n2][11:3],~sprAddr[n2][2]};
2'd2:	sprAddr1[n2] <= {sprAddr[n2][10:2],~sprAddr[n2][1]};
2'd3:	sprAddr1[n2] <= {sprAddr[n2][ 9:1],~sprAddr[n2][0]};
default:	;
endcase

// The three LSBs of the image index need to be pipelined so they may be used
// to select the pixel. Output from the SRAM is always 32-bits wide so an
// additional mux is needed.
integer n4, n5, n27, n29;
always_ff @(posedge vclk)
for (n4 = 0; n4 < pnSpr; n4 = n4 + 1)
	sprAddr2[n4] <= ~sprAddr[n4][2:0];
always_ff @(posedge vclk)
for (n5 = 0; n5 < pnSpr; n5 = n5 + 1)
	sprAddr3[n5] <= sprAddr2[n5];
always_ff @(posedge vclk)
for (n27 = 0; n27 < pnSpr; n27 = n27 + 1)
	sprAddr4[n27] <= sprAddr3[n27];
always_ff @(posedge vclk)
for (n29 = 0; n29 < pnSpr; n29 = n29 + 1)
	sprAddr5[n29] <= sprAddr4[n29];

// The pixels are displayed from most signicant to least signicant bits of the 
// word. Display order is opposite to memory storage. So, the least significant
// address bits are flipped to get the correct display.
integer n3;
always_ff @(posedge vclk)
for (n3 = 0; n3 < pnSpr; n3 = n3 + 1)
case(sprColorDepth[n3])
2'd1:
	case(sprAddr5[n3][1:0])
	2'd3:	sprOut5[n3] <= sprOut4[n3][31:24];
	2'd2:	sprOut5[n3] <= sprOut4[n3][23:16];
	2'd1:	sprOut5[n3] <= sprOut4[n3][15:8];
	2'd0:	sprOut5[n3] <= sprOut4[n3][7:0];
	endcase
2'd2:
	case(sprAddr5[n3][0])
	1'd0:	sprOut5[n3] <= {sprOut4[n3][15],16'h0000,sprOut4[n3][14:0]};
	1'd1:	sprOut5[n3] <= {sprOut4[n3][31],16'h0000,sprOut4[n3][30:16]};
	endcase
2'd3:
	sprOut5[n3] <= sprOut4[n3];
default:	;
endcase

generate
for (g = 0; g < pnSpr; g = g + 1) begin : sprRam
	SpriteRam sprRam0
	(
		.clka(m_clk_i),
		.addra(m_adr_or),
		.dina(m_dat_ir[63:0]),
		.ena(sprWe[g]),
		.wea(sprWe[g]),
		// Core reg and output reg 3 clocks from read address
		.clkb(vclk),
		.addrb(sprAddr1[g]),
		.doutb(sprOut4[g]),
		.enb(1'b1)
	);
	end
endgenerate

//-------------------------------------------------------------
// Timing counters and addressing
// Sprites are like miniature bitmapped displays, they need
// all the same timing controls.
//-------------------------------------------------------------

// Create a timing reference using horizontal and vertical
// sync
wire hSyncEdge, vSyncEdge;
edge_det ed0(.rst(rst_i), .clk(vclk), .ce(1'b1), .i(hSync), .pe(hSyncEdge), .ne(), .ee() );
edge_det ed1(.rst(rst_i), .clk(vclk), .ce(1'b1), .i(vSync), .pe(vSyncEdge), .ne(), .ee() );

always_ff @(posedge vclk)
if (hSyncEdge) hctr <= {phBits{1'b0}};
else hctr <= hctr + 2'd1;

always_ff @(posedge vclk)
if (vSyncEdge) vctr <= {pvBits{1'b0}};
else if (hSyncEdge) vctr <= vctr + 2'd1;

// track sprite horizontal reset
integer n19;
always_ff @(posedge vclk)
for (n19 = 0; n19 < pnSpr; n19 = n19 + 1)
	hSprReset[n19] <= hctr==hSprPos[n19];

// track sprite vertical reset
integer n20;
always_ff @(posedge vclk)
for (n20 = 0; n20 < pnSpr; n20 = n20 + 1)
	vSprReset[n20] <= vctr==vSprPos[n20];

integer n21;
always_comb
for (n21 = 0; n21 < pnSpr; n21 = n21 + 1)
	sprDe[n21] <= hSprDe[n21] & vSprDe[n21];


// take care of sprite size scaling
// video clock division
reg [31:0] hSprNextPixel;
reg [31:0] vSprNextPixel;
reg [3:0] hSprPt [31:0];   // horizontal pixel toggle
reg [3:0] vSprPt [31:0];   // vertical pixel toggle
integer n17;
always_comb
for (n17 = 0; n17 < pnSpr; n17 = n17 + 1)
    hSprNextPixel[n17] = hSprPt[n17]==hSprRes[n17];
integer n18;
always_comb
for (n18 = 0; n18 < pnSpr; n18 = n18 + 1)
    vSprNextPixel[n18] = vSprPt[n18]==vSprRes[n18];

// horizontal pixel toggle counter
integer n6;
always_ff @(posedge vclk)
for (n6 = 0; n6 < pnSpr; n6 = n6 + 1)
	if (hSprReset[n6])
		hSprPt[n6] <= 4'd0;
  else if (hSprNextPixel[n6])
    hSprPt[n6] <= 4'd0;
  else
    hSprPt[n6] <= hSprPt[n6] + 2'd1;

// vertical pixel toggle counter
integer n7;
always_ff @(posedge vclk)
for (n7 = 0; n7 < pnSpr; n7 = n7 + 1)
  if (hSprReset[n7]) begin
  	if (vSprReset[n7])
  		vSprPt[n7] <= 4'd0;
    else if (vSprNextPixel[n7])
      vSprPt[n7] <= 4'd0;
    else
      vSprPt[n7] <= vSprPt[n7] + 2'd1;
  end

// Animation rate count and frame increment.
integer n28;
always_ff @(posedge vclk)
	if (vSyncEdge) begin
		for (n28 = 0; n28 < pnSpr; n28 = n28 + 1) begin
			if (sprEnableAnimation[n28]) begin
				sprCurRateCount[n28] <= sprCurRateCount[n28] + 2'd1;
				if (sprCurRateCount[n28] >= sprRate[n28]) begin
					sprCurRateCount[n28] <= 'd0;
					sprCurFrame[n28] <= sprCurFrame[n28] + 2'd1;
					sprFrameProd[n28] <= sprFrameProd[n28] + sprFrameSize[n28];
					if (sprCurFrame[n28] >= sprFrames[n28]) begin
						sprCurFrame[n28] <= 'd0;
						sprFrameProd[n28] <= 'd0;
					end
				end
			end
			else begin
				sprCurFrame[n28] <= 'd0;
				sprFrameProd[n28] <= 'd0;
			end
		end
	end

// clock sprite image address counters
integer n8;
always_ff @(posedge vclk)
for (n8 = 0; n8 < pnSpr; n8 = n8 + 1) begin
    // hReset and vReset - top left of sprite,
    // reset address to image offset
	if (hSprReset[n8] & vSprReset[n8]) begin
		sprAddr[n8]  <= sprImageOffs[n8] + sprFrameProd[n8];
		sprAddrB[n8] <= sprImageOffs[n8] + sprFrameProd[n8];
	end
	// hReset:
	//  If the next vertical pixel
	//      set backup address to current address
	//  else
	//      set current address to backup address
	//      in order to rescan the line
	else if (hSprReset[n8]) begin
		if (vSprNextPixel[n8])
			sprAddrB[n8] <= sprAddr[n8];
		else
			sprAddr[n8]  <= sprAddrB[n8];
	end
	// Not hReset or vReset - somewhere on the sprite scan line
	// just advance the address when the next pixel should be
	// fetched
	else if (hSprDe[n8] & hSprNextPixel[n8])
		sprAddr[n8] <= sprAddr[n8] + 2'd1;
end


// clock sprite column (X) counter
integer n9;
always_ff @(posedge vclk)
for (n9 = 0; n9 < pnSpr; n9 = n9 + 1)
	if (hSprReset[n9])
		hSprCnt[n9] <= 8'd1;
	else if (hSprNextPixel[n9])
		hSprCnt[n9] <= hSprCnt[n9] + 2'd1;


// clock sprite horizontal display enable
integer n10;
always_ff @(posedge vclk)
for (n10 = 0; n10 < pnSpr; n10 = n10 + 1) begin
	if (hSprReset[n10])
		hSprDe[n10] <= 1'b1;
	else if (hSprNextPixel[n10]) begin
		if (hSprCnt[n10] == sprWidth[n10])
			hSprDe[n10] <= 1'b0;
	end
end


// clock the sprite row (Y) counter
integer n11;
always_ff @(posedge vclk)
for (n11 = 0; n11 < pnSpr; n11 = n11 + 1)
	if (hSprReset[n11]) begin
		if (vSprReset[n11])
			vSprCnt[n11] <= 8'd1;
		else if (vSprNextPixel[n11])
			vSprCnt[n11] <= vSprCnt[n11] + 2'd1;
	end


// clock sprite vertical display enable
integer n12;
always_ff @(posedge vclk)
for (n12 = 0; n12 < pnSpr; n12 = n12 + 1) begin
	if (hSprReset[n12]) begin
		if (vSprReset[n12])
			vSprDe[n12] <= 1'b1;
		else if (vSprNextPixel[n12]) begin
			if (vSprCnt[n12] == sprHeight[n12])
				vSprDe[n12] <= 1'b0;
		end
	end
end


//-------------------------------------------------------------
// Output stage
//-------------------------------------------------------------

// function used for color blending
// given an alpha and a color component, determine the resulting color
// this blends towards black or white
// alpha is eight bits ranging between 0 and 1.999...
// 1 bit whole, 7 bits fraction
function [11:0] fnBlend;
input [7:0] alpha;
input [11:0] color1bits;
input [11:0] color2bits;

begin
	fnBlend = (({8'b0,color1bits} * alpha) >> 7) + (({8'h00,color2bits} * (9'h100 - alpha)) >> 7);
end
endfunction


// pipeline delays for display enable
reg [31:0] sprDe1, sprDe2, sprDe3, sprDe4, sprDe5, sprDe6;
reg [31:0] sproact;
integer n13;
always_ff @(posedge vclk)
for (n13 = 0; n13 < pnSpr; n13 = n13 + 1)
	sprDe1[n13] <= sprDe[n13];
integer n22;
always_ff @(posedge vclk)
for (n22 = 0; n22 < pnSpr; n22 = n22 + 1)
	sprDe2[n22] <= sprDe1[n22];
integer n23;
always_ff @(posedge vclk)
for (n23 = 0; n23 < pnSpr; n23 = n23 + 1)
	sprDe3[n23] <= sprDe2[n23];
integer n24;
always_ff @(posedge vclk)
for (n24 = 0; n24 < pnSpr; n24 = n24 + 1)
	sprDe4[n24] <= sprDe3[n24];
integer n25;
always_ff @(posedge vclk)
for (n25 = 0; n25 < pnSpr; n25 = n25 + 1)
	sprDe5[n25] <= sprDe4[n25];
integer n26;
always_ff @(posedge vclk)
for (n26 = 0; n26 < pnSpr; n26 = n26 + 1)
	sprDe6[n26] <= sprDe5[n26];


// Detect which sprite outputs are active
// The sprite output is active if the current display pixel
// address is within the sprite's area, the sprite is enabled,
// and it's not a transparent pixel that's being displayed.
integer n14;
always_ff @(posedge vclk)
for (n14 = 0; n14 < pnSpr; n14 = n14 + 1)
	sproact[n14] <= sprEn[n14] && sprDe5[n14] && sprTc[n14]!=sprOut5[n14];
integer n15;
always_ff @(posedge vclk)
for (n15 = 0; n15 < pnSpr; n15 = n15 + 1)
	sprOut[n15] <= sprOut5[n15];

// register sprite activity flag
// The image combiner uses this flag to know what to do with
// the sprite output.
always_ff @(posedge vclk)
	outact <= |sproact & ce;

// Display data comes from the active sprite with the
// highest display priority.
// Make sure that alpha blending is turned off when
// no sprite is active.
integer n16;
always_ff @(posedge vclk)
begin
	out <= 32'h0080;	// alpha blend max (and off)
	outplane <= 4'h0;
	colorBits <= 2'b00;
	for (n16 = pnSprm; n16 >= 0; n16 = n16 - 1)
		if (sproact[n16]) begin
			out <= sprOut[n16];
			outplane <= sprPlane[n16];
			colorBits <= sprColorDepth[n16];
		end
end


// combine the text / graphics color output with sprite color output
// blend color output
wire [35:0] blendedColor32 = {
 	fnBlend({out[31:27],3'd0},{out[26:18],4'h0},zrgb_i[35:24]),
 	fnBlend({out[31:27],3'd0},{out[17:9],4'h0},zrgb_i[23:12]),
 	fnBlend({out[31:27],3'd0},{out[8:0],4'h0},zrgb_i[11: 0])}
 	;

wire [35:0] blendedColor16 = {
 	fnBlend({out[15:12],4'd0},{out[11:8],8'h0},zrgb_i[35:24]),
 	fnBlend({out[15:12],4'd0},{out[7:4],8'h0},zrgb_i[23:12]),
 	fnBlend({out[15:12],4'd0},{out[3:0],8'h0},zrgb_i[11: 0])}
 	;

wire [35:0] blendedColor8 = {
 	fnBlend({out[7:6],6'd0},{out[5:4],10'h0},zrgb_i[35:24]),
 	fnBlend({out[7:6],6'd0},{out[3:2],10'h0},zrgb_i[23:12]),
 	fnBlend({out[7:6],6'd0},{out[1:0],10'h0},zrgb_i[11: 0])}
 	;

always_ff @(posedge vclk)
if (blank_i)
	zrgb_o <= 0;
else begin
	if (outact) begin
		if (zrgb_i[39:36] > outplane) begin			// rgb input is in front of sprite
			zrgb_o <= zrgb_i;
		end
		else 
			case(colorBits)
			2'd2:	zrgb_o <= {outplane,blendedColor16};
			2'd3:	zrgb_o <= {outplane,blendedColor32};
			default:	zrgb_o <= {outplane,blendedColor8};
			endcase
	end
	else
		zrgb_o <= zrgb_i;
end


//--------------------------------------------------------------------
// Collision logic
//--------------------------------------------------------------------

// Detect when a sprite-sprite collision has occurred. The criteria
// for this is that a pixel from the sprite is being displayed, while
// there is a pixel from another sprite that could be displayed at the
// same time.

//--------------------------------------------------------------------
// ToDo: make collision also depend on plane
//--------------------------------------------------------------------

cntpop32 ucntp1 (
	.i(sproact),
	.o(actcnt)
);

// Detect when a sprite-background collision has occurred
integer n31;
always_comb
for (n31 = 0; n31 < pnSpr; n31 = n31 + 1)
	bkCollision[n31] <=
		sproact[n31] && zrgb_i[39:36]==sprPlane[n31];

// Load the sprite collision register. This register continually
// accumulates collision bits until reset by reading the register.
// Set the collision IRQ on the first collision and don't set it
// again until after the collision register has been read.
always_ff @(posedge vclk)
if (rst_i) begin
	sprSprIRQPending1 <= 0;
	sprSprCollision1 <= 0;
	sprSprIRQ1 <= 0;
end
else if (actcnt > 6'd1) begin
	// isFirstCollision
	if ((sprSprCollision1==0)||(cs_io && wb_reqs.sel[0] && wb_reqs.adr[9:2]==8'b11110010)) begin
		sprSprIRQPending1 <= 1;
		sprSprIRQ1 <= sprSprIe;
		sprSprCollision1 <= sproact;
	end
	else
		sprSprCollision1 <= sprSprCollision1|sproact;
end
else if (cs_io && wb_reqs.sel[0] && wb_reqs.adr[9:2]==8'b11110010) begin
	sprSprCollision1 <= 0;
	sprSprIRQPending1 <= 0;
	sprSprIRQ1 <= 0;
end


// Load the sprite background collision register. This register
// continually accumulates collision bits until reset by reading
// the register.
// Set the collision IRQ on the first collision and don't set it
// again until after the collision register has been read.
// Note the background collision indicator is externally supplied,
// it will come from the color processing logic.
always_ff @(posedge vclk)
if (rst_i) begin
	sprBkIRQPending1 <= 0;
	sprBkCollision1 <= 0;
	sprBkIRQ1 <= 0;
end
else if (|bkCollision) begin
	// Is the register being cleared at the same time
	// a collision occurss ?
	// isFirstCollision
	if ((sprBkCollision1==0) || (cs_io && wb_reqs.sel[0] && wb_reqs.adr[9:2]==8'b11110011)) begin	
		sprBkIRQ1 <= sprBkIe;
		sprBkCollision1 <= bkCollision;
		sprBkIRQPending1 <= 1;
	end
	else
		sprBkCollision1 <= sprBkCollision1|bkCollision;
end
else if (cs_io && wb_reqs.sel[0] && wb_reqs.adr[9:2]==8'b11110011) begin
	sprBkCollision1 <= 0;
	sprBkIRQPending1 <= 0;
	sprBkIRQ1 <= 0;
end

endmodule

/*
module SpriteRam32 (
	clka, adra, dia, doa, cea, wea,
	clkb, adrb, dib, dob, ceb, web
);
input clka;
input [9:0] adra;
input [31:0] dia;
output [31:0] doa;
input cea;
input wea;
input clkb;
input [9:0] adrb;
input [31:0] dib;
output [31:0] dob;
input ceb;
input web;

reg [31:0] mem [0:1023];
reg [9:0] radra;
reg [9:0] radrb;

always @(posedge clka)	if (cea) radra <= adra;
always @(posedge clkb) 	if (ceb) radrb <= adrb;
assign doa = mem [radra];
assign dob = mem [radrb];
always @(posedge clka)
	if (cea & wea) mem[adra] <= dia;
always @(posedge clkb)
	if (ceb & web) mem[adrb] <= dib;

endmodule

*/
