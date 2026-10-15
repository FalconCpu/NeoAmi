`timescale 1ns/1ns

// SDRAM Arbiter
// Priority: vga > audio > dcache > icache > gemma

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

    // Connection to gemma (read/write, does need tags)
    input  logic         gemma_sdram_req,
    input  logic         gemma_sdram_write,
    output logic         gemma_sdram_ack,
    input  logic [127:0] gemma_sdram_wdata,
    input  logic [15:0]  gemma_sdram_strb,
    input  logic [7:0]   gemma_sdram_tag,
    input  logic [25:0]  gemma_sdram_addr,
    output logic [1:0]   gemma_sdram_rvalid,
    output logic [7:0]   gemma_sdram_rtag,
    output logic [31:0]  gemma_sdram_rdata,

    // Connection to audio (read only)
    input  logic         audio_sdram_req,
    output logic         audio_sdram_ready,
    input  logic [25:0]  audio_sdram_address,
    output logic         audio_sdram_rvalid,
    output logic [25:0]  audio_sdram_raddress,
    output logic [31:0]  audio_sdram_rdata,
    output logic         audio_sdram_complete,


    // Connection to the SDRAM controller
    output logic         sdram_req,
    input  logic         sdram_ack,
    output logic         sdram_write,
    output logic [25:0]  sdram_addr,
    output logic [127:0] sdram_wdata,
    output logic [15:0]  sdram_wstrb,
    output logic [10:0]  sdram_tag,
    input  logic [1:0]   sdram_rvalid,
    input  logic [31:0]  sdram_rdata,
    input  logic [10:0]  sdram_rtag,
    input  logic [25:0]  sdram_raddress
);

logic         next_sdram_req;
logic         next_sdram_write;
logic [25:0]  next_sdram_addr;
logic [127:0] next_sdram_wdata;
logic [15:0]  next_sdram_wmask;
logic [10:0]  next_sdram_tag;

logic         queue_sdram_req,   next_queue_sdram_req;
logic         queue_sdram_write, next_queue_sdram_write;
logic [25:0]  queue_sdram_addr,  next_queue_sdram_addr;
logic [127:0] queue_sdram_wdata, next_queue_sdram_wdata;
logic [15:0]  queue_sdram_wmask, next_queue_sdram_wmask;
logic [10:0]  queue_sdram_tag,   next_queue_sdram_tag;

logic         new_sdram_req;
logic         new_sdram_write;
logic [25:0]  new_sdram_addr;
logic [127:0] new_sdram_wdata;
logic [15:0]  new_sdram_wmask;
logic [10:0]  new_sdram_tag;


always_comb begin
    dcache_sdramw_ack = 1'b0;
    dcache_sdramr_ack = 1'b0;
    icache_sdram_ack = 1'b0;
    gemma_sdram_ack = 1'b0;
    vga_sdram_ack = 1'b0;
    audio_sdram_ready = 1'b0;

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
        next_queue_sdram_tag = 11'bx;

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

    // Determine the highest-priority request that can be accepted.
    if (queue_sdram_req) begin
        // There is already a request in the queue, so we can't accept a new one
        new_sdram_req = 1'b0;
        new_sdram_write = 1'bx;
        new_sdram_addr = 26'bx;
        new_sdram_wdata = 128'bx;
        new_sdram_wmask = 16'bx;
        new_sdram_tag = 11'bx;

    end else if (vga_sdram_req) begin
        // Accept request from vga
        vga_sdram_ack = 1'b1;
        new_sdram_req = 1'b1;
        new_sdram_write = 1'b0;
        new_sdram_addr = vga_sdram_addr;
        new_sdram_wdata = 128'bx;
        new_sdram_wmask = 16'bx;
        new_sdram_tag = {3'b010, vga_sdram_tag[7:0]};

    end else if (audio_sdram_req) begin
        audio_sdram_ready = 1'b1;
        new_sdram_req = 1'b1;
        new_sdram_write = 1'b0;
        new_sdram_addr = audio_sdram_address;
        new_sdram_wdata = 128'bx;
        new_sdram_wmask = 16'bx;
        new_sdram_tag = {3'b100, 8'b0};

    end else if (dcache_sdramw_req) begin
        // Accept request from dcache
        new_sdram_req = 1'b1;
        new_sdram_write = 1'b1;
        new_sdram_addr = dcache_sdramw_addr;
        new_sdram_wdata = dcache_sdramw_data;
        new_sdram_wmask = dcache_sdramw_strb;
        new_sdram_tag = 11'bx;
        dcache_sdramw_ack = 1'b1;

    end else if (dcache_sdramr_req) begin
        // Accept request from dcache
        new_sdram_req = 1'b1;
        new_sdram_write = 1'b0;
        new_sdram_addr = dcache_sdramr_addr;
        new_sdram_wdata = 128'bx;
        new_sdram_wmask = 16'bx;
        new_sdram_tag = {3'b001, 8'b0};
        dcache_sdramr_ack = 1'b1;

    end else if (icache_sdram_req) begin
        // Accept request from icache
        icache_sdram_ack = 1'b1;
        new_sdram_req = 1'b1;
        new_sdram_write = 1'b0;
        new_sdram_addr = icache_sdram_addr;
        new_sdram_wdata = 128'bx;
        new_sdram_wmask = 16'bx;
        new_sdram_tag = {3'b000, 8'b0};

    end else if (gemma_sdram_req) begin
        // Accept request from gemma
        gemma_sdram_ack = 1'b1;
        new_sdram_req = 1'b1;
        new_sdram_write = gemma_sdram_write;
        new_sdram_addr = gemma_sdram_addr;
        new_sdram_wdata = gemma_sdram_wdata;
        new_sdram_wmask = gemma_sdram_strb;
        new_sdram_tag = {3'b011, gemma_sdram_tag};

    end else begin
        // No new request
        new_sdram_req = 1'b0;
        new_sdram_write = 1'bx;
        new_sdram_addr = 26'bx;
        new_sdram_wdata = 128'bx;
        new_sdram_wmask = 16'bx;
        new_sdram_tag = 11'bx;
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
    gemma_sdram_rvalid = 2'b0;
    gemma_sdram_rdata = 32'bx;
    gemma_sdram_rtag = 8'bx;
    audio_sdram_rvalid = 1'b0;
    audio_sdram_raddress = sdram_raddress;
    audio_sdram_rdata = 32'bx;
    audio_sdram_complete = 1'b0;

    if (sdram_rtag[10:8] == 3'b000) begin
        // Response for icache
        icache_sdram_rvalid = sdram_rvalid;
        icache_sdram_rdata = sdram_rdata;
    end else if (sdram_rtag[10:8] == 3'b001) begin
        // Response for dcache
        dcache_sdramr_rvalid = sdram_rvalid;
        dcache_sdramr_rdata = sdram_rdata;
    end else if (sdram_rtag[10:8] == 3'b010) begin
        // Response for vga  
        vga_sdram_rvalid = sdram_rvalid;
        vga_sdram_rdata = sdram_rdata;
        vga_sdram_rtag = sdram_rtag[7:0];
    end else if (sdram_rtag[10:8] == 3'b011) begin
        // Response for gemma  
        gemma_sdram_rvalid = sdram_rvalid;
        gemma_sdram_rdata = sdram_rdata;
        gemma_sdram_rtag = sdram_rtag[7:0];
    end else if (sdram_rtag[10:8] == 3'b100) begin
        audio_sdram_rvalid = |sdram_rvalid;
        audio_sdram_rdata = sdram_rdata;
        audio_sdram_complete = sdram_rvalid == 2'b11;
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
