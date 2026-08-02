#define _CRT_SECURE_NO_WARNINGS
#include <stdio.h>
#include <string.h>
#include "f32.h"


// GEMMA - GEometry and Matrix Multiplication Accelerator
//
// GEMMA is a custom hardware accelerator for matrix multiplication and geometry processing.
// In this emulator, we model GEMMA as a memory-mapped I/O device. We make no attempt to 
// make this cycle accurate - but do provide a golden model to verify the RTL against. 

/**
 * Gemma 
 * 
 * Model GEMMA as just a memory-mapped I/O device. Curently we don't implement any actual GEMMA functionality
 */

 // GEMMA register map
#define GEMMA_START          (0x00/4)
#define GEMMA_BUSY           (0x04/4)
#define GEMMA_AUTO           (0x08/4)
#define GEMMA_OUTPUT_PTR     (0x0C/4)
#define GEMMA_CLIP_X1        (0x10/4)
#define GEMMA_CLIP_Y1        (0x14/4)
#define GEMMA_CLIP_X2        (0x18/4)
#define GEMMA_CLIP_Y2        (0x1C/4)
#define GEMMA_TEXTURE_ADDR   (0x20/4)
#define GEMMA_TEXTURE_STRIDE (0x24/4)

// Triangle setup registers
#define GEMMA_TS_V0_X  (0x500/4)        // Vertex 0 X coordinate (S12.4 fixed-point)
#define GEMMA_TS_V0_Y  (0x504/4)        // Vertex 0 Y coordinate (S12.4 fixed-point)
#define GEMMA_TS_V0_Z  (0x508/4)        // Vertex 0 Inverse Z coordinate (U20 )
#define GEMMA_TS_V0_R  (0x50C/4)        // Vertex 0 R color component (S12.12 fixed-point)
#define GEMMA_TS_V0_G  (0x510/4)        // Vertex 0 G color component (S12.12 fixed-point)
#define GEMMA_TS_V0_B  (0x514/4)        // Vertex 0 B color component (S12.12 fixed-point)
#define GEMMA_TS_V1_X  (0x520/4)
#define GEMMA_TS_V1_Y  (0x524/4)
#define GEMMA_TS_V1_Z  (0x528/4)
#define GEMMA_TS_V1_R  (0x52C/4)
#define GEMMA_TS_V1_G  (0x530/4)
#define GEMMA_TS_V1_B  (0x534/4)
#define GEMMA_TS_V2_X  (0x540/4)
#define GEMMA_TS_V2_Y  (0x544/4)
#define GEMMA_TS_V2_Z  (0x548/4)
#define GEMMA_TS_V2_R  (0x54C/4)
#define GEMMA_TS_V2_G  (0x550/4)
#define GEMMA_TS_V2_B  (0x554/4)
#define GEMMA_TS_FLAGS (0x57C/4)

// Iris Sprite format
#define IRIS_FLAGS      0x00    // Bit4: 1 = Midpoint on right edge, 0 = Midpoint on left edge
#define IRIS_CLIP_X1    0x02   
#define IRIS_CLIP_X2    0x04   
#define IRIS_YTOP       0x06    // Top scanline of the triangle (inclusive)
#define IRIS_YBOT       0x08    // Bottom scanline of the triangle (inclusive)
#define IRIS_X0         0x0A    // Coordinates of the top vertex of the triangle (V0)  (S12.4 fixed-point)
#define IRIS_Y0         0x0C    // Coordinates of the top vertex of the triangle (V0)  (S12.4 fixed-point)
#define IRIS_X1         0x0E    // Coordinates of the middle vertex of the triangle (V1)  (S12.4 fixed-point)
#define IRIS_Y1         0x10    // Coordinates of the middle vertex of the triangle (V1)  (S12.4 fixed-point)
#define IRIS_DX1_DY     0x12    // Slope V0->V1 (if mid on left) or V0->V2 (if mid on right)
#define IRIS_DX2_DY     0x14    // Slope V0->V2 (if mid on left) or V0->V1 (if mid on right)
#define IRIS_DX3_DY     0x16    // Slope V1->V2 (either case)
#define IRIS_Z1         0x18   
#define IRIS_DZ_DX      0x1A   
#define IRIS_DZ_DY      0x1C   
#define IRIS_reserved   0x1E   
#define IRIS_R1         0x20   
#define IRIS_DR_DX      0x22   
#define IRIS_DR_DY      0x24   
#define IRIS_G1         0x26   
#define IRIS_DG_DX      0x28   
#define IRIS_DG_DY      0x2A   
#define IRIS_B1         0x2C   
#define IRIS_DB_DX      0x2E   
#define IRIS_DB_DY      0x30   
#define IRIS_TEX_STRIDE 0x32   
#define IRIS_TEX_ADDR   0x34   
#define IRIS_USERDATA   0x3C   

static int gemma_regs[384];


// =================================================================
//                Triangle Setup
// =================================================================

static int to_psfloat(int x) {
    // Convert a fixed point value in S12.4 format to a pseudo-float representation in 16 bits (2 exponent bits, 14 bit signed mantissa)

    if (x>-0x1fff && x<0x1fff) {
        // Value is in the range -2.0 to 2.0, so we can use the 14-bit signed mantissa with exponent 0
        return (x & 0x3fff);
    } else if (x>-0xffff && x<0xffff) {
        // Value is in the range -16.0 to 16.0, so we can use the 14-bit signed mantissa with exponent 1
        return (((x>>3) & 0x3fff) | 0x4000);
    } else if (x>-0x7ffff && x<0x7ffff) {
        // Value is in the range -128.0 to 128.0, so we can use the 14-bit signed mantissa with exponent 2
        return (((x>>6) & 0x3fff) | 0x8000);
    } else {
        // Use the largest exponent (3) and the 14-bit signed mantissa. This will saturate at +/- 512.0
        return (((x>>9) & 0x3fff) | 0xc000);
    }
}

static void run_triangle_setup() {
    // This is a golden model of the triangle setup algorithm. It is not cycle accurate, but it should produce the same results as the RTL implementation.
    printf("GEMMA: Running triangle setup\n");

    // Note - we require the vertex coordinates to be sorted in ascending Y order before calling this function

    for(int i=0; i<31; i++) {
        printf("GEMMA: reg[%02X] = 0x%08X\n", i, gemma_regs[(0x500/4) + i]);
    }

    // Find the top and bottom scanlines for this triangle, 
    // The Y coordinates are in S12.4 fixed-point format, so we need to shift right by 4 to get the integer scanline values.
    // And clip to the clipping region
    int ytop = (gemma_regs[GEMMA_TS_V0_Y]) >> 4;
    if (ytop < gemma_regs[GEMMA_CLIP_Y1])
        ytop = gemma_regs[GEMMA_CLIP_Y1];

    int ybot = (gemma_regs[GEMMA_TS_V2_Y]) >> 4;
    if (ybot > gemma_regs[GEMMA_CLIP_Y2])
        ybot = gemma_regs[GEMMA_CLIP_Y2];
    
    if (ybot <= ytop) {
        printf("GEMMA: Triangle has no scanlines to draw (ytop=%d, ybot=%d)\n", ytop, ybot);
        return;         // No scanlines to draw
    }

    int output_ptr = gemma_regs[GEMMA_OUTPUT_PTR];
    do_store(1, output_ptr, IRIS_YTOP, ytop);
    do_store(1, output_ptr, IRIS_YBOT, ybot);
    do_store(1, output_ptr, IRIS_CLIP_X1, gemma_regs[GEMMA_CLIP_X1]);
    do_store(1, output_ptr, IRIS_CLIP_X2, gemma_regs[GEMMA_CLIP_X2]);


    // Calculate the slopes of the edges - in 12-bit fixed point format
    int x0 = gemma_regs[GEMMA_TS_V0_X];     // Vertices are in S12.4 fixed-point format
    int y0 = gemma_regs[GEMMA_TS_V0_Y];
    int x1 = gemma_regs[GEMMA_TS_V1_X];
    int y1 = gemma_regs[GEMMA_TS_V1_Y];
    int x2 = gemma_regs[GEMMA_TS_V2_X];
    int y2 = gemma_regs[GEMMA_TS_V2_Y];

    int dx01 = x1 - x0;      // Edge 0-1 delta X, S12.4 fixed-point
    int dy01 = y1 - y0;
    int dx02 = x2 - x0;
    int dy02 = y2 - y0;
    int dx12 = x2 - x1;
    int dy12 = y2 - y1;

    int slope01 = (dy01 != 0) ? ((dx01 << 12) / dy01) : 0;   // Slope of edge 0-1 with 12 fractional bits
    int slope02 = (dy02 != 0) ? ((dx02 << 12) / dy02) : 0;   // Slope of edge 0-2
    int slope12 = (dy12 != 0) ? ((dx12 << 12) / dy12) : 0;   // Slope of edge 1-2

    int flags = gemma_regs[GEMMA_TS_FLAGS];
    int slope1,slope2,slope3;

    // Check special case where the triangle is flat on the top
    if (dy01 == 0 && dx01 > 0) {
        // Flat top triangle, with 0 on left, 1 on right
        slope1 = slope02;
        slope2 = 0;   // not used
        slope3 = slope12;
        flags |= 0x10;  // Mid point on the right edge
    } else if (dy01 == 0 && dx01 < 0) {
        // Flat top triangle, with 0 on right, 1 on left
        slope1 = 0;   // not used
        slope2 = slope02;
        slope3 = slope12;
        flags &= ~0x10;  // Mid point on the left edge
    } else if (dy12 == 0 && dx12 > 0) {
        // Flat bottom triangle, with 1 on left, 2 on right
        slope1 = slope01;
        slope2 = slope02;
        slope3 = 0;   // not used
    } else if (dy12 == 0 && dx12 < 0) {
        // Flat bottom triangle, with 1 on right, 2 on left
        slope1 = slope02;
        slope2 = slope01;
        slope3 = 0;   // not used
        flags &= ~0x10;  // Mid point on the left edge
    } else if (slope01 < slope02) {
        // Vertex 1 is on the left edge
        slope1 = slope01;
        slope2 = slope02;
        slope3 = slope12;
        flags &= ~0x10;  // Mid point on the left edge
    } else {
        // Vertex 1 is on the right edge
        slope1 = slope02;
        slope2 = slope01;
        slope3 = slope12;
        flags |= 0x10;  // Mid point on the right edge
    }

    printf("GEMMA: Triangle setup complete. Storing at 0x%08X\n", output_ptr);
    do_store(1, output_ptr, IRIS_X0, x0);
    do_store(1, output_ptr, IRIS_Y0, y0);
    do_store(1, output_ptr, IRIS_X1, x1);
    do_store(1, output_ptr, IRIS_Y1, y1);
    do_store(1, output_ptr, IRIS_DX1_DY, to_psfloat(slope1));
    do_store(1, output_ptr, IRIS_DX2_DY, to_psfloat(slope2));
    do_store(1, output_ptr, IRIS_DX3_DY, to_psfloat(slope3));
    do_store(1, output_ptr, IRIS_FLAGS, flags);

    int den = ((dx01*dy02) - (dx02*dy01)) / 256;
    int invDen = 16*1024*1024 / den;
    printf("GEMMA: den = %d, invDen = %d\n", den, invDen);

    int dr01 = gemma_regs[GEMMA_TS_V1_R] - gemma_regs[GEMMA_TS_V0_R];
    int dr02 = gemma_regs[GEMMA_TS_V2_R] - gemma_regs[GEMMA_TS_V0_R];
    int dRdX = (((dr01*dy02 - dr02*dy01)/256) * invDen) / 4096;
    int dRdY = (((dr02*dx01 - dr01*dx02)/256) * invDen) / 4096;
    do_store(1, output_ptr, IRIS_R1, gemma_regs[GEMMA_TS_V0_R]);
    do_store(1, output_ptr, IRIS_DR_DX, to_psfloat(dRdX));
    do_store(1, output_ptr, IRIS_DR_DY, to_psfloat(dRdY));

    int dg01 = gemma_regs[GEMMA_TS_V1_G] - gemma_regs[GEMMA_TS_V0_G];
    int dg02 = gemma_regs[GEMMA_TS_V2_G] - gemma_regs[GEMMA_TS_V0_G];
    int dGdX = (((dg01*dy02 - dg02*dy01)/256) * invDen) / 4096;
    int dGdY = (((dg02*dx01 - dg01*dx02)/256) * invDen) / 4096;
    do_store(1, output_ptr, IRIS_G1, gemma_regs[GEMMA_TS_V0_G]);
    do_store(1, output_ptr, IRIS_DG_DX, to_psfloat(dGdX));
    do_store(1, output_ptr, IRIS_DG_DY, to_psfloat(dGdY));

    int db01 = gemma_regs[GEMMA_TS_V1_B] - gemma_regs[GEMMA_TS_V0_B];
    int db02 = gemma_regs[GEMMA_TS_V2_B] - gemma_regs[GEMMA_TS_V0_B];
    int dBdX = (((db01*dy02 - db02*dy01)/256) * invDen) / 4096;
    int dBdY = (((db02*dx01 - db01*dx02)/256) * invDen) / 4096;
    do_store(1, output_ptr, IRIS_B1, gemma_regs[GEMMA_TS_V0_B]);
    do_store(1, output_ptr, IRIS_DB_DX, to_psfloat(dBdX));
    do_store(1, output_ptr, IRIS_DB_DY, to_psfloat(dBdY));

    int dz01 = gemma_regs[GEMMA_TS_V1_Z] - gemma_regs[GEMMA_TS_V0_Z];
    int dz02 = gemma_regs[GEMMA_TS_V2_Z] - gemma_regs[GEMMA_TS_V0_Z];
    int dZdX = (((dz01*dy02 - dz02*dy01)/256) * invDen) / 4096;
    int dZdY = (((dz02*dx01 - dz01*dx02)/256) * invDen) / 4096;
    do_store(1, output_ptr, IRIS_Z1, gemma_regs[GEMMA_TS_V0_Z]);
    do_store(1, output_ptr, IRIS_DZ_DX, to_psfloat(dZdX));
    do_store(1, output_ptr, IRIS_DZ_DY, to_psfloat(dZdY));
}


// =================================================================
//                GEMMA read/write functions
// =================================================================

int read_gemma(int reg) {
    if (reg < 0 || reg >= 384)
        return 0;
    return gemma_regs[reg];
}

void write_gemma(int reg, int value) {
    gemma_regs[0] = 0;      // Start register is self clearing
    printf("GEMMA: Write to reg[%02X] = 0x%08X\n", reg, value);

    if (reg < 0 || reg >= 384)
        return ;
    gemma_regs[reg] = value;


    if (gemma_regs[GEMMA_START] & 0x8)
        run_triangle_setup();

    // Run algorithms when the start register is written to
    return;
}
