`timescale 1ns/1ns
`include "cpu.vh"

module cpu_branch (
    input logic         clock,
    input logic         reset,

    input logic         p3_is_branch,      // Indicates that the instruction is a branch/jump operation
    input logic [31:0]  p3_data_a,         // Data from source A
    input logic [31:0]  p3_data_b,         // Data from source B
    input logic [31:0]  p3_pc,             // The program counter value associated with the instruction
    input logic [2:0]   p3_branch_op,      // Branch operation type
    input logic [31:0]  p3_immediate,      // Literal value for the instruction
    
    output logic        p4_jump_taken,     // Indicates that a jump instruction was taken
    output logic [31:0] p4_jump_target     // The target address for the jump
);

logic        p3_jump_taken;     // Indicates that a jump instruction was taken
logic [31:0] p3_jump_target;     // The target address for the jump


always_comb begin
    p3_jump_taken = 1'b0;
    p3_jump_target = 32'hx;

    if (p3_is_branch && !reset) begin
        p3_jump_target = p3_pc + p3_immediate;
        case(p3_branch_op)
            `BRANCH_BEQ  : p3_jump_taken = (p3_data_a == p3_data_b);
            `BRANCH_BNE  : p3_jump_taken = (p3_data_a != p3_data_b);
            `BRANCH_BLT  : p3_jump_taken = ($signed(p3_data_a) < $signed(p3_data_b));
            `BRANCH_BGE  : p3_jump_taken = ($signed(p3_data_a) >= $signed(p3_data_b));
            `BRANCH_BLTU : p3_jump_taken = (p3_data_a < p3_data_b);
            `BRANCH_BGEU : p3_jump_taken = (p3_data_a >= p3_data_b);
            `BRANCH_JMP  : p3_jump_taken = 1'b1;
            `BRANCH_JMPR : begin
                               p3_jump_taken = 1'b1;
                               p3_jump_target = p3_data_a + p3_immediate;
                           end
        endcase
    end
end

always_ff @(posedge clock) begin
    p4_jump_taken <= p3_jump_taken;
    p4_jump_target <= p3_jump_target;
end

endmodule
