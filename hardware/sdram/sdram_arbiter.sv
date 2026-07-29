`timescale 1ns/1ns

// SDRAM Arbiter
// Arbitrates between dcache (CPU data), icache (CPU instruction), and vga (display) requests to SDRAM
// Priority: vga > dcache > icache 

module sdram_arbiter(
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

    // Connection to icache (read only, no tags needed)
    output logic         icache_sdram_ack,
    input  logic         icache_sdram_req,
    input  logic [25:0]  icache_sdram_addr,
    output logic [1:0]   icache_sdram_rvalid,
    output logic [31:0]  icache_sdram_rdata,

    // Connection to VGA (read only, does need tags)
    input  logic         vga_sdram_req,
    output logic         vga_sdram_ack,
    input  logic [25:0]  vga_sdram_addr,
    input  logic [7:0]   vga_sdram_tag,
    output logic [1:0]   vga_sdram_rvalid,
    output logic [31:0]  vga_sdram_rdata,
    output logic [7:0]   vga_sdram_rtag,

    // Connection to the SDRAM controller
    output logic         sdram_req,
    input  logic         sdram_ack,
    output logic         sdram_write,
    output logic [25:0]  sdram_addr,
    output logic [127:0] sdram_wdata,
    output logic [15:0]  sdram_wstrb,
    output logic [9:0]   sdram_tag,
    input  logic [1:0]   sdram_rvalid,
    input  logic [31:0]  sdram_rdata,
    input  logic [9:0]   sdram_rtag 
);

logic         next_sdram_req;
logic         next_sdram_write;
logic [25:0]  next_sdram_addr;
logic [127:0] next_sdram_wdata;
logic [15:0]  next_sdram_wmask;
logic [9:0]   next_sdram_tag;

logic         queue_sdram_req,   next_queue_sdram_req;
logic         queue_sdram_write, next_queue_sdram_write;
logic [25:0]  queue_sdram_addr,  next_queue_sdram_addr;
logic [127:0] queue_sdram_wdata, next_queue_sdram_wdata;
logic [15:0]  queue_sdram_wmask, next_queue_sdram_wmask;
logic [9:0]   queue_sdram_tag,   next_queue_sdram_tag;

logic         new_sdram_req;
logic         new_sdram_write;
logic [25:0]  new_sdram_addr;
logic [127:0] new_sdram_wdata;
logic [15:0]  new_sdram_wmask;
logic [9:0]   new_sdram_tag;


always_comb begin
    dcache_sdramw_ack = 1'b0;
    dcache_sdramr_ack = 1'b0;
    icache_sdram_ack = 1'b0;
    vga_sdram_ack = 1'b0;

    // If the SDRAM is ready then shift the new request through, otherwise hold it in the queue
    if (sdram_ack) begin
        next_sdram_req = queue_sdram_req;
        next_sdram_write = queue_sdram_write;
        next_sdram_addr = queue_sdram_addr;
        next_sdram_wdata = queue_sdram_wdata;
        next_sdram_wmask = queue_sdram_wmask;
        next_sdram_tag = queue_sdram_tag;
        next_queue_sdram_req = 1'b0;
        next_queue_sdram_write = 1'bx;
        next_queue_sdram_addr = 26'bx;
        next_queue_sdram_wdata = 128'bx;
        next_queue_sdram_wmask = 16'bx;
        next_queue_sdram_tag = 10'bx;

    end else begin
        next_sdram_req = sdram_req;
        next_sdram_write = sdram_write;
        next_sdram_addr = sdram_addr;
        next_sdram_wdata = sdram_wdata;
        next_sdram_wmask = sdram_wstrb;
        next_sdram_tag = sdram_tag;
        next_queue_sdram_req = queue_sdram_req;
        next_queue_sdram_write = queue_sdram_write;
        next_queue_sdram_addr = queue_sdram_addr;
        next_queue_sdram_wdata = queue_sdram_wdata;
        next_queue_sdram_wmask = queue_sdram_wmask;
        next_queue_sdram_tag = queue_sdram_tag;
    end

    // Determine new request based on priority (dcache > icache > vga)
    if (queue_sdram_req) begin
        // There is already a request in the queue, so we can't accept a new one
        new_sdram_req = 1'b0;
        new_sdram_write = 1'bx;
        new_sdram_addr = 26'bx;
        new_sdram_wdata = 128'bx;
        new_sdram_wmask = 16'bx;
        new_sdram_tag = 10'bx;

    end else if (vga_sdram_req) begin
        // Accept request from vga
        vga_sdram_ack = 1'b1;
        new_sdram_req = 1'b1;
        new_sdram_write = 1'b0;
        new_sdram_addr = vga_sdram_addr;
        new_sdram_wdata = 128'bx;
        new_sdram_wmask = 16'bx;
        new_sdram_tag = {2'b10, vga_sdram_tag[7:0]};

    end else if (dcache_sdramw_req) begin
        // Accept request from dcache
        new_sdram_req = 1'b1;
        new_sdram_write = 1'b1;
        new_sdram_addr = dcache_sdramw_addr;
        new_sdram_wdata = dcache_sdramw_data;
        new_sdram_wmask = dcache_sdramw_strb;
        new_sdram_tag = 10'bx;
        dcache_sdramw_ack = 1'b1;

    end else if (dcache_sdramr_req) begin
        // Accept request from dcache
        new_sdram_req = 1'b1;
        new_sdram_write = 1'b0;
        new_sdram_addr = dcache_sdramr_addr;
        new_sdram_wdata = 128'bx;
        new_sdram_wmask = 16'bx;
        new_sdram_tag = 10'h1xx;
        dcache_sdramr_ack = 1'b1;

    end else if (icache_sdram_req) begin
        // Accept request from icache
        icache_sdram_ack = 1'b1;
        new_sdram_req = 1'b1;
        new_sdram_write = 1'b0;
        new_sdram_addr = icache_sdram_addr;
        new_sdram_wdata = 128'bx;
        new_sdram_wmask = 16'bx;
        new_sdram_tag = 10'h0xx;

    end else begin
        // No new request
        new_sdram_req = 1'b0;
        new_sdram_write = 1'bx;
        new_sdram_addr = 26'bx;
        new_sdram_wdata = 128'bx;
        new_sdram_wmask = 16'bx;
        new_sdram_tag = 10'bx;
    end

    // Send new request to SDRAM, or add it to the queue
    if (new_sdram_req && !sdram_req) begin
        // SDRAM is idle, so we can send the new request directly
        next_sdram_req = new_sdram_req;
        next_sdram_write = new_sdram_write;
        next_sdram_addr = new_sdram_addr;
        next_sdram_wdata = new_sdram_wdata;
        next_sdram_wmask = new_sdram_wmask;
        next_sdram_tag = new_sdram_tag;
    end else if (new_sdram_req) begin
        // SDRAM is busy, so we need to queue the new request
        next_queue_sdram_req = new_sdram_req;
        next_queue_sdram_write = new_sdram_write;
        next_queue_sdram_addr = new_sdram_addr;
        next_queue_sdram_wdata = new_sdram_wdata;
        next_queue_sdram_wmask = new_sdram_wmask;
        next_queue_sdram_tag = new_sdram_tag;
    end

    // Reset
    if (reset) begin
        next_queue_sdram_req = 1'b0;
        next_sdram_req = 1'b0;
    end
end


// Route read data back to the correct client based on the tag
always_comb begin
    dcache_sdramr_rvalid = 2'b0;
    dcache_sdramr_rdata = 32'bx;
    icache_sdram_rvalid = 2'b0;
    icache_sdram_rdata = 32'bx;
    vga_sdram_rvalid = 2'b0;
    vga_sdram_rdata = 32'bx;
    vga_sdram_rtag = 8'bx;

    if (sdram_rtag[9:8] == 2'h0) begin
        // Response for icache
        icache_sdram_rvalid = sdram_rvalid;
        icache_sdram_rdata = sdram_rdata;
    end else if (sdram_rtag[9:8] == 2'h1) begin
        // Response for dcache
        dcache_sdramr_rvalid = sdram_rvalid;
        dcache_sdramr_rdata = sdram_rdata;
    end else if (sdram_rtag[9:8] == 2'h2) begin
        // Response for vga  
        vga_sdram_rvalid = sdram_rvalid;
        vga_sdram_rdata = sdram_rdata;
        vga_sdram_rtag = sdram_rtag[7:0];
    end

end


always_ff @(posedge clock) begin
    sdram_req <= next_sdram_req;
    sdram_write <= next_sdram_write;
    sdram_addr <= next_sdram_addr;
    sdram_wdata <= next_sdram_wdata;
    sdram_wstrb <= next_sdram_wmask;
    sdram_tag <= next_sdram_tag;
    queue_sdram_req <= next_queue_sdram_req;
    queue_sdram_write <= next_queue_sdram_write;
    queue_sdram_addr <= next_queue_sdram_addr;
    queue_sdram_wdata <= next_queue_sdram_wdata;
    queue_sdram_wmask <= next_queue_sdram_wmask;
    queue_sdram_tag <= next_queue_sdram_tag;
end

endmodule
