`timescale 1ns/1ns

module iris_palette(
    input logic clock,

    // Input interface
    input logic         pal_valid,
    output logic        pal_ready,
    input logic [7:0]   pal_flags,      // [3:2]=Paltette bank, Bit 5: transparency
    input logic [9:0]   pal_x,
    input logic [7:0]   pal_color_index,
    input logic [19:0]  pal_z,
    input logic [8:0]   pal_brightness,  // Brightness value for the pixel

    // Output interface
    output logic        out_valid,
    input logic         out_ready,
    output logic [9:0]  out_x,
    output logic [23:0] out_color,
    output logic [19:0] out_z,
    output logic [8:0]  out_brightness,

    // Configuration interface
    input logic            aux_iris_palette_req,
    input logic [9:0]     aux_iris_addr,
    input logic [31:0]     aux_iris_wdata
);

logic [23:0] palette[0:1023];  // 4 banks of 256 colors

// ==============================================================
//                 Palette Lookup
// ==============================================================

assign pal_ready = out_ready || !out_valid;

always_ff @(posedge clock) begin
    if (pal_ready) begin
        if (pal_color_index==8'h0 && pal_flags[5]) begin
            // Transparent pixel - don't output
            out_valid <= 1'b0;

        end else begin
            // Lookup color in palette
            out_valid <= pal_valid;
            out_x     <= pal_x;
            out_z     <= pal_z;
            out_color <= palette[{pal_flags[3:2], pal_color_index}];
            out_brightness <= pal_brightness;
        end
    end
end



// ==============================================================
//                 Palette Write Logic
// ==============================================================

always_ff @(posedge clock) begin
    // Write to palette memory
    if (aux_iris_palette_req)
        palette[aux_iris_addr] <= aux_iris_wdata[23:0];
end

wire unused = &{aux_iris_wdata[31:24], pal_flags[1:0], pal_flags[7:6], pal_flags[4]};

endmodule
