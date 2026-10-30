# Composite video: technical notes

## 32X composite output (BA7237)

Sources: the 32X service manual and the data sheets of the BA7237's family (BA7230LS, BA7232FS); no
BA7237 data sheet exists. Measured with a Hantek 6022BL oscilloscope at the AV jack on one 32X,
showing Mega Drive test ROMs in pass-through and the 32X's own 240p test patterns, through a passive
cable chain whose effect was measured on a Mega Drive (0.98 at 1.7 MHz, 0.92 at 3.6 MHz, hue +1°).
One console, not a survey.

1. **Signal path.** With a 32X attached, the TV is plugged into the 32X. Its BA7237 encoder (Sega
   315-5788) takes the Mega Drive's RGB and the 32X's RGB, picks one of them for each pixel with the
   YS switch, and encodes the result. The Mega Drive's own composite output is not used.
2. **Sync and carrier** come from the Mega Drive. The C-SYNC's vertical interval is equalising, broad
   and equalising pulses, three lines each (measured on a Mega Drive and a 32X). The first pixel
   comes 676 master clocks after the falling edge of sync. A line is 228 subcarrier cycles.
3. **Encoder**: the BA7232's levels and the BA7230 family's square-wave colour modulators. The colour
   oscillator is phase-locked to the Mega Drive's own colour burst. Measured: levels, sync, burst
   size, burst timing, linearity (a 32-step grey ramp, within 1%), picture position and the vertical
   interval match. The colours sit 7.6° behind where the burst puts them; this is the oscillator's
   lock error and will vary a little from unit to unit.
4. **Board filters**: the chroma network is from the service manual. The luma filter measures as a
   1.56 MHz, Q 0.57 low-pass; the schematic's trap network would pass far more fine detail (0.86 of a
   2-pixel stripe at 1.7 MHz, where the real 32X gives 0.53).
5. **Saturated colours** go below black far enough to reach the sync level: 100% red against black
   dips to −0.297 V, with sync tip at −0.30 V.

## How it is implemented

1. **Sync and carrier**: the core keeps its original FPGA Genesis, which has no C-SYNC or subcarrier
   pins. A block of the composite path makes them from the Genesis's syncs and picture: the vertical
   interval above, starting three lines after the Genesis's vertical sync, and the carrier phase
   counted from the falling edge of sync.
2. **Encoder**: the levels and modulators above; the assumptions where nothing is published are
   listed in `rtl/composite/ba7237.sv`. The 7.6° offset is carried by the burst.
3. **Board filters**: the measured luma low-pass and the service manual's chroma network.
4. **Composite filters**: Kitrinx's composite decoder from the NES core, run at 15 samples per
   subcarrier cycle, with the changes listed below. Its contrast input is fixed at what a set's
   sync AGC gives for this console's sync level. One output pixel every two samples: 26.85 MHz,
   1710 a line, so the scaler has 7.5 samples per subcarrier cycle to draw the decoded picture
   with (one in four left it 3.75).
5. **Gamma**: the decoded pixels come every two clocks, too fast for the gamma block inside
   `video_mixer`, which looks R, G and B up one after another and needs four clocks per pixel.
   The core uses the framework's `gamma_fast` instead, in front of the mixer on both paths, which
   looks the three up at once from the same curve with the same one-pixel delay.

Not implemented: interlaced sync, PAL.

In simulation, the sync generator reproduces the vertical interval and the picture offset, and the
decoder gives one line start per line on all 84 pairs of full-strength colours.

## Changes to Kitrinx's composite decoder

The decoder is Kitrinx's from the NES core (MIT licence; the changes are MIT too), in
`rtl/composite/composite_decoder.sv`. It is the same file in the Mega Drive, Mega CD and 32X cores.

* **Burst gate and black clamp** are timed from the trailing edge of sync, as a set's burst gate
  pulse is, instead of from the leading edge. The Mega Drive's sync is 5.83 µs wide, so gates timed
  from the leading edge for a 4.7 µs sync would land inside it. With a 4.7 µs sync both still fall
  6.0 and 8.5 µs after the leading edge, as before.
* **Chroma is blanked** until the back porch is over (3.8 µs after sync ends), as a set blanks it
  through horizontal blanking, so the long burst is never shown.
* **Premium TV comb** uses a set's fixed 227.5-cycle delay instead of one line of the source. Mega
  Drive lines are 228 cycles, so a delay of one source line would meet chroma in phase and cancel
  the burst and the colour.
* **Sync separator** slices the signal averaged over one subcarrier cycle, as a set's does through
  its low-pass, instead of the raw signal. On a 32X, saturated colours swing the signal down to the
  sync tip (100% red against black: −0.297 V; sync tip: −0.30 V). The raw slicer counted those dips
  as line starts and tore the picture. The average's delay is taken back out, so all timing is as
  before; 0 of 84 pairs of full-strength colours now give a false line start.
* **Samples per cycle**: the core runs the decoder at 15 samples per subcarrier cycle (odd). The
  notch's half-cycle delay is then the mean of the two samples around it, and the comb's half-sample
  delay likewise.
* Not changing the picture: the sharpness filter's tap spacing is a parameter, two products are
  folded into one each (same results), and the comb's line store is a RAM inside the decoder rather
  than the core's dpram.

With a 4.7 µs sync and standard NTSC timing, the decoder gives the same picture as the original.

## Build

Quartus 17.0.2 Lite, seed 3. Logic 69%, DSP blocks 96/112, RAM blocks 547/553 (99%). Worst setup
slack is +0.271 ns and hold slack +0.246 ns, so timing passes.
