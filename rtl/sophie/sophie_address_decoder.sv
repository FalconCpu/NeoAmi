`timescale 1ns/1ns

// SOPHIE (System Organision and Peripheral Hardware IntEgration)
//
// This module implements glue logic for the System on a Chip. 

module sophie_address_decoder (
    input logic         clock,
    input logic         reset,

    // CPU bus - allows CPU to read/write to the auxiliary memory and peripherals
    input  logic        cpu_aux_req,        // Request to read/write the data memory
    input  logic        cpu_aux_write,      // Indicates a write operation to the data memory
    input  logic [31:0] cpu_aux_addr,       // Address for the read/write
    input  logic [31:0] cpu_aux_wdata,      // Data to be written to the data memory
    input  logic [3:0]  cpu_aux_strb,       // Byte enable signals (For both read and write)
    input  logic [4:0]  cpu_aux_dest,       // Destination register for a load
    output logic        cpu_aux_rvalid,     // Indicates that the data read from the data memory is valid
    output logic [31:0] cpu_aux_rdata,      // Data read from the data memory
    output logic [4:0]  cpu_aux_rdest,      // Destination register for the instruction in stage 3

    // Copper bus - allow Copper tp write to peripheral memory
    input  logic        copper_aux_req,
    output logic        copper_aux_ack,
    input  logic [19:0] copper_aux_addr,    // Copper can only access MMIO space (Implicit 0xE00 on top of the address)
    input  logic [31:0] copper_aux_wdata,

    // Sophie peripherals
    output logic        aux_hwregs_req,      // Request to read/write the hardware registers
    output logic        aux_hwregs_write,    // Indicates a write operation to the hardware registers
    output logic [15:0] aux_hwregs_addr,     // Address for the read/write
    output logic [31:0] aux_hwregs_wdata,    // Data to be written to the hardware registers
    output logic [3:0]  aux_hwregs_strb,     // Byte enable signals (For both read and write)
    input  logic [31:0] aux_hwregs_rdata,    // Data read from the hardware registers

    // IRIS bus  (write only)
    output logic        aux_iris_req,        // Request to read/write the Iris memory
    output logic [15:0] aux_iris_addr,       // Address for the read/write operation
    output logic [31:0] aux_iris_wdata,      // Data to be written to the Iris memory

    // Gemma bus (read/write)
    output logic        aux_gemma_req,       // Request to read/write the Gemma memory
    output logic        aux_gemma_write,     // Indicates a write operation to the Gemma memory
    output logic [15:0] aux_gemma_addr,      // Address for the read/write operation
    output logic [31:0] aux_gemma_wdata,     // Data to be written to the Gemma memory
    input  logic [31:0] aux_gemma_rdata,     // Data read from the Gemma memory

    // Instruction memory
    output logic        aux_irom_req,        // Request to read/write the instruction memory
    output logic        aux_irom_write,      // Indicates a write operation to the instruction memory
    output logic [15:0] aux_irom_addr,       // Address for the read/write operation
    output logic [31:0] aux_irom_wdata,      // Data to be written to the instruction memory
    input  logic [31:0] aux_irom_rdata       // Data read from the instruction memory
);

logic [4:0] dest_dly1, dest_dly2;
logic [3:0] strb_dly1, strb_dly2;
logic       rvalid_dly1, rvalid_dly2;

logic [31:0] rdata;

// CPU has precedence over Copper for accessing the auxiliary memory and peripherals
logic        aux_req;
logic [31:0] aux_addr;
logic        aux_write;
logic [31:0] aux_wdata;
logic [3:0]  aux_strb;

always_comb begin
    copper_aux_ack = 1'b0;

    if (cpu_aux_req) begin
        aux_req   = 1'b1;
        aux_addr  = cpu_aux_addr;
        aux_write = cpu_aux_write;
        aux_wdata = cpu_aux_wdata;
        aux_strb  = cpu_aux_strb;
    end else if (copper_aux_req) begin
        aux_req   = 1'b1;
        aux_addr  = {12'hE00, copper_aux_addr};
        aux_wdata = copper_aux_wdata;
        aux_write = 1'b1; // Copper can only write whole words
        aux_strb  = 4'hf; 
        copper_aux_ack = copper_aux_req && !cpu_aux_req;
    end else begin
        aux_req   = 1'b0;
        aux_addr  = 32'bx;
        aux_write = 1'bx;
        aux_wdata = 32'bx;
        aux_strb  = 4'bx;
    end
end



always_ff @(posedge clock) begin
    // Default values for the outputs
    aux_hwregs_req <= 1'b0;
    aux_hwregs_write <= 1'bx;
    aux_hwregs_addr <= 16'bx;
    aux_hwregs_wdata <= 32'bx;
    aux_hwregs_strb <= 4'bx;
    aux_irom_req <= 1'b0;
    aux_irom_write <= 1'bx;
    aux_irom_addr <= 16'bx;
    aux_irom_wdata <= 32'bx;
    aux_iris_req <= 1'b0;
    aux_iris_addr <= 16'bx;
    aux_iris_wdata <= 32'bx;
    aux_gemma_req <= 1'b0;
    aux_gemma_write <= 1'bx;
    aux_gemma_addr <= 16'bx;
    aux_gemma_wdata <= 32'bx;

    // Delay the destination register and byte enable signals by 2 cycles to match the
    // latency of the memory read operations. 
    cpu_aux_rvalid <= rvalid_dly2;
    rvalid_dly2    <= rvalid_dly1;
    rvalid_dly1    <= cpu_aux_req && !cpu_aux_write;
    cpu_aux_rdest  <= dest_dly2;
    dest_dly2      <= dest_dly1;
    dest_dly1      <= cpu_aux_dest;
    strb_dly2      <= strb_dly1;
    strb_dly1      <= cpu_aux_strb;

    // Combine the data read from the various sources
    // And apply the byte enables
    // verilator lint_off BLKSEQ
    rdata = aux_hwregs_rdata | aux_irom_rdata | aux_gemma_rdata;
    case (strb_dly2)
        4'b0001: cpu_aux_rdata <= {{24{rdata[7]}}, rdata[7:0]};
        4'b0010: cpu_aux_rdata <= {{24{rdata[15]}}, rdata[15:8]};
        4'b0100: cpu_aux_rdata <= {{24{rdata[23]}}, rdata[23:16]};
        4'b1000: cpu_aux_rdata <= {{24{rdata[31]}}, rdata[31:24]};
        4'b0011: cpu_aux_rdata <= {{16{rdata[15]}}, rdata[15:0]};
        4'b1100: cpu_aux_rdata <= {{16{rdata[31]}}, rdata[31:16]};
        4'b1111: cpu_aux_rdata <= rdata;
        default: cpu_aux_rdata <= 32'bx; // Invalid byte enable
    endcase 

    // Route the requests to the appropriate peripheral
    if (aux_req && !reset) begin
        if (aux_addr[31:16] == 16'hE000) begin
            // Route to the Sophie hardware registers
            aux_hwregs_req <= 1'b1;
            aux_hwregs_write <= aux_write;
            aux_hwregs_addr <= aux_addr[15:0];
            aux_hwregs_wdata <= aux_wdata;
            aux_hwregs_strb <= aux_strb;
        end else if (aux_addr[31:16] == 16'hE001) begin
            // Route to the Iris memory
            aux_iris_req <= 1'b1;
            aux_iris_addr <= aux_addr[15:0];
            aux_iris_wdata <= aux_wdata;
        end else if (aux_addr[31:16] == 16'hE002) begin
            // Route to GEMMA
            aux_gemma_req <= 1'b1;
            aux_gemma_write <= aux_write;
            aux_gemma_addr <= aux_addr[15:0];
            aux_gemma_wdata <= aux_wdata;
        end else if (aux_addr[31:16] == 16'hFFFF) begin
            // Route to the instruction memory
            aux_irom_req <= 1'b1;
            aux_irom_write <= aux_write;
            aux_irom_addr <= aux_addr[15:0];
            aux_irom_wdata <= aux_wdata;
        end else begin
            // Invalid address range, ignore the request
        end
    end


end
endmodule
