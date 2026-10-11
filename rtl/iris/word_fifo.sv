`timescale 1ns/1ns

// A generic 32 entry deep FIFO for words (60 bits wide)

module word_fifo(
    input  logic         clock,
    input  logic         reset,

    // Write interface
    input  logic         write_enable,
    output logic         fifo_nearly_full,
    input  logic [59:0]  write_data,

    // Read interface
    input  logic         read_enable,
    output logic         read_valid,    
    output logic [59:0]  read_data
);

logic [59:0] ram[0:31];
logic [4:0]  write_ptr;
logic [4:0]  read_ptr;

wire [4:0]  inc_write_ptr = write_ptr + 5'd1;
wire [4:0]  inc_read_ptr = read_ptr + 5'd1;

wire [4:0]   slots_free = read_ptr - inc_write_ptr;
assign fifo_nearly_full = (slots_free <= 5'd3);

wire [4:0] next_read_ptr = (read_enable && read_valid) ? inc_read_ptr : read_ptr;

always_ff @(posedge clock) begin

    // Write logic
    if (write_enable) begin
        ram[write_ptr] <= write_data;
        write_ptr <= inc_write_ptr;
    end

    // Read logic
    read_data <= ram[next_read_ptr];
    read_valid <= (write_ptr != next_read_ptr);
    read_ptr <= next_read_ptr;

    if (reset) begin
        write_ptr <= 5'd0;
        read_ptr  <= 5'd0;
        read_valid <= 1'b0;
    end
end
endmodule
