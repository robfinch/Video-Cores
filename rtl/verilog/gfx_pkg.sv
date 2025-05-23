// ============================================================================
//        __
//   \\__/ o\    (C) 2015-2025  Robert Finch, Waterloo
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

package gfx_pkg;

parameter point_width = 16;
parameter address_width = 32;

typedef enum logic [1:0] {
	BPP8 = 2'd0,		// 8
	BPP16 = 2'd1,		// 1-5-5-5
	BPP24 = 2'd2,		// 1-8-8-7
	BPP32 = 2'd3		// 2-10-10-10
} color_depth_t;

typedef enum logic [3:0] {
	FB_IDLE = 4'd0,
	FB_NEXT_BURST = 4'd1,
	LOADCOLOR = 4'd2,
	LOADSTRIP = 4'd3,
	STORESTRIP = 4'd4,
	ACKSTRIP = 4'd5,
	WAITLOAD = 4'd6,
	WAITRST = 4'd7,
	ICOLOR1 = 4'd8,
	ICOLOR2 = 4'd9,
	ICOLOR3 = 4'd10,
	ICOLOR4 = 4'd11,
	LOAD_OOB = 4'd12,
	PCMD1 = 4'd13,
	PCMD2 = 4'd14,
	PCMD3 = 4'd15
} fb_state_t;

endpackage
