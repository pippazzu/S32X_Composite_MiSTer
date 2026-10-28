# [Sega 32X](https://en.wikipedia.org/wiki/32X) for [MiSTer Platform](https://github.com/MiSTer-devel/Main_MiSTer/wiki)
by [Sergey Dvodnenko](https://github.com/srg320)

[![Patreon](https://img.shields.io/website?label=patreon&logo=patreon&style=social&url=https%3A%2F%2Fwww.patreon.com%2Fsrg320%2F)](https://www.patreon.com/srg320)

## Status
* Most games are playable and run without major issues.
* Some bugs present with audio playback and graphics.
* Some features like cheats and game saves are not implemented at this time. Please don't submit an issue to request cheats or saves, this is known.

Check the issues page to see if the issue you are experiencing is already known before submitting a new issue.

## Region detection
Region detection is known to work for all commercially released 32X games except the following. These are not bugs, this is due to the way the games were developed and due to the nature of the region code system in Sega Genesis games in general:

* Shadow Squadron ~ Stellar Assault (USA, Europe) always initially boots to Europe region. The ROM header has "E" (Europe) for the region, so the developers set it to the european region, you will have to set the region manually.
* FIFA Soccer 96 (Europe) and Mortal Kombat II (Europe) boot to US/JP Region. Header has the "JUE" (Region-Free) region code, so just set your region priority.

## Composite video
**Audio & Video → Composite Filter** (JP and US regions) shows the composite video of a Mega Drive
with a 32X attached, on a modelled NTSC TV: Budget TV (notch filter) or Premium TV (comb filter),
with Comp. Brightness and Comp. Sharpness. The picture goes through a model of the 32X's own
encoder, as the real 32X's output does. No frame buffer: the added delay is under a microsecond.
Composite Blend is removed (the composite path does that blending itself). The scandoubler, HQ2x
and scanline effects are kept, but are hidden while composite is on.

Try first: Sega's "Mars Check Program" (the 32X factory test cartridge).

Technical notes and measurements: [docs/composite.md](docs/composite.md).
