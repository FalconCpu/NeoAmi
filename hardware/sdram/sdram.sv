`timescale 1ns/1ns

module sdram (
    input logic         clock,
    input logic         reset,

    // Write Connection to cpu dcache (no tags needed)
    input  logic         dcache_sdramw_req,
    output logic         dcache_sdramw_ack,
    input  logic [25:0]  dcache_sdramw_addr,
    input  logic [127:0] dcache_sdramw_data,
    input  logic [15:0]  dcache_sdramw_strb,

    // Read Connection to cpu dcache (no tags needed)
    input  logic         dcache_sdramr_req,
    output logic         dcache_sdramr_ack,
    input  logic [25:0]  dcache_sdramr_addr,
    output logic [1:0]   dcache_sdramr_rvalid,
    output logic [31:0]  dcache_sdramr_rdata,

    // Connection to icache (CPU instruction cache)
    input  logic         icache_sdram_req,
    output logic         icache_sdram_ack,
    input  logic [25:0]  icache_sdram_addr,
    output logic [1:0]   icache_sdram_rvalid,
    output logic [31:0]  icache_sdram_rdata,

    // Connection to VGA (display controller)
    input  logic         vga_sdram_req,
    output logic         vga_sdram_ack,
    input  logic [25:0]  vga_sdram_addr,
    input  logic [7:0]   vga_sdram_tag,
    output logic [1:0]   vga_sdram_rvalid,
    output logic [31:0]  vga_sdram_rdata,
    output logic [7:0]   vga_sdram_rtag,

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

logic         sdram_ack;
logic         sdram_req;
logic         sdram_write;
logic [25:0]  sdram_addr;
logic [127:0] sdram_wdata;
logic [15:0]  sdram_wstrb;
logic [9:0]   sdram_tag;
logic [1:0]   sdram_rvalid;
logic [31:0]  sdram_rdata;
logic [9:0]   sdram_rtag;

sdram_arbiter  sdram_arbiter_inst (
    .clock(clock),
    .reset(reset),
    .dcache_sdramw_req(dcache_sdramw_req),
    .dcache_sdramw_ack(dcache_sdramw_ack),
    .dcache_sdramw_addr(dcache_sdramw_addr),
    .dcache_sdramw_data(dcache_sdramw_data),
    .dcache_sdramw_strb(dcache_sdramw_strb),
    .dcache_sdramr_req(dcache_sdramr_req),
    .dcache_sdramr_ack(dcache_sdramr_ack),
    .dcache_sdramr_addr(dcache_sdramr_addr),
    .dcache_sdramr_rvalid(dcache_sdramr_rvalid),
    .dcache_sdramr_rdata(dcache_sdramr_rdata),
    .icache_sdram_ack(icache_sdram_ack),
    .icache_sdram_req(icache_sdram_req),
    .icache_sdram_addr(icache_sdram_addr),
    .icache_sdram_rvalid(icache_sdram_rvalid),
    .icache_sdram_rdata(icache_sdram_rdata),
    .vga_sdram_req(vga_sdram_req),
    .vga_sdram_ack(vga_sdram_ack),
    .vga_sdram_addr(vga_sdram_addr),
    .vga_sdram_tag(vga_sdram_tag),
    .vga_sdram_rvalid(vga_sdram_rvalid),
    .vga_sdram_rdata(vga_sdram_rdata),
    .vga_sdram_rtag(vga_sdram_rtag),
    .sdram_req(sdram_req),
    .sdram_ack(sdram_ack),
    .sdram_write(sdram_write),
    .sdram_addr(sdram_addr),
    .sdram_wdata(sdram_wdata),
    .sdram_wstrb(sdram_wstrb),
    .sdram_tag(sdram_tag),
    .sdram_rvalid(sdram_rvalid),
    .sdram_rdata(sdram_rdata),
    .sdram_rtag(sdram_rtag)
  );

sdram_controller  sdram_controller_inst (
    .clock(clock),
    .reset(reset),
    .sdram_ack(sdram_ack),
    .sdram_req(sdram_req),
    .sdram_write(sdram_write),
    .sdram_addr(sdram_addr),
    .sdram_wdata(sdram_wdata),
    .sdram_wstrb(sdram_wstrb),
    .sdram_tag(sdram_tag),
    .sdram_rvalid(sdram_rvalid),
    .sdram_rdata(sdram_rdata),
    .sdram_rtag(sdram_rtag),
    .DRAM_ADDR(DRAM_ADDR),
    .DRAM_BA(DRAM_BA),
    .DRAM_CAS_N(DRAM_CAS_N),
    .DRAM_CKE(DRAM_CKE),
    .DRAM_CS_N(DRAM_CS_N),
    .DRAM_DQ(DRAM_DQ),
    .DRAM_LDQM(DRAM_LDQM),
    .DRAM_RAS_N(DRAM_RAS_N),
    .DRAM_UDQM(DRAM_UDQM),
    .DRAM_WE_N(DRAM_WE_N)
  );

endmodule
