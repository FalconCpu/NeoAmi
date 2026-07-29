`timescale 1ns/1ns

// IRIS - Interpolated Rasterization Image Synthesizer
//
// Pipeline for rendering 2D triangles
//
// * Object walk
// * Span walk
// * Address Generation
// * Texture lookup
// * Palette lookup
// * Path Combiner
// * Z buffer
// * Scanline ram



// Memory map
// 0x0000 - 0x3FFF: Object list memory (16KB)
// 0x4000 - 0x4FFF: Palette memory (4 banks of 256 colors, 4KB)
// 0x5000 - 0x5FFF:

module iris (
    input  logic            clock,           // 125 MHz system clock
    input  logic            reset,
    input logic  [2:0]         KEY,

    // Aux bus - for configuration and memory access
    input logic            aux_iris_req,
    input logic [15:0]     aux_iris_addr,
    input logic [31:0]     aux_iris_wdata,

    // VGA interface
	output logic       	   VGA_BLANK_N,
	output logic  [7:0]	   VGA_B,
	output logic       	   VGA_CLK,
	output logic  [7:0]	   VGA_G,
	output logic       	   VGA_HS,
	output logic  [7:0]	   VGA_R,
	output logic       	   VGA_SYNC_N,
	output logic       	   VGA_VS
);

logic           start_of_pixel;
logic           start_of_line;
logic           start_of_frame;
logic [9:0]     ypos;
logic [10:0]    xpos;
logic           vga_clk;
logic           hsync;
logic           vsync;

// Span bus
logic        span_valid;
logic        span_ready;
logic [7:0]  span_flags;
logic [9:0]  span_x1;
logic [9:0]  span_x2;
logic [23:0] span_z;
logic [23:0] span_dzdx;
logic [23:0] span_r;
logic [23:0] span_drdx;
logic [23:0] span_g;
logic [23:0] span_dgdx;
logic [23:0] span_b;
logic [23:0] span_dbdx;
logic [25:0] span_texaddr;
logic [15:0] span_texstride;

// scanline buffer
logic [7:0]  vga_r;
logic [7:0]  vga_g;
logic [7:0]  vga_b;

iris_objwalk  iris_objwalk_inst (
    .clock(clock),
    .reset(reset),
    .start_of_line(start_of_line),
    .ypos(ypos),
    .aux_iris_req(aux_iris_req && aux_iris_addr[15:14] == 2'b0),
    .aux_iris_addr(aux_iris_addr[13:2]),
    .aux_iris_wdata(aux_iris_wdata),
    .span_valid(span_valid),
    .span_ready(span_ready),
    .span_flags(span_flags),
    .span_x1(span_x1),
    .span_x2(span_x2),
    .span_z(span_z),
    .span_dzdx(span_dzdx),
    .span_r(span_r),
    .span_drdx(span_drdx),
    .span_g(span_g),
    .span_dgdx(span_dgdx),
    .span_b(span_b),
    .span_dbdx(span_dbdx),
    .span_texaddr(span_texaddr),
    .span_texstride(span_texstride)
  );

// ============================================================
//                SPAN WALK
// ============================================================
logic        pixel_valid_gourand;
logic        pixel_ready_gourand;
logic        pixel_valid_texture;
logic        pixel_ready_texture;
logic [9:0]  pixel_x;
logic [23:0] pixel_z;
logic [23:0] pixel_r;
logic [23:0] pixel_g;
logic [23:0] pixel_b;
logic [7:0]  pixel_flags;

iris_span  iris_span_inst (
    .clock(clock),
    .reset(reset),
    .span_valid(span_valid),
    .span_ready(span_ready),
    .span_flags(span_flags),
    .span_x1(span_x1),
    .span_x2(span_x2),
    .span_z(span_z),
    .span_dzdx(span_dzdx),
    .span_r(span_r),
    .span_drdx(span_drdx),
    .span_g(span_g),
    .span_dgdx(span_dgdx),
    .span_b(span_b),
    .span_dbdx(span_dbdx),
    .pixel_valid_gourand(pixel_valid_gourand),
    .pixel_valid_texture(pixel_valid_texture),
    .pixel_ready_gourand(pixel_ready_gourand),
    .pixel_ready_texture(pixel_ready_texture),
    .pixel_flags(pixel_flags),
    .pixel_x(pixel_x),
    .pixel_z(pixel_z),
    .pixel_r(pixel_r),
    .pixel_g(pixel_g),
    .pixel_b(pixel_b)
  );

logic         pal_valid;
logic         pal_ready;
logic [7:0]   pal_flags;
logic [9:0]   pal_x;
logic [7:0]   pal_color_index;
logic [19:0]  pal_z;
logic [8:0]   pal_brightness;

// ============================================================
//                GOURAND SHADER
// ============================================================
logic        gourand_valid;
logic        gourand_ready;
logic [9:0]  gourand_x;
logic [23:0] gourand_color;
logic [19:0] gourand_z;


iris_gourand  iris_gourand_inst (
    .clock(clock),
    .pixel_valid_gourand(pixel_valid_gourand),
    .pixel_ready_gourand(pixel_ready_gourand),
    .pixel_flags(pixel_flags),
    .pixel_x(pixel_x),
    .pixel_r(pixel_r),
    .pixel_g(pixel_g),
    .pixel_b(pixel_b),
    .pixel_z(pixel_z[23:4]),
    .out_valid(gourand_valid),
    .out_ready(gourand_ready),
    .out_x(gourand_x),
    .out_color(gourand_color),
    .out_z(gourand_z)
);

// ============================================================
//                Palette Lookup
// ============================================================

logic        texpath_valid;
logic        texpath_ready;
logic [9:0]  texpath_x;
logic [23:0] texpath_color;
logic [19:0] texpath_z;
logic [8:0]  texpath_brightness;

iris_palette  iris_palette_inst (
    .clock(clock),
    .pal_valid(pal_valid),
    .pal_ready(pal_ready),
    .pal_flags(pal_flags),
    .pal_x(pal_x),
    .pal_color_index(pal_color_index),
    .pal_z(pal_z),
    .pal_brightness(pal_brightness),
    .out_valid(texpath_valid),
    .out_ready(texpath_ready),
    .out_x(texpath_x),
    .out_color(texpath_color),
    .out_z(texpath_z),
    .out_brightness(texpath_brightness),
    .aux_iris_palette_req(aux_iris_req && aux_iris_addr[15:12] == 4'h4),
    .aux_iris_addr(aux_iris_addr[11:2]),
    .aux_iris_wdata(aux_iris_wdata)
  );

// ============================================================
//                PATH COMBINER
// ============================================================

logic        bri_valid;
logic [9:0]  bri_x;
logic [23:0] bri_color;
logic [19:0] bri_z;
logic [8:0]  bri_brightness;

iris_combine  iris_combine_inst (
    .clock(clock),
    .src0_valid(texpath_valid),
    .src0_ready(texpath_ready),
    .src0_x(texpath_x),
    .src0_color(texpath_color),
    .src0_z(texpath_z),
    .src0_brightness(texpath_brightness),
    .src1_valid(gourand_valid),
    .src1_ready(gourand_ready),
    .src1_x(gourand_x),
    .src1_color(gourand_color),
    .src1_z(gourand_z),
    .src1_brightness(9'h100),
    .out_valid(bri_valid),
    .out_x(bri_x),
    .out_color(bri_color),
    .out_z(bri_z),
    .out_brightness(bri_brightness)
  );

// ============================================================
//                BRIGHTNESS ADJUST
// ============================================================

logic        zbuf_valid;
logic [9:0]  zbuf_x;
logic [23:0] zbuf_color;
logic [19:0] zbuf_z;

iris_brightness  iris_brightness_inst (
    .clock(clock),
    .bri_valid(bri_valid),
    .bri_x(bri_x),
    .bri_color(bri_color),
    .bri_z(bri_z),
    .bri_brightness(bri_brightness),
    .out_valid(zbuf_valid),
    .out_x(zbuf_x),
    .out_color(zbuf_color),
    .out_z(zbuf_z)
  );

// ============================================================
//                Z BUFFER
// ============================================================

 logic              ram_wren;
 logic [9:0]        ram_xpos;
 logic [23:0]       ram_color;

iris_zbuf  iris_zbuf_inst (
    .clock(clock),
    .reset(reset),
    .start_of_line(start_of_line),
    .zbuf_valid(zbuf_valid),
    .zbuf_x(zbuf_x),
    .zbuf_color(zbuf_color),
    .zbuf_z(zbuf_z),
    .out_valid(ram_wren),
    .out_color(ram_color),
    .out_x(ram_xpos)
  );  
// ============================================================
//                SCANLINE RAM
// ============================================================

iris_scanline_ram  iris_scanline_ram_inst (
    .clock(clock),
    .ram_wren(ram_wren),
    .ram_xpos(ram_xpos),
    .ram_color(ram_color),
    .xpos(xpos),
    .ypos(ypos),
    .start_of_pixel(start_of_pixel),
    .vga_r(vga_r),
    .vga_g(vga_g),
    .vga_b(vga_b)
  );

// ============================================================
//                TIMING GENERATOR
// ============================================================

iris_timing_generator  iris_timing_generator_inst (
    .clock(clock),
    .reset(reset),
    .KEY(KEY),
    .start_of_pixel(start_of_pixel),
    .start_of_line(start_of_line),
    .start_of_frame(start_of_frame),
    .ypos(ypos),
    .xpos(xpos),
    .vga_clk(vga_clk),
    .hsync(hsync),
    .vsync(vsync)
  );

always @(posedge clock) begin
    VGA_BLANK_N <= 1'b1;
    VGA_SYNC_N <= 1'b1;
    VGA_R <= vga_r;
    VGA_G <= vga_g;
    VGA_B <= vga_b;
    VGA_CLK <= vga_clk;
    VGA_HS <= !hsync;
    VGA_VS <= !vsync;
end

wire unused = &{pixel_z[3:0], aux_iris_addr[1:0]};

endmodule
