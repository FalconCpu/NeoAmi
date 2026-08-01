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

#define GEMMA_TS_V0_X  (0x500/4)
#define GEMMA_TS_V0_Y  (0x504/4)
#define GEMMA_TS_V0_Z  (0x508/4)
#define GEMMA_TS_V0_R  (0x50C/4)
#define GEMMA_TS_V0_G  (0x510/4)
#define GEMMA_TS_V0_B  (0x514/4)
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

static int gemma_regs[384];


// =================================================================
//                Triangle Setup
// =================================================================

void run_triangle_setup() {
    // This is a golden model of the triangle setup algorithm. It is not cycle accurate, but it should produce the same results as the RTL implementation.

    // Find the scanline for each vertex, adjusting for 0.5 pixel center of the scanline
        var y1 = (v1.y) as Int
        var y2 = (v2.y) as Int
        var y3 = (v3.y) as Int

        if y3 <= y1
            return false
        if y3 < clipY1 or y1 >= clipY2
            return false

}


// =================================================================
//                GEMMA read/write functions
// =================================================================

int read_gemma(int reg) {
    reg = reg / 4; // Convert byte address to word index
    if (reg < 0 || reg >= 384)
        return 0;
    return gemma_regs[reg];
}

void write_gemma(int reg, int value) {
    gemma_regs[0] = 0;      // Start register is self clearing
    reg = reg / 4; // Convert byte address to word index

    if (reg < 0 || reg >= 384)
        return ;
    gemma_regs[reg] = value;


    // Run algorithms when the start register is written to
    return;
}
