module rfFrameBuffer_tb();

reg rst;
reg clk;
wire [31:0] fb_irq;
fta_cmd_request128_t fb_req;
fta_cmd_response128_t fb_resp, fb_resp1;
wire [31:0] fb_rgb;
wire hSync, vSync, blank, border;

initial begin
	rst = 1'b0;
	clk = 1'b0;
	#100 rst = 1'b1;
	#500 rst = 1'b0;
end

always 
	#12.5 clk <= ~clk;

rfFrameBuffer_fta64 uframebuf1
(
	.rst_i(rst),
	.irq_o(fb_irq),
	.cs_config_i(1'b0),
	.cs_io_i(1'b0),
	.s_clk_i(clk),
	.s_req('d0),
	.s_resp(),
	.m_clk_i(clk),
	.m_fst_o(), 
	.m_req(fb_req),
	.m_resp(fb_resp1),
	.dot_clk_i(clk),
	.rgb_i('d0),
	.rgb_o(fb_rgb),
	.xonoff_i(1'b1),
	.xal_o(),
	.hsync_o(hSync),
	.vsync_o(vSync),
	.blank_o(blank),
	.border_o(border),
	.hctr_o(),
	.vctr_o(),
	.fctr_o(),
	.vblank_o()
);

VideoTPG uvtpg1
(
	.rst(rst),
	.clk(clk),
	.en(1'b1),
	.vSync(vSync),
	.req(fb_req),
	.resp(fb_resp1),
	.ex_resp('d0)
);

endmodule
