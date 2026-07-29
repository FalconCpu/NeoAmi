`timescale 1ns/1ns

// Texture RAM
//
// Perform bilinear filtering on a texture stored in RAM. The texture is stored in a 2D array of
// pixels, and the RAM is accessed using a 2D address.
//
// The texture ram is only 20 bits wide (to match the FPGA BRAM width), So we store colors as RGB776
// (7 bits red, 7 bits green, 6 bits blue), but treat them as RGB888 (8 bits per channel) for input and output.

module iris_texture_ram (
    input logic        clock,
    input logic        reset,

    // Pixel interface
    input logic               pixel_valid,  // 
    output logic              pixel_ready,
    input logic        [15:0] pixel_x,      // X coordinate of the pixel (pass through)
    input logic        [19:0] pixel_z,      // Z coordinate of the pixel (pass through)
    input logic signed [15:0] pixel_u,      // U coordinate of the pixel (texture coordinate) S8.8 format
    input logic signed [15:0] pixel_v,      // V coordinate of the pixel (texture coordinate) S8.8 format

    // Output pixel interface
    output logic              texel_valid,  // Output pixel valid
    input  logic              texel_ready,  // Output pixel ready
    output logic       [15:0] texel_x,      // X coordinate of the output pixel (pass through)
    output logic       [19:0] texel_z,      // Z coordinate of
    output logic       [7:0]  texel_r,      // Red channel of the output pixel
    output logic       [7:0]  texel_g,      // Green channel of
    output logic       [7:0]  texel_b,      // Blue channel of the output pixel

    // Memory interface
    input logic               aux_texram_req, // Write enable for the texture RAM
    input logic        [15:0] aux_texram_addr,  // Address of the pixel in memory
    input logic        [31:0] aux_texram_data   // Data to write to the texture RAM
);

// 4 Banks of 4K x 20 bits to store the texture data. 
// Bank 0 : Even U, Even V
// Bank 1 : Odd U, Even V
// Bank 2 : Even U, Odd V
// Bank 3 : Odd U, Odd V
logic [19:0] texram0 [0:4095]; // Texture RAM (16K x 32 bits)
logic [19:0] texram1 [0:4095]; // Texture RAM (16K x 32 bits)
logic [19:0] texram2 [0:4095]; // Texture RAM (16K x 32 bits)
logic [19:0] texram3 [0:4095]; // Texture RAM (16K x 32 bits)

// ===============================================================
//                  Pipeline control
// ===============================================================

logic p2_valid, p2_ready;
assign p2_ready = texel_ready || !texel_valid;
assign pixel_ready = p2_ready || !p2_valid;



// ===============================================================
//                  First stage: Determine address
// ===============================================================
// Bit 8 of U and V is used to select the bank
// Bits 


logic [5:0] p1_u0, p1_u1, p1_v0, p1_v1; // 6-bit U and V coordinates for the four texels
logic [8:0] p1_frac_u0, p1_frac_v0; // 8-bit fractional parts of U and V for interpolation
logic [8:0] p1_frac_u1, p1_frac_v1; // 8-bit fractional parts of U and V for interpolation

always_comb begin
    if (pixel_u[8]==1'b0) begin
        // Even U
        p1_u0 = pixel_u[14:9]; // Even U
        p1_u1 = pixel_u[14:9];
        p1_frac_u0 = 9'h100 - pixel_u[7:0]; // Fractional part of U for even U
        p1_frac_u1 = {1'b0, pixel_u[7:0]}; // Fractional part of U for odd U
    end else begin
        p1_u0 = pixel_u[14:9] + 1'b1; // Odd U
        p1_u1 = pixel_u[14:9];
        p1_frac_u0 =  {1'b0, pixel_u[7:0]}; // Fractional part of U for even U
        p1_frac_u1 = 9'h100 - pixel_u[7:0]; // Fractional part of U for odd U
    end

    if (pixel_v[8]==1'b0) begin
        // Even V
        p1_v0 = pixel_v[14:9]; // Even V
        p1_v1 = pixel_v[14:9];
        p1_frac_v0 = 9'h100 - pixel_v[7:0]; // Fractional part of V for even V
        p1_frac_v1 = {1'b0, pixel_v[7:0]}; // Fractional part of V for odd V
    end else begin
        p1_v0 = pixel_v[14:9] + 1'b1; // Odd V
        p1_v1 = pixel_v[14:9];
        p1_frac_v0 = {1'b0, pixel_v[7:0]}; // Fractional part of V for even V
        p1_frac_v1 = 9'h100 - pixel_v[7:0]; // Fractional part of V for odd V
    end
end



// ===============================================================
//                  Fetch texels from RAM
// ===============================================================

logic       [15:0] p2_x;
logic       [19:0] p2_z;
logic       [19:0] texel0, texel1, texel2, texel3; // Four texels fetched from the RAM
logic       [17:0]  p2_frac0, p2_frac1, p2_frac2, p2_frac3; // Fractional parts for interpolation


always_ff @(posedge clock) begin
    if (pixel_ready) begin

        p2_valid <= pixel_valid;
        p2_x     <= pixel_x;
        p2_z     <= pixel_z;

        // Fetch the four texels from the RAM
        texel0 <= texram0[{p1_v0, p1_u0}]; // Even U, Even V
        texel1 <= texram1[{p1_v0, p1_u1}]; // Odd U, Even V
        texel2 <= texram2[{p1_v1, p1_u0}]; // Even U, Odd V
        texel3 <= texram3[{p1_v1, p1_u1}]; // Odd U, Odd V

        p2_frac0 <= p1_frac_u0 * p1_frac_v0; // Fractional part for texel0
        p2_frac1 <= p1_frac_u1 * p1_frac_v0; // Fractional part for texel1
        p2_frac2 <= p1_frac_u0 * p1_frac_v1; // Fractional part for texel2
        p2_frac3 <= p1_frac_u1 * p1_frac_v1; // Fractional part for texel3
    end

end

// ===============================================================
//                  Multiply colors by fractional parts
// ===============================================================

logic       [15:0] p3_x;
logic       [19:0] p3_z;
logic              p3_valid;
logic [17:0] p3_r0, p3_g0, p3_b0; // Texel 0 color multiplied by fractional part
logic [17:0] p3_r1, p3_g1, p3_b1; // Texel 1 color multiplied by fractional part
logic [17:0] p3_r2, p3_g2, p3_b2; // Texel 2 color multiplied by fractional part
logic [17:0] p3_r3, p3_g3, p3_b3; // Texel 3 color multiplied by fractional part

always_ff @(posedge clock) begin
    if (p2_ready) begin
        p3_valid <= p2_valid;
        p3_x <= p2_x;
        p3_z <= p2_z;

        p3_r0 <= texel0[19:13] * p2_frac0[17:9]; // Red channel of texel0 multiplied by fractional part
        p3_g0 <= texel0[12:6]  * p2_frac0[17:9]; // Green channel of texel0 multiplied by fractional part
        p3_b0 <= texel0[5:0]   * p2_frac0[17:9]; // Blue channel of texel0 multiplied by fractional part

        p3_r1 <= texel1[19:13] * p2_frac1[17:9]; // Red channel of texel1 multiplied by fractional part
        p3_g1 <= texel1[12:6]  * p2_frac1[17:9]; // Green channel of texel1 multiplied by fractional part
        p3_b1 <= texel1[5:0]   * p2_frac1[17:9]; // Blue channel of texel1 multiplied by fractional part

        p3_r2 <= texel2[19:13] * p2_frac2[17:9]; // Red channel of texel2 multiplied by fractional part
        p3_g2 <= texel2[12:6]  * p2_frac2[17:9]; // Green channel of texel2 multiplied by fractional part
        p3_b2 <= texel2[5:0]   * p2_frac2[17:9]; // Blue channel of texel2 multiplied by fractional part

        p3_r3 <= texel3[19:13] * p2_frac3[17:9]; // Red channel of texel3 multiplied by fractional part
        p3_g3 <= texel3[12:6]  * p2_frac3[17:9]; // Green channel of texel3 multiplied by fractional part
        p3_b3 <= texel3[5:0]   * p2_frac3[17:9]; // Blue channel of texel3 multiplied by fractional part
    end
end


// ===============================================================
//                  Texture RAM Write Logic
// ===============================================================
//
// Address fields:
// 1:0     Byte offset (ignored, since we write 32 bits at a time)
// 2       Bank select X
// 8:3     Column address (U coordinate)
// 9       Bank select Y
// 15:10   Row address (V coordinate)

wire [11:0] ram_addr = {aux_texram_addr[15:10], aux_texram_addr[8:3]}; // 12-bit address for the RAM (row and column)
wire [19:0] ram_wdata = {aux_texram_data[23:17], aux_texram_data[15:9], aux_texram_data[7:2]}; // 20-bit data to write to the RAM (RGB776 format)

always_ff @(posedge clock) begin
    if (aux_texram_req) begin
        case ({aux_texram_addr[9], aux_texram_addr[2]}) // Bank select
            2'b00: texram0[ram_addr] <= ram_wdata; // Even U, Even V
            2'b01: texram1[ram_addr] <= ram_wdata; // Odd U, Even V
            2'b10: texram2[ram_addr] <= ram_wdata; // Even U, Odd V
            2'b11: texram3[ram_addr] <= ram_wdata; // Odd U, Odd V
        endcase
    end
end

endmodule
    