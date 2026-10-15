`timescale 1ns/1ns

// RAM access module for the Iris system
// 
// Arbitrates access to the SDRAM between the iris sub-modules that require memory access.

module iris_ram_access(
    input logic clock,
    input logic reset,

    // Connections to iris_readmem block
    output logic         readmem_sdram_ready,    // SDRAM is ready for a req_valid
    input  logic         readmem_sdram_req,      // Request memory
    input  logic [25:0]  readmem_sdram_addr,     // Address
    input  logic [5:0]   readmem_sdram_tag,      // Tag to identify request
    output logic [1:0]   readmem_sdram_rvalid,   // 00:No data, 01:First word, 10:Mid burst, 11:Last word
    output logic [31:0]  readmem_sdram_rdata,    // Read data
    output logic [5:0]   readmem_sdram_rtag,      // Tag identifying which request this data is for

    // connections to iris_objfetch
    output logic         objfetch_sdram_ready,    // SDRAM is ready for a req_valid
    input  logic         objfetch_sdram_req,      // Request memory
    input  logic [25:0]  objfetch_sdram_addr,     // Address
    input  logic [5:0]   objfetch_sdram_tag,      // Tag to identify request
    output logic [1:0]   objfetch_sdram_rvalid,   // 00:No data, 01:First word, 10:Mid burst, 11:Last word
    output logic [31:0]  objfetch_sdram_rdata,    // Read data
    output logic [5:0]   objfetch_sdram_rtag,      // Tag identifying which request this data is for

    // connections to iris_copper
    output logic         copper_sdram_ready,    // SDRAM is ready for a req_valid
    input  logic         copper_sdram_req,      // Request memory
    input  logic [25:0]  copper_sdram_addr,     // Address
    input  logic [5:0]   copper_sdram_tag,      // Tag to identify request
    output logic [1:0]   copper_sdram_rvalid,   // 00:No data, 01:First word, 10:Mid burst, 11:Last word
    output logic [31:0]  copper_sdram_rdata,    // Read data
    output logic [5:0]   copper_sdram_rtag,      // Tag identifying which request this data is for

    // connections to the sdram
    input  logic         vga_sdram_ack,      // SDRAM is ready for a req_valid
    output logic         vga_sdram_req,      // Request memory
    output logic [25:0]  vga_sdram_addr,     // Address
    output logic [7:0]   vga_sdram_tag,      // Tag to identify request
    input  logic [1:0]   vga_sdram_rvalid,   // 00:No data, 01:First word, 10:Mid burst, 11:Last word
    input  logic [31:0]  vga_sdram_rdata,    // Read data
    input  logic [7:0]   vga_sdram_rtag       // Tag identifying which request this data is for
);

logic         next_sdram_req;
logic [25:0]  next_sdram_addr;
logic [7:0]   next_sdram_tag;

// Mux to select which module gets access to the SDRAM
always_comb begin
    next_sdram_req = 1'b0;
    next_sdram_addr = 26'bx;
    next_sdram_tag = 8'bx;
    readmem_sdram_ready = 1'b0;
    objfetch_sdram_ready = 1'b0;
    copper_sdram_ready = 1'b0;

    if (vga_sdram_req==1'b0) begin
        if (readmem_sdram_req) begin
            readmem_sdram_ready = 1'b1;
            next_sdram_req = 1'b1;
            next_sdram_addr = readmem_sdram_addr;
            next_sdram_tag = {2'b00,readmem_sdram_tag};
        end else if (objfetch_sdram_req) begin
            objfetch_sdram_ready = 1'b1;
            next_sdram_req = 1'b1;
            next_sdram_addr = objfetch_sdram_addr;
            next_sdram_tag = {2'b01,objfetch_sdram_tag};
        end else if (copper_sdram_req) begin
            copper_sdram_ready = 1'b1;
            next_sdram_req = 1'b1;
            next_sdram_addr = copper_sdram_addr;
            next_sdram_tag = {2'b10,copper_sdram_tag};
        end
    end
end



always_ff @(posedge clock) begin
    // Send requests to the SDRAM
    if (reset || vga_sdram_ack) begin
        vga_sdram_req <= 1'b0;
        vga_sdram_addr <= 26'bx;
        vga_sdram_tag <= 8'bx;
    end else if (next_sdram_req) begin
        vga_sdram_req <= next_sdram_req;
        vga_sdram_addr <= next_sdram_addr;
        vga_sdram_tag <= next_sdram_tag;
    end

    // Pass the read data and valid signals back to the requesting module
    readmem_sdram_rvalid <= 2'b00;
    objfetch_sdram_rvalid <= 2'b00;
    copper_sdram_rvalid <= 2'b00;
    readmem_sdram_rdata <= 32'bx;
    objfetch_sdram_rdata <= 32'bx;
    copper_sdram_rdata <= 32'bx;
    readmem_sdram_rtag <= 6'bx;
    objfetch_sdram_rtag <= 6'bx;
    copper_sdram_rtag <= 6'bx;


    if (vga_sdram_rvalid != 2'b00) begin
        case (vga_sdram_rtag[7:6])
            2'b00: begin
                readmem_sdram_rvalid <= vga_sdram_rvalid;
                readmem_sdram_rdata <= vga_sdram_rdata;
                readmem_sdram_rtag <= vga_sdram_rtag[5:0];
            end
            2'b01: begin
                objfetch_sdram_rvalid <= vga_sdram_rvalid;
                objfetch_sdram_rdata <= vga_sdram_rdata;
                objfetch_sdram_rtag <= vga_sdram_rtag[5:0];
            end
            2'b10: begin
                copper_sdram_rvalid <= vga_sdram_rvalid;
                copper_sdram_rdata <= vga_sdram_rdata;
                copper_sdram_rtag <= vga_sdram_rtag[5:0];
            end
            default: begin
                // Do nothing for unknown tags
            end
        endcase
    end

end


endmodule
