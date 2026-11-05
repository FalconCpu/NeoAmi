`timescale 1ns/1ps

// A 8KB direct-mapped instruction cache with 16-byte lines
// Handles both IRAM (ROM at 0xFFFF0000) and SDRAM (0x00000000-0x03FFFFFF)
//
// Address breakdown for SDRAM:
// [25:13] tag (13 bits)
// [12:4]  index (9 bits = 512 lines)
// [3:2]   word offset
// [1:0]   byte offset (not used)

module cpu_icache(
    input  logic         clock,
    input  logic         reset,

    // Input address
    output logic         p0_ready,          // Indicates that the icache is ready to accept the next instruction address
    input logic [31:0]   p0_pc,             // Current program counter value

    // Output data
    output logic         p1_instr_valid,
    input  logic         p1_ready,
    output logic [31:0]  p1_instr,
    output logic [31:0]  p1_pc,

    // Flush control
    input  logic         icache_flush,
    output logic         icache_flush_in_progress, 

    // Connection to the iram (ROM at 0xFFFF0000)
    output logic         icache_iram_req,
    output logic [15:0]  icache_iram_addr,
    input  logic         icache_iram_rvalid,
    input  logic [31:0]  icache_iram_rdata,

    // Connection to SDRAM 
    input  logic         icache_sdram_ready,
    output logic         icache_sdram_req,
    output logic [25:0]  icache_sdram_addr,
    input  logic [1:0]   icache_sdram_rvalid,  // 01=first, 10=middle, 11=last
    input  logic [31:0]  icache_sdram_rdata
);

// The RAMs
logic [13:0]  tag_array  [0:511];      // 1 valid bit + 13 tag bits
logic [31:0]  data_array [0:512*4-1];  // 512 lines of 4 words each

// Latch the input address and request signals
logic [31:0]  this_pc;
logic [31:0]  this_data;
logic [13:0]  this_tag;

logic         tag_match;
logic         sdram_match;
logic         prev_sdram_req;
logic [25:0]  prev_sdram_addr;
logic         prev_sdram_ready;
logic         sdram_req_in_progress, prev_sdram_req_in_progress;

assign     p0_ready = p1_ready && p1_instr_valid;


always_comb begin
    icache_sdram_req = prev_sdram_req;
    icache_sdram_addr = prev_sdram_addr;
    sdram_req_in_progress = prev_sdram_req_in_progress;

    // Determine if the current access is to the ROM (0xFFFF0000 region)
    icache_iram_req = p0_pc[31:16] == 16'hFFFF;
    icache_iram_addr = icache_iram_req ? p0_pc[15:0] : 16'bx;

    // Check if the tag matches and the line is valid
    tag_match = this_tag[13] && (this_tag[12:0] == this_pc[25:13]);
    sdram_match = icache_sdram_rvalid!=2'b00 && (prev_sdram_addr == this_pc[25:0]);
    p1_instr_valid = tag_match || icache_iram_rvalid || sdram_match;
    
    p1_instr = icache_iram_rvalid ? icache_iram_rdata :
               sdram_match        ? icache_sdram_rdata : 
                                    this_data;
    p1_pc = this_pc;

    // Do we need to request data from SDRAM?
    if (!tag_match && !icache_iram_rvalid && !sdram_req_in_progress) begin
        icache_sdram_req = 1'b1;
        icache_sdram_addr = this_pc[25:0];
        sdram_req_in_progress = 1'b1;
    end

    // Clear the SDRAM request in progress if the previous request has been acknowledged
    if (prev_sdram_ready)
        icache_sdram_req = 1'b0;

    // Increment the address as data is received from SDRAM
    if (icache_sdram_rvalid!=2'b0)
        icache_sdram_addr = {prev_sdram_addr[25:4], prev_sdram_addr[3:0] + 4'd4};

    // Clear the request in progress once SDRAM burst is complete
    if (icache_sdram_rvalid==2'b11)
        sdram_req_in_progress = 1'b0;

    if (reset) begin
        icache_sdram_req = 1'b0;
        icache_sdram_addr = 26'bx;
        sdram_req_in_progress = 1'b0;
    end
end

initial begin
    integer i;
    for (i = 0; i < 512; i = i + 1) 
        tag_array[i] = 14'b0;
end

always_ff @(posedge clock) begin
    this_pc  <= p0_pc;
    this_data <= data_array[this_pc[12:2]];
    this_tag  <= tag_array[this_pc[12:4]];


    // Store data from SDRAM into the cache
    if (icache_sdram_rvalid!=2'b0) begin
        data_array[prev_sdram_addr[12:2]] <= icache_sdram_rdata;
        tag_array[prev_sdram_addr[12:4]] <= {icache_sdram_rvalid==2'b11, prev_sdram_addr[25:13]};   // Set valid bit if burst is complete and store tag
    end

    prev_sdram_req <= icache_sdram_req;
    prev_sdram_addr <= icache_sdram_addr;
    prev_sdram_ready <= icache_sdram_ready;
    prev_sdram_req_in_progress <= sdram_req_in_progress;
end

endmodule
