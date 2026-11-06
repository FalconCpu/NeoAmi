`timescale 1ns/1ns

// SOPHIE SDRAM arbiter module
//
// This module implements an arbiter for the SOPHIE subsystem that manages access to the SDRAM controller.
// It arbitrates between requests from different components (currently audio, but can be extended for future modules)
// and ensures that only one request is sent to the SDRAM controller at a time.

module sophie_sdram_arb (
    input logic         clock,
    input logic         reset,

    // Request signals from audio module
    input logic         audio_sdram_req,     // Request signal from the audio module
    output logic        audio_sdram_ack,     // Acknowledge signal to the audio module
    input logic [25:0]  audio_sdram_addr,    // Address for the audio request
    output logic [31:0] audio_sdram_rdata,   // Data read for the audio request
    output logic [1:0]  audio_sdram_rvalid,  // Valid signal for the audio read data

    // Request signals from copper module
    input logic         copper_sdram_req,     // Request signal from the copper module
    output logic        copper_sdram_ack,     // Acknowledge signal to the copper module
    input logic [25:0]  copper_sdram_addr,    // Address for the copper request
    output logic [31:0] copper_sdram_rdata,   // Data read for the copper request
    output logic [1:0]  copper_sdram_rvalid,  // Valid signal for the copper read data

    // Output signals to the SDRAM controller
    output logic         sophie_sdram_req,    // Request signal to the SDRAM controller
    input  logic         sophie_sdram_ack,    // Acknowledge signal from the SDRAM controller
    output logic [25:0]  sophie_sdram_addr,   // Address for the SDRAM request
    output logic [7:0]   sophie_sdram_tag,    // Tag for the SDRAM request
    input  logic [1:0]   sophie_sdram_rvalid, // 00: No data, 01:First beat, 10:Middle beats, 11:Last beat
    input  logic [7:0]   sophie_sdram_rtag,   // Tag for the SDRAM response
    input  logic [31:0]  sophie_sdram_rdata   // Data read from the SDRAM
);

// Priority: Audio > Copper
assign audio_sdram_ack = audio_sdram_req && !sophie_sdram_req; // Acknowledge the request when the arbiter is not busy
assign copper_sdram_ack = copper_sdram_req && !audio_sdram_ack && !sophie_sdram_req; // Acknowledge the request when the arbiter is not busy

always_ff @(posedge clock) begin

    // =============================================================
    // Clear the SDRAM request signals when acknowledged 
    // =============================================================
    if (sophie_sdram_ack) begin
        sophie_sdram_req <= 1'b0;
        sophie_sdram_addr <= 26'bx;
        sophie_sdram_tag <= 8'bx;
    end

    // =============================================================
    // Process new requests from audio and copper modules
    // =============================================================
    if (audio_sdram_ack) begin
        sophie_sdram_req <= 1'b1;
        sophie_sdram_addr <= audio_sdram_addr;
        sophie_sdram_tag <= 8'h0;
    end else if (copper_sdram_ack) begin
        sophie_sdram_req <= 1'b1;
        sophie_sdram_addr <= copper_sdram_addr;
        sophie_sdram_tag <= 8'h1;
    end

    // =============================================================
    // Pass received data from SDRAM to the audio module
    // =============================================================
    if (sophie_sdram_rvalid != 2'b00 && sophie_sdram_rtag == 8'h0) begin
        audio_sdram_rdata <= sophie_sdram_rdata;
        audio_sdram_rvalid <= sophie_sdram_rvalid;
    end else begin
        audio_sdram_rvalid <= 2'b00;
        audio_sdram_rdata <= 32'bx;
    end

    // =============================================================
    // Pass received data from SDRAM to the copper module
    // =============================================================
    if (sophie_sdram_rvalid != 2'b00 && sophie_sdram_rtag == 8'h1) begin
        copper_sdram_rdata <= sophie_sdram_rdata;
        copper_sdram_rvalid <= sophie_sdram_rvalid;
    end else begin
        copper_sdram_rvalid <= 2'b00;
        copper_sdram_rdata <= 32'bx;
    end


    // =============================================================
    // Reset
    // =============================================================
    if (reset) begin
        sophie_sdram_req <= 1'b0;
        sophie_sdram_addr <= 26'b0;
        sophie_sdram_tag <= 8'b0;
    end 
end

endmodule
