`timescale 1ns/1ns

module iris_addrgen(
    input logic         clock,
    input logic         reset,
    
    // Input stream of pixel requests from the spanwalk stage
    output logic                pixel_ready,     // We can accept a req_valid
    input  logic                pixel_valid,     // A transaction is ready to be processed
    input  logic        [15:0]  pixel_flags,     // bit 0: 0=texture fetch, 1=solid color
    input  logic        [25:0]  pixel_addr,      // Base address for texture fetch
    input  logic        [15:0]  pixel_stride,    // Stride to add to the address for each pixel in the span (for textures)
    input  logic signed [23:0]  pixel_u,         // U coordinate for texture fetches,or R coordinate for solid color fills
    input  logic signed [23:0]  pixel_v,         // V coordinate for texture fetches, or G coordinate for solid color fills
    input  logic signed [23:0]  pixel_bright,    // Brghtness level 
    input  logic        [23:0]  pixel_z,         // Z coordinate for z-buffering (passed through for textures)
    input  logic        [9:0]   pixel_x,         // Pixel X coordinate (for texture fetches)
    
    // Output stream to the readmem stage
    input  logic         readmem_ready,     // We can accept a req_valid
    output logic         readmem_req,       // We have a pixel request ready
    output logic [15:0]  readmem_mode,      // Mode (passed through from spanwalk)
    output logic [25:0]  readmem_addr,      // Address to read or data to pass through (for solid color)
    output logic [23:0]  readmem_z,         // Z coordinate for z-buffering
    output logic [8:0]   readmem_bright,    // Brightness level for solid color fills (passed through from addrgen)
    output logic [9:0]   readmem_x          // Pixel X coordinate
);

wire req_for_us = pixel_valid;
wire not_stall = readmem_ready || readmem_req==1'b0 || reset;
assign pixel_ready = not_stall && req_for_us;

wire signed [11:0] v = pixel_v[23:12];
wire signed [15:0] strise_s = pixel_stride;
wire signed [25:0] vv = strise_s * v;

always_ff @(posedge clock) begin
    if (not_stall) begin
        readmem_req <= req_for_us;
        readmem_mode <= pixel_flags;
        readmem_addr <= pixel_addr + {14'b0,pixel_u[23:12]} + vv;
        readmem_z <= pixel_z;
        readmem_x <= pixel_x;
        readmem_bright <= pixel_bright[20:12];
    end
end

wire unused = &{pixel_u[11:0], pixel_v[11:0], pixel_bright[11:0], pixel_bright[23:21]};

endmodule

