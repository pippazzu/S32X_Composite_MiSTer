// 32X NTSC board networks between the BA7237's Y/C outputs and its Y/C MIX
// inputs, and the resulting composite video at the 32X's AV jack.
//
//   Luma   measured, not the schematic: a 20 MHz stage into a 1.56 MHz, Q 0.57
//          second-order low-pass, DC gain 1/2 (see below)
//   Chroma C OUT - R47 100R - node, node - C77 47nF - C IN
//                             node - L4 12uH, C78 100pF - GND
//
// Chroma: 32X service manual, schematic diagram 3 and its NTSC/PAL difference table
// (R48 not fitted). The BA7237 has no data sheet, so C OUT is taken as a 75R driver
// as on the BA7232 and C IN as loading nothing. The output amplifier's 6 MHz
// bandwidth (BA7230) is one pole.
//
// Luma: the schematic network (Y OUT - R45 0R - L5 100uH || C74 18pF - Y IN with
// C75 56pF, R46 empty) with the BA7230's 1k source and load inside the chip passes
// far more than a real 32X: measured on a 32X in pass-through (stripes of 0.42 to
// 3.36 MHz, white-to-black pulses on grey, corrected for the 0.7 dB cable loss of the
// measuring chain), the response falls from 0.93 at 0.42 MHz to 0.53 at 1.68 MHz and
// 0.18 at 3.36 MHz, without peaking or a trap. That is reproduced to about 0.03 by a
// 1.56 MHz, Q 0.57 second-order low-pass (with the 6 MHz pole below): series RLC with
// 1k characteristic impedance, preceded by a 20 MHz pole, input gain 1/2. These
// values describe one console and are not derived from its parts.
//
// Each network is the exact zero-order-hold discretisation of its state
// equations at the master clock T: for dx/dt = Ac x + Bc u, A = exp(Ac T) and
// B = Ac^-1 (A - I) Bc, with currents carried as volts across 1k. Q16
// coefficients and Q3.16 states, every product 18 x 19.

module s32x_av_board (
	input                    clk,
	input                    reset,
	input  signed [23:0]     y_in,     // Q2.21, jack-referred luma + sync
	input  signed [23:0]     c_in,     // Q2.21, jack-referred chroma + burst
	output reg signed [23:0] cvbs      // Q2.21 volts at the jack, 75R terminated
);

// Luma: states {20 MHz stage, RLC current x 1k, output voltage}.
localparam signed [17:0] LA00 =   18'sd6310;
localparam signed [17:0] LA01 =  18'sd0;
localparam signed [17:0] LA02 =  18'sd0;
localparam signed [17:0] LA10 =   18'sd3684;
localparam signed [17:0] LA11 =   18'sd46620;
localparam signed [17:0] LA12 = -18'sd10153;
localparam signed [17:0] LA20 =  18'sd504;
localparam signed [17:0] LA21 =   18'sd10153;
localparam signed [17:0] LA22 =   18'sd64559;
localparam signed [17:0] LB0  =   18'sd29613;
localparam signed [17:0] LB1  =   18'sd3235;
localparam signed [17:0] LB2  =   18'sd237;

// Chroma: states {L4 current x 1k, node voltage}; 175R source, no load.
localparam signed [17:0] CA00 =  18'sd58842;
localparam signed [17:0] CA01 =  18'sd59683;
localparam signed [17:0] CA10 = -18'sd7162;
localparam signed [17:0] CA11 =  18'sd17917;
localparam signed [17:0] CB0  =  18'sd38249;
localparam signed [17:0] CB1  =  18'sd40926;

// Output pole at 6 MHz: 1 - exp(-2 pi 6 MHz T), Q16.
localparam signed [17:0] KOUT =  18'sd33061;

function automatic signed [18:0] sat19(input signed [24:0] v);
	if      (v >  25'sd262143) sat19 =  19'sd262143;
	else if (v < -25'sd262144) sat19 = 19'sh40000;
	else                       sat19 =  v[18:0];
endfunction

// One state row: two sums of two products, each sum one DSP block.
function automatic signed [18:0] row(
	input signed [17:0] a0, input signed [18:0] x0,
	input signed [17:0] a1, input signed [18:0] x1,
	input signed [17:0] a2, input signed [18:0] x2,
	input signed [17:0] bb, input signed [18:0] u);
	/* verilator lint_off UNUSEDSIGNAL */
	reg signed [40:0] acc;
	/* verilator lint_on UNUSEDSIGNAL */
	begin
		acc = (a0 * x0 + a1 * x1) + (a2 * x2 + bb * u);
		row = sat19(acc[40:16]);
	end
endfunction

// Q2.21 in, Q3.16 out of the pins: Y OUT at twice the jack level for its
// 1k / 1k network, C OUT at the jack level.
wire signed [18:0] uy = y_in[22:4];
wire signed [18:0] uc = c_in[23:5];

reg signed [18:0] l0, l1, l2;
reg signed [18:0] k0, k1;

always @(posedge clk) begin
	if (reset) begin
		{l0, l1, l2} <= 57'd0;
		{k0, k1} <= 38'd0;
	end else begin
		l0 <= row(LA00, l0, LA01, l1, LA02, l2, LB0, uy);
		l1 <= row(LA10, l0, LA11, l1, LA12, l2, LB1, uy);
		l2 <= row(LA20, l0, LA21, l1, LA22, l2, LB2, uy);
		k0 <= row(CA00, k0, CA01, k1, 18'sd0, 19'sd0, CB0, uc);
		k1 <= row(CA10, k0, CA11, k1, 18'sd0, 19'sd0, CB1, uc);
	end
end

// Y/C mix and the output amplifier's pole.
reg  signed [18:0] vo;
wire signed [19:0] mix = l2 + k1;
wire signed [20:0] dv  = mix - vo;
/* verilator lint_off UNUSEDSIGNAL */
wire signed [38:0] dk  = dv * KOUT;
/* verilator lint_on UNUSEDSIGNAL */

always @(posedge clk) begin
	if (reset) vo <= 19'sd0;
	else       vo <= sat19(vo + $signed(dk[38:16]));
end

always @(posedge clk) begin
	if (reset) cvbs <= 24'sd0;
	else       cvbs <= {vo, 5'd0};
end

endmodule
