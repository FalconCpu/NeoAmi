`timescale 1ns/1ns

// Writeback module
//
// Combines the results from the ALU and other execution units and writes them back to the register file

module cpu_writeback (
    input logic         clock,
    input logic         reset,

    // Input from the ALU
    input logic         p4_alu_valid,       // Indicates that the ALU result is valid
    input logic         p4_alu_latent,       // Indicates that the ALU result is from a multi-cycle instruction
    input logic [4:0]   p4_alu_rd,          // Destination register for the ALU result
    input logic [31:0]  p4_alu_result,      // Result from the ALU operation

    // Input from the result queue
    input  logic        aux_wb_valid,          // We have a valid result to write back to the register file
    input  logic [4:0]  aux_wb_rd,             // Destination register for the writeback
    input  logic [31:0] aux_wb_result,         // Result to be written back to the register file

    // Input from the dcache
    input  logic         dcache_rvalid,          // Indicates that the dcache has a valid result to write back to the register file
    input  logic [4:0]   dcache_rdest,           // Destination register for the dcache result
    input  logic [31:0]  dcache_rdata,

    // Input from the multiplier
    input  logic         mul_valid,          // Indicates that the multiply result is valid
    input  logic [4:0]   mul_rd,             // Destination register for the multiply
    input  logic [31:0]  mul_result,

    // Input from the divider
    input  logic         divider_valid,          // Indicates that the divider has a valid result to write back to the register file
    input  logic [4:0]   divider_reg_d,           // Destination register for the divider result
    input  logic [31:0]  divider_result,

    // Input from the FPU
    input  logic         fpu_valid,         // Indicates that the FPU result is valid
    input  logic [4:0]   fpu_dest,          // Destination register for the FPU result
    input  logic [31:0]  fpu_result,        // Result from the FPU operation

    // Output to the register file
    output logic [4:0]  p4_rd,              // Destination register for the writeback
    output logic [31:0] p4_result,          // Result to be written back to the register file
    output logic        p4_wren,            // Indicates that the writeback is valid
    output logic        p4_latent,          // Indicates that the writeback came from a multi-cycle instruction
    output logic        writeback_fault     // Indicates that a fault occurred during writeback
);

typedef struct packed {
    logic        valid;
    logic [4:0]  rd;
    logic [31:0] result;
} writeback_entry;

writeback_entry queue0, next_queue0;
writeback_entry queue1, next_queue1;
writeback_entry queue2, next_queue2;
logic next_writeback_fault;



always_comb begin
    next_writeback_fault = 1'b0;

    // shift the queues
    if (p4_alu_valid==1'b0 && dcache_rvalid==1'b0) begin
        next_queue0 = queue1;
        next_queue1 = queue2;
        next_queue2 = {1'b0, 5'bx, 32'bx};
    end else begin
        next_queue0 = queue0;
        next_queue1 = queue1;
        next_queue2 = queue2;
    end

    // If a result arrives from the ALU and DCACHE at the same cycle then we need to 
    // queue the result from the dcache. 
    if (p4_alu_valid && dcache_rvalid) begin
        if (next_queue0.valid==1'b0)
            next_queue0 = {dcache_rvalid, dcache_rdest, dcache_rdata};
        else if (next_queue1.valid==1'b0)
            next_queue1 = {dcache_rvalid, dcache_rdest, dcache_rdata};
        else if (next_queue2.valid==1'b0)
            next_queue2 = {dcache_rvalid, dcache_rdest, dcache_rdata};
        else
            next_writeback_fault = 1'b1;
    end

    // Queue results from the multiplier
    if (next_queue0.valid==1'b0)
        next_queue0 = {mul_valid, mul_rd, mul_result};
    else if (next_queue1.valid==1'b0)
        next_queue1 = {mul_valid, mul_rd, mul_result};
    else if (next_queue2.valid==1'b0)
        next_queue2 = {mul_valid, mul_rd, mul_result};
    else
        next_writeback_fault = next_writeback_fault || mul_valid;

    // Queue results from the divider
    if (next_queue0.valid==1'b0)
        next_queue0 = {divider_valid, divider_reg_d, divider_result};
    else if (next_queue1.valid==1'b0)
        next_queue1 = {divider_valid, divider_reg_d, divider_result};
    else if (next_queue2.valid==1'b0)
        next_queue2 = {divider_valid, divider_reg_d, divider_result};
    else
        next_writeback_fault = next_writeback_fault || divider_valid;

    // Queue results from the aux writeback
    if (next_queue0.valid==1'b0)
        next_queue0 = {aux_wb_valid, aux_wb_rd, aux_wb_result};
    else if (next_queue1.valid==1'b0)
        next_queue1 = {aux_wb_valid, aux_wb_rd, aux_wb_result};
    else if (next_queue2.valid==1'b0)
        next_queue2 = {aux_wb_valid, aux_wb_rd, aux_wb_result};
    else
        next_writeback_fault = next_writeback_fault || aux_wb_valid;

    // Queue results from the FPU
    if (next_queue0.valid==1'b0)
        next_queue0 = {fpu_valid, fpu_dest, fpu_result};
    else if (next_queue1.valid==1'b0)
        next_queue1 = {fpu_valid, fpu_dest, fpu_result};
    else if (next_queue2.valid==1'b0)
        next_queue2 = {fpu_valid, fpu_dest, fpu_result};
    else
        next_writeback_fault = next_writeback_fault || fpu_valid;

    // Send a result to the register file. Priority is given to the ALU result, then dache, then queue
    if (p4_alu_valid) begin
        p4_rd = p4_alu_rd;
        p4_result = p4_alu_result;
        p4_wren = 1'b1;
        p4_latent = p4_alu_latent;
    end else if (dcache_rvalid) begin
        p4_rd = dcache_rdest;
        p4_result = dcache_rdata;
        p4_wren = 1'b1;
        p4_latent = 1'b1;
    end else begin
        p4_rd = queue0.rd;
        p4_result = queue0.result;
        p4_wren = queue0.valid;
        p4_latent = 1'b1;
    end 

    // reset
    if (reset) begin
        next_queue0 = {1'b0, 5'bx, 32'bx};
        next_queue1 = {1'b0, 5'bx, 32'bx};
        next_queue2 = {1'b0, 5'bx, 32'bx};
    end 
end

always_ff @(posedge clock) begin
    queue0 <= next_queue0;
    queue1 <= next_queue1;
    queue2 <= next_queue2;
    writeback_fault <= next_writeback_fault;
    // synthesis translate_off
    if (next_writeback_fault)
        $display("ERROR %t: Writeback queue overflow", $time);
    // synthesis translate_on
end

endmodule
