`timescale 1ns/1ns

// CPU instruction queue
//
// This module implements a simple skid buffer for the CPU instruction queue.

module cpu_instr_queue (
    input logic         clock,
    input logic         reset,
    input logic         flush,

    // Input from the instruction memory (irom)
    input logic         p1_instr_valid,    // Indicates that the instruction output is valid
    output logic        p1_ready,          // Indicates that the instruction FIFO is full and cannot accept more instructions
    input logic [31:0]  p1_instr,          // The instruction fetched from the instruction memory
    input logic [31:0]  p1_pc,             // The program counter value associated with the instruction

    // Output to the CPU pipeline
    input  logic        p2_ready,          // Indicates that the CPU is ready to consume the instruction
    output logic        p2_instr_valid,    // Indicates that the instruction output is valid
    output logic [31:0] p2_instr,          // The instruction to be executed by the CPU
    output logic [31:0] p2_pc
);

logic        skid_valid, next_skid_valid;
logic [31:0] skid_instr, next_skid_instr;
logic [31:0] skid_pc, next_skid_pc;

logic        next_p2_instr_valid;
logic [31:0] next_p2_instr;
logic [31:0] next_p2_pc;

assign p1_ready = !skid_valid;

always_comb begin
    if (flush || reset) begin
        // If a flush is requested, clear both the skid buffer and the output to the CPU
        next_skid_valid = 0;
        next_p2_instr_valid = 0;
        next_p2_instr   = 32'bx;
        next_p2_pc      = 32'bx;
        next_skid_instr = 32'bx;
        next_skid_pc    = 32'bx;
    end else if (p2_ready && skid_valid) begin
        // If the CPU is ready for an instruction, and we have one in the skid buffer,
        // send it to the CPU and clear the skid buffer
        next_p2_instr_valid = 1;
        next_p2_instr = skid_instr;
        next_p2_pc = skid_pc;
        next_skid_valid = 0;
        next_skid_instr = 32'bx;
        next_skid_pc = 32'bx;
    end else if (p2_ready) begin
        // If the CPU is ready for an instruction, but the skid buffer is empty,
        // take the instruction directly from the icache (p1) and send it to the CPU
        next_p2_instr_valid = p1_instr_valid;
        next_p2_instr = p1_instr;
        next_p2_pc = p1_pc;
        next_skid_valid = 1'b0;
        next_skid_instr = 32'bx;
        next_skid_pc = 32'bx;
    end else if (p1_instr_valid && !skid_valid) begin
        // If the CPU is not ready, but we have a valid instruction from the icache,
        // store it in the skid buffer
        next_skid_valid = 1;
        next_skid_instr = p1_instr;
        next_skid_pc = p1_pc;
        next_p2_instr_valid = p2_instr_valid;
        next_p2_instr = p2_instr;
        next_p2_pc = p2_pc;
    end else begin
        // If none of the above conditions are met, maintain the current state
        next_skid_valid = skid_valid;
        next_skid_instr = skid_instr;
        next_skid_pc = skid_pc;
        next_p2_instr_valid = p2_instr_valid;
        next_p2_instr = p2_instr;
        next_p2_pc = p2_pc;
    end
end




always_ff @(posedge clock) begin
    skid_valid <= next_skid_valid;
    skid_instr <= next_skid_instr;
    skid_pc <= next_skid_pc;

    p2_instr_valid <= next_p2_instr_valid;
    p2_instr <= next_p2_instr;
    p2_pc <= next_p2_pc;
end

endmodule

