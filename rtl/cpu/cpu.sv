`timescale 1ns/1ns

// Top level CPU module
//
// This module instantiates the CPU submodules and connects them together. 

module cpu (
    input logic         clock,
    input logic         reset,

    // Aux bus interface for reading/writing the instruction memory
    input logic         aux_irom_req,        // Request to read/write the instruction memory
    input logic         aux_irom_write,      // Indicates a write operation to the instruction memory
    input logic [15:0]  aux_irom_addr,       // Address for the read/write operation
    input logic [31:0]  aux_irom_wdata,
    output logic [31:0] aux_irom_rdata,
    output logic        aux_irom_rvalid,

    // Aux bus interface for reading/writing the data memory
    output logic        cpu_aux_req,      // Request to read/write the data memory
    output logic        cpu_aux_write,    // Indicates a write operation to the data memory
    output logic [31:0] cpu_aux_addr,     // Address for the read/write
    output logic [31:0] cpu_aux_wdata,    // Data to be written to the data memory
    output logic [3:0]  cpu_aux_strb,     // Byte enable signals (For both read and write)
    output logic [4:0]  cpu_aux_rd,       // Destination register for the instruction in stage 3
    input logic         cpu_aux_rvalid,   // Indicates that the data read from the data memory is valid
    input logic [31:0]  cpu_aux_rdata,    // Data read from the data memory
    input logic [4:0]   cpu_aux_rdest,    // Destination register for the instruction in stage 3

    // Write Interface to SDRAM
    output logic         dcache_sdramw_req,     // Request write burst to SDRAM
    input logic          dcache_sdramw_ack,     // SDRAM is ready to accept write burst
    output logic [25:0]  dcache_sdramw_addr,    
    output logic [127:0] dcache_sdramw_data,
    output logic [15:0]  dcache_sdramw_strb,

    // Read Interface to SDRAM
    output logic         dcache_sdramr_req,     // Request read burst from SDRAM
    input logic          dcache_sdramr_ack,     // SDRAM accepted read request
    output logic [25:0]  dcache_sdramr_addr,    // Address for read burst
    input logic  [1:0]   dcache_sdramr_rvalid,   // 01=first beat, 10=middle beats, 11=last beat
    input logic [31:0]   dcache_sdramr_rdata,    // Data from SDRAM read burst

    output logic [31:0]  cpu_pc
);

// Signals driven by the PC module
logic [31:0] p0_pc;
logic        p0_req;

// Signals driven by the instruction memory module
logic        p1_instr_valid;
logic [31:0] p1_instr;
logic [31:0] p1_pc;

// Signals driven by the instruction queue module
logic        p1_fifo_full;
logic        p2_ready;
logic        p2_instr_valid;
logic [31:0] p2_instr;
logic [31:0] p2_pc;
logic        instr_fifo_fault;

// Signals driven by the decoder module
logic [4:0]  p2_rs1;
logic [4:0]  p2_rs2;
logic        p2_use_immediate;
logic [31:0] p2_immediate;
logic        p3_is_alu;
logic [2:0]  p3_alu_op;
logic        p3_is_shift;
logic [2:0]  p3_shift_op;
logic        p3_is_branch;
logic [2:0]  p3_branch_op;
logic        p3_is_load;
logic        p3_is_store;
logic        p3_is_mult;
logic        p3_is_divide;
logic        p3_is_sys;
logic        p3_is_fpu;
logic [2:0]  p3_mem_op;
logic [31:0] p3_pc;
logic [31:0] p4_pc;
logic [4:0]  p3_rd;
logic [31:0] p3_immediate;
logic        p4_is_store;

// Signals driven by the register file module
logic [31:0] p3_data_a;
logic [31:0] p3_data_b;

// signals driven by the ALU module
logic        p4_alu_valid;
logic [4:0]  p4_alu_rd;
logic [31:0] p3_alu_result;
logic [31:0] p4_alu_result;
logic        mem_ready;
logic        mul_valid;
logic [4:0]  mul_rd;
logic [31:0] mul_result;

// Signals driven by the writeback
logic [4:0]   p4_rd;
logic [31:0]  p4_result;
logic         p4_wren;
logic         writeback_fault;

// signals driven by divider
logic         divider_ready;
logic         divider_valid;
logic  [31:0] divider_result;
logic  [4:0]  divider_reg_d;

logic        fpu_div_busy;


// Cpu to DCache interface signals    
logic        dcache_req;
logic        dcache_ack;
logic        dcache_write;
logic [25:0] dcache_addr;
logic [31:0] dcache_wdata;
logic [3:0]  dcache_strb;
logic [4:0]  dcache_dest;
logic        dcache_rvalid;
logic [31:0] dcache_rdata;
logic [4:0]  dcache_rdest;
logic        memif_fault;



logic p4_jump_taken;
logic [31:0] p4_jump_target;


cpu_pc  cpu_pc_inst (
    .clock(clock),
    .reset(reset),
    .p0_req(p0_req),
    .p0_pc(p0_pc),
    .p1_fifo_full(p1_fifo_full),
    .p4_jump_taken(p4_jump_taken),
    .p4_jump_target(p4_jump_target)
  );

cpu_irom  cpu_irom_inst (
    .clock(clock),
    .reset(reset),
    .p0_req(p0_req),
    .p0_pc(p0_pc),
    .p1_instr_valid(p1_instr_valid),
    .p1_instr(p1_instr),
    .p1_pc(p1_pc),
    .aux_irom_req(aux_irom_req),
    .aux_irom_write(aux_irom_write),
    .aux_irom_addr(aux_irom_addr),
    .aux_irom_wdata(aux_irom_wdata),
    .aux_irom_rdata(aux_irom_rdata),
    .aux_irom_rvalid(aux_irom_rvalid)
  );

cpu_instr_queue  cpu_instr_queue_inst (
    .clock(clock),
    .reset(reset),
    .p1_instr_valid(p1_instr_valid),
    .p1_instr(p1_instr),
    .p1_pc(p1_pc),
    .p1_fifo_full(p1_fifo_full),
    .p2_ready(p2_ready),
    .p2_instr_valid(p2_instr_valid),
    .p2_instr(p2_instr),
    .p2_pc(p2_pc),
    .p4_jump_taken(p4_jump_taken),
    .instr_fifo_fault(instr_fifo_fault)
  );

cpu_decoder  cpu_decoder_inst (
    .clock(clock),
    .reset(reset),
    .p4_jump_taken(p4_jump_taken),
    .p2_instr_valid(p2_instr_valid),
    .p2_instr(p2_instr),
    .mem_ready(mem_ready),
    .divider_ready(divider_ready),
    .fpu_div_busy(fpu_div_busy),
    .p2_pc(p2_pc),
    .p2_ready(p2_ready),
    .p2_rs1(p2_rs1),
    .p2_rs2(p2_rs2),
    .p2_use_immediate(p2_use_immediate),
    .p2_immediate(p2_immediate),
    .p3_is_alu(p3_is_alu),
    .p3_alu_op(p3_alu_op),
    .p3_is_shift(p3_is_shift),
    .p3_is_mult(p3_is_mult),
    .p3_is_divide(p3_is_divide),
    .p3_is_sys(p3_is_sys),
    .p3_is_fpu(p3_is_fpu),
    .p3_shift_op(p3_shift_op),
    .p3_is_branch(p3_is_branch),
    .p3_branch_op(p3_branch_op),
    .p3_immediate(p3_immediate),
    .p3_is_load(p3_is_load),
    .p3_is_store(p3_is_store),
    .p3_mem_op(p3_mem_op),
    .p3_pc(p3_pc),
    .p4_pc(p4_pc),
    .p3_rd(p3_rd),
    .p4_rd(p4_rd),
    .p4_wren(p4_wren),
    .p4_is_store(p4_is_store)
  );

cpu_regfile  cpu_regfile_inst (
    .clock(clock),
    .p2_rs1(p2_rs1),
    .p2_rs2(p2_rs2),
    .p2_use_immediate(p2_use_immediate),
    .p2_immediate(p2_immediate),
    .p3_is_alu(p3_is_alu),
    .p3_rd(p3_rd),
    .p3_alu_result(p3_alu_result),
    .p4_wren(p4_wren),
    .p4_rd(p4_rd),
    .p4_result(p4_result),
    .p3_data_a(p3_data_a),
    .p3_data_b(p3_data_b)
  );

cpu_alu  cpu_alu_inst (
    .clock(clock),
    .p3_data_a(p3_data_a),
    .p3_data_b(p3_data_b),
    .p3_pc(p3_pc),
    .p3_rd(p3_rd),
    .p3_is_alu(p3_is_alu),
    .p3_alu_op(p3_alu_op),
    .p3_shift_op(p3_shift_op),
    .p3_is_shift(p3_is_shift),
    .p3_is_mult(p3_is_mult),
    .p3_alu_result(p3_alu_result),
    .p4_alu_valid(p4_alu_valid),
    .p4_alu_rd(p4_alu_rd),
    .p4_alu_result(p4_alu_result),
    .mul_valid(mul_valid),
    .mul_rd(mul_rd),
    .mul_result(mul_result)
  );

cpu_divider  cpu_divider_inst (
    .clock(clock),
    .reset(reset),
    .p3_is_divide(p3_is_divide),
    .p3_alu_op(p3_alu_op[1:0]),
    .p3_data_a(p3_data_a),
    .p3_data_b(p3_data_b),
    .p3_rd(p3_rd),
    .divider_ready(divider_ready),
    .divider_valid(divider_valid),
    .divider_result(divider_result),
    .divider_reg_d(divider_reg_d)
  );

cpu_branch  cpu_branch_inst (
    .clock(clock),
    .reset(reset),
    .p3_is_branch(p3_is_branch),
    .p3_data_a(p3_data_a),
    .p3_data_b(p3_data_b),
    .p3_pc(p3_pc),
    .p3_branch_op(p3_branch_op),
    .p3_immediate(p3_immediate),
    .p4_jump_taken(p4_jump_taken),
    .p4_jump_target(p4_jump_target)
  );

cpu_mem  cpu_mem_inst (
    .clock(clock),
    .reset(reset),
    .mem_ready(mem_ready),
    .p3_is_load(p3_is_load),
    .p3_is_store(p3_is_store),
    .p3_mem_op(p3_mem_op),
    .p3_data_a(p3_data_a),
    .p3_immediate(p3_immediate),
    .p3_data_b(p3_data_b),
    .p3_rd(p3_rd),
    .dcache_req(dcache_req),
    .dcache_ack(dcache_ack),
    .dcache_write(dcache_write),
    .dcache_addr(dcache_addr),
    .dcache_wdata(dcache_wdata),
    .dcache_strb(dcache_strb),
    .dcache_dest(dcache_dest),
    .cpu_aux_req(cpu_aux_req),
    .cpu_aux_write(cpu_aux_write),
    .cpu_aux_addr(cpu_aux_addr),
    .cpu_aux_wdata(cpu_aux_wdata),
    .cpu_aux_strb(cpu_aux_strb),
    .cpu_aux_rd(cpu_aux_rd),
    .memif_fault(memif_fault)
  );

logic        fpu_valid;
logic [4:0]  fpu_dest;
logic [31:0] fpu_result;

fpu  fpu_inst (
    .clock(clock),
    .p3_is_fpu(p3_is_fpu),
    .fpu_op(p3_alu_op),
    .fpu_in_a(p3_data_a),
    .fpu_in_b(p3_data_b),
    .fpu_in_dest(p3_rd),
    .fpu_valid(fpu_valid),
    .fpu_dest(fpu_dest),
    .fpu_result(fpu_result),
    .fpu_div_busy(fpu_div_busy)
  );

cpu_writeback  cpu_writeback_inst (
  .clock(clock),
  .reset(reset),
    .p4_alu_valid(p4_alu_valid),
    .p4_alu_rd(p4_alu_rd),
    .p4_alu_result(p4_alu_result),
    .p4_rd(p4_rd),
    .p4_result(p4_result),
    .p4_wren(p4_wren),
    .aux_wb_valid(cpu_aux_rvalid),
    .aux_wb_rd(cpu_aux_rdest),
    .aux_wb_result(cpu_aux_rdata),
    .mul_valid(mul_valid),
    .mul_rd(mul_rd),
    .mul_result(mul_result),
    .divider_valid(divider_valid),
    .divider_reg_d(divider_reg_d),
    .divider_result(divider_result),
    .dcache_rvalid(dcache_rvalid),
    .dcache_rdest(dcache_rdest),
    .dcache_rdata(dcache_rdata),
    .fpu_valid(fpu_valid),
    .fpu_dest(fpu_dest),
    .fpu_result(fpu_result),
    .writeback_fault(writeback_fault)
);

cpu_dcache  cpu_dcache_inst (
    .clock(clock),
    .reset(reset),
    .dcache_req(dcache_req),
    .dcache_ack(dcache_ack),
    .dcache_write(dcache_write),
    .dcache_addr(dcache_addr),
    .dcache_wdata(dcache_wdata),
    .dcache_strb(dcache_strb),
    .dcache_dest(dcache_dest),
    .dcache_rvalid(dcache_rvalid),
    .dcache_rdata(dcache_rdata),
    .dcache_rdest(dcache_rdest),
    .dcache_sdramw_req(dcache_sdramw_req),
    .dcache_sdramw_ack(dcache_sdramw_ack),
    .dcache_sdramw_addr(dcache_sdramw_addr),
    .dcache_sdramw_data(dcache_sdramw_data),
    .dcache_sdramw_strb(dcache_sdramw_strb),
    .dcache_sdramr_req(dcache_sdramr_req),
    .dcache_sdramr_ack(dcache_sdramr_ack),
    .dcache_sdramr_addr(dcache_sdramr_addr),
    .dcache_sdramr_rvalid(dcache_sdramr_rvalid),
    .dcache_sdramr_rdata(dcache_sdramr_rdata)
  );

logic [31:1]  interrupt_source;
logic         interrupt_signal;
logic [4:0]   interrupt_cause;
logic         supervisor_mode;
logic         dmpu_clear;
logic         dmpu_add;
logic [31:0]  dmpu_data;
logic         dmpu_fault=1'b0;
logic         misaligned_fault=1'b0;
logic [31:0]  dmpu_fault_addr;
logic         icache_flush;
logic         icache_flush_in_progress;
logic         p3_is_illegal;
logic [31:0]  p3_instr;
logic         idx_bounds_exception;
logic         exception_jump;
logic [31:0]  exception_target;
logic         sys_valid;
logic [4:0]   sys_reg_d;
logic [31:0]  sys_result;


cpu_sys  cpu_sys_inst (
    .clock(clock),
    .reset(reset),
    .interrupt_source(interrupt_source),
    .p3_is_sys(p3_is_sys),
    .p3_alu_op(p3_alu_op),
    .p3_rd(p3_rd),
    .p3_imm(p3_immediate),
    .p3_data_a(p3_data_a),
    .interrupt_signal(interrupt_signal),
    .interrupt_cause(interrupt_cause),
    .supervisor_mode(supervisor_mode),
    .dmpu_clear(dmpu_clear),
    .dmpu_add(dmpu_add),
    .dmpu_data(dmpu_data),
    .dmpu_fault(dmpu_fault),
    .misaligned_fault(misaligned_fault),
    .dmpu_fault_addr(dmpu_fault_addr),
    .p4_is_store(p4_is_store),
    .icache_flush(icache_flush),
    .icache_flush_in_progress(icache_flush_in_progress),
    .p3_pc(p3_pc),
    .p4_pc(p4_pc),
    .p3_is_illegal(p3_is_illegal),
    .p3_instr(p3_instr),
    .idx_bounds_exception(idx_bounds_exception),
    .exception_jump(exception_jump),
    .exception_target(exception_target),
    .sys_valid(sys_valid),
    .sys_reg_d(sys_reg_d),
    .sys_result(sys_result)
  );

always_ff @(posedge clock) begin
  cpu_pc <= p2_pc;
end

endmodule
