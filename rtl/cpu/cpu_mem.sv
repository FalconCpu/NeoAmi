`timescale 1ns/1ns
`include "cpu.vh"

// CPU memory module
// 
// Implements load and store operations for the CPU. Calculates the effective address for the memory
// operation and generates the appropriate control signals for the memory interface.

module cpu_mem (
    input logic         clock,
    input logic         reset,

    // Input from the CPU pipeline
    input logic         p3_is_load,         // Indicates that the instruction is a load operation
    input logic         p3_is_store,        // Indicates that the instruction is a store operation
    input logic [2:0]   p3_mem_op,          // Memory operation type (byte, halfword, word)
    input logic [31:0]  p3_data_a,          // Base address for the memory operation
    input logic [31:0]  p3_immediate,       // Offset for the memory operation
    input logic [31:0]  p3_data_b,          // Data to be stored for a store operation
    input logic [4:0]   p3_rd,              // Destination register for the instruction in stage 3

    // Interface to the dcache
    output logic        dcache_req,
    input  logic        dcache_ack,
    output logic        dcache_write,
    output logic [25:0] dcache_addr,
    output logic [31:0] dcache_wdata,
    output logic [3:0]  dcache_strb,
    output logic [4:0]  dcache_dest,

    // Interface to aux bus for reading/writing the data memory
    output logic        cpu_aux_req,      // Request to read/write the data memory
    output logic        cpu_aux_write,    // Indicates a write operation to the data memory
    output logic [31:0] cpu_aux_addr,     // Address for the read/write
    output logic [31:0] cpu_aux_wdata,    // Data to be written to the data memory
    output logic [3:0]  cpu_aux_strb,     // Byte enable signals (For both read and write)
    output logic [4:0]  cpu_aux_rd,       // Destination register for the instruction in stage 3

    output logic        mem_ready,        // Indicates that the memory is ready to accept a new request
    output logic        memif_fault
);

logic misaligned_access;
logic next_memif_fault;

logic        req;
logic [31:0] addr;
logic [31:0] wdata;
logic [3:0]  strb;
logic        write;

typedef struct packed  {
    logic        req;
    logic        write;
    logic [25:0] addr;
    logic [31:0] wdata;
    logic [3:0]  strb;
    logic [4:0]  dest;
} dcache_queue_entry;


dcache_queue_entry dcache_queue0,   prev_dcache_queue0;
dcache_queue_entry dcache_queue1,   prev_dcache_queue1;
dcache_queue_entry dcache_queue2,   prev_dcache_queue2;
assign dcache_req = dcache_queue0.req;
assign dcache_write = dcache_queue0.write;
assign dcache_addr = dcache_queue0.addr;
assign dcache_wdata = dcache_queue0.wdata;
assign dcache_strb = dcache_queue0.strb;
assign dcache_dest = dcache_queue0.dest;

always_comb begin
    cpu_aux_req = 1'b0;
    cpu_aux_write = 1'bx;
    cpu_aux_addr = 32'bx;
    cpu_aux_wdata = 32'bx;
    cpu_aux_strb = 4'hx;
    cpu_aux_rd = 5'bx;
    misaligned_access = 1'b0;
    req = 1'b0;
    addr = 32'bx;
    wdata = 32'bx;
    write = 1'bx;
    strb = 4'bx;
    next_memif_fault = 1'b0;

    // Handle load and store operations
    if (p3_is_load || p3_is_store) begin
        addr = p3_data_a + p3_immediate;
        req   = p3_is_load || p3_is_store;
        write = p3_is_store;
        case({p3_mem_op, addr[1:0]})
            5'b000_00: begin strb = 4'b0001; wdata = {24'hx, p3_data_b[7:0]}; end
            5'b000_01: begin strb = 4'b0010; wdata = {16'hx, p3_data_b[7:0], 8'hx}; end
            5'b000_10: begin strb = 4'b0100; wdata = {8'hx, p3_data_b[7:0], 16'hx}; end
            5'b000_11: begin strb = 4'b1000; wdata = {p3_data_b[7:0], 24'hx}; end
            5'b001_00: begin strb = 4'b0011; wdata = {16'hx, p3_data_b[15:0]}; end
            5'b001_10: begin strb = 4'b1100; wdata = {p3_data_b[15:0], 16'hx}; end
            5'b010_00: begin strb = 4'b1111; wdata = p3_data_b; end
            default: misaligned_access = 1'b1; // Misaligned access
        endcase
        if (misaligned_access)
            req = 1'b0; // Do not issue the request if misaligned
    end

    // Shift dcache queue
    if (dcache_ack) begin
        dcache_queue0 = prev_dcache_queue1;
        dcache_queue1 = prev_dcache_queue2;
        dcache_queue2 = {1'b0, 1'bx, 26'bx, 32'bx, 4'bx, 5'bx}; // Clear the last entry
    end else begin
        dcache_queue0 = prev_dcache_queue0;
        dcache_queue1 = prev_dcache_queue1;
        dcache_queue2 = prev_dcache_queue2;
    end

    // Route to either the dcache or aux bus based on the address
    if (req) begin
        if (addr[31:26] == 6'b000000) begin // Address range for dcache
            if (dcache_queue0.req==1'b0)
                dcache_queue0 = {req, write, addr[25:0], wdata, strb, p3_rd};
            else if (dcache_queue1.req==1'b0)
                dcache_queue1 = {req, write, addr[25:0], wdata, strb, p3_rd};
            else if (dcache_queue2.req==1'b0)
                dcache_queue2 = {req, write, addr[25:0], wdata, strb, p3_rd};
            else
                next_memif_fault = 1'b1; // Dcache queue is full
        end else begin // Address range for aux bus
            cpu_aux_req = 1'b1;
            cpu_aux_write = write;
            cpu_aux_addr = addr;
            cpu_aux_wdata = wdata;
            cpu_aux_strb = strb;
            cpu_aux_rd = p3_rd;
        end
    end

    // Reset
    if (reset) begin
        dcache_queue0 = {1'b0, 1'bx, 26'bx, 32'bx, 4'bx, 5'bx};
        dcache_queue1 = {1'b0, 1'bx, 26'bx, 32'bx, 4'bx, 5'bx};
        dcache_queue2 = {1'b0, 1'bx, 26'bx, 32'bx, 4'bx, 5'bx};
        next_memif_fault = 1'b0;
    end
end


always_ff @(posedge clock) begin
    mem_ready <= !dcache_queue2.req;
    prev_dcache_queue0 <= dcache_queue0;
    prev_dcache_queue1 <= dcache_queue1;
    prev_dcache_queue2 <= dcache_queue2;
    memif_fault <= next_memif_fault;
    // synthesis translate_off
    if (next_memif_fault)
        $display("ERROR %t: DCACHE queue overflow", $time);
    // synthesis translate_on
end

endmodule
