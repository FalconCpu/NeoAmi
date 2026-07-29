# NeoAmi

In this project I seek to imagine what a next generation Amiga might have looked like by the mid 1990's, and then trying to build such a system from scratch using a modern FPGA.

> My interest is more to design and build a complete computer system from scratch, rather than being truly authentic. So while the design is inspired by the Amiga, I'm going to completely ignoring all backwards compatability issues. 

## Gatecount

I'm using a Terasic DE1 Development board, a modern budget FPGA board primarily targetted at students and hobbyists. The board has a CycloneV FPGA, a mid-range device from Altera (now Intel). This FPGA has 88K LUT6s (LUT's beign the building blocks inside an FPGA). A LUT6 is roughly equivalent to 2.5 ASIC gates, so my FPGA is roughly 220K ASIC gates.

For comparison, the OCS chip set (Agnus, Denise, Paula, Gary and the 68000 CPU) was roughly 40K ASIC gates. Ie this FPGA capacity is roughly 5 times the size of the original Amiga chip set. Assume Moore's law, with a doubling of transistor count every 1.5-2 years, So this FPGA represents roughly 5 years of progress in silicon technology. If we regard the original Amiga as commercially availible in 1988 design, then this FPGA is roughly equivalent to a commercial 1993 chipset design.

[ And as a further datapoint, ASICs with 1M gates became commercially available around 1996, so agian this FPGA is roughly equivalent to a 1993 design. ]

The desgign constraints are very different between custom silicon and an FPGA - implementation details will differ greatly, but total hardware resources should be similar. 

All this is to say, something that can be implemented on a CycloneV FPGA,  would be have been implementable around 1993 as a custom silicon chipset.

## Alternate history

So lets imagine an alternative history, where Commodore had prioritized R&D throughout the Amiga's life cycle. So the chipset revisions would have come at 2 year intervals. OCS in 1985, ECS in 1987, AGA in 1989 and AAA in 1991. Thus around 1993 we would be looking at a next generation Amiga chipset - which I've called the FALCON.

> I'm ignoring the Hombre chipset - it really doesn't fit with the Amiga's design philosophy, and is more of a 3D graphics accelerator than a general purpose computer system.

In the real timeline, Commodore started working on the AAA chipset, then drastically scaled back to produce AGA. So in this alternate history, lets assume AGA was planned from the start as a stop-gap measure, and AAA was the real next generation Amiga chipset.

## AA chipset

From what we know of the AAA chipset, it was fully 32 bit architecture. A 32-bit CPU (probably a 68020 or 68030), connected to a 32-bit wide memory bus, with 32-bit wide graphics and audio subsystems. 

One big change we know that was planned was that the AAA would decouple the system clock from the video clock. The AAA architecture used a scanline based video system, where a whole scanline of pixels was loaded into a line buffer, and then the video system would read from this line buffer at the video clock rate. The A4000 already contained a primitive version of this, for the scan doubler, as a bolted on extra chip. The AAA would have integrated this into the chipset from the start, and would have allowed for a much more flexible video system.

One big advantage of this scanline based video system is that it allows for a much more flexible graphics system. Since we can now decouple the memory fetch from the video output - we are no longer constrained to fetching pixels in the order they are displayed on the screen. This allows for a more flexible graphics system, where we can combine multiple objects into a single output frame on the fly. We know Commodore were planning to use this to allow mixing resolutions on the screen, and probably also to allow for more advanced sprite systems.

## The IRIS graphics system

So for the next generation Amiga, I've assumed we lean heavily on the scanline based video system from AAA and take it to the next level. I've called this next gen graphics chip IRIS (Interpolated Raster Image Synthesizer).

We merge the Amiga concept of bitplanes and sprites into a single graphics system. Now each scanline of the output frame is composed of up to 256 objects, where each object can be a rectangular or triangular shape, and can be filled with either a bitmap or Gouraud shadeding. 

Bitmaps can be either 8-bit color indexed, or RGB565 true color. Bitmap graphics can be scaled and rotated on the fly.  A hardware texture mapping system is also included, with bilinear filtering. 

Depth ordering of the objects is handled in hardware, by means of a scanline Z buffer. Each object can be assigned a Z value (or gradient), and the IRIS chip will automatically handle the depth ordering of pixels. 

Bitmaps are stored in chunky format rather than planar format. 

> Any real Amiga at the time would have had to support planar graphics for backwards compatability. But I'm not going to bother with backwards compatability, and will use chunky graphics throughout. 


## The CPU

It is clear that Commodore were planning to move away from the 68k CPU architecture, and towards a RISC based CPU. In the real timeline, Commodore were planning to use the PowerPC architecture, but in this alternate history, I've assumed they used a "F32" CPU.

> I've based this F32 CPU loosely on RISC-V. Obviously RISC-V itself did not exist in 1993, but there were many competing RISC CPUs around at the time. Since this is my project, I can take liberties and assume someone at the time had implemented a nice clean RISC architecture, that happens to fit the Amiga nicely and that Commodore were able to license it.

The F32 is a 32-bit RISC CPU, with a 32-bit instruction set, 32-bit registers and a 32-bit data bus. It has a 4 stage pipeline (fetch, decode, execute, writeback), and uses a scoreboard based in-order issue, out-of-order completion.

It has a 16kB direct mapped instruction cache, and a 16kB direct mapped data cache (write-through, no allocate on write). The CPU runs at 125MHz, which is on the high end of what was possible in 1993, but not unreasonable (the 200Mhz version of DEC Alpha launched in Feb 1993). 

The CPU has a region based memory protection system, but no MMU. This fits with the Amiga philosophy of tasks running in a single address space, yet still providing some level of memory protection.  

It supports floating point operations, but using the same registers as the integer operations (Like RISC-V Zfinx). This again fits the Amiga - where floating point operations were not common. 

My FPGA board has 64MB of SDRAM, which is more than enough for a 1993 system.  Running at 125MHz, the SDRAM system can provide a peak bandwidth of 250MB/s.

> SDRAM at this speed would not have been available in 1993, but a real system at that time would have used wider memory buses, and Amiga style Chip- and Fast- Banks to allow CPU and custom chips to access memory simultaneously. So this represents roughly the same memory bandwidth as a 1993 system would have had, just in different form factor.

## GEMMA (GEometry and Matrix Manipulation Accelerator)

Still in the graphics domain, Commodore were planning to include a 3D graphics accelerator in the AAA chipset. I'm still sketching out the details of this, but it will be a geometry and matrix manipulation accelerator, that can perform 3D transformations on vertices, perform lighting calculations, 3D clipping and perspective division, and then output the transformed vertices in a format that can be used by the IRIS graphics system.

## The Audio system

The AAA chipset was also planned to include a more advanced audio system, with 8 channels of PCM audio, with sample rates up to 48kHz. Each channel can be independently panned and volume controlled, and can be looped or played once.

I plan to implement this audio system, but it is still a work in progress.

## Blitter and Copper

A system isn't a true Amiga without a blitter and copper. We know AAA was planning a significant overhaul of the blitter, moving away from the Amiga's word oriented blitter, to a more pixel oriented blitter. 

I'm still sketching out the details of this, but it will be a 2D graphics blitter, that can perform bit block transfers (BitBlt), affine transformations (scaling, rotation and translation), and text rendering.

A copper will also be included, to allow for the same kind of display effects that were possible on the original Amiga, but probably with more flexibility, multiple channels, and more advanced effects.



## Project architecture

The project is split into several sub-projects, each of which is more or less independent of the others. 

* FALCON 
   * Top level system, combining all the sub-projects into a single system

* CPU
  * 32 bit RISC CPU, inspired by RISC-V, but designed from scratch.
  * 125MHz clock speed
  * 32 bit instructions, 32 bit registers, 32 bit data bus.
  * Scoreboard based in-order issue, out-of-order completion.
  * 4 stage pipeline (fetch, decode, execute, writeback)
  * Region based memory protection, (no MMU).
  * 16kB Direct mapped instruction cache
  * 16kB Direct mapped Data cache (write-through, no allocate on write)

* SDRAM Controller
   * Interfaces with an external SDRAM chip
   * 16 bit wide, 125MHz clock speed
   * 16 byte burst length  - giving a peak bandwidth of 250MB/s
   + Historical Context: SDRAM at this speed would not have been available in 1995, but a real system at that time would have used wider memory buses, and Amiga style Chip- and Fast- Banks. So this should give roughly the same memory bandwidth as a 1995 system would have had, just in a more modern form factor.

* IRIS (Interpolated Raster Image Synthesizer)
    * Graphics "custom chip" for the Falcon
    * Provide the signals to drives an external VGA monitor
    * 640x480 resoultion with 24 bit color depth, 60Hz refresh rate
    * Composes an output image from multiple sources on the fly
    * Supports up to 256 objects per scanline, 
    * Objects can be filled with:-
        * 8-bit color indexed bitmap (4 palette banks)
        * RGB565 bitmap
        * 24-bit RGB888 Gouraud shaded
        * Texture mapped, (with bilinear filtering)
    * Affine transformations, including scaling and rotation
    * Z-ordering of layers in hardware
    * Cliping to a user defined rectangular region

* SOPHIE (System Organision and Peripheral Hardware IntEgration)
    * Glue logic "custom chip" 
    * responsible for arbitrating access to the memory bus, decoding the memory addresses and interfacing with the peripherals.
    * Handles UART, PS/2 keyboard and mouse, and other peripherals.
    >  Note: My FPGA board does not natively support any accessible persistent storage. So we will emulate a simple block device over the UART serial port, and use a host computer to provide persistent storage. 

* GEMMA (GEometry and Matrix Manipulation Accelerator)
    * Still very much a work in progress
    * 3D graphics accelerator
    * Performs 3D transformations on vertices, including lighting calculations, 3D clipping and perspective division
    * Outputs transformed vertices in a format that can be used by the IRIS graphics system


* Compiler - my own FPL (Falcon Programming Language), with a Kotlin like syntax over C like semantics. 
    * Strong static typed, with type inference and path dependent type refinement
    * Compiles to native code for the Falcon CPU
    * Explicit memory management - new and free, no garbage collection
    * Null safety built in to the type system
    * Errors as values
    * Support for Classes, Gernerics, Structs, Enums, Arrays and Tuples. 
