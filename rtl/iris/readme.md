# IRIS — Interpolated Raster Image Synthesizer

IRIS (Interpolated Raster Image Synthesizer) is the graphics "custom chip" in the NoeAmi, the equivalent of the Amiga's "Denise" chip. It is responsible for combining multiple graphics objects into a single output image, which is then sent to the VGA monitor.

Compared to the Amiga's Denise chip, IRIS is a much more powerful graphics subsystem. The main changes from Denise are:
* The number of sprites has been increased from 8 to 256
* Each sprite can now be of any width and height (up to the full screen size)
* Sprites are drawn in 256 colors mode, with 4 separate palette banks (selectable per sprite). They can also be gouraud shaded (in 24-bit resolution).
* Sprites can be triangular or rectangular
* Bitmap images can be scaled and rotated in hardware, with 12-bit precision
* Depth sorting is performed in hardware, so that sprites can be drawn in any order and the correct pixels will be visible.
* Each sprite has an brightness setting, independent of the color palette, which can be used to fade sprites in and out, or to create lighting effects.
* Each sprite has an independent clipping rectangle, so that only a portion of the sprite is visible. 
* Sprites can be drawn with transparency, so that the background or other sprites can be seen through them (alpha blending). Alpha can be set either per color, or gourard shaded across the sprite. The alpha blending is performed in 24-bit resolution, so that the colors are not degraded by the blending.
* Amiga style - sprites can be re-programmed partway through the screen refresh, by the Copper (or by GEMMA) allowing for more than 256 sprites to be displayed on the screen at once, or for effects where the sprites change size, color or position partway down the screen.

Note - there is only a finite memory bandwidth of the SDRAM. IRIS has the highest priority for memory access (as it needs data in a timely manner to drive the display). So if you make excessive use of sprites, the CPU and other peripherals may be starved of memory bandwidth, and eventually pixels will be dropped from the display. As a guide - A sprite the full size of the screen (640x480) will consume about 1/8 of the available memory bandwidth. So doing a 2 layer parallax scrolling effect with 2 full screen sprites will consume about 1/4 of the available memory bandwidth - still leaving 3/4 for the CPU and other peripherals. But an 8 layer parallax scrolling is probably not going to work.

The depth sorting and alpha blending are mutually exclusive - if you want to use depth sorting, you cannot use alpha blending, and vice versa

# Graphics Registers

Each sprite is stored as a 64 byte structure in memory. The array of 256 sprites is mapped at address 0xE0001000 in the NeoAmi's memory map. The structure is defined as follows:


| Field      | Offset | Format | Description                                                           |
|------------|--------|--------|-----------------------------------------------------------------------|
| FLAGS      | 0x00   | U16    | object flags (see below)                                              |
| CLIP_X1    | 0x02   | U16    | The left X coordinate of the clipping rectangle (inclusive)           |
| CLIP_X2    | 0x04   | U16    | The right X coordinate of the clipping rectangle (exclusive)          |
| YTOP       | 0x06   | U16    | The first visible scanline of the object (inclusive)                  |
| YBOT       | 0x08   | U16    | The last visible scanline of the object (exclusive)                   |
| X1         | 0x0A   | S12.4  | X-coordianate of the topmost vertex of the object                     |
| Y1         | 0x0C   | S12.4  | Y-coordianate of the topmost vertex of the object                     |
| X2         | 0x0E   | S12.4  | X-coordianate of the middle vertex of the object                      |
| Y2         | 0x10   | S12.4  | Y-coordianate of the middle vertex of the object                      |
| DX1/DY     | 0x12   | FP16   | Slope of the left edge from top vertex                                |
| DX2/DY     | 0x14   | FP16   | Slope of the right edge from top vertex                               |
| DX3/DY     | 0x16   | FP16   | Slope from middle vertex to bottom vertex                             |
| Z1         | 0x18   | S12.4  | depth value at the (X1,Y1) vertex                                     |
| DZ/DX      | 0x1A   | FP16   | Slope of the depth value across the triangle                          |
| DZ/DY      | 0x1C   | FP16   | Slope of the depth value down the triangle                            |
| reserved   | 0x1E   | U16    | Reserved for future use                                               |
| R1         | 0x20   | U12.4  | Red color or U coordinate at the (X1,Y1) vertex                       |
| DR/DX      | 0x22   | FP16   | Slope of the red/U value across the triangle                          |
| DR/DY      | 0x24   | FP16   | Slope of the red/U value down the triangle                            |
| G1         | 0x26   | U12.4  | Green color or V coordinate at the (X1,Y1) vertex                     |
| DG/DX      | 0x28   | FP16   | Slope of the green/V value across the triangle                        |
| DG/DY      | 0x2A   | FP16   | Slope of the green/V value down the triangle                          |
| B1         | 0x2C   | U12.4  | Blue color or Brightness value at the (X1,Y1) vertex                  |
| DB/DX      | 0x2E   | FP16   | Slope of the blue/brightness value across the triangle                |
| DB/DY      | 0x30   | FP16   | Slope of the blue/brightness value down the triangle                  |
| TEX_STRIDE | 0x32   | U16    | The stride of the texture in bytes (width * bytes per pixel)          |
| TEX_ADDR   | 0x34   | U32    | The address of the texture in memory                                  |
| USERDATA   | 0x3C   | U32    | Not used by IRIS, but can be used by the application to store any data associated with the object |

Note - internally all coordinates and slopes are processed in S12.12 fixed point format, but to keep the 
data structure compact, a mix of S12.4 fixed point and 16-bit floating point formats are used in the object structure.

For a triangle, X1,Y1 and X2,Y2 are the coordinates of the top and middle vertices of the triangle, they are stored with 4 bits of fractional precision to allow sub-pixel accuracy. The bottom vertex is not stored, but is calculated from the top and middle vertices, the slopes and YBOT.

YTOP and YBOT are the first and last visible scanlines of the object. It is permissible for Y1 and Y2 to be outside this range, in which case the triangle will be clipped to the visible range. 

Rectangles can be drawn by setting (X1,Y1) to the top left corner and (X2,Y2) to the top right corner,
setting all the slopes to zero and setting the RIGHT_EDGE flag to indicate that the middle vertex is the right edge. The rectangle will then be drawn from (X1,YTOP) to (X2,YBOT).

R,G,B values are calculated at each pixel relative to the X1,Y1 vertex. For Gourard shaded triangles, the R,G,B values are the color at each vertex (in range 0..255). For textured triangles and bitmaps, the R,G values are the U,V texture coordinates, and the B value is the brightness of the texture.

## Floating Point Format

The slopes are encoded in a 16-bit floating point format, with a 2 bit exponent and a 14 bit mantissa.
This allows a wide range of values to be represented in a compact format. Bit [15:14] = exponent,
bits [13:0] = mantissa in 2's complement format. The value is calculated as:

    exponent = 0:   value = mantissa * 2^-12   (Gives range of -2 to +2, with a resolution of 1/4096)
    exponent = 1:   value = mantissa * 2^-9    (Gives range of -16 to +16, with a resolution of 1/512)
    exponent = 2:   value = mantissa * 2^-6    (Gives range of -128 to +128, with a resolution of 1/64)
    exponent = 3:   value = mantissa * 2^-3    (Gives range of -1024 to +1024, with a resolution of 1/8)

## Flags:

The FLAGS field is a 16-bit value that controls the behavior of the layer. The bits are defined as follows:

| Bit | Name          | Description                                                                                |
|-----|---------------|--------------------------------------------------------------------------------------------|
| 1:0 | MODE          | 00=8 bit indexed color, 01=16 bit RGB565, 10=Gourard shaded triangle, 11=Textured triangle |
| 3:2 | PALETTE       | For 8 bit indexed color mode, this selects which of 4 pallete banks to use (0-3)           |
| 4   | RIGHT_EDGE    | For triangles, this indicates the middle vertex is the right edge (1) or left edge (0)     |
| 5   | TRANSPARENCY  | treat color index 0 as transparent (1) or opaque (0)                                       |
| 6   | ALPHA         | Use the B value as an alpha value for blending (1) or as a brightness value (0) |
