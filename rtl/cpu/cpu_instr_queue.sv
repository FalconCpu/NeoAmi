`timescale 1ns/1ns

// CPU instruction queue
//
// This module implements a simple instruction queue (FIFO) for the CPU. It buffers instructions fetched from the
// instruction memory (irom) and provides them to the CPU pipeline.

module cpu_instr_queue (
    input logic         clock,
    input logic         reset,

    // Input from the instruction memory (irom)
    input logic         p1_instr_valid,    // Indicates that the instruction output is valid
    input logic [31:0]  p1_instr,          // The instruction fetched from the instruction memory
    input logic [31:0]  p1_pc,             // The program counter value associated with the instruction
    output logic        p1_fifo_full,      // Indicates that the instruction FIFO is full and cannot accept more instructions

    // Output to the CPU pipeline
    input  logic        p2_ready,          // Indicates that the CPU is ready to consume the instruction
    output logic        p2_instr_valid,    // Indicates that the instruction output is valid
    output logic [31:0] p2_instr,          // The instruction to be executed by the CPU
    output logic [31:0] p2_pc, 
    input  logic        p4_jump_taken,     // Flush the instruction queue if a jump is taken
    output logic        instr_fifo_fault  // Indicates that the instruction FIFO has overflowed
);

logic        queue0_valid, next_queue0_valid;
logic [31:0] queue0_instr, next_queue0_instr;
logic [31:0] queue0_pc, next_queue0_pc;
logic        queue1_valid, next_queue1_valid;
logic [31:0] queue1_instr, next_queue1_instr;
logic [31:0] queue1_pc, next_queue1_pc;
logic        queue2_valid, next_queue2_valid;
logic [31:0] queue2_instr, next_queue2_instr;
logic [31:0] queue2_pc, next_queue2_pc;
logic        next_fault;


assign p2_instr_valid = queue0_valid;
assign p2_instr = queue0_instr;
assign p2_pc = queue0_pc;

always_comb begin
    p1_fifo_full = queue2_valid || (queue1_valid && p1_instr_valid);

    next_fault = 1'b0;
    // If the CPU is ready to consume an instruction, shift the queue down
    if (p2_ready) begin
        next_queue0_valid = queue1_valid;
        next_queue0_instr = queue1_instr;
        next_queue0_pc    = queue1_pc;
        next_queue1_valid = queue2_valid;
        next_queue1_instr = queue2_instr;
        next_queue1_pc    = queue2_pc;
        next_queue2_valid = 1'b0;
        next_queue2_instr = 32'hx;
        next_queue2_pc    = 32'hx;
    end else begin
        next_queue0_valid = queue0_valid;
        next_queue0_instr = queue0_instr;
        next_queue0_pc    = queue0_pc;
        next_queue1_valid = queue1_valid;
        next_queue1_instr = queue1_instr;
        next_queue1_pc    = queue1_pc;
        next_queue2_valid = queue2_valid;
        next_queue2_instr = queue2_instr;
        next_queue2_pc    = queue2_pc;
    end

    // Add the new instruction from the instruction memory to the queue
    if (next_queue0_valid == 1'b0) begin
        next_queue0_valid = p1_instr_valid;
        next_queue0_instr = p1_instr;
        next_queue0_pc    = p1_pc;
    end else if (next_queue1_valid == 1'b0) begin
        next_queue1_valid = p1_instr_valid;
        next_queue1_instr = p1_instr;
        next_queue1_pc    = p1_pc;
    end else if (next_queue2_valid == 1'b0) begin
        next_queue2_valid = p1_instr_valid;
        next_queue2_instr = p1_instr;
        next_queue2_pc    = p1_pc;
    end else 
        next_fault = p1_instr_valid; // If the queue is full and a new instruction is valid, set the fault flag

    // If a jump is taken, flush the instruction queue
    if (p4_jump_taken || reset) begin
        next_queue0_valid = 1'b0;
        next_queue0_instr = 32'hx;
        next_queue0_pc    = 32'hx;
        next_queue1_valid = 1'b0;
        next_queue1_instr = 32'hx;
        next_queue1_pc    = 32'hx;
        next_queue2_valid = 1'b0;
        next_queue2_instr = 32'hx;
        next_queue2_pc    = 32'hx;
    end
end


always_ff @(posedge clock) begin
    queue0_valid <= next_queue0_valid;
    queue0_instr <= next_queue0_instr;
    queue0_pc    <= next_queue0_pc;

    queue1_valid <= next_queue1_valid;
    queue1_instr <= next_queue1_instr;
    queue1_pc    <= next_queue1_pc;

    queue2_valid <= next_queue2_valid;
    queue2_instr <= next_queue2_instr;
    queue2_pc    <= next_queue2_pc;
    
    instr_fifo_fault <= next_fault;

    // synthesis translate_off
    if (next_fault) 
        $display("ERROR %t: Instruction FIFO overflow", $time);
    // synthesis translate_on
end




endmodule
