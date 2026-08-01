`timescale 1ns/1ns

// GEMMA register bank module
//
// This module implements a register bank between stages in the GEMMA pipeline. 
// It provides a double-buffered register bank that allows one stage to write data while another stage reads data, enabling efficient pipelining and data flow control.
//
// Also provides an interface for the CPU to read and write registers in the bank, allowing for configuration and control of the GEMMA pipeline. NOTE - there are no 
// interlock mechanisms to prevent the CPU from reading/writing while a stage is writing/reading. The CPU must ensure that it does not access the register bank while
// a stage is accessing it.

module gemma_regbank (
    input logic          clock,
    input logic          reset,
    input logic          stage_start,       // The next stage is about to start processing. Trigges the banks to swap.
    output logic         bank_valid,        // Indicates that the data in the current bank is valid and ready to be read by the next stage.

    // Read interface for the next stage
    input logic  [4:0]   bank_read_index,   // Index of the register to read from the current bank
    output logic [31:0]  bank_read_data,    // Data read from the current bank

    // Write interface for the current stage
    input logic          bank_write_enable,  // Enable signal for writing to the current bank
    input logic  [4:0]   bank_write_index,   // Index of the register to write to the current bank
    input logic [31:0]   bank_write_data,
    
    // CPU interface for reading and writing registers
    input logic          bank_cpu_req,        // Request signal from the CPU to read/write registers
    input logic          bank_cpu_write,      // Indicates whether the CPU request is a write operation
    input logic  [4:0]   bank_cpu_index,      // Index of the register to read/write
    input logic [31:0]   bank_cpu_write_data, // Data to write to the register if it's a write operation
    output logic [31:0]  bank_cpu_read_data   // Data read from the register if it's a read operation
);
    

logic ping_pong;    // Indicates which bank is currently used for writing. 0=write to bank0 read from bank1, 1=write to bank1 read from bank0

// ==============================================================
//                 Register file instances
// ==============================================================

logic [31:0] rdata0, rdata1;
logic [31:0] wdata0, wdata1;
logic [4:0]  raddr0, raddr1;
logic [4:0]  waddr0, waddr1;
logic        wren0, wren1;

regfile_ram  regfile0 (
    .clock(clock),
    .data(wdata0),
    .rdaddress(raddr0),
    .wraddress(waddr0),
    .wren(wren0),
    .q(rdata0)
  );

regfile_ram  regfile1 (
    .clock(clock),
    .data(wdata1),
    .rdaddress(raddr1),
    .wraddress(waddr1),
    .wren(wren1),
    .q(rdata1)
  );

// ==============================================================
//                 Steering logic for ping-pong banks
// ==============================================================

always_comb begin
    if (ping_pong == 1'b0) begin
        if (bank_cpu_req) begin
            wdata0 = bank_cpu_write_data;
            waddr0 = bank_cpu_index;
            wren0  = bank_cpu_write;
            raddr0 = bank_cpu_index;
        end else begin
            wdata0 = bank_write_data;
            waddr0 = bank_write_index;
            wren0  = bank_write_enable;
            raddr0 = 5'hx;            
        end

        raddr1 = bank_read_index;
        bank_read_data = rdata1;
        wdata1 = 32'hx;
        waddr1 = 5'hx;
        wren1  = 1'b0;
    end else begin
        if (bank_cpu_req) begin
            wdata1 = bank_cpu_write_data;
            waddr1 = bank_cpu_index;
            wren1  = bank_cpu_write;
            raddr1 = bank_cpu_index;
        end else begin
            wdata1 = bank_write_data;
            waddr1 = bank_write_index;
            wren1  = bank_write_enable;
            raddr1 = 5'hx;            
        end

        raddr0 = bank_read_index;
        bank_read_data = rdata0;
        wdata0 = 32'hx;
        waddr0 = 5'hx;
        wren0  = 1'b0;
    end
end

// ==============================================================
//                 Bank control logic
// ==============================================================

always_ff @(posedge clock) begin
    if (reset) begin
        ping_pong <= 1'b0;
        bank_valid <= 1'b0;
    end else if (stage_start) begin
        ping_pong <= ~ping_pong;
        bank_valid <= 1'b0;
    end else if ((wren0 && waddr0==5'h1F) || (wren1 && waddr1==5'h1F)) begin
        // If the last register in the bank is written, then the bank is valid and ready to be read by the next stage.
        bank_valid <= 1'b1;
    end
end

// ==============================================================
//                 CPU read data
// ==============================================================

always_ff @(posedge clock) begin
    if (bank_cpu_req && !bank_cpu_write) begin
        if (ping_pong == 1'b0) begin
            bank_cpu_read_data <= rdata0;
        end else begin
            bank_cpu_read_data <= rdata1;
        end
    end else begin
        bank_cpu_read_data <= 32'h0;
    end
end

endmodule
