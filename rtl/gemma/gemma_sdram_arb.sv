`timescale 1ns/1ns

// GEMMA SDRAM arbiter module
//
// This module implements an arbiter for the GEMMA pipeline that manages access to the SDRAM controller.
// It arbitrates between requests from different stages of the pipeline and ensures that only one request
// is sent to the SDRAM controller at a time.

module gemma_sdram_arb (
    input logic         clock,
    input logic         reset,

    // Request signals from different stages of the GEMMA pipeline
    input logic         ts_sdram_req,     // Request signal from the triangle setup stage
    output logic        ts_sdram_ack,     // Acknowledge signal from the triangle setup stage
    input logic [25:0]  ts_sdram_addr,    // Address for the triangle setup stage request
    input logic [127:0] ts_sdram_wdata,   // Data to write to the SDRAM if it's a write operation
    input logic [15:0]  ts_sdram_strb,    // Byte enable signals for the triangle setup stage request

    // Output signals to the SDRAM controller
    output logic         gemma_sdram_req,     // Request signal to the SDRAM controller
    input  logic         gemma_sdram_ack,     // Acknowledge signal from the SDRAM controller
    output logic         gemma_sdram_write,   // Indicates whether the request is a write operation
    output logic [25:0]  gemma_sdram_addr,    // Address for the SDRAM request
    output logic [7:0]   gemma_sdram_tag,     // Tag for the SDRAM request (used for vga)
    output logic [127:0] gemma_sdram_wdata,   // Data to write to the SDRAM if it's a write operation
    output logic [15:0]  gemma_sdram_strb,    // Byte enable signals for the SDRAM request
    input  logic [1:0]   gemma_sdram_rvalid,  // 00: No data, 01:First beat, 10:Middle beats, 11:Last beat
    input  logic [7:0]   gemma_sdram_rtag,     // Tag for the SDRAM response (used for vga)
    input  logic [31:0]  gemma_sdram_rdata    // Data read from the SDRAM
);

assign ts_sdram_ack = ts_sdram_req && !gemma_sdram_req; // Acknowledge the request when the arbiter is not busy

always_ff @(posedge clock) begin

    // =============================================================
    // Clear the SDRAM request signals when acknowledged 
    // =============================================================
    if (gemma_sdram_ack) begin
        gemma_sdram_req <= 1'b0;
        gemma_sdram_write <= 1'bx;
        gemma_sdram_addr <= 26'bx;
        gemma_sdram_wdata <= 128'bx;
        gemma_sdram_strb <= 16'bx;
    end

    // =============================================================
    // Triangle setup request.   Write only
    // =============================================================
    if (ts_sdram_ack) begin
        gemma_sdram_req <= 1'b1;
        gemma_sdram_write <= 1'b1;
        gemma_sdram_addr <= ts_sdram_addr;
        gemma_sdram_wdata <= ts_sdram_wdata;
        gemma_sdram_strb <= ts_sdram_strb;
        gemma_sdram_tag <= 8'hx;
    end

    // =============================================================
    // Reset
    // =============================================================
    if (reset) begin
        gemma_sdram_req <= 1'b0;
        gemma_sdram_write <= 1'b0;
        gemma_sdram_addr <= 26'b0;
        gemma_sdram_wdata <= 128'b0;
        gemma_sdram_strb <= 16'b0;
    end 
end

endmodule

