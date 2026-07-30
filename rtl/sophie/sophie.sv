`timescale 1ns/1ns

// Top level module for the SOPHIE (System Organision and Peripheral Hardware IntEgration) 

module sophie (
    input logic         clock,
    input logic         reset,

    // CPU bus
    input  logic        cpu_aux_req,        // Request to read/write the data memory
    input  logic        cpu_aux_write,      // Indicates a write operation to the data memory
    input  logic [31:0] cpu_aux_addr,       // Address for the read/write
    input  logic [31:0] cpu_aux_wdata,      // Data to be written to the data memory
    input  logic [3:0]  cpu_aux_strb,       // Byte enable signals (For both read and write)
    input  logic [4:0]  cpu_aux_dest,       // Destination register for a load
    output logic        cpu_aux_rvalid,     // Indicates that the data read from the data memory is valid
    output logic [31:0] cpu_aux_rdata,      // Data read from the data memory
    output logic [4:0]  cpu_aux_rdest,      // Destination register for the instruction in stage 3

    // Instruction memory
    output logic        aux_irom_req,        // Request to read/write the instruction memory
    output logic        aux_irom_write,      // Indicates a write operation to the instruction memory
    output logic [15:0] aux_irom_addr,       // Address for the read/write operation
    output logic [31:0] aux_irom_wdata,      // Data to be written to the instruction memory
    input  logic [31:0] aux_irom_rdata,      // Data read from the instruction memory

    // Iris bus  (write only)
    output logic        aux_iris_req,        // Request to read/write the Iris memory
    output logic [15:0] aux_iris_addr,       // Address for the read/write operation
    output logic [31:0] aux_iris_wdata,      // Data to be written to the Iris memory
    input  logic [9:0]  ypos,                // Current Y position of the rasterizer (for debug)

    // Chip pins
    output logic [6:0]	HEX0,
  	output logic [6:0]	HEX1,
  	output logic [6:0]	HEX2,
  	output logic [6:0]	HEX3,
  	output logic [6:0]	HEX4,
  	output logic [6:0]	HEX5,
  	input  logic [3:0]	KEY,
  	output logic [9:0]	LEDR,
    input  logic [9:0]  SW,
    output logic        UART_TX,
    input  logic        UART_RX,
    inout               PS2_CLK,
    inout               PS2_DAT,
    inout               PS2_CLK2,
    inout               PS2_DAT2,
    inout               SDA,
    output              SCL,
    output logic [9:0]  mouse_x,
    output logic [9:0]  mouse_y,
    input  logic [31:0] cpu_pc             // Current CPU PC (for capture on seven seg)
);

logic        aux_hwregs_req;
logic        aux_hwregs_write;
logic [15:0] aux_hwregs_addr;
logic [31:0] aux_hwregs_wdata;
logic [3:0]  aux_hwregs_strb;
logic [31:0] aux_hwregs_rdata;


sophie_address_decoder  sophie_address_decoder_inst (
    .clock(clock),
    .reset(reset),
    .cpu_aux_req(cpu_aux_req),
    .cpu_aux_write(cpu_aux_write),
    .cpu_aux_addr(cpu_aux_addr),
    .cpu_aux_wdata(cpu_aux_wdata),
    .cpu_aux_strb(cpu_aux_strb),
    .cpu_aux_dest(cpu_aux_dest),
    .cpu_aux_rvalid(cpu_aux_rvalid),
    .cpu_aux_rdata(cpu_aux_rdata),
    .cpu_aux_rdest(cpu_aux_rdest),
    .aux_hwregs_req(aux_hwregs_req),
    .aux_hwregs_write(aux_hwregs_write),
    .aux_hwregs_addr(aux_hwregs_addr),
    .aux_hwregs_wdata(aux_hwregs_wdata),
    .aux_hwregs_strb(aux_hwregs_strb),
    .aux_hwregs_rdata(aux_hwregs_rdata),
    .aux_irom_req(aux_irom_req),
    .aux_irom_write(aux_irom_write),
    .aux_irom_addr(aux_irom_addr),
    .aux_irom_wdata(aux_irom_wdata),
    .aux_irom_rdata(aux_irom_rdata),
    .aux_iris_req(aux_iris_req),
    .aux_iris_addr(aux_iris_addr),
    .aux_iris_wdata(aux_iris_wdata)
  );

sophie_hwregs  sophie_hwregs_inst (
    .clock(clock),
    .reset(reset),
    .aux_hwregs_req(aux_hwregs_req),
    .aux_hwregs_write(aux_hwregs_write),
    .aux_hwregs_addr(aux_hwregs_addr),
    .aux_hwregs_strb(aux_hwregs_strb),
    .aux_hwregs_wdata(aux_hwregs_wdata),
    .aux_hwregs_rdata(aux_hwregs_rdata),
    .ypos(ypos),
    .HEX0(HEX0),
    .HEX1(HEX1),
    .HEX2(HEX2),
    .HEX3(HEX3),
    .HEX4(HEX4),
    .HEX5(HEX5),
    .KEY(KEY),
    .LEDR(LEDR),
    .SW(SW),
    .UART_TX(UART_TX),
    .UART_RX(UART_RX),
    .PS2_CLK(PS2_CLK),
    .PS2_DAT(PS2_DAT),
    .PS2_CLK2(PS2_CLK2),
    .PS2_DAT2(PS2_DAT2),
    .SDA(SDA),
    .SCL(SCL),
    .mouse_x(mouse_x),
    .mouse_y(mouse_y),
    .cpu_pc(cpu_pc)
  );

endmodule
