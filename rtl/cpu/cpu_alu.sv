`timescale 1ns/1ns
`include "cpu.vh"

// CPU ALU module
//
// This module implements the ALU for the CPU. It takes in two source operands and performs the specified ALU
// operation on them. The result is then sent to the next stage of the pipeline.
//
// Note - for timing reasons, we split the ALU into two blocks, The first block implements the most common
// ALU operations (AND, OR, XOR, ADD, SUB, CLT, CLTU) and is used for the register forwarding path.
// The second block implements the less common ALU operations (LSL, LSR, ASR, PC). These are
// sent to the writeback path, but not the register forwarding path (And thus suffer a 1 cycle latency penalty).
//  This is a compromise to reduce the critical path of the ALU.

module cpu_alu (
    input logic         clock,

    input logic [31:0]  p3_data_a,         // Data from source A
    input logic [31:0]  p3_data_b,         // Data from source B
    input logic [4:0]   p3_rd,             // Destination register for the instruction in stage 3
    input logic [31:0]  p3_pc,             // Program counter for the instruction in stage 3

    input logic         p3_is_alu,         // Indicates this is an instruction for the ALU
    input logic         p3_is_mult,        // Indicates this is a multiply instruction (encoding is in p3_alu_op)
    input logic [2:0]   p3_alu_op,         // ALU operation type

    input logic [2:0]   p3_shift_op,       // Shift operation type
    input logic         p3_is_shift,       // Indicates that the instruction is a shift operation

    output logic [31:0] p3_alu_result,     // Result from the ALU operation - for register forwarding
    output logic        p4_alu_valid,      // Indicates that the ALU result is valid
    output logic [4:0]  p4_alu_rd,         // Destination register for the
    output logic [31:0] p4_alu_result,     // Result from the ALU operation - for register writeback

    output logic        mul_valid,          // Indicates that the multiply result is valid
    output logic [4:0]  mul_rd,             // Destination register for the multiply
    output logic [31:0] mul_result          // Result from the multiply operation
);

logic [31:0] p3_shift_result;

wire signed [31:0] signed_a = p3_data_a;
wire signed [31:0] signed_b = p3_data_b;

// ALU operation
always_comb begin
    p3_alu_result = 32'hx;

    if (p3_is_alu)
    case (p3_alu_op)
        `ALU_AND: p3_alu_result = p3_data_a & p3_data_b;
        `ALU_OR:  p3_alu_result = p3_data_a | p3_data_b;
        `ALU_XOR: p3_alu_result = p3_data_a ^ p3_data_b;
        `ALU_LD:  p3_alu_result = p3_data_b;
        `ALU_ADD: p3_alu_result = p3_data_a + p3_data_b;
        `ALU_SUB: p3_alu_result = p3_data_a - p3_data_b;
        `ALU_CLT: p3_alu_result = (signed_a < signed_b) ? 32'h1 : 32'h0;
        `ALU_CLTU: p3_alu_result = (p3_data_a < p3_data_b) ? 32'h1 : 32'h0;
        default:  p3_alu_result = 32'hx;
    endcase
    
end

// Shift operations
//
// We split the less commonly used 
always_comb begin
    p3_shift_result = 32'hx;

    if (p3_is_shift)
    case (p3_shift_op)
        `SHIFT_LSL: p3_shift_result = p3_data_a << p3_data_b[4:0];
        `SHIFT_LSR: p3_shift_result = p3_data_a >> p3_data_b[4:0];
        `SHIFT_ASR: p3_shift_result = signed_a >>> p3_data_b[4:0];
        `SHIFT_PC:  p3_shift_result = p3_pc + 4;
        default:    p3_shift_result = 32'hx;
    endcase
end

// Multiply operation
// For timings we do multiply ops in parallel with the ALU ops, then mux in the result combinatorially
// To handle the signed multiply operations, we do an unsigned multiply and apply a correction term to the
// upper 32 bits of the result to account for the signedness of the operands.

logic [63:0] p4_mult_result;
logic [31:0] p4_mult_correction;
logic        p4_is_mult_upper, p4_is_mult_lower;

always_ff @(posedge clock) begin
    p4_is_mult_upper <= 1'b0;
    p4_is_mult_lower <= 1'b0;
    p4_mult_result <= 64'hx;
    p4_mult_correction <= 32'hx;

    if (p3_is_mult) begin
        p4_mult_result <= p3_data_a * p3_data_b;
        case (p3_alu_op) 
            `MULT_MUL:    begin 
                p4_is_mult_lower <= 1'b1; 
            end
            `MULT_MULH:   begin 
                p4_is_mult_upper <= 1'b1; 
                p4_mult_correction <= 32'h0; 
            end
            `MULT_MULHS:  begin 
                p4_is_mult_upper <= 1'b1; 
                p4_mult_correction <= (p3_data_a[31] ? p3_data_b : 32'h0) + (p3_data_b[31] ? p3_data_a : 32'h0); 
            end
            `MULT_MULHSU: begin 
                p4_is_mult_upper <= 1'b1;
                p4_mult_correction <= (p3_data_a[31] ? p3_data_b : 32'h0);
            end
            default: begin end
        endcase
    end
end


// Output latch
always_ff @(posedge clock) begin
    mul_valid <= p3_is_mult;
    mul_rd <= p3_rd;

    p4_alu_valid <= p3_is_alu || p3_is_shift;
    p4_alu_rd <= p3_rd;


    if (p3_is_alu) begin
        p4_alu_result <= p3_alu_result;
    end else if (p3_is_shift) begin
        p4_alu_result  <= p3_shift_result;
    end else begin
        p4_alu_result <= 32'hx;
    end
end

// Output the correct result for multiply operations
always_comb begin
    if (p4_is_mult_upper) begin
        mul_result = p4_mult_result[63:32] - p4_mult_correction;
    end else if (p4_is_mult_lower) begin
        mul_result = p4_mult_result[31:0];
    end else begin
        mul_result = 32'hx;
    end
end

endmodule
