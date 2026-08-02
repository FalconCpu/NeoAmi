`timescale 1ns/1ps

// GEMMA Triangle setup module
//
// This module implements the triangle setup stage of the GEMMA pipeline. It takes in vertex data and computes the
// necessary parameters for rasterization, including edge equations, bounding boxes, and other relevant data needed
// for the rasterization process. 
// 
// It writes the computed data to main memory

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
    input logic  [4:0]   ts_read_index,   // Index of the register to read from the current bank
    output logic [31:0]  ts_read_data,    // Data read from the current bank

    // Connection to reciprocal unit
    output logic         ts_recip_req,    // Request signal to the reciprocal unit
    output logic [26:0]  ts_recip_in,     // Input value for the reciprocal unit (S15.12 format)
    input  logic         ts_recip_valid,  // Valid signal from the reciprocal unit indicating that the output is ready
    input  logic [26:0]  ts_recip_out,    // Output value from the reciprocal unit (S7.20 format)

    // Output data to main memory
    output logic         ts_sdram_req,     // Request signal to the SDRAM controller
    input  logic         ts_sdram_ack,     // Acknowledge signal from the SDRAM controller
    output logic [25:0]  ts_sdram_addr,    // Address for the SDRAM request
    output logic [127:0] ts_sdram_wdata,   // Data to write to the SDRAM if it's a write operation
    output logic [15:0]  ts_sdram_strb     // Byte enable signals for the SDRAM request
);

logic [5:0] state, next_state;

endmodule
