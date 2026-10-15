`timescale 1ns/1ns

module iris_palette(
    input logic clock,
    input logic reset,

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

logic [23:0] pal_color;     // Color fetched from the palette
logic [23:0] ham_color;     // Color computed for HAM mode
logic        use_pal_color; 

assign pal_ready = out_ready || !out_valid;

logic [9:0] palette_index;
always_comb begin
    if (pal_flags[1:0] == 2'b01) begin
        // HAM mode - only use the bottom half of the color index
        palette_index = {pal_flags[3:2], 1'b0, pal_color_index[6:0]};
    end else begin
        // Regular palette lookup
        palette_index = {pal_flags[3:2], pal_color_index};
    end
end

assign out_color = use_pal_color ? pal_color : ham_color;

logic [7:0] ham_inc;
logic [8:0] ham_add;

// verilator lint_off BLKSEQ
always_ff @(posedge clock) begin
    ham_color <= out_color;
    use_pal_color <= 1'b0;
    ham_inc = 8'hx;
    ham_add = 9'hx;


    if (pal_ready) begin
        if (!pal_valid) begin
            out_valid <= 1'b0;
        end else if (pal_color_index==8'h0) begin
            // Transparent pixel - don't output
            // TODO - add qualification based on input flags
            out_valid <= 1'b0;
        end else begin
            // Lookup color in palette
            out_valid <= pal_valid;
            out_x     <= pal_x;
            out_z     <= pal_z;
            out_brightness <= pal_brightness;

            if (pal_flags[1:0]!=2'b01 || pal_color_index[7]==1'b0) begin
                // Not in HAM mode or using a regular palette color
                use_pal_color <= 1'b1;
            end else begin
                // HAM mode - modify the appropriate color component based on the lower bits of the palette index
                use_pal_color <= 1'b0;
                ham_inc = pal_color_index[3:0]==4'b0000 ? 8'h8 : {{4{pal_color_index[3]}}, pal_color_index[3:0]};
                if (pal_color_index[6]) begin
                    // Modify red component - add the HAM increment to the current red value, and clamp the result to [0, 255]
                    ham_add = {1'b0, out_color[23:16]} + {{1{ham_inc[7]}}, ham_inc};
                    ham_color[23:16] <= ham_add[8]==1'b0 ? ham_add[7:0]
                                    : ham_add[7]==1'b1 ? 8'h0
                                    : 8'hff;
                end
                if (pal_color_index[5]) begin
                    // Modify green component
                    ham_add = {1'b0, out_color[15:8]} + {{1{ham_inc[7]}}, ham_inc};
                    ham_color[15:8] <= ham_add[8]==1'b0 ? ham_add[7:0]
                                    : ham_add[7]==1'b1 ? 8'h0 
                                    : 8'hff;
                end
                if (pal_color_index[4]) begin
                    // Modify blue component
                    ham_add = {1'b0, out_color[7:0]} + {{1{ham_inc[7]}}, ham_inc};
                    ham_color[7:0] <= ham_add[8]==1'b0 ? ham_add[7:0]
                                    : ham_add[7]==1'b1 ? 8'h0 
                                    : 8'hff;
                end 
            end
        end
    end

    pal_color <= palette[palette_index];


    if (reset) begin
        out_valid <= 1'b0;
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
