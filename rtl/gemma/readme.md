# GEMMA (GEometry and Matrix Manipulation Accelerator)

Gemma is a new custom chip for the NeoAmi. It provides a hardware accelerator for certain matrix and geometry operations, which are commonly used in graphics rendering. By offloading these operations to dedicated hardware, Gemma can free up the main CPU for other tasks, resulting in improved performance and efficiency in graphics applications.

Gemma consists of a number of specialized processing units each connected to a register bank. There are multiple memory banks. Each processing unit reads its input from one bank and writes its output to another bank. For example processing unit 0 reads from memory bank 0 and writes to memory bank 1, while processing unit 1 reads from memory bank 1 and writes to memory bank 2. In this way, the processing units can be chained together to perform complex operations in a pipelined fashion.

## Registers

Gemma is mapped into the NeoAmi's memory space at address 0xE002xxxx. Within that 64kB range, the addresses are allocated as follows:

| Address         | Description                                   |
|-----------------|-----------------------------------------------|
| 0x0000 - 0x00FF | General Control/Status                        |
| 0x0100 - 0x01FF | Transformation Matrix                         |
| 0x0200 - 0x02FF | Register bank 0 (input for processing unit 0) |
| 0x0300 - 0x03FF | Register bank 1 (output for processing unit 0, input for processing unit 1) |
| 0x0400 - 0x04FF | Register bank 2 (output for processing unit 1, input for processing unit 2) |
| 0x0500 - 0x05FF | Register bank 3 (output for processing unit 2), and so on for additional processing units |

The register banks have shadow registers for each processing unit. So when a processing unit starts it effectively takes a snapshot of the registers in its input bank, and uses those values for the entire operation. This allows the previous unit (or the CPU) to change the values in the register banks while a processing unit is running, without affecting the current operation.

Results are undefined if the CPU accesses the register banks while a processing unit is running. The CPU should wait until the BUSY bit for the processing unit is cleared before reading or writing to the register banks.

## General Control/Status Registers

These registers control the operation of the processing units, for example starting and stopping them, checking their busy status, enabling automatic processing.

Registers in this range are also used to hold values common to multiple triangle setup operations, such as the clipping rectangle and the destination write pointer for the triangle setup stage.


| Address         | Name   | Description                                   |
|-----------------|--------|-----------------------------------------|
| 0x0000          | START  | One bit per processing unit. Writing a 1 to a bit starts the corresponding processing unit. |
| 0x0004          | BUSY   | One bit per processing unit. A bit is set to 1 when the corresponding processing unit is busy, and cleared to 0 when it is idle. |
| 0x0008          | AUTO   | One bit per processing unit. When set to 1, the corresponding processing unit will automatically start processing as soon as its input data is available, and its output buffer is free. When cleared to 0, the processing unit will only start when the START bit is set. |
| 0x000C          | OUTPUT_PTR | The destination write pointer for the triangle setup stage. This holds an address in main memory where the triangle data will be written. The address is a 32-bit value, and must be aligned to a 16-byte boundary. |
| 0x0010          | CLIP_X1   | The left edge of the clipping rectangle. Used in the triangle setup stage. This is a 16-bit signed integer, and must be less than CLIP_X2. |
| 0x0014          | CLIP_Y1   | The top edge of the clipping rectangle. Used in the triangle setup stage. This is a 16-bit signed integer, and must be less than CLIP_Y2. |
| 0x0018          | CLIP_X2   | The right edge of the clipping rectangle. Used in the triangle setup stage. This is a 16-bit signed integer, and must be greater than CLIP_X1. |
| 0x001C          | CLIP_Y2   | The bottom edge of the clipping rectangle. Used in the triangle setup stage. This is a 16-bit signed integer, and must be greater than CLIP_Y1. |
| 0x0020          | TEXTURE_ADDR | The base address of the texture in main memory. Used in the triangle setup stage for textured triangles. This is a 32-bit value, and must be aligned to a 16-byte boundary. |
| 0x0024          | TEXTURE_STRIDE | The stride of the texture in bytes. Used in the triangle setup stage for textured triangles. This is a 16-bit unsigned integer, and must be greater than 0. |



## UNIT 0: COORDINATE TRANSFORM

To be defined.

## UNIT 1: CLIPPING

To be defined.

## UNIT 2: PERSPECTIVE DIVISION

To be defined.

## UNIT 3: TRIANGLE SETUP

The triangle setup unit takes a triangle defined by three vertices in screen coordinates, and computes the edge equations and bounding box for the triangle. The output is written to main memory at the address specified by the OUTPUT_PTR register as an IRIS sprite. The OUTPUT_PTR register is automatically incremented by 64 bytes after each triangle is written, so that multiple triangles can be written in sequence.

The input registers are as follows:

| Address  | Name      | Description                                   |
|----------|-----------|-----------------------------------------------|
| 0x0500   | V0_X      | The X coordinate of the topmost vertex in screen space. S12.4 format. |
| 0x0504   | V0_Y      | The Y coordinate of the topmost vertex in screen space. S12.4 format. |
| 0x0508   | V0_Z      | The inverse depth value of the topmost vertex. Pixels with a higher Z value are closer to the camera. U20 format. |
| 0x050C   | V0_R      | The red color component, or U coordinate of the topmost vertex. S12.12 format. |
| 0x0510   | V0_G      | The green color component, or V coordinate of the topmost vertex. S12.12 format. |
| 0x0514   | V0_B      | The blue color component, or brighness value, of the topmost vertex. S12.12 format. |
| 0x0520   | V1_X      | The X coordinate of the middle vertex in screen space. S12.4 format. |
| 0x0524   | V1_Y      | The Y coordinate of the middle vertex in screen space. S12.4 format. |
| 0x0528   | V1_Z      | The inverse depth value of the middle vertex. Pixels with a higher Z value are closer to the camera. U20 format. |
| 0x052C   | V1_R      | The red color component, or U coordinate of the middle vertex. S12.12 format. |
| 0x0530   | V1_G      | The green color component, or V coordinate of the middle vertex. S12.12 format. |
| 0x0534   | V1_B      | The blue color component, or brighness value, of the middle vertex. S12.12 format. |
| 0x0540   | V2_X      | The X coordinate of the bottommost vertex in screen space. S12.4 format. |
| 0x0544   | V2_Y      | The Y coordinate of the bottommost vertex in screen space. S12.4 format. |
| 0x0548   | V2_Z      | The inverse depth value of the bottommost vertex. Pixels with a higher Z value are closer to the camera. U20 format. |
| 0x054C   | V2_R      | The red color component, or U coordinate of the bottommost vertex. S12.12 format. |
| 0x0550   | V2_G      | The green color component, or V coordinate of the bottommost vertex. S12.12 format. |
| 0x0554   | V2_B      | The blue color component, or brighness value, of the bottommost vertex. S12.12 format. |
| 0x057C   | FLAGS     | Control flags for the triangle setup operation, see below. Writing to this register marks the input data as valid, and will start the triangle setup operation if the AUTO bit is set in the general control register. |

The flags register is mostly passed through to the IRIS sprite header, but bit 4 (RIGHT_EDGE) is calculated by the triangle setup unit based on the input vertex coordinates. 

| Bit | Name          | Description                                                                                |
|-----|---------------|--------------------------------------------------------------------------------------------|
| 1:0 | MODE          | 00=8 bit indexed color, 01=16 bit RGB565, 10=Gourard shaded triangle, 11=Textured triangle |
| 3:2 | PALETTE       | For 8 bit indexed color mode, this selects which of 4 pallete banks to use (0-3)           |
| 4   | RIGHT_EDGE    | For triangles, this indicates the middle vertex is the right edge (1) or left edge (0)     |
| 5   | TRANSPARENCY  | treat color index 0 as transparent (1) or opaque (0)                                       |





