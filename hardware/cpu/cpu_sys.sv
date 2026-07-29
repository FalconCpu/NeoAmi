`timescale 1ns/1ns
`include "cpu.vh"

// Exception and interrupt handling logic for the CPU

module cpu_sys(
    input logic clock,
    input logic reset,
    input logic [31:1]   interrupt_source,      // External interrupt sources. (bit 0 is reserved for timer interrupt)

    // connection to the decoder
    input  logic         p3_is_sys,
    input  logic [2:0]   p3_alu_op,     // 0=cfgr, 1=cfgw, 2=rte, 3=syscall, 7=interrupt
    input  logic [4:0]   p3_rd,      // Destination register for cfgr   
    input  logic [31:0]  p3_imm,        // Register index for cfgr/w
    input  logic [31:0]  p3_data_a,     // Value to write for cfgr

    output logic         interrupt_signal,   // request the decode block to send us an interrupt instruction
    output logic [4:0]   interrupt_cause,    // Encoded cause of the interrupt (index of the interrupting source)

    // Connection to the DMPU for memory access control
    output logic         supervisor_mode,
    output logic         dmpu_clear,    // Clear all regions
    output logic         dmpu_add,      // Add a region
    output logic [31:0]  dmpu_data,     // Region data to add
    input  logic         dmpu_fault,
    input  logic         misaligned_fault,
    input  logic [31:0]  dmpu_fault_addr, // The address that caused the DMPU fault or misalignment
    input  logic         p4_is_store,

    // Icache flush control
    output logic         icache_flush,   // Signal to flush the icache
    input  logic         icache_flush_in_progress, // Signal from icache that flush is in progress

    // Exception and interrupt inputs
    input  logic [31:0]  p3_pc,
    input  logic [31:0]  p4_pc,
    input  logic         p3_is_illegal, // An illegal instruction was detected in the decode stage
    input  logic [31:0]  p3_instr,      // The instruction that caused the illegal instruction exception 
    input  logic         idx_bounds_exception, // The memory access index was out of bounds in the ALU stage

    output logic         exception_jump,  // Trigger a jump
    output logic [31:0]  exception_target, // Target address for exception jump

    // connection to the writeback stage
    output logic         sys_valid,
    output logic [4:0]   sys_reg_d,
    output logic [31:0]  sys_result
);

logic [31:0] reg_epc,      next_reg_epc;
logic [7:0]  reg_ecause,   next_reg_ecause;
logic [31:0] reg_edata,    next_reg_edata;
logic [7:0]  reg_estatus,  next_reg_estatus;
logic [31:0] reg_escratch, next_reg_escratch;
logic [7:0]  reg_status,   next_reg_status;
logic [31:0] reg_ipc,      next_reg_ipc;
logic [7:0]  reg_icause,   next_reg_icause;
logic [7:0]  reg_istatus,  next_reg_istatus;
logic [31:0] reg_intvec,   next_reg_intvec;
logic [31:0] reg_timer,    next_reg_timer;
logic [31:0] reg_iscratch, next_reg_iscratch;
logic [31:0] result;
logic        exception;

logic [31:0] pending_interrupts, next_pending_interrupts;
logic [31:0] cleared_interrupts;
logic        next_interrupt_signal;
logic [4:0]  next_interrupt_cause;
logic        timer_interrupt, next_timer_interrupt;
logic        next_icache_flush;
integer i;

logic        next_dmpu_clear;
logic        next_dmpu_add;
logic [31:0]  next_dmpu_data;

// Status register bits
// Bit 0: Supervisor mode (1 = supervisor, 0 = user)
// Bit 1: Interrupt enable

assign supervisor_mode = reg_status[0];

always_comb begin
    next_reg_epc = reg_epc;
    next_reg_ecause = reg_ecause;
    next_reg_edata = reg_edata;
    next_reg_estatus = reg_estatus;
    next_reg_escratch = reg_escratch;
    next_reg_status = reg_status;
    next_reg_ipc = reg_ipc;
    next_reg_icause = reg_icause;
    next_reg_istatus = reg_istatus;
    next_reg_intvec = reg_intvec;
    next_reg_iscratch = reg_iscratch;
    // Timer counts down each cycle (stops at 0)
    next_reg_timer = (reg_timer != 0) ? reg_timer - 1 : 32'h0;
    next_interrupt_signal = 1'b0;
    next_interrupt_cause = 5'b0;
    next_dmpu_clear = 1'b0;
    next_dmpu_add = 1'b0;
    next_dmpu_data = 32'b0;
    result = 32'bx;
    exception = 1'b0;
    exception_jump = 1'b0;
    exception_target = 32'hFFFF0004;
    cleared_interrupts = 32'b0;
    next_icache_flush = 1'b0;

    // Do register writes
    if (p3_is_sys && p3_alu_op==3'b001) begin
        case (p3_imm[7:0]) 
            `CFGREG_EPC: next_reg_epc = p3_data_a;
            `CFGREG_ECAUSE: next_reg_ecause = p3_data_a[7:0];
            `CFGREG_EDATA: next_reg_edata = p3_data_a;
            `CFGREG_ESTATUS: next_reg_estatus = p3_data_a[7:0];
            `CFGREG_ESCRATCH: next_reg_escratch = p3_data_a;
            `CFGREG_STATUS: next_reg_status = p3_data_a[7:0];
            `CFGREG_IPC: next_reg_ipc = p3_data_a;
            `CFGREG_ICAUSE: next_reg_icause = p3_data_a[7:0];
            `CFGREG_ISTATUS: next_reg_istatus = p3_data_a[7:0];
            `CFGREG_INTVEC: next_reg_intvec = p3_data_a;
            `CFGREG_TIMER: next_reg_timer = p3_data_a;
            `CFGREG_MPU_CLR: next_dmpu_clear = 1'b1; 
            `CFGREG_MPU_DATA: begin next_dmpu_add = 1'b1; next_dmpu_data = p3_data_a; end
            `CFGREG_ICACHE: next_icache_flush = p3_data_a[0]; // Trigger an icache flush if bit 0 is set
            `CFGREG_ISCRATCH: next_reg_iscratch = p3_data_a;
            default: begin end
        endcase
    end

    // Do register reads
    if (p3_is_sys && (p3_alu_op==3'b000 || p3_alu_op==3'b001)) begin
        case (p3_imm[7:0]) 
            `CFGREG_VERSION: result = 32'h00020000;
            `CFGREG_EPC: result = reg_epc;
            `CFGREG_ECAUSE: result = {24'b0, reg_ecause};
            `CFGREG_EDATA: result = reg_edata;
            `CFGREG_ESTATUS: result = {24'b0, reg_estatus};
            `CFGREG_ESCRATCH: result = reg_escratch;
            `CFGREG_STATUS: result = {24'b0, reg_status};
            `CFGREG_IPC: result = reg_ipc;
            `CFGREG_ICAUSE: result = {24'b0, reg_icause};
            `CFGREG_ISTATUS: result = {24'b0, reg_istatus};
            `CFGREG_INTVEC: result = reg_intvec;
            `CFGREG_TIMER: result = reg_timer;
            `CFGREG_ICACHE: result = {31'b0, icache_flush_in_progress}; // Indicate whether an icache flush is in progress in bit 0 
            `CFGREG_ISCRATCH: result = reg_iscratch;
            default: begin end
        endcase
    end

    // Handle exceptions
    // dmpu and misalignment faults first as they relate to instruction at p4, while the others relate to the instruction at p3. 
    // This means if we have a dmpu/misalignment fault, we want to report that instead of any other exceptions that might also be pending for the same instruction.
    if (misaligned_fault) begin
        next_reg_ecause = p4_is_store ? `CAUSE_STORE_MISALIGN : `CAUSE_LOAD_MISALIGN;
        next_reg_edata = dmpu_fault_addr;
        exception = 1'b1;
    end else if (dmpu_fault) begin
        next_reg_ecause = p4_is_store ? `CAUSE_STORE_ACCESS : `CAUSE_LOAD_ACCESS;
        next_reg_edata = dmpu_fault_addr;
        exception = 1'b1;
    end

    if (p3_is_illegal) begin
        next_reg_ecause = `CAUSE_ILLEGAL;
        next_reg_edata = p3_instr;
        exception = 1'b1;
    end

    if (idx_bounds_exception) begin
        next_reg_ecause = `CAUSE_INDEX;
        next_reg_edata = p3_data_a; // The index that was out of bounds
        exception = 1'b1;
    end


    // Syscall
    if (p3_is_sys && p3_alu_op==3'b011) begin
        next_reg_ecause = `CAUSE_SYS;
        next_reg_edata = p3_imm;
        exception = 1'b1;
    end

    // interrupt
    if (p3_is_sys && p3_alu_op==3'b111 && reg_status[1]) begin
        next_reg_icause = p3_imm[7:0];
        next_reg_ipc = p3_pc;
        next_reg_istatus = reg_status;
        next_reg_status = (reg_status | 8'h01) & 8'hFD; // Switch to supervisor mode, disable interrupts
        cleared_interrupts = 32'b1 << p3_imm[4:0];
        exception_jump = 1'b1;
        exception_target = reg_intvec;
    end

    // Return from exception
    if (p3_is_sys && p3_alu_op==3'b010) begin
        exception_jump = 1'b1;
        if (p3_imm[0]==1'b0) begin    // rte
            exception_target = reg_epc;
            next_reg_status = reg_estatus;
        end else begin                  // rti
            exception_target = reg_ipc;
            next_reg_status = reg_istatus;
        end
    end
        
    if (exception) begin
        next_reg_epc = (dmpu_fault || misaligned_fault) ? p4_pc : p3_pc;
        next_reg_estatus = reg_status;
        next_reg_status = reg_status | 8'h01; // Switch to supervisor mode       
        exception_jump = 1'b1; 
    end



    // Update interrupts state
    next_timer_interrupt = (reg_timer == 1); // Timer is about to hit 0, so trigger interrupt on next cycle
    for(i=0; i<32; i=i+1) begin
        if (pending_interrupts[i]) begin
            next_interrupt_signal = 1'b1;
            next_interrupt_cause = i[4:0];
        end
    end
    if (!reg_status[1]) begin
        // If interrupts are globally disabled, don't signal any interrupts
        next_interrupt_signal = 1'b0;
    end

    next_pending_interrupts = (pending_interrupts | {interrupt_source,timer_interrupt}) & ~cleared_interrupts;

    if (reset) begin
        next_reg_status = 8'h01;
        next_pending_interrupts = 32'b0;
        next_reg_timer = 32'h0;
    end

end



always_ff @(posedge clock) begin
    reg_epc <= next_reg_epc;
    reg_ecause <= next_reg_ecause;
    reg_edata <= next_reg_edata;
    reg_estatus <= next_reg_estatus;
    reg_escratch <= next_reg_escratch;
    reg_status <= next_reg_status;
    reg_ipc <= next_reg_ipc;
    reg_icause <= next_reg_icause;
    reg_istatus <= next_reg_istatus;
    reg_intvec <= next_reg_intvec;
    reg_timer <= next_reg_timer;
    reg_iscratch <= next_reg_iscratch;
    timer_interrupt <= next_timer_interrupt;
    dmpu_clear <= next_dmpu_clear;
    dmpu_add <= next_dmpu_add;
    dmpu_data <= next_dmpu_data;

    sys_valid <= p3_is_sys && (p3_alu_op==3'b000 || p3_alu_op==3'b001);
    sys_reg_d <= p3_rd;
    sys_result <= result;

    interrupt_signal <= next_interrupt_signal;
    interrupt_cause <= next_interrupt_cause;
    pending_interrupts <= next_pending_interrupts;
    icache_flush <= next_icache_flush;
end 

endmodule
