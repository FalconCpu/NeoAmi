`timescale 1ns/1ps

// GEMMA Triangle setup module
//
// This module implements the triangle setup stage of the GEMMA pipeline. It takes in vertex data and computes the
// necessary parameters for rasterization, including edge equations, bounding boxes, and other relevant data needed
// for the rasterization process. 
// 
// It writes the computed data to main memory


// TODO - add code to check for totally clipped triangles and skip writing to memory in that case

module gemma_triangle_setup (
    input logic         clock,
    input logic         reset,

    // Control signals
    input logic         ts_start,        // Signal to start the triangle setup stage
    output logic        ts_busy,         // Signal indicating that the triangle setup stage is busy processing
    input logic [25:0]  ts_output_ptr,   // The destination write pointer for the triangle setup stage.
    output logic        ts_inc_output_ptr,   // Signal to increment the output pointer after writing data to main memory
    input logic [15:0]  clip_x1,
    input logic [15:0]  clip_y1,
    input logic [15:0]  clip_x2,
    input logic [15:0]  clip_y2,
    input logic [25:0]  texture_addr,
    input logic [15:0]  texture_stride,

    // Input vertex data
    output logic  [4:0]   ts_read_index,   // Index of the register to read from the current bank
    input  logic [31:0]  ts_read_data,    // Data read from the current bank

    // Connection to reciprocal unit
    output logic         ts_recip_req,    // Request signal to the reciprocal unit
    output logic [26:0]  ts_recip_in,     // Input value for the reciprocal unit (S15.12 format)
    input  logic [26:0]  ts_recip_out,    // Output value from the reciprocal unit (S7.20 format)

    // Output data to main memory
    output logic         ts_sdram_req,     // Request signal to the SDRAM controller
    input  logic         ts_sdram_ack,     // Acknowledge signal from the SDRAM controller
    output logic [25:0]  ts_sdram_addr,    // Address for the SDRAM request
    output logic [127:0] ts_sdram_wdata,   // Data to write to the SDRAM if it's a write operation
    output logic [15:0]  ts_sdram_strb     // Byte enable signals for the SDRAM request
);

logic [5:0] state, next_state;
logic [26:0] dx01, next_dx01;
logic [26:0] dy01, next_dy01;
logic [26:0] dx02, next_dx02;
logic [26:0] dy02, next_dy02;
logic [26:0] dx12, next_dx12;
logic [26:0] dy12, next_dy12;
logic [26:0] recip_dy01, next_recip_dy01;
logic [26:0] recip_dy02, next_recip_dy02;
logic [26:0] recip_dy12, next_recip_dy12;

// Addresses in the input register bank for the vertex data
localparam INPUT_V0_X  = 5'h0;
localparam INPUT_V0_Y  = 5'h1;
localparam INPUT_V0_Z  = 5'h2;
localparam INPUT_V0_R  = 5'h3;
localparam INPUT_V0_G  = 5'h4;
localparam INPUT_V0_B  = 5'h5;
localparam INPUT_V1_X  = 5'h8;
localparam INPUT_V1_Y  = 5'h9;
localparam INPUT_V1_Z  = 5'ha;
localparam INPUT_V1_R  = 5'hb;
localparam INPUT_V1_G  = 5'hc;
localparam INPUT_V1_B  = 5'hd;
localparam INPUT_V2_X  = 5'h10;
localparam INPUT_V2_Y  = 5'h11;
localparam INPUT_V2_Z  = 5'h12;
localparam INPUT_V2_R  = 5'h13;
localparam INPUT_V2_G  = 5'h14;
localparam INPUT_V2_B  = 5'h15;
localparam INPUT_FLAGS = 5'h1f;

// Locations in the data to be written to main memory for the triangle setup output
// 4 words of 8*16 bits each, for a total of 64 bytes
localparam OUT_0_CLIP_X1  = 3'h0;  
localparam OUT_0_CLIP_X2  = 3'h1;
localparam OUT_0_YTOP     = 3'h2;
localparam OUT_0_YBOT     = 3'h3;  
localparam OUT_0_X1       = 3'h4;
localparam OUT_0_Y1       = 3'h5;  
localparam OUT_0_X2       = 3'h6;  
localparam OUT_0_Y2       = 3'h7; 

localparam OUT_1_FLAGS    = 3'h0;    
localparam OUT_1_DX1_DY   = 3'h1;  
localparam OUT_1_DX2_DY   = 3'h2;  
localparam OUT_1_DX3_DY   = 3'h3;    
localparam OUT_1_Z1       = 3'h4;  
localparam OUT_1_DZ_DX    = 3'h5;    
localparam OUT_1_DZ_DY    = 3'h6;    

localparam OUT_2_R1         = 3'h0;  
localparam OUT_2_DR_DX      = 3'h1;
localparam OUT_2_DR_DY      = 3'h2;
localparam OUT_2_G1         = 3'h3;  
localparam OUT_2_DG_DX      = 3'h4;
localparam OUT_2_DG_DY      = 3'h5;  
localparam OUT_2_B1         = 3'h6;  
localparam OUT_2_DB_DX      = 3'h7;  

localparam OUT_3_DB_DY      = 3'h0;  
localparam OUT_3_TEX_STRIDE = 3'h1;
localparam OUT_3_TEX_ADDR   = 3'h2;
localparam OUT_3_USERDATA   = 3'h4;  

logic [7:0][15:0] wdata, next_wdata;
logic             next_ts_sdram_req;
logic [25:0]      next_ts_sdram_addr;
assign ts_sdram_wdata = {wdata[7], wdata[6], wdata[5], wdata[4], wdata[3], wdata[2], wdata[1], wdata[0]};

logic signed [26:0] mult_a, mult_b;
logic signed [53:0] mult_result;

logic signed [26:0] slope01, next_slope01;
logic signed [26:0] slope02, next_slope02;
logic signed [26:0] slope12, next_slope12;

logic next_ts_inc_output_ptr;

// =========================================================
//                 State Machine
// =========================================================

always_comb begin
    next_dx01 = dx01;
    next_dy01 = dy01;
    next_dx02 = dx02;
    next_dy02 = dy02;
    next_dx12 = dx12;
    next_dy12 = dy12;
    next_wdata = wdata;
    next_ts_sdram_req = 1'b0;
    next_ts_sdram_addr = ts_sdram_addr;
    next_ts_inc_output_ptr = 1'b0;
    next_recip_dy01 = recip_dy01;
    next_recip_dy02 = recip_dy02;
    next_recip_dy12 = recip_dy12;
    next_slope01 = slope01;
    next_slope02 = slope02;
    next_slope12 = slope12;
    ts_read_index = 5'hx;
    ts_recip_req = 1'b0;
    ts_recip_in = 27'hx;
    mult_a = 27'hx;
    mult_b = 27'hx;

    // Clear SDRAM request when acknowledged
    if (ts_sdram_ack) begin
        next_ts_sdram_req = 1'b0;
        next_wdata = 128'hx;
    end
    
    // State machine for triangle setup
    next_state = (state==6'h63) ? 6'h63 : state + 1'b1; 
    case (state)
        6'h0: begin // Read vertex 0 Y coordinate
            ts_read_index = INPUT_V0_Y;
            next_dy01 = ts_read_data[26:0];
            next_dy02 = ts_read_data[26:0];
            next_wdata[OUT_0_Y1] = ts_read_data[15:0];
            next_wdata[OUT_0_CLIP_X1] = clip_x1;
            next_wdata[OUT_0_CLIP_X2] = clip_x2;
            next_wdata[OUT_0_YTOP] = clip_y1;
            next_wdata[OUT_0_YBOT] = clip_y2;
        end

        6'h1: begin // Read vertex 1 Y coordinate
            ts_read_index = INPUT_V1_Y;
            next_dy01 = ts_read_data[26:0] - dy01;
            next_dy12 = ts_read_data[26:0];
            next_wdata[OUT_0_Y2] = ts_read_data[15:0];
        end

        6'h2: begin // Read vertex 2 Y, and calculate reciprocal of dy01
            ts_read_index = INPUT_V2_Y;
            next_dy02 = ts_read_data[26:0] - dy02;
            next_dy12 = ts_read_data[26:0] - dy12;
            ts_recip_req = 1'b1;
            ts_recip_in = dy01;
        end

        6'h3: begin // Read vertex 0 X coordinate, and calculate reciprocal of dy01
            ts_read_index = INPUT_V0_X;
            next_dx01 = ts_read_data[26:0];
            next_dx02 = ts_read_data[26:0];
            next_wdata[OUT_0_X1] = ts_read_data[15:0];
            next_recip_dy01 = ts_recip_out;
            ts_recip_req = 1'b1;
            ts_recip_in = dy02;
        end

        6'h4: begin // Read vertex 1 X coordinate, and calculate reciprocal of dy02
            ts_read_index = INPUT_V1_X;
            next_dx01 = ts_read_data[26:0] - dx01;
            next_dx12 = ts_read_data[26:0];
            next_wdata[OUT_0_X2] = ts_read_data[15:0];
            next_recip_dy02 = ts_recip_out;
            ts_recip_req = 1'b1;
            ts_recip_in = dy12;
            next_state = 6'h8;
        end

        6'h5: begin // Read vertex 2 X coordinate
            ts_read_index = INPUT_V2_X;
            next_dx02 = ts_read_data[26:0] - dx02;
            next_dx12 = ts_read_data[26:0] - dx12;
        end

        default: begin
            // Default case to handle unexpected states
            next_state = 6'd63; // Reset state
        end
    endcase

    if (ts_start) begin
        next_state = 6'h0; 
    end

    if (reset) begin
        next_state = 6'd63; // Reset state
    end

end

// =========================================================
//                 Registers
// =========================================================


always_ff @(posedge clock) begin
    state <= next_state;
    dx01 <= next_dx01;
    dy01 <= next_dy01;
    dx02 <= next_dx02;
    dy02 <= next_dy02;
    dx12 <= next_dx12;
    dy12 <= next_dy12;
    recip_dy01 <= next_recip_dy01;
    recip_dy02 <= next_recip_dy02;
    recip_dy12 <= next_recip_dy12;
    slope01 <= next_slope01;
    slope02 <= next_slope02;
    slope12 <= next_slope12;
    wdata <= next_wdata;
    ts_sdram_req <= next_ts_sdram_req;
    ts_sdram_addr <= next_ts_sdram_addr;
    ts_inc_output_ptr <= next_ts_inc_output_ptr;
    mult_result <= mult_a * mult_b;
    ts_busy <= (next_state != 6'h63); // Busy when not in reset state
end

endmodule
