`timescale 1ns/1ns

// Z-buffer module
//
// Check each pixel against the Z-buffer and output the pixel if it is closer than the current value in the Z-buffer 
// (Z value is 1/distance from camera, so larger Z values are closer to the camera).
//
// In order to clear the Z-buffer between lines, we double buffer the Z-buffer and switch between the two buffers
// at the start of each line.

module iris_zbuf(
    input logic clock,
    input logic reset,
    input logic start_of_line,

    // Input interface
    input logic        zbuf_valid,
    input logic [9:0]  zbuf_x,
    input logic [23:0] zbuf_color,
    input logic [19:0] zbuf_z,

    // Output interface
    output logic        out_valid,
    output logic [23:0] out_color,
    output logic [9:0]  out_x
);

logic [19:0] zbuf0[0:1023];
logic        zbuf0_wen;
logic [9:0]  zbuf0_waddr;
logic [19:0] zbuf0_wdata;
logic [19:0] zbuf0_rdata;

logic [19:0] zbuf1[0:1023];
logic        zbuf1_wen;
logic [9:0]  zbuf1_waddr;
logic [19:0] zbuf1_wdata;
logic [19:0] zbuf1_rdata;

logic        zbuf_select;
logic [9:0]  clear_index;
logic        clear_done;
logic        out_valid_pre_check;
logic [19:0] out_z;

logic [19:0] zbuf_rdata;

always_comb begin
    // Select the appropriate Z-buffer based on the current line
    zbuf_rdata = zbuf_select ? zbuf1_rdata : zbuf0_rdata;

    // Qualify the output as valid if the Z-buffer is ready and the pixel is closer than the current value in the Z-buffer
    out_valid = out_valid_pre_check && (out_z > zbuf_rdata);

    // Update the Z-buffer of the selceted buffer when outputting a pixel
    // Blank the other buffer to clear it for the next line
    if (zbuf_select) begin
        zbuf1_wen   = out_valid;
        zbuf1_waddr = out_x;
        zbuf1_wdata = out_z;
        zbuf0_wen   = 1'b1;
        zbuf0_waddr = clear_index;
        zbuf0_wdata = 20'd0;
    end else begin
        zbuf0_wen   = out_valid;
        zbuf0_waddr = out_x;
        zbuf0_wdata = out_z;
        zbuf1_wen   = 1'b1;
        zbuf1_waddr = clear_index;
        zbuf1_wdata = 20'd0;
    end
end

always_ff @(posedge clock) begin

    // Load a new operation when ready
    out_valid_pre_check <= zbuf_valid;
    out_x     <= zbuf_x;
    out_color <= zbuf_color;
    out_z     <= zbuf_z;

    // Increment the clear index if we are clearing the Z-buffer
    if (!clear_done) begin
        clear_index <= clear_index + 10'd1;
        if (clear_index == 10'd1023)
            clear_done <= 1'b1;
    end

    // At the start of each line, switch the Z-buffer and clear the new buffer
    if (start_of_line) begin
        zbuf_select <= ~zbuf_select;
        clear_index <= 10'd0;
        clear_done  <= 1'b0;
    end

    // Reset
    if (reset) begin
        zbuf_select <= 1'b0;
        clear_index <= 10'd0;
        clear_done  <= 1'b0;
        out_valid_pre_check <= 1'b0;
    end

end
// Clear the Z-buffer at the start of each line


// Z-buffer memory read/write logic
always_ff @(posedge clock) begin
    if (zbuf0_wen) 
        zbuf0[zbuf0_waddr] <= zbuf0_wdata;
    if (zbuf1_wen) 
        zbuf1[zbuf1_waddr] <= zbuf1_wdata;
    zbuf0_rdata <= zbuf0[zbuf_x];
    zbuf1_rdata <= zbuf1[zbuf_x];
end

endmodule
