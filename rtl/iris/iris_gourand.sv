`timescale 1ns/1ns

module iris_gourand(
    input logic clock,
    input logic reset,

    // Input interface
    input logic         pixel_valid_gourand,
    output logic        pixel_ready_gourand,
    input logic [7:0]   pixel_flags,
    input logic [9:0]   pixel_x,
    input logic [23:0]  pixel_r,
    input logic [23:0]  pixel_g,
    input logic [23:0]  pixel_b,
    input logic [19:0]  pixel_z,

    // Output interface
    output logic        out_valid,
    input logic         out_ready,
    output logic [9:0]  out_x,
    output logic [23:0] out_color,
    output logic [19:0] out_z
);

assign pixel_ready_gourand = out_ready || !out_valid;

// The color values arrive as S12.12 fixed-point numbers.
// Saturate the color values to the range [0, 255] and convert them to 8-bit integers.

wire [7:0] color_r = (pixel_r[23:20]==4'h0) ? pixel_r[19:12] :
                     (pixel_r[23]==1'b0)    ? 8'hFF
                                            : 8'h00;
wire [7:0] color_g = (pixel_g[23:20]==4'h0) ? pixel_g[19:12] :
                     (pixel_g[23]==1'b0)    ? 8'hFF
                                            : 8'h00;
wire [7:0] color_b = (pixel_b[23:20]==4'h0) ? pixel_b[19:12] :
                     (pixel_b[23]==1'b0)    ? 8'hFF
                                            : 8'h00;


always_ff @(posedge clock) begin
    if (pixel_ready_gourand) begin
        out_valid <= pixel_valid_gourand;
        out_x     <= pixel_x;
        out_color <= {color_r, color_g, color_b};
        out_z     <= pixel_z;
    end

    if (reset) begin
        out_valid <= 1'b0;
    end
end

wire unused = &{pixel_r[11:0], pixel_g[11:0], pixel_b[11:0], pixel_flags};

endmodule
