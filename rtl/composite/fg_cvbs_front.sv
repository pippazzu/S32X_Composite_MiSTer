// Composite video front end for a Genesis that has no C-SYNC or SBCR pins.
//
// The FPGA Genesis gives separate H and V syncs and an RGB picture; the
// BA7237 model wants what the real VDP gives it: the C-SYNC waveform and the
// subcarrier phase, one sample per master clock. Both are made here, locked
// to the picture:
//
//   * the line counter c has the Mega Drive's own timing: the first active
//     pixel is 676 master clocks after the falling edge of sync (H40, as
//     measured on a real console), and a line is 3420 clocks, 228 subcarrier
//     cycles, so the carrier phase repeats every line;
//   * the carrier angle is counted from the falling edge of sync;
//   * the vertical interval is the real one, measured on a Mega Drive and a
//     32X: three lines of half-line equalising pulses (2.9 us), three of broad
//     pulses (27.65 us, 4.2 us serrations), three of equalising pulses, then
//     5.83 us line syncs. It starts three lines after the Genesis's VS: the
//     real VDP's vertical sync sits three lines later against its picture
//     than the FPGA Genesis's does (checked against Nuked-MD).
//
// Not modelled: interlace (the sync of an odd field), and PAL: composite is
// an NTSC set.

module fg_cvbs_front (
	input            clk,          // master clock, 53.69 MHz
	input            reset,

	input      [7:0] r,
	input      [7:0] g,
	input      [7:0] b,
	input            blank,        // the picture's blanking (H or V)
	input            hblank,       // the picture's horizontal blanking
	input            vs_n,         // the Genesis's vertical sync, low in sync

	output reg [8:0] r2 = 9'd0,    // two-tick sums, as the Nuked front gives them
	output reg [8:0] g2 = 9'd0,
	output reg [8:0] b2 = 9'd0,
	output reg [1:0] s2 = 2'd0,    // ticks C-SYNC was low
	output reg [5:0] ang = 6'd0    // carrier angle, 6 degree steps
);

localparam [11:0] LINE      = 12'd3420;
localparam [11:0] PIC_START = 12'd677;     // 676 clocks from sync to the first pixel, plus the register that makes the picture sample
localparam [11:0] HSYNC_W   = 12'd313;     // 5.83 us
localparam [11:0] EQ_W      = 12'd155;     // 2.9 us
localparam [11:0] BROAD_W   = 12'd1485;    // 27.65 us
localparam [11:0] HALF      = 12'd1710;
localparam [11:0] SERR_END  = 12'd3195;

// ------------------------------------------------------------ line phase

reg [11:0] c   = 12'd0;           // clocks since the falling edge of sync
reg [3:0]  c15 = 4'd0;            // c mod 15
reg        hb_d = 1'b1;

wire pic_start = hb_d & ~hblank;
wire wrap      = (c == LINE - 12'd1);
wire [11:0] c_n   = pic_start ? PIC_START : wrap ? 12'd0 : c + 12'd1;
wire [3:0]  c15_n = pic_start ? 4'd2 : (c15 == 4'd14) ? 4'd0 : c15 + 4'd1;   // 677 = 45 * 15 + 2
wire line_tick = (c_n == 12'd0);

// ------------------------------------------------------------ vertical interval

reg        vs_d = 1'b1;
reg [1:0]  dly = 2'd0;            // lines until the real vertical sync starts
reg [9:0]  fl = 10'd0;            // lines since it started
reg [9:0]  flen = 10'd262;        // lines in the last frame

wire vs_fall = vs_d & ~vs_n;
wire start_now = line_tick && (dly == 2'd1);

always @(posedge clk) begin
	if (reset) begin
		hb_d  <= 1'b1;
		vs_d  <= 1'b1;
		c     <= 12'd0;
		c15   <= 4'd0;
		dly   <= 2'd0;
		fl    <= 10'd262;
		flen  <= 10'd262;
	end else begin
		hb_d <= hblank;
		vs_d <= vs_n;
		c    <= c_n;
		c15  <= c15_n;

		if (vs_fall)       dly <= 2'd3;
		else if (line_tick && dly != 2'd0) dly <= dly - 2'd1;

		if (start_now) begin
			flen <= fl + 10'd1;
			fl   <= 10'd0;
		end else if (line_tick && ~&fl) fl <= fl + 10'd1;
	end
end

// ------------------------------------------------------------ C-SYNC

wire broad = (fl < 10'd3);
wire eq    = ~broad && (fl < 10'd6 || fl >= flen - 10'd3);

wire low_n = (c < HSYNC_W);
wire low_e = (c < EQ_W) || (c >= HALF && c < HALF + EQ_W);
wire low_b = (c < BROAD_W) || (c >= HALF && c < SERR_END);
wire sync_low = broad ? low_b : eq ? low_e : low_n;

// ------------------------------------------------------------ samples

always @(posedge clk) begin
	if (reset) begin
		{r2, g2, b2} <= 27'd0;
		s2  <= 2'd0;
		ang <= 6'd0;
	end else begin
		{r2, g2, b2} <= blank ? 27'd0 : {r, 1'b0, g, 1'b0, b, 1'b0};
		s2  <= sync_low ? 2'd2 : 2'd0;
		ang <= {c15, 2'b00};
	end
end

endmodule
