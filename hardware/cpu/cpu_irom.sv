`timescale 1ns/1ns

// CPU instruction ROM (irom) module
// 
// This module contains the instruction memory for the CPU. It is a notionally read-only memory (ROM) that is
// initialized with the program instructions. The CPU fetches instructions from this memory based on the program
// counter (PC) value provided by the cpu_pc module.
//
// I say its "notionally" read-only, because we do allow the CPU to write to it during the boot process, 
// So the CPU can load a boot image over UART. 


module cpu_irom (
    input logic         clock,
    input logic         reset,

    // PC interface
    input logic         p0_req,            // Request from the PC for the next instruction address
    input logic [31:0]  p0_pc,             // Current program counter value)

    // Instruction output
    output logic        p1_instr_valid,    // Indicates that the instruction output is valid
    output logic [31:0] p1_instr,          // The instruction fetched from the instruction memory
    output logic [31:0] p1_pc,             // The program counter value associated with the instruction

    // Aux bus interface for reading/writing the instruction memory
    input logic         aux_irom_req,        // Request to read/write the instruction memory
    input logic         aux_irom_write,      // Indicates a write operation to the instruction memory
    input logic [15:0]  aux_irom_addr,       // Address for the read/write operation
    input logic [31:0]  aux_irom_wdata,
    output logic [31:0] aux_irom_rdata,
    output logic        aux_irom_rvalid
);

logic [31:0] irom [0:16383];     // Instruction memory array 64kB (16K x 32 bits)
logic [31:0] instr;              // Register to hold the fetched instruction
logic [31:0] aux_irom_rdata_reg; // Register to hold the read data for the aux bus

assign p1_instr = p1_instr_valid ? instr : 32'hx;
assign aux_irom_rdata = aux_irom_rvalid ? aux_irom_rdata_reg : 32'h0;

initial begin
    // Initialize the instruction memory with the boot image
    $readmemh("asm.hex", irom);
end


always_ff @(posedge clock) begin
    // Fetch the instruction from the instruction memory
    instr <= irom[p0_pc[15:2]];  
    p1_instr_valid <= p0_req && p0_pc[31:16] == 16'hFFFF;
    p1_pc <= p0_pc;

    // Handle aux bus read/write requests to the instruction memory
    // verilator lint_off BLKSEQ
    if (aux_irom_req && aux_irom_write) 
        irom[aux_irom_addr[15:2]] = aux_irom_wdata;
    aux_irom_rdata_reg <= irom[aux_irom_addr[15:2]];
    aux_irom_rvalid <= aux_irom_req && !aux_irom_write;
end


wire unused = &{reset, p0_pc[1:0], aux_irom_addr[1:0]}; // Avoid unused signal warnings

endmodule
