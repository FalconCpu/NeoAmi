`timescale 1ns/1ns

// Generates an approximate reciprocal of the input value 'a' , 
// with approx 10 bits of precision. 
//
// To maximize the utilisation of the lookup table, we calculate the 
// first 3 bits algorithmically, and use the lookup table for the remaining 10 bits.

module gemma_fast_recip (
    input logic         clock,

    input logic         ts_recip_req,       // Someone is requesting a reciprocal
    input  logic [23:0] ts_recip_in,        // U12.12 fixed point format
    output logic        ts_recip_valid,     // We are ready to accept a new reciprocal request
    output logic [23:0] ts_recip_out        // U4.20 fixed point format (one cycle latency)
);

assign ts_recip_valid = 1'b1; // Always ready to accept a new request

// ===========================================================================
//                         Prioritize input requests
// ===========================================================================

logic        recip_req;
logic        recip_source;
logic [23:0] recip_in;
logic        p1_req;
logic        p1_source;
logic [23:0] p1_out;

always_comb begin
    if (ts_recip_req) begin
        recip_req = 1'b1;
        recip_source = 1'b0; // Triangle setup stage
        recip_in = ts_recip_in;
    end else begin
        recip_req = 1'b0;
        recip_source = 1'b0;
        recip_in = 24'd0;
    end
end

always_ff @(posedge clock) begin
    if (ts_recip_req)
        ts_recip_valid <= 1'b0;

    if (p1_req && p1_source == 1'b0) begin
        ts_recip_out <= p1_out;
        ts_recip_valid <= 1'b1;
    end
end


// ===========================================================================
//                         Lookup Table for Reciprocal Values
// ===========================================================================

logic [9:0] recip_lookup [0:1023];  // 10 bit lookup table for reciprocal values
initial
    $readmemh("recip_lookup.hex", recip_lookup);

// ===========================================================================
//                       Normalize Input Value
// ===========================================================================

logic [9:0] p0_index;
logic [3:0] p0_shift;
logic       p0_small;

always_comb begin
    p0_small = 1'b0;
    p0_index = 10'd0;
    p0_shift = 4'd0;
    casez(recip_in)
        24'b1???????????????????????: begin p0_index = recip_in[22:13];  p0_shift = 4'd0; end
        24'b01??????????????????????: begin p0_index = recip_in[21:12];  p0_shift = 4'd1; end
        24'b001?????????????????????: begin p0_index = recip_in[20:11];  p0_shift = 4'd2; end
        24'b0001????????????????????: begin p0_index = recip_in[19:10];  p0_shift = 4'd3; end
        24'b00001???????????????????: begin p0_index = recip_in[18:9];   p0_shift = 4'd4; end
        24'b000001??????????????????: begin p0_index = recip_in[17:8];   p0_shift = 4'd5; end
        24'b0000001?????????????????: begin p0_index = recip_in[16:7];   p0_shift = 4'd6; end
        24'b00000001????????????????: begin p0_index = recip_in[15:6];   p0_shift = 4'd7; end
        24'b000000001???????????????: begin p0_index = recip_in[14:5];   p0_shift = 4'd8; end
        24'b0000000001??????????????: begin p0_index = recip_in[13:4];   p0_shift = 4'd9; end
        24'b00000000001?????????????: begin p0_index = recip_in[12:3];   p0_shift = 4'd10; end
        24'b000000000001????????????: begin p0_index = recip_in[11:2];   p0_shift = 4'd11; end
        24'b0000000000001???????????: begin p0_index = recip_in[10:1];   p0_shift = 4'd12; end
        24'b00000000000001??????????: begin p0_index = recip_in[9:0];    p0_shift = 4'd13; end
        24'b000000000000001?????????: begin p0_index = {recip_in[8:0], 1'b0}; p0_shift = 4'd14; end
        24'b0000000000000001????????: begin p0_index = {recip_in[7:0], 2'b00}; p0_shift = 4'd15; end
        default: p0_small = 1'b1; // Treat small values as zero to avoid divide by zero
    endcase
end

// ===========================================================================
//                       Fetch Reciprocal from Lookup Table
// ===========================================================================
logic [9:0] p1_recip_value;
logic [3:0] p1_shift;
logic       p1_small;
logic       p1_leading_bit;
logic       p1_second_bit;
logic [26:0] recip_out_temp;

always_ff @(posedge clock) begin
    p1_recip_value <= recip_lookup[p0_index];
    p1_shift <= p0_shift;
    p1_small <= p0_small;
    p1_leading_bit <= (p0_index==10'd0);
    p1_second_bit <= (p0_index < 10'd342 && p0_index!=10'd0);  // the point at which the second bit of the reciprocal becomes 1 (1/3.0 = 0.3333)
end

always_comb begin
    if (p1_small || (p1_leading_bit && p1_shift==15))
        recip_out_temp = 27'h7FFFFFF; // Output zero for small input values
    else 
        recip_out_temp = {14'b0, p1_leading_bit, !p1_leading_bit, p1_second_bit, p1_recip_value} << p1_shift; 
    p1_out = recip_out_temp[26:3]; // Convert to U4.20 format
end

wire unused = &{recip_out_temp[2:0], recip_req}; // Avoid unused signal warning

endmodule
