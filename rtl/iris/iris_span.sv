`timescale 1ns/1ns

module iris_span(
    input logic       clock,
    input logic       reset,

    // Input bus
    input logic        span_valid,
    output logic       span_ready,
    input logic [7:0]  span_flags,
    input logic [9:0]  span_x1,          // Start X coordinate
    input logic [9:0]  span_x2,          // End X coordinate
    input logic [23:0] span_z,
    input logic [23:0] span_dzdx,
    input logic [23:0] span_r,
    input logic [23:0] span_drdx,
    input logic [23:0] span_g,
    input logic [23:0] span_dgdx,
    input logic [23:0] span_b,
    input logic [23:0] span_dbdx,

    // Output bus
    output logic        pixel_valid_gourand,
    output logic        pixel_valid_texture,
    input logic         pixel_ready_gourand,
    input logic         pixel_ready_texture,
    output logic [9:0]  pixel_x,         // Pixel X coordinate
    output logic [7:0]  pixel_flags,
    output logic [23:0] pixel_z,
    output logic [23:0] pixel_r,
    output logic [23:0] pixel_g,
    output logic [23:0] pixel_b
);

logic [9:0]  pixel_x2;
logic [23:0] pixel_dzdx;
logic [23:0] pixel_drdx;
logic [23:0] pixel_dgdx;
logic [23:0] pixel_dbdx;
logic        busy;

assign span_ready = !busy;
assign pixel_valid_gourand = busy && pixel_flags[1:0]==2'h2;
assign pixel_valid_texture = busy && pixel_flags[1]==1'h0;
wire advance = (pixel_valid_gourand && pixel_ready_gourand) || (pixel_valid_texture && pixel_ready_texture);
wire [9:0] x_inc = pixel_x + 10'd1;


always_ff @(posedge clock) begin
    if (busy==1'b0) begin
        busy       <= span_valid;
        pixel_flags <= span_flags;
        pixel_x    <= span_x1;
        pixel_x2   <= span_x2;
        pixel_z    <= span_z;
        pixel_dzdx <= span_dzdx;
        pixel_r    <= span_r;
        pixel_drdx <= span_drdx;
        pixel_g    <= span_g;
        pixel_dgdx <= span_dgdx;
        pixel_b    <= span_b;
        pixel_dbdx <= span_dbdx;

    end else if (advance) begin
        busy       <= (x_inc < pixel_x2);
        pixel_x    <= x_inc;
        pixel_z    <= pixel_z + pixel_dzdx;
        pixel_r    <= pixel_r + pixel_drdx;
        pixel_g    <= pixel_g + pixel_dgdx;
        pixel_b    <= pixel_b + pixel_dbdx;
    end

    if (reset) begin
        busy <= 1'b0;
    end
end


endmodule
