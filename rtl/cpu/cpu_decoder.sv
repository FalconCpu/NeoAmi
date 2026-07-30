`timescale 1ns/1ns
`include "cpu.vh"

// CPU decoder module
//
// This module decodes the instruction fetched from the instruction memory and generates control signals for the CPU pipeline.
// It also handles the scoreboard for the CPU, which tracks the status of the registers and 
// stalls the pipeline if a register is not ready to be read.

module cpu_decoder (
    input logic         clock,
    input logic         reset,
    input logic         p4_jump_taken,     // A jump instruction was taken

    // Input from the instruction queue
    input logic         p2_instr_valid,    // Indicates that the instruction output is valid
    input logic [31:0]  p2_instr,          // The instruction to be executed by the CPU
    input logic [31:0]  p2_pc,             // The program counter value associated with the instruction
    output logic        p2_ready,          // Indicates that we can accept the next instruction from the instruction queue

    output logic [4:0]  p2_rs1,            // Source register 1
    output logic [4:0]  p2_rs2,            // Source register 2
    output logic        p2_use_immediate,  // Indicates that the instruction uses an immediate value for rs2
    output logic [31:0] p2_immediate,      // Immediate value for the instruction
    input  logic        mem_ready,         // Indicates that the memory is ready to accept a new request
    input  logic        divider_ready,     // Indicates that the divide unit is ready to accept a new request
    input  logic        fpu_div_busy,      // Indicates that the FPU divide unit is busy

    // Output to the CPU pipeline
    output logic [31:0] p3_immediate,       // Literal value for the instruction
    output logic        p3_is_alu,          // Indicates that the instruction is an ALU operation
    output logic [2:0]  p3_alu_op,
    output logic        p3_is_shift,        // Indicates that the instruction is a shift operation
    output logic [2:0]  p3_shift_op,
    output logic        p3_is_branch,       // Indicates that the instruction is a branch/jump operation
    output logic [2:0]  p3_branch_op,
    output logic        p3_is_load,         // Indicates that the instruction is a memory operation (load/store)
    output logic        p3_is_store,        // Indicates that the instruction is a store operation
    output logic        p3_is_mult,         // Indicates that the instruction is a multiply operation
    output logic        p3_is_divide,       // Indicates that the instruction is a divide operation
    output logic        p3_is_sys,          // Indicates that the instruction is a system operation
    output logic        p3_is_fpu,          // Indicates that the instruction is a floating-point operation
    output logic        p3_is_idx,
    output logic [2:0]  p3_mem_op,          // Memory operation type (byte, halfword, word)
    output logic [31:0] p3_pc,              // The program counter value associated with the instruction
    output logic [31:0] p4_pc,
    output logic [4:0]  p3_rd,              // Destination register for the instruction in stage 3

    output logic        p4_is_store,
    input logic [4:0]   p4_rd,              // Destination register for the instruction in stage 4
    input logic         p4_wren,            // Indicates that the destination register is valid
    input logic         p4_latent           // The writeback came from a multi-cycle instruction
);

// Break the instruction into its fields
//
// 109876 543 21098 76543 21098765 43210
// KKKKKK III DDDDD AAAAA CCCCCCCC BBBBB
wire [5:0] instr_k = p2_instr[31:26];  // Major opcode
wire [2:0] instr_i = p2_instr[25:23];  // Minor opcode
wire [4:0] instr_d = p2_instr[22:18];  // Destination register
wire [4:0] instr_a = p2_instr[17:13];  // Source register 1
wire [7:0] instr_c = p2_instr[12:5];   // Immediate value (for branch/jump instructions)
wire [4:0] instr_b = p2_instr[4:0];    // Source register 2

assign p2_rs1 = instr_a;
assign p2_rs2 = instr_b;


// Scoreboard logic
// 1 bit per register, 1=not ready, 0=ready
logic [31:0] scoreboard, next_scoreboard;


logic        p2_is_alu, p2_is_shift, p2_is_branch, p2_is_load, p2_is_store;
logic        p2_is_mult, p2_is_divide, p2_is_sys, p2_is_fpu, p2_is_idx;
logic        p3_is_alu_x, p3_is_shift_x, p3_is_branch_x, p3_is_load_x, p3_is_store_x;
logic        p3_is_mult_x, p3_is_divide_x, p3_is_sys_x, p3_is_fpu_x, p3_is_idx_x;
logic [2:0]  p2_alu_op, p2_shift_op, p2_mem_op;
logic [2:0]  p2_branch_op;
logic        stall_regs;    // Indicates that the pipeline should stall due to a register not being ready
logic        stall_resource;  // Indicates that the pipeline should stall due to a resource not being ready
logic        stall;
logic        p2_wren;
logic        p2_latent, p3_latent;    // The instruction may take multiple cycles to complete 

// On a jump instruction, we need to flush the pipeline. We can do this by combinationally
// setting all the p3_is_* signals to 0.
assign p3_is_alu = p3_is_alu_x && !p4_jump_taken;
assign p3_is_shift = p3_is_shift_x && !p4_jump_taken;
assign p3_is_branch = p3_is_branch_x && !p4_jump_taken;
assign p3_is_load = p3_is_load_x && !p4_jump_taken;
assign p3_is_store = p3_is_store_x && !p4_jump_taken;
assign p3_is_mult = p3_is_mult_x && !p4_jump_taken;
assign p3_is_divide = p3_is_divide_x && !p4_jump_taken;
assign p3_is_sys = p3_is_sys_x && !p4_jump_taken;
assign p3_is_fpu = p3_is_fpu_x && !p4_jump_taken;
assign p3_is_idx = p3_is_idx_x && !p4_jump_taken;


always_comb begin
    p2_is_alu = 1'b0;
    p2_is_shift = 1'b0;
    p2_is_branch = 1'b0;
    p2_is_load = 1'b0;
    p2_is_store = 1'b0;
    p2_is_mult = 1'b0;
    p2_is_divide = 1'b0;
    p2_is_sys = 1'b0;
    p2_is_fpu = 1'b0;
    p2_is_idx = 1'b0;
    p2_alu_op = 3'bx;
    p2_shift_op = 3'bx;
    p2_branch_op = 3'bx;
    p2_mem_op = 3'bx;
    p2_use_immediate = 1'b0;
    p2_immediate = 32'hx;
    p2_wren = 1'b0;
    p2_latent = 1'b0;
    stall_resource = 1'b0;

    // Decode the instruction based on the major opcode
    if (p2_instr_valid && !p4_jump_taken && !reset)
    case (instr_k)
        `KIND_ALU: begin
            if (instr_i == 3'h3) begin
                p2_is_shift = 1'b1;
                p2_shift_op = {1'b0,instr_c[1:0]};
                p2_latent = 1'b1;
            end else begin
                p2_is_alu = 1'b1;
                p2_alu_op = instr_i;
            end
            p2_wren = 1'b1;
        end

        `KIND_ALUI: begin
            if (instr_i == 3'h3) begin
                p2_is_shift = 1'b1;
                p2_shift_op = {1'b0,instr_c[1:0]};
                p2_latent = 1'b1;
            end else begin
                p2_is_alu = 1'b1;
                p2_alu_op = instr_i;
            end
            p2_use_immediate = 1'b1;
            p2_immediate = {{19{instr_c[7]}}, instr_c, instr_b};
            p2_wren = 1'b1;
        end

        `KIND_LDU: begin
            p2_is_alu = 1'b1;
            p2_use_immediate = 1'b1;
            p2_alu_op = `ALU_LD;
            p2_immediate = {instr_c, instr_i, instr_a, instr_b, 11'b0};
            p2_wren = 1'b1;
        end

        `KIND_LDPC: begin
            p2_is_alu = 1'b1;
            p2_use_immediate = 1'b1;
            p2_alu_op = `ALU_LD;
            p2_immediate = p2_pc + {{9{instr_c[7]}}, instr_c, instr_i, instr_a, instr_b, 2'b0};
            p2_wren = 1'b1;
        end

        `KIND_BRA: begin
            p2_is_branch = 1'b1;
            p2_branch_op = instr_i;
            p2_immediate = {{17{instr_c[7]}}, instr_c, instr_d, 2'b0};
        end

        `KIND_LD: begin
            stall_resource = !mem_ready;
            p2_is_load = mem_ready;
            p2_mem_op = instr_i;
            p2_latent = 1'b1;
            p2_immediate = {{19{instr_c[7]}}, instr_c, instr_b};
            p2_wren = 1'b1;
        end

        `KIND_ST: begin
            stall_resource = !mem_ready;
            p2_is_store = mem_ready;
            p2_mem_op = instr_i;
            p2_immediate = {{19{instr_c[7]}}, instr_c, instr_d};
        end

        `KIND_JMP: begin
            p2_is_branch = 1'b1;
            p2_branch_op = 3'h6;
            p2_immediate = {{9{instr_c[7]}}, instr_c, instr_i, instr_a, instr_b, 2'b0};

            // Use the shift unit to generate the link address
            p2_is_shift = 1'b1;  
            p2_shift_op = `SHIFT_PC;
            p2_wren = 1'b1;
            p2_latent = 1'b1;
        end

        `KIND_JMPR: begin
            p2_is_branch = 1'b1;
            p2_branch_op = 3'h7;
            p2_immediate = {{17{instr_c[7]}}, instr_c, instr_b, 2'b0};
            // Use the shift unit to generate the link address
            p2_is_shift = 1'b1;  
            p2_shift_op = `SHIFT_PC;
            p2_wren = 1'b1;
            p2_latent = 1'b1;
        end

        `KIND_IDX: begin
            p2_is_idx = 1'b1;
            p2_alu_op = instr_i;
            p2_wren = 1'b1;
        end

        `KIND_MUL: begin
                p2_alu_op = instr_i;
                p2_wren = 1'b1;
                p2_latent = 1'b1;
            if (instr_i[2]==1'b0) begin
                p2_is_mult = 1'b1;
            end else begin
                p2_is_divide = divider_ready;
                stall_resource = !divider_ready;
            end
        end

        `KIND_MULI: begin
            p2_alu_op = instr_i;
            p2_use_immediate = 1'b1;
            p2_immediate = {{19{instr_c[7]}}, instr_c, instr_b};
            p2_wren = 1'b1;
            p2_latent = 1'b1;
            if (instr_i[2]==1'b0) begin
                p2_is_mult = 1'b1;
            end else begin
                p2_is_divide = divider_ready;
                stall_resource = !divider_ready;
            end
        end
        
        `KIND_CFG: begin
            p2_is_sys = 1'b1;
            p2_alu_op = instr_i;
            p2_wren = (instr_i==3'b000 || instr_i==3'b001); // Only CFGREG read/writes write to a register
            p2_latent = p2_wren;
            p2_immediate = {{19{instr_c[7]}}, instr_c, instr_b};
            p2_use_immediate = 1'b1;
        end

        `KIND_FPU: begin
            stall_resource = fpu_div_busy && (instr_i == 3'h3); // Stall if the FPU divide unit is busy and we are trying to execute a divide instruction
            p2_is_fpu = 1'b1;
            p2_alu_op = instr_i;
            p2_wren = 1'b1;
            p2_latent = 1'b1;
        end


        default: begin
        end
    endcase

    // Check the scoreboard to see if the source registers are ready. If not, stall the pipeline.
    next_scoreboard = scoreboard;
    if (p4_wren && p4_latent)
        next_scoreboard[p4_rd] = 1'b0; // Mark the destination register as ready
    if (p4_jump_taken && p3_latent)
        next_scoreboard[p3_rd] = 1'b0; // Mark the destination register as ready if we are jumping and the instruction is latent
    next_scoreboard[0] = 1'b0; // Register 0 is always ready
    stall_regs = scoreboard[instr_a] || scoreboard[instr_b] || scoreboard[instr_d];

    stall = p2_instr_valid && (stall_regs || stall_resource);

    if (stall) begin
        p2_is_alu = 1'b0;
        p2_is_shift = 1'b0;
        p2_is_branch = 1'b0;
        p2_is_load = 1'b0;
        p2_is_store = 1'b0;
        p2_is_mult = 1'b0;
        p2_is_divide = 1'b0;
        p2_is_sys = 1'b0;
        p2_is_fpu = 1'b0;
        p2_is_idx = 1'b0;
        p2_wren = 1'b0;
    end

    if (p2_wren && p2_latent)
        next_scoreboard[instr_d] = 1'b1; // Mark the destination register as not ready

    if (reset)
        next_scoreboard = 32'h0;

    p2_ready = !stall;

end

always_ff @(posedge clock) begin
    scoreboard <= next_scoreboard;
    p3_is_alu_x <= p2_is_alu;
    p3_is_shift_x <= p2_is_shift;
    p3_is_branch_x <= p2_is_branch;
    p3_is_load_x <= p2_is_load;
    p3_is_store_x <= p2_is_store;
    p3_is_mult_x <= p2_is_mult;
    p3_is_divide_x <= p2_is_divide;
    p3_is_sys_x <= p2_is_sys;
    p3_is_fpu_x <= p2_is_fpu;
    p3_is_idx_x <= p2_is_idx;
    p3_alu_op <= p2_alu_op;
    p3_shift_op <= p2_shift_op;
    p3_branch_op <= p2_branch_op;
    p3_mem_op <= p2_mem_op;
    p3_pc <= p2_pc;
    p4_pc <= p3_pc;
    p3_rd <= instr_d;
    p3_immediate <= p2_immediate;
    p3_latent <= p2_latent;
    p4_is_store <= p3_is_store;
end

endmodule
