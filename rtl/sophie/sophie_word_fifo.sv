`timescale 1ns / 1ps

// Word FIFO module for buffering 32-bit words

module sophie_word_fifo (
    input  logic        clock,
    input  logic        reset,

    input  logic [31:0] write_data,
    input  logic        write_en,

    output logic [31:0] read_data,
    output logic        read_valid,
    input  logic        read_en,

    output logic [5:0]  slots_free
);

logic [4:0]  rd_ptr, next_rd_ptr;
logic [4:0]  wr_ptr, next_wr_ptr;

regfile_ram  regfile_ram_inst (
    .clock(clock),
    .data(write_data),
    .rdaddress(rd_ptr),
    .wraddress(wr_ptr),
    .wren(write_en),
    .q(read_data)
  );

always_comb begin
    next_wr_ptr = wr_ptr;
    next_rd_ptr = rd_ptr;
    read_valid = (wr_ptr != rd_ptr);
    slots_free = 32 - (wr_ptr - rd_ptr);

    if (write_en)
        next_wr_ptr = wr_ptr + 1;
    if (read_en)
        next_rd_ptr = rd_ptr + 1;
    if (reset) begin
        next_wr_ptr = 0;
        next_rd_ptr = 0;
    end
end

always_ff @(posedge clock) begin
    wr_ptr <= next_wr_ptr;
    rd_ptr <= next_rd_ptr;
end

endmodule
