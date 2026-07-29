`timescale 1ns/1ns

module iris_brightness(
    input logic clock,

    // Input interface
    input logic        bri_valid,
    input logic [9:0]  bri_x,
    input logic [23:0] bri_color,
    input logic [19:0] bri_z,
    input logic [8:0]  bri_brightness,

    // Output interface
    output logic       out_valid,
    output logic [9:0] out_x,
    output logic [23:0] out_color,
    output logic [19:0] out_z
);

logic [15:0] tmp;

// verilator lint_off BLKSEQ
always_ff @(posedge clock) begin
    out_valid <= bri_valid;
    out_x     <= bri_x;
    out_z     <= bri_z;

    // Scale the color values by the brightness factor, and saturate to 255
    // Red
    tmp = (bri_color[23:16] * bri_brightness) >> 8;
    if (tmp > 16'hFF)
        out_color[23:16] <= 8'hFF;
    else
        out_color[23:16] <= tmp[7:0];

    // Green    
    tmp = (bri_color[15:8] * bri_brightness) >> 8;
    if (tmp > 16'hFF)
        out_color[15:8] <= 8'hFF;   
    else
        out_color[15:8] <= tmp[7:0];

    // Blue
    tmp = (bri_color[7:0] * bri_brightness) >> 8;
    if (tmp > 16'hFF)
        out_color[7:0] <= 8'hFF;
    else
        out_color[7:0] <= tmp[7:0];
end

endmodule
