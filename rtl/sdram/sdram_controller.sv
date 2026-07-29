`timescale 1ns/1ps

// Top-level module for the SDRAM controller.
//
// Transactions are always 128 bits (16 bytes) wide. For writes the CPU sends a 128-bit word and 
// a 16-bit write mask, where each bit corresponds to one byte of the 128-bit word. For reads,
// the CPU sends the address and a tag, which the controller acknowledges the request with the 
// cpu_sdram_ready signal. The controller then responds some number of cycles later
// with a 4 beat burst of 32 bit data values. 
//
// For a write the address must be 16-byte aligned (ie lower 4 bits must be 0). 
// 
// For a read the address sent by the CPU must be word aligned, but can be anywhere
// in the 16-byte block. The first beat of the read response corresponds to 
// the word at the requested address, and the following beats are the subsequent words in the block 
// (wrapping around to the start of the block as necessary). The tag sent by the CPU is included
// in the read response so that the CPU can match it up with the original request.
//
// Address breakdown:
//  [25:13] Row
//  [12:11] Bank
//  [10:1]  Column
//  [0]     Byte offset within word (not used)

module sdram_controller(
    input logic         clock,
    input logic         reset,

    // Connection to the CPU
    output logic         sdram_ack,       // AXI-style ready/valid handshake
    input  logic         sdram_req,
    input  logic         sdram_write,
    input  logic [25:0]  sdram_addr,
    input  logic [127:0] sdram_wdata,       // Data to write
    input  logic [15:0]  sdram_wstrb,       // Byte mask for write data
    input  logic [9:0]   sdram_tag,         // Tag to include in read response
    output logic [1:0]   sdram_rvalid,      // 00=no data, 01=first beat, 10=middle beats, 11=final beat
    output logic [31:0]  sdram_rdata,
    output logic [9:0]   sdram_rtag,        // Tag from read data

    // Connection to the SDRAM chip
    output logic [12:0]   DRAM_ADDR,
	output logic  [1:0]   DRAM_BA,
	output logic          DRAM_CAS_N,
	output logic          DRAM_CKE,
	output logic          DRAM_CS_N,
	inout        [15:0]   DRAM_DQ,
	output logic          DRAM_LDQM,
	output logic          DRAM_RAS_N,
	output logic          DRAM_UDQM,
	output logic          DRAM_WE_N
);

logic [2:0]   cmd;
logic [12:0]  addr;
logic [1:0]   ba;
logic [127:0] write_data, next_write_data;
logic [15:0]  write_strobe, next_write_strobe;
logic [7:0]   oe, next_oe;

logic [3:0]  bank_precharge;
logic [3:0]  bank_activate;
logic [3:0]  bank_read;
logic [3:0]  bank_write;
logic        precharge_all;
logic        refresh;
logic        load_mode;
logic        freeze;
logic        sdram_idle;
logic [3:0]  burst_counter, next_burst_counter;
logic [9:0]  read_tag, next_read_tag;
logic        bus_write, next_bus_write;
logic [31:0] read_data;
logic [2:0]  read_counter, next_read_counter;
logic [9:0]  next_sdram_rtag;


localparam [2:0] CMD_NOP       = 3'b111;
localparam [2:0] CMD_PRECHARGE = 3'b010;
localparam [2:0] CMD_ACTIVATE  = 3'b011;
localparam [2:0] CMD_READ      = 3'b101;
localparam [2:0] CMD_WRITE     = 3'b100;
localparam [2:0] CMD_REFRESH   = 3'b001;
localparam [2:0] CMD_LOAD_MODE = 3'b000;

assign DRAM_CS_N = 1'b0;  // Always select the SDRAM chip
assign DRAM_CKE = 1'b1;   // Always enable the SDRAM chip
assign DRAM_DQ = oe[0] ? write_data[15:0] : 16'bz; // Tri-state the DQ lines when not driving them
assign DRAM_LDQM = write_strobe[0];
assign DRAM_UDQM = write_strobe[1];


always_comb begin
    cmd = CMD_NOP;
    addr = 13'bx;
    ba = sdram_addr[12:11];
    next_oe = {1'b0, oe[7:1]};
    next_write_data = {16'bx, write_data[127:16]};
    next_write_strobe = {2'b00, write_strobe[15:2]};
    next_read_tag = read_tag;
    next_bus_write = bus_write;
    next_read_counter = (read_counter > 0) ? read_counter - 1'b1 : 3'd0;
    next_sdram_rtag = sdram_rtag;
    sdram_ack = 1'b0;
    next_burst_counter = (burst_counter > 0) ? burst_counter - 1'b1 : 4'b0;
    
    // SDRAM is idle when no request pending, no burst active, and no bank operations
    sdram_idle = !sdram_req && (burst_counter == 0);
    
    if (bank_read != 4'b0000 && burst_counter==4'h0) begin
        cmd  = CMD_READ;
        addr = {3'b0, sdram_addr[10:2], 1'b0};
        next_read_tag = sdram_tag;
        sdram_ack = 1'b1;
        next_bus_write = 1'b0;
        next_burst_counter = 4'd8;

    end else if (bank_write!=4'b0000 && burst_counter==4'h0 && read_counter==3'h0) begin
        cmd  = CMD_WRITE;
        addr = {3'b0, sdram_addr[10:2], 1'b0};
        next_write_data = sdram_wdata;
        next_write_strobe = ~sdram_wstrb[15:0];
        next_oe = 8'hFF;
        sdram_ack = 1'b1;
        next_bus_write = 1'b1;
        next_burst_counter = 4'd8;
        
    end else if (load_mode) begin
        cmd = CMD_LOAD_MODE;
        addr =  13'b0000_0010_0011;

    end else if (refresh) begin
        cmd = CMD_REFRESH;

    end else if (bank_precharge != 4'b0000) begin
        cmd  = CMD_PRECHARGE;
        addr = 13'b0;

    end else if (precharge_all) begin
        cmd  = CMD_PRECHARGE;
        addr = 13'b0010000000000;

    end else if (bank_activate != 4'b0000) begin
        cmd  = CMD_ACTIVATE;
        addr = sdram_addr[25:13];

    end else if (!sdram_req) begin
        // No new request - stay idle
        cmd = CMD_NOP;
        sdram_ack = 1'b1;        
    end

    // Start the read counter a short while after the read command to account for the CAS latency
    if (burst_counter==4'd5 && bus_write==1'b0) begin
        next_read_counter = 3'd7;
        next_sdram_rtag = read_tag;
    end

    // Reset handling
    if (reset) begin
        cmd = CMD_NOP;
        next_bus_write = 1'b0;
        sdram_ack = 1'b0;
        next_burst_counter = 4'b0;
        next_read_counter = 3'b0;
    end
end

always_comb begin
    // Drive the sdram_rvalid and sdram_rdata signals based on the read counter. 
    sdram_rvalid = 2'b00;
    sdram_rdata = 32'hx;
    if (read_counter==3'd7) begin
        sdram_rvalid = 2'b01;
        sdram_rdata = read_data[31:0];
    end else if (read_counter==3'd5 || read_counter==3'd3) begin
        sdram_rvalid = 2'b10;
        sdram_rdata = read_data[31:0];
    end else if (read_counter==3'd1) begin
        sdram_rvalid = 2'b11;
        sdram_rdata = read_data[31:0];
    end
end

always_ff @(posedge clock) begin
    write_data <= next_write_data;
    write_strobe <= next_write_strobe;
    oe <= next_oe;
    burst_counter <= next_burst_counter;
    read_counter <= next_read_counter;
    read_tag <= next_read_tag;
    bus_write <= next_bus_write;
    read_data <= {DRAM_DQ, read_data[31:16]};
    sdram_rtag <= next_sdram_rtag;
    DRAM_ADDR <= addr;
    DRAM_BA <= ba;
    DRAM_RAS_N <= cmd[2];
    DRAM_CAS_N <= cmd[1];
    DRAM_WE_N <= cmd[0];
end

sdram_refresh  sdram_refresh_inst (
    .clock(clock),
    .reset(reset),
    .sdram_idle(sdram_idle),
    .precharge_all(precharge_all),
    .refresh(refresh),
    .freeze(freeze),
    .load_mode(load_mode)
  );

sdram_bank # (.BANK_ID(2'd0) ) sdram_bank_inst_0 (
    .clock(clock),
    .reset(reset),
    .sdram_req(sdram_req),
    .sdram_write(sdram_write),
    .sdram_addr(sdram_addr),
    .cmd(cmd),
    .addr(addr),
    .ba(ba),
    .freeze(freeze),
    .bank_precharge(bank_precharge[0]),
    .bank_activate(bank_activate[0]),
    .bank_read(bank_read[0]),
    .bank_write(bank_write[0])
  );

sdram_bank # (.BANK_ID(2'd1) ) sdram_bank_inst_1 (
    .clock(clock),
    .reset(reset),
    .sdram_req(sdram_req),
    .sdram_write(sdram_write),
    .sdram_addr(sdram_addr),
    .cmd(cmd),
    .addr(addr),
    .ba(ba),
    .freeze(freeze),
    .bank_precharge(bank_precharge[1]),
    .bank_activate(bank_activate[1]),
    .bank_read(bank_read[1]),
    .bank_write(bank_write[1])
  );

sdram_bank # (.BANK_ID(2'd2) ) sdram_bank_inst_2 (
    .clock(clock),
    .reset(reset),
    .sdram_req(sdram_req),
    .sdram_write(sdram_write),
    .sdram_addr(sdram_addr),
    .cmd(cmd),
    .addr(addr),
    .ba(ba),
    .freeze(freeze),
    .bank_precharge(bank_precharge[2]),
    .bank_activate(bank_activate[2]),
    .bank_read(bank_read[2]),
    .bank_write(bank_write[2])
  );

sdram_bank # (.BANK_ID(2'd3) ) sdram_bank_inst_3 (
    .clock(clock),
    .reset(reset),
    .sdram_req(sdram_req),
    .sdram_write(sdram_write),
    .sdram_addr(sdram_addr),
    .cmd(cmd),
    .addr(addr),
    .ba(ba),
    .freeze(freeze),
    .bank_precharge(bank_precharge[3]),
    .bank_activate(bank_activate[3]),
    .bank_read(bank_read[3]),
    .bank_write(bank_write[3])
  );

endmodule

