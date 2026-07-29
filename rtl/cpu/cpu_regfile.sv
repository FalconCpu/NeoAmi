`timescale 1ns/1ns

// CPU register file module
// This module implements the register file for the CPU. It also handles
// register forwarding and intermediate muxing

module cpu_regfile (
    input logic         clock,

    // Connections from the decoder module
    input logic [4:0]   p2_rs1,            // Source register 1
    input logic [4:0]   p2_rs2,            // Source register 2
    input logic         p2_use_immediate,  // Indicates that the instruction uses an immediate value for rs2
    input logic [31:0]  p2_immediate,      // Immediate value for the instruction

    // Forwarding from the ALU
    input logic         p3_is_alu,         // Indicates that the instruction is an ALU operation
    input logic [4:0]   p3_rd,             // Destination register for the instruction in stage 3
    input logic [31:0]  p3_alu_result,     // Result from the ALU operation

    // Forwarding from writeback
    input logic         p4_wren,           // Indicates that the destination register is valid
    input logic [4:0]   p4_rd,             // Destination register for the
    input logic [31:0]  p4_result,         // Data to write back to the register file

    // Outputs to the datapath
    output logic [31:0] p3_data_a,         // Data from source
    output logic [31:0] p3_data_b          // Data from source
);

// Instantiate register memories
wire wren = p4_wren && (p4_rd != 5'h0);
wire [31:0] data_a, data_b;

regfile_ram  regfile_ram_inst_a (
    .clock(clock),
    .wren(wren),
    .wraddress(p4_rd),
    .data(p4_result),
    .rdaddress(p2_rs1),
    .q(data_a)
  );

regfile_ram  regfile_ram_inst_b (
    .clock(clock),
    .wren(wren),
    .wraddress(p4_rd),
    .data(p4_result),
    .rdaddress(p2_rs2),
    .q(data_b)
  );

always_ff @(posedge clock) begin

    // Forwarding logic for source A
    if (p3_is_alu && (p3_rd == p2_rs1) && (p2_rs1 != 5'h0)) 
        p3_data_a <= p3_alu_result;
    else if (p4_wren && (p4_rd == p2_rs1) && (p2_rs1 != 5'h0)) 
        p3_data_a <= p4_result;
    else
        p3_data_a <= data_a;
    
    // Forwarding logic for source B
    if (p2_use_immediate)
        p3_data_b <= p2_immediate;
    else if (p3_is_alu && (p3_rd == p2_rs2) && (p2_rs2 != 5'h0))
        p3_data_b <= p3_alu_result;
    else if (p4_wren && (p4_rd == p2_rs2) && (p2_rs2 != 5'h0))
        p3_data_b <= p4_result;
    else
        p3_data_b <= data_b; // Read from register file
end

// synthesis translate_off
integer fh;
initial begin
    fh = $fopen("rtl_reg.log", "w");    
    if (fh == 0) begin
        $display("Error: Could not open regfile.log for writing");
        $finish;
    end
end

always_ff @(posedge clock) begin
    if (wren)
        $fwrite(fh, "$%d = %08x\n", p4_rd, p4_result);
end

// For debugging - keep a copy of each register in a separate array for easy viewing in waveform viewers
reg [31:0] reg_1, reg_2, reg_3, reg_4, reg_5, reg_6, reg_7, reg_8;
reg [31:0] reg_9, reg_10, reg_11, reg_12, reg_13, reg_14, reg_15;
reg [31:0] reg_16, reg_17, reg_18, reg_19, reg_20, reg_21, reg_22, reg_23;
reg [31:0] reg_24, reg_25, reg_26, reg_27, reg_28, reg_29, reg_30, reg_31;
always_ff @(posedge clock) begin
    if (wren) begin
        case (p4_rd)
            5'h0: begin end
            5'h1: reg_1 <= p4_result;
            5'h2: reg_2 <= p4_result;
            5'h3: reg_3 <= p4_result;
            5'h4: reg_4 <= p4_result;
            5'h5: reg_5 <= p4_result;
            5'h6: reg_6 <= p4_result;
            5'h7: reg_7 <= p4_result;
            5'h8: reg_8 <= p4_result;
            5'h9: reg_9 <= p4_result;
            5'ha: reg_10 <= p4_result;
            5'hb: reg_11 <= p4_result;
            5'hc: reg_12 <= p4_result;
            5'hd: reg_13 <= p4_result;
            5'he: reg_14 <= p4_result;
            5'hf: reg_15 <= p4_result;
            5'h10: reg_16 <= p4_result;
            5'h11: reg_17 <= p4_result;
            5'h12: reg_18 <= p4_result;
            5'h13: reg_19 <= p4_result;
            5'h14: reg_20 <= p4_result;
            5'h15: reg_21 <= p4_result;
            5'h16: reg_22 <= p4_result;
            5'h17: reg_23 <= p4_result;
            5'h18: reg_24 <= p4_result;
            5'h19: reg_25 <= p4_result;
            5'h1a: reg_26 <= p4_result;
            5'h1b: reg_27 <= p4_result;
            5'h1c: reg_28 <= p4_result;
            5'h1d: reg_29 <= p4_result;
            5'h1e: reg_30 <= p4_result;
            5'h1f: reg_31 <= p4_result;            
        endcase
    end
end

wire unused = &{reg_1, reg_2, reg_3, reg_4, reg_5, reg_6, reg_7, reg_8,
                reg_9, reg_10, reg_11, reg_12, reg_13, reg_14, reg_15,
                reg_16, reg_17, reg_18, reg_19, reg_20, reg_21, reg_22,
                reg_23, reg_24, reg_25, reg_26, reg_27, reg_28, reg_29,
                reg_30, reg_31};

// synthesis translate_on
endmodule
