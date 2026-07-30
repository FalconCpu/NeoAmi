`timescale 1ns/1ns

module iris_combine(
    input logic clock,
    input logic reset,

    // Input interfaces
    input logic        src0_valid,
    output logic       src0_ready,
    input logic [9:0]  src0_x,
    input logic [23:0] src0_color,
    input logic [19:0] src0_z,
    input logic [8:0]  src0_brightness,

    // Input interfaces
    input logic        src1_valid,
    output logic       src1_ready,
    input logic [9:0]  src1_x,
    input logic [23:0] src1_color,
    input logic [19:0] src1_z,
    input logic [8:0]  src1_brightness,

    // Output interface
    output logic        out_valid,
    output logic [9:0]  out_x,
    output logic [23:0] out_color,
    output logic [19:0] out_z,
    output logic [8:0]  out_brightness
);

assign src0_ready = src0_valid || reset;
assign src1_ready = (src1_valid && !src0_valid) || reset;

always_ff @(posedge clock) begin
    if (src0_valid) begin
        out_valid <= 1'b1;
        out_x     <= src0_x;
        out_color <= src0_color;
        out_z     <= src0_z;
        out_brightness <= src0_brightness;
    end else begin
        out_valid <= src1_valid;
        out_x     <= src1_x;
        out_color <= src1_color;
        out_z     <= src1_z;
        out_brightness <= src1_brightness;
    end
end

endmodule
