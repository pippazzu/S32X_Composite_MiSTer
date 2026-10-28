# Composite video: technical notes

With a 32X attached, the TV is plugged into the 32X. The 32X's BA7237 encoder takes the Mega Drive's
RGB and the 32X's RGB, picks one of them for each pixel, and encodes the result. The Mega Drive's own
composite output is not used. The model follows that chain, then shows the result on a TV, as
Kitrinx's NES core does.

## What is modelled

1. **Sync and carrier.** The core keeps its original FPGA Genesis, which has no C-SYNC or subcarrier
   pins. A block of the composite path makes them from the Genesis's syncs and picture:
   * The C-SYNC has the vertical interval measured on a Mega Drive and a 32X: equalising, broad and
     equalising pulses, three lines each, starting three lines after the Genesis's vertical sync.
   * The carrier phase is counted from the falling edge of sync, with the first pixel 676 master
     clocks after it, as on a real console.
2. **BA7237 encoder** (Sega 315-5788), from the 32X service manual. This covers the YS switch, the
   BA7230 family's square-wave colour modulators, the BA7232's levels and the board's chroma
   network. The colour oscillator is locked to the Mega Drive's own colour burst. No BA7237 data
   sheet exists; the assumptions are listed in `rtl/composite/ba7237.sv`.
3. **Measured instead of taken from the schematic:**
   * The luma filter is a 1.56 MHz, Q 0.57 low-pass. The schematic's trap network passed far more
     fine detail than the real board: 0.86 of a 2-pixel stripe at 1.7 MHz, where the real 32X gives
     0.53.
   * The colours sit 7.6° behind where the burst puts them. This is the colour oscillator's lock
     error and will vary a little from unit to unit.
4. **TV**: Kitrinx's composite decoder from the NES core (MIT licence), with the changes a Mega Drive
   needs. The burst gate is timed from the end of sync, and the Premium TV comb uses a
   set's fixed 227.5-cycle delay because the lines are 228 cycles. The sync separator averages over
   one colour cycle before slicing. Without that averaging, the 32X's saturated colours (100% red
   against black dips to −0.297 V, and sync tip is −0.30 V) were taken for sync and tore the picture.

**Not modelled:** interlaced sync and PAL.

## Measured against a real 32X

One 32X was measured with a Hantek 6022BL oscilloscope at the AV jack. It showed Mega Drive test ROMs
in pass-through and the 32X's own 240p test patterns. The signal went through a passive cable chain
whose effect was measured on the Mega Drive (0.98 at 1.7 MHz, 0.92 at 3.6 MHz, hue +1°).

These match: levels, sync, burst size, burst timing, linearity (a 32-step grey ramp, within 1%),
picture position and the vertical interval. Colours and the luma response are as described above.
This was one console, not a survey. In simulation, the sync generator reproduces the vertical
interval and the picture offset, and the decoder gives one line start per line on all 84 pairs of
full-strength colours. On a MiSTer, the core has been run with several games, including the screens
that tore before the sync separator was fixed.

## Build

Quartus 17.0.2 Lite, seed 3. Logic 69%, DSP blocks 96/112, RAM blocks 545/553 (99%). Worst setup
slack is +0.614 ns and hold slack +0.249 ns, so timing passes.
