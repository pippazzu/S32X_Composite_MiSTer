// Rohm BA7237FS (Sega 315-5788), the 32X's RGB encoder, NTSC mode, one
// sample per master clock.
//
// The 32X takes the Mega Drive's RGB from its AV port and the 32X ASIC's
// RGB, picks one per pixel with YS, and encodes the result; the Mega Drive's
// own composite output is not used. Sega published only the block diagram
// (32X service manual, IC12): two clamped RGB sets, a YS switch, the matrix,
// a chroma generator driven by a VCXO and the burst flag, sync mixing and
// Y/C mixing around external networks. Its VCXO is phase-locked to the
// burst of the Mega Drive's composite video on VIN (pin 14, APC filter on
// PDO), so the colour carrier is the Mega Drive's subcarrier.
//
// Levels are those of the BA7232FS, the family member with a data sheet,
// and the modulators are the family's rectangular two-phase balanced
// modulators (BA7230LS data sheet):
//
//   R/G/B in      1 Vp-p = 100%, clamped to the level seen in the burst flag
//   White         0.70 V      Y = 0.30 R + 0.59 G + 0.11 B
//   Sync          0.30 V      added in the Y path while C SYNC is low
//   Burst         0.29 Vp-p   180 deg
//   Chroma        0.493 (B-Y) and 0.877 (R-Y), square-wave carriers
//
// Outputs are jack-referred; s32x_av_board drives the 32X's networks with
// them. Taken as assumptions, since nothing published gives them:
//   * the burst flag comes 0.5 us after the C-SYNC rising edge for 2.75 us,
//     as in the Mega Drive's CXA1145;
//   * the 32X's burst has the phase of the Mega Drive's burst at its jack: the
//     CXA1145's 63.9 degree carrier lag plus the 5.1 degrees of the Mega Drive's
//     chroma network, with one correction. On a 32X in pass-through every colour
//     (both layers, six patterns) measured 7.6 degrees (6.8 to 8.4) behind where
//     that puts it against the burst, once the measuring chain's 1 degree is taken
//     off, so the burst here carries a small component on the v axis (BURST_V,
//     tan 7.6 degrees of the peak, with BURST_PEAK scaled to keep 0.29 Vp-p). One
//     console; the real figure is the APC loop's static phase error, which will
//     vary with the unit's oscillator.

module ba7237 (
	input                clk,
	input                reset,

	input          [8:0] r2,        // two-tick sums after the YS switch, 510 = 1 V
	input          [8:0] g2,
	input          [8:0] b2,
	input          [1:0] s2,        // ticks C SYNC was low
	input          [5:0] ang,       // subcarrier angle, 6 degree steps

	output reg signed [23:0] y_out,  // Q2.21 volts, jack-referred, with sync
	output reg signed [23:0] c_out   // Q2.21 volts, jack-referred, with burst
);

// 0.70 V / 510 per input step in Q2.21, split by the luma weights.
localparam signed [12:0] KYR = 13'sd863;
localparam signed [12:0] KYG = 13'sd1698;
localparam signed [12:0] KYB = 13'sd317;
localparam signed [12:0] K   = 13'sd2878;
// Colour difference weights, Q16.
localparam signed [16:0] KU  = 17'sd32309;     // 0.493
localparam signed [16:0] KV  = 17'sd57475;     // 0.877
// Sync tip 0.30 V, Q2.21, and burst peak 0.145 V, Q2.16.
localparam signed [23:0] SYNC_TICK  = 24'sd314573;  // per tick, two per sample
localparam signed [18:0] BURST_PEAK = 19'sd9420;   // burst on the -u axis
localparam signed [18:0] BURST_V    = 19'sd1257;   // and a little on the v axis: see the hue note below

// Burst flag from the C SYNC rising edge, in master clocks.
localparam [7:0]  BF_DELAY = 8'd27;      // 0.50 us
localparam [7:0]  BF_WIDTH = 8'd148;     // 2.76 us
// Half-H killer: a rising edge within 0.75 H of the last is not a line.
localparam [11:0] HALF_H_KILL = 12'd2565;

// ------------------------------------------------------------ carrier table

// A +-1 square wave in phase with sin(n * 6 deg - 69.0 deg), averaged over the
// 24 degrees of a master clock, scaled to a fundamental of 2047.
function automatic signed [11:0] carrier(input [5:0] n);
	case (n)
		6'd10: carrier = -12'sd1208;  6'd11: carrier = -12'sd404;
		6'd12: carrier =  12'sd400;   6'd13: carrier =  12'sd1204;
		6'd40: carrier =  12'sd1208;  6'd41: carrier =  12'sd404;
		6'd42: carrier = -12'sd400;   6'd43: carrier = -12'sd1204;
		default: carrier = (n > 6'd13 && n < 6'd40) ? 12'sd1608 : -12'sd1608;
	endcase
endfunction

// ------------------------------------------------------------ burst flag

wire sync_in = |s2;
reg  sync_d;
reg [11:0] since_line;
reg  [7:0] bf_cnt;
reg        bf_run;

wire line_edge = sync_d & ~sync_in & (since_line >= HALF_H_KILL);
wire bf = bf_run && (bf_cnt >= BF_DELAY);

always @(posedge clk) begin
	if (reset) begin
		sync_d <= 1'b0;
		since_line <= 12'd0;
		bf_cnt <= 8'd0;
		bf_run <= 1'b0;
	end else begin
		sync_d <= sync_in;
		if (line_edge) since_line <= 12'd0;
		else if (~&since_line) since_line <= since_line + 12'd1;

		if (line_edge) begin
			bf_cnt <= 8'd0;
			bf_run <= 1'b1;
		end else if (bf_run) begin
			bf_cnt <= bf_cnt + 8'd1;
			if (bf_cnt == BF_DELAY + BF_WIDTH - 8'd1) bf_run <= 1'b0;
		end
	end
end

// ------------------------------------------------------------ input clamp

// The inputs are AC coupled and clamped while the burst flag is up; the
// level found there is black for the rest of the line. Both RGB sets show
// their blanking level then, so one clamp after the switch is the same.
reg [15:0] acc_r, acc_g, acc_b;
reg  [8:0] blk_r, blk_g, blk_b;
reg  [7:0] clamp_n;

always @(posedge clk) begin
	if (reset) begin
		{acc_r, acc_g, acc_b} <= 48'd0;
		{blk_r, blk_g, blk_b} <= 27'd0;
		clamp_n <= 8'd0;
	end else if (line_edge) begin
		{acc_r, acc_g, acc_b} <= 48'd0;
		clamp_n <= 8'd0;
	end else if (bf && !clamp_n[7]) begin
		acc_r <= acc_r + r2;
		acc_g <= acc_g + g2;
		acc_b <= acc_b + b2;
		clamp_n <= clamp_n + 8'd1;
		if (clamp_n == 8'd127) begin
			blk_r <= (acc_r + r2) >> 7;
			blk_g <= (acc_g + g2) >> 7;
			blk_b <= (acc_b + b2) >> 7;
		end
	end
end

// ------------------------------------------------------------ matrix

wire signed [9:0] rn = $signed({1'b0, r2}) - $signed({1'b0, blk_r});
wire signed [9:0] gn = $signed({1'b0, g2}) - $signed({1'b0, blk_g});
wire signed [9:0] bn = $signed({1'b0, b2}) - $signed({1'b0, blk_b});

reg signed [23:0] y1, rq1, bq1, sync1;
reg               bf1;
reg signed [11:0] sin1, cos1;

always @(posedge clk) begin
	y1    <= rn * KYR + gn * KYG + bn * KYB;
	rq1   <= rn * K;
	bq1   <= bn * K;
	sync1 <= s2[1] ? SYNC_TICK + SYNC_TICK : s2[0] ? SYNC_TICK : 24'sd0;
	bf1   <= bf;
	sin1  <= carrier(ang);
	cos1  <= carrier((ang >= 6'd45) ? ang - 6'd45 : ang + 6'd15);
end

// ------------------------------------------------------------ colour difference

/* verilator lint_off UNUSEDSIGNAL */
wire signed [24:0] by = bq1 - y1;
wire signed [24:0] ry = rq1 - y1;
wire signed [36:0] u_m = $signed(by[23:5]) * KU;
wire signed [36:0] v_m = $signed(ry[23:5]) * KV;
/* verilator lint_on UNUSEDSIGNAL */

reg signed [18:0] u2, v2;
reg signed [23:0] y2;
reg signed [11:0] sin2, cos2;

always @(posedge clk) begin
	u2   <= u_m[34:16] - (bf1 ? BURST_PEAK : 19'sd0);
	v2   <= v_m[34:16] - (bf1 ? BURST_V : 19'sd0);
	y2   <= y1 - sync1;
	sin2 <= sin1;
	cos2 <= cos1;
end

// ------------------------------------------------------------ modulators

/* verilator lint_off UNUSEDSIGNAL */
wire signed [31:0] c_m = u2 * sin2 + v2 * cos2;
/* verilator lint_on UNUSEDSIGNAL */

always @(posedge clk) begin
	y_out <= y2;
	c_out <= c_m[29:6];
end

endmodule
