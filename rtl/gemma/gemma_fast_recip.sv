`timescale 1ns/1ns

// Generates an approximate reciprocal of the input value 'a' , 
// with approx 10 bits of precision. 
//
// To maximize the utilisation of the lookup table, we calculate the 
// first 3 bits algorithmically, and use the lookup table for the remaining 10 bits.

module gemma_fast_recip (
    input logic         clock,

    input logic         ts_recip_req,       // Someone is requesting a reciprocal
    input  logic [26:0] ts_recip_in,        // U15.12 fixed point format
    output logic [26:0] ts_recip_out        // U2.25 fixed point format (one cycle latency)
);

// ===========================================================================
//                         Prioritize input requests
// ===========================================================================

logic        recip_req;
logic [26:0] recip_in;

always_comb begin
    if (ts_recip_req) begin
        recip_req = 1'b1;
        recip_in = ts_recip_in;
    end else begin
        recip_req = 1'b0;
        recip_in = 27'bx;
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
        27'b01?????????????????????????: begin p0_index = recip_in[24:15];  p0_shift = 4'd0; end
        27'b001????????????????????????: begin p0_index = recip_in[23:14];  p0_shift = 4'd1; end
        27'b0001???????????????????????: begin p0_index = recip_in[22:13];  p0_shift = 4'd2; end
        27'b00001??????????????????????: begin p0_index = recip_in[21:12];  p0_shift = 4'd3; end
        27'b000001?????????????????????: begin p0_index = recip_in[20:11];  p0_shift = 4'd4; end
        27'b0000001????????????????????: begin p0_index = recip_in[19:10];  p0_shift = 4'd5; end
        27'b00000001???????????????????: begin p0_index = recip_in[18:9];   p0_shift = 4'd6; end
        27'b000000001??????????????????: begin p0_index = recip_in[17:8];   p0_shift = 4'd7; end
        27'b0000000001?????????????????: begin p0_index = recip_in[16:7];   p0_shift = 4'd8; end
        27'b00000000001????????????????: begin p0_index = recip_in[15:6];   p0_shift = 4'd9; end
        27'b000000000001???????????????: begin p0_index = recip_in[14:5];   p0_shift = 4'd10; end
        27'b0000000000001??????????????: begin p0_index = recip_in[13:4];   p0_shift = 4'd11; end
        27'b00000000000001?????????????: begin p0_index = recip_in[12:3];   p0_shift = 4'd12; end
        27'b000000000000001????????????: begin p0_index = recip_in[11:2];   p0_shift = 4'd13; end
        27'b0000000000000001???????????: begin p0_index = recip_in[10:1];   p0_shift = 4'd14; end 
        27'b00000000000000001??????????: begin p0_index = recip_in[ 9:0];   p0_shift = 4'd15; end
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
    if (recip_req)
        $display("Reciprocal requested: Input=%d, Index=%d, Shift=%d, Small=%b, Leading=%b, Second=%b, Lookup Value=%d", recip_in, p0_index, p0_shift, p0_small, p1_leading_bit, p1_second_bit, p1_recip_value);
end

always_comb begin
    if (p1_small || (p1_leading_bit && p1_shift==15))
        recip_out_temp = 27'h7FFFFFF; // Output zero for small input values
    else 
        recip_out_temp = {14'b0, p1_leading_bit, !p1_leading_bit, p1_second_bit, p1_recip_value} ; 
    ts_recip_out = recip_out_temp << p1_shift; // Convert to U4.20 format
end

wire unused = &{recip_out_temp[2:0], recip_req}; // Avoid unused signal warning

endmodule
