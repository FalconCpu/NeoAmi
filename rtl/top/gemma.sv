`timescale 1ns/1ns

// GEMMA top 
//
// This module implements the top level of the GEMMA pipeline


module gemma (
    input logic         clock,
    input logic         reset,

    // CPU interface
    input logic         aux_gemma_req,       // Request signal from the CPU to read/write registers
    input logic         aux_gemma_write,     // Indicates whether the CPU request is a write operation
    input logic [15:0]  aux_gemma_addr,      // Index of the register to read/write
    input logic [31:0]  aux_gemma_wdata,     // Data to write to the register if it's a write operation
    output logic [31:0] aux_gemma_rdata,     // Data read from the register if it's a read operation

    // SDRAM interface
    output logic         gemma_sdram_req,     // Request signal to the SDRAM controller
    input  logic         gemma_sdram_ack,     // Acknowledge signal from the SDRAM controller
    output logic         gemma_sdram_write,   // Indicates whether the request is a write operation
    output logic [25:0]  gemma_sdram_addr,    // Address for the SDRAM request
    output logic [7:0]   gemma_sdram_tag,     // Tag for the SDRAM request (used for vga)
    output logic [127:0] gemma_sdram_wdata,   // Data to write to the SDRAM if it's a write operation
    output logic [15:0]  gemma_sdram_strb,    // Byte enable signals for the SDRAM request
    input  logic [1:0]   gemma_sdram_rvalid,  // 00: No data, 01:First beat, 10:Middle beats, 11:Last beat
    input  logic [7:0]   gemma_sdram_rtag,     // Tag for the SDRAM response (used for vga)
    input  logic [31:0]  gemma_sdram_rdata    // Data read from the SDRAM
);

// =============================================================
//                  Misc registers
// =============================================================

assign gemma_sdram_req = 1'b0;

// =============================================================
//                  Register Banks
// =============================================================

logic [3:0] stage_start = 4'h0;
logic [3:0] stage_valid;
logic [4:0] bank_read_index0, bank_read_index1, bank_read_index2, bank_read_index3;
logic [31:0] bank_read_data0, bank_read_data1, bank_read_data2, bank_read_data3;
logic        bank_write_enable0=1'b0, bank_write_enable1=1'b0, bank_write_enable2=1'b0, bank_write_enable3=1'b0;
logic [4:0]  bank_write_index0, bank_write_index1, bank_write_index2, bank_write_index3;
logic [31:0] bank_write_data0, bank_write_data1, bank_write_data2, bank_write_data3;
logic [31:0] aux_gemma_rdata0, aux_gemma_rdata1, aux_gemma_rdata2, aux_gemma_rdata3, aux_gemma_rdata_ctrl;

assign aux_gemma_rdata = aux_gemma_rdata0 | aux_gemma_rdata1 | aux_gemma_rdata2 | aux_gemma_rdata3 | aux_gemma_rdata_ctrl;

gemma_regbank  gemma_regbank_0 (
    .clock(clock),
    .reset(reset),
    .stage_start(stage_start[0]),
    .bank_valid(stage_valid[0]),
    .bank_read_index(bank_read_index0),
    .bank_read_data(bank_read_data0),
    .bank_write_enable(bank_write_enable0),
    .bank_write_index(bank_write_index0),
    .bank_write_data(bank_write_data0),
    .bank_cpu_req(aux_gemma_req && (aux_gemma_addr[15:8] == 8'h2)),
    .bank_cpu_write(aux_gemma_write),
    .bank_cpu_index(aux_gemma_addr[6:2]),
    .bank_cpu_write_data(aux_gemma_wdata),
    .bank_cpu_read_data(aux_gemma_rdata0)
  );

gemma_regbank  gemma_regbank_1 (
    .clock(clock),
    .reset(reset),
    .stage_start(stage_start[1]),
    .bank_valid(stage_valid[1]),
    .bank_read_index(bank_read_index1),
    .bank_read_data(bank_read_data1),
    .bank_write_enable(bank_write_enable1),
    .bank_write_index(bank_write_index1),
    .bank_write_data(bank_write_data1),
    .bank_cpu_req(aux_gemma_req && (aux_gemma_addr[15:8] == 8'h3)),
    .bank_cpu_write(aux_gemma_write),
    .bank_cpu_index(aux_gemma_addr[6:2]),
    .bank_cpu_write_data(aux_gemma_wdata),
    .bank_cpu_read_data(aux_gemma_rdata1)
  );

gemma_regbank  gemma_regbank_2 (
    .clock(clock),
    .reset(reset),
    .stage_start(stage_start[2]),
    .bank_valid(stage_valid[2]),
    .bank_read_index(bank_read_index2),
    .bank_read_data(bank_read_data2),
    .bank_write_enable(bank_write_enable2),
    .bank_write_index(bank_write_index2),
    .bank_write_data(bank_write_data2),
    .bank_cpu_req(aux_gemma_req && (aux_gemma_addr[15:8] == 8'h4)),
    .bank_cpu_write(aux_gemma_write),
    .bank_cpu_index(aux_gemma_addr[6:2]),
    .bank_cpu_write_data(aux_gemma_wdata),
    .bank_cpu_read_data(aux_gemma_rdata2)
  );


gemma_regbank  gemma_regbank_3 (
    .clock(clock),
    .reset(reset),
    .stage_start(stage_start[3]),
    .bank_valid(stage_valid[3]),
    .bank_read_index(bank_read_index3),
    .bank_read_data(bank_read_data3),
    .bank_write_enable(bank_write_enable3),
    .bank_write_index(bank_write_index3),
    .bank_write_data(bank_write_data3),
    .bank_cpu_req(aux_gemma_req && (aux_gemma_addr[15:8] == 8'h5)),
    .bank_cpu_write(aux_gemma_write),
    .bank_cpu_index(aux_gemma_addr[6:2]),
    .bank_cpu_write_data(aux_gemma_wdata),
    .bank_cpu_