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
4. **Composite filters**: Kitrinx's composite decoder from the NES core (MIT licence), with the
   changes a Mega Drive needs: the burst gate is timed from the end of sync, the Premium TV comb uses
   a set's fixed 227.5-cycle delay because the lines are 228 cycles, and the sync separator averages
   over one colour cycle before slicing, so saturated colours (item 5 above) are never taken for sync.

Not implemented: interlaced sync, PAL.

In simulation, the sync generator reproduces the vertical interval and the picture offset, and the
decoder gives one line start per line on all 84 pairs of full-strength colours.

## Build

Quartus 17.0.2 Lite, seed 3. Logic 69%, DSP blocks 96/112, RAM blocks 545/553 (99%). Worst setup
slack is +0.614 ns and hold slack +0.249 ns, so timing passes.
