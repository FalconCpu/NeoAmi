`timescale 1ns/1ns

// This module controlls a single bank of the SDRAM. 

module sdram_bank #(
    parameter [1:0] BANK_ID = 0
) (
    input logic         clock,
    input logic         reset,

    // Monitor the sdram requests
    input  logic        sdram_req,
    input  logic        sdram_write,
    input  logic [25:0] sdram_addr,

    // Monitor the sdram interface
    input  logic [2:0]  cmd,
    input  logic [12:0] addr,
    input  logic [1:0]  ba,
    input  logic        freeze,

    // Requests to the controller
    output logic        bank_precharge,
    output logic        bank_activate,
    output logic        bank_read,
    output logic        bank_write
);
logic [3:0]  timer;
logic [3:0]  timer_precharge;  // Time between read/write and precharge
logic        bank_active;
logic [12:0] bank_row;

logic        next_bank_read;
logic        next_bank_write;

localparam [2:0] CMD_PRECHARGE = 3'b010;
localparam [2:0] CMD_ACTIVATE  = 3'b011;
localparam [2:0] CMD_READ      = 3'b101;
localparam [2:0] CMD_WRITE     = 3'b100;

always_comb begin
    bank_precharge = 1'b0;
    bank_activate = 1'b0;
    next_bank_read = 1'b0;
    next_bank_write = 1'b0;

    if (timer!=0 || freeze) begin
        // Wait until the timer expires
    end else if (sdram_req && (sdram_addr[12:11] == BANK_ID)) begin
        if (!bank_active) begin
            bank_activate = 1'b1;
        end else if (bank_row != sdram_addr[25:13]) begin
            bank_precharge = (timer_precharge==0);
        end else if (sdram_write) begin
            next_bank_write = 1'b1;
        end else begin
            next_bank_read = 1'b1;
        end
    end
end



always_ff @(posedge clock) begin
    timer <= (timer > 0) ? timer - 1'b1 : 4'd0;
    timer_precharge <= (timer_precharge > 0) ? timer_precharge - 1'b1 : 4'd0;
    bank_read <= next_bank_read;
    bank_write <= next_bank_write;

    if (reset) begin
        bank_active <= 1'b0;
        bank_row <= 13'b0;
        timer <= 4'b0;
    end
    if (cmd == CMD_PRECHARGE && (addr[10] || ba==BANK_ID)) begin
        bank_active <= 1'b0;
        timer <= 4'd2; 
    end else if (cmd == CMD_ACTIVATE && (ba==BANK_ID)) begin
        bank_active <= 1'b1;
        bank_row <= addr;
        timer <= 4'd1;
    end else if ((cmd == CMD_READ || cmd == CMD_WRITE) && (ba==BANK_ID)) begin
        timer <= 4'd2;
        timer_precharge <= 4'd8;
    end
end

wire unused = &{sdram_addr[10:0]};  // Avoid unused signal warnings

endmodule