`timescale 1ns/1ns

// Iris Timing Generator
//
// Generate the timing signals.

module iris_timing_generator (
    input logic                clock,           // 125 MHz system clock
    input logic                reset,
    input logic signed [2:0]   KEY,

    output logic               start_of_pixel,
    output logic               start_of_line,
    output logic               start_of_frame,
    output logic signed [9:0]  ypos,
    output logic signed [10:0] xpos,

    output logic                vga_clk,         // 25 MHz pixel clock
    output logic                hsync,
    output logic                vsync
);

localparam signed H_ACTIVE = 640;
localparam signed H_FRONT_PORCH = 16;
localparam signed H_SYNC = 96;
localparam signed H_BACK_PORCH = 48;
localparam signed V_ACTIVE = 480;
localparam signed V_FRONT_PORCH = 10;
localparam signed V_SYNC = 2;
localparam signed V_BACK_PORCH = 33;

logic [2:0]  count, next_count;
logic signed [10:0]  next_xpos;
logic signed [9:0]  next_ypos;
logic next_start_of_pixel;
logic next_start_of_line;
logic next_start_of_frame;

always_comb begin
    next_count = count + 1'b1;
    next_xpos = xpos;
    next_ypos = ypos;

    next_start_of_pixel = 0;
    next_start_of_line = 0;
    next_start_of_frame = 0;

    if (count == 4) begin
        next_start_of_pixel = 1'b1;
        next_count = 0;
        next_xpos = xpos + 1'b1;

        if (xpos == H_ACTIVE-1) begin
            next_xpos = -(H_FRONT_PORCH + H_SYNC + H_BACK_PORCH);
            next_ypos = ypos + 1'b1;
            next_start_of_line = 1;
            if (ypos == V_ACTIVE) begin
                next_ypos = -(V_FRONT_PORCH + V_SYNC + V_BACK_PORCH);
                next_start_of_frame = 1'b1;
            end
        end
    end

    if (reset) begin
        next_count = 0;
        next_xpos = 0;
        next_ypos = 479;  // Start at the beginning of the vertical blanking interval
    end
end 

always_ff @(posedge clock) begin
    count <= next_count;
    xpos <= next_xpos;
    ypos <= next_ypos;
    hsync <= (xpos >= -H_BACK_PORCH - H_SYNC + 1) && (xpos < -H_BACK_PORCH + 1);
    vsync <= (ypos >= -V_BACK_PORCH - V_SYNC + 10'sd2) && (ypos < -V_BACK_PORCH + 10'sd2);
    vga_clk <= count[1];
    start_of_pixel <= next_start_of_pixel;
    start_of_line <= next_start_of_line;
    start_of_frame <= next_start_of_frame;
end

endmodule
