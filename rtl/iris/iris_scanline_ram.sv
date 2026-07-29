`timescale 1ns/1ns

// Line buffer for Iris
//
// Double-buffered scanline buffer.
// 
// Receives pixel data from the span rasterizer into one buffer while the other buffer is being read out to the VGA interface.
// When the scanline is complete, the buffers are swapped.

module iris_scanline_ram (
    input  logic            clock,

    // Input signals
    input logic              ram_wren,          // Write enable for the scanline buffer
    input logic [9:0]        ram_xpos,          // X coordinate of the pixel to write
    input logic [23:0]       ram_color,         // Color of the pixel to write

    // Output bus
    input logic signed [10:0] xpos,             // X coordinate of the pixel to read
    input logic signed [9:0]  ypos,             // Y coordinate of the pixel to read
    input logic               start_of_pixel,   // Start of pixel signal from the timing generator
    output logic        [7:0] vga_r,
    output logic        [7:0] vga_g,
    output logic        [7:0] vga_b
);

// Double-buffered scanline buffer
logic [23:0]  ram_0[0:1023];        
logic [23:0]  ram_1[0:1023];

logic        ram0_wren;
logic        ram0_rden;
logic [9:0]  ram0_addr;
logic [23:0] ram0_wdata;
logic [23:0] ram0_rdata;

logic        ram1_wren;
logic        ram1_rden;
logic [9:0]  ram1_addr;
logic [23:0] ram1_wdata;
logic [23:0] ram1_rdata;

logic        pixel_valid, next_pixel_valid;     // Indicates we have read a valid pixel from the scanline buffer
logic        second_cycle;                      // Indicates we are in the second cycle of reading a pixel from the scanline buffer

always_comb begin
    // Default values
    ram0_wren = 1'b0;
    ram0_rden = 1'b0;
    ram0_addr = 10'hx;
    ram0_wdata = 24'hx;
    ram1_wren = 1'b0;
    ram1_rden = 1'b0;
    ram1_addr = 10'hx;
    ram1_wdata = 24'hx;
    next_pixel_valid = pixel_valid;

    // Write to the scanline buffer
    if (ram_wren) begin
        if (ypos[0] == 1'b0) begin
            ram0_wren = 1'b1;
            ram0_addr = ram_xpos;
            ram0_wdata = ram_color;
        end else begin
            ram1_wren = 1'b1;
            ram1_addr = ram_xpos;
            ram1_wdata = ram_color;
        end
    end

    // Read from the scanline buffer
    if (start_of_pixel) begin
        if (ypos[0] == 1'b0) begin
            ram1_rden = 1'b1;
            ram1_addr = xpos[9:0];
        end else begin
            ram0_rden = 1'b1;
            ram0_addr = xpos[9:0];
        end

        // Note - offset by one in vertical direction to account for the fact that the scanline buffer is
        // being filled while the previous scanline is being read out.
        next_pixel_valid = (xpos >= 0) && (xpos < 640) && (ypos >= 1) && (ypos < 481);
    end
    
    // Erase the pixel values after they have been read out, ready for the next scanline 
    if (second_cycle) begin
        if (ypos[0] == 1'b0) begin
            ram1_wren = 1'b1;
            ram1_addr = xpos[9:0];
            ram1_wdata = 24'h000000;
        end else begin
            ram0_wren = 1'b1;
            ram0_addr = xpos[9:0];
            ram0_wdata = 24'h000000;
        end
    end

    // Output pixel color
    if (!pixel_valid) begin
        vga_r = 8'h00;
        vga_g = 8'h00;
        vga_b = 8'h00;
    end else if (ypos[0] == 1'b0) begin
        vga_r = ram1_rdata[23:16];
        vga_g = ram1_rdata[15:8];
        vga_b = ram1_rdata[7:0];
    end else begin
        vga_r = ram0_rdata[23:16];
        vga_g = ram0_rdata[15:8];
        vga_b = ram0_rdata[7:0];
    end
end


always_ff @(posedge clock) begin
    if (ram0_wren)
        ram_0[ram0_addr] <= ram0_wdata;
    if (ram0_rden)
        ram0_rdata <= ram_0[ram0_addr];
    if (ram1_wren)
        ram_1[ram1_addr] <= ram1_wdata;
    if (ram1_rden)
        ram1_rdata <= ram_1[ram1_addr];
    pixel_valid <= next_pixel_valid;
    second_cycle <= start_of_pixel;
end


endmodule
