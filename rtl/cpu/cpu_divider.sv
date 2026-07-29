`timescale 1ns/1ps

module cpu_divider(
    input logic         clock,
    input logic         reset,

    // Connection to the execute stage
    input  logic         p3_is_divide,
    input  logic  [1:0]  p3_alu_op,  // 00=divu, 01=divs, 10=modu, 11=mods
    input  logic  [31:0] p3_data_a,
    input  logic  [31:0] p3_data_b,
    input  logic  [4:0]  p3_rd,

    // Connection to the writeback stage
    output logic         divider_ready,
    output logic         divider_valid,
    output logic  [31:0] divider_result,
    output logic  [4:0]  divider_reg_d
);

logic [31:0]    numerator, next_numerator;
logic [31:0]    denominator, next_denominator;
logic [33:0]    denominator3, next_denominator3;
logic [31:0]    quotient, next_quotient;
logic [31:0]    remainder, next_remainder;
logic [4:0]     bit_index, next_bit_index;
logic           busy, next_busy;
logic           sign, next_sign;
logic           mod_mode, next_mod_mode;     // true if we are computing remainder rather than quotient
logic           next_p4_valid;
logic [4:0]     next_reg_d;

logic [33:0]    s0,s1,s2,s3;


assign divider_ready = !busy && !p3_is_divide;

always_comb begin
    next_numerator = numerator;
    next_denominator = denominator;
    next_denominator3 = denominator3;
    next_quotient = quotient;
    next_remainder = remainder;
    next_bit_index = bit_index;
    next_busy = busy;
    next_mod_mode = mod_mode;
    next_sign = sign;
    next_p4_valid = 1'b0;
    next_reg_d = divider_reg_d;
    divider_result = 32'bx;
    s0 = 34'bx;
    s1 = 34'bx;
    s2 = 34'bx;
    s3 = 34'bx;

    if (p3_is_divide) begin
        // Start a new division operation
        next_busy = 1'b1;     
        next_mod_mode = p3_alu_op[1];  // div vs mod   
        next_reg_d = p3_rd;
        case (p3_alu_op)
            2'b00, 2'b10: begin  // divu, modu
                next_sign = 1'b0;
                next_numerator = p3_data_a;
                next_denominator = p3_data_b;
            end
            2'b01: begin // divs
                // Signed division - convert to unsigned by taking the absolute value of the inputs
                next_sign = p3_data_a[31] ^ p3_data_b[31]; // Record the sign of the result
                next_numerator = p3_data_a[31] ? -p3_data_a : p3_data_a; // Absolute value of numerator
                next_denominator = p3_data_b[31] ? -p3_data_b : p3_data_b;
            end
            2'b11: begin // mods
                // Signed division - convert to unsigned by taking the absolute value of the inputs
                next_sign = p3_data_a[31]; // Record the sign of the result (remainder has same sign as numerator)
                next_numerator = p3_data_a[31] ? -p3_data_a : p3_data_a; // Absolute value of numerator
                next_denominator = p3_data_b[31] ? -p3_data_b : p3_data_b;
            end
        endcase
        next_denominator3 = {1'b0, next_denominator} + {next_denominator, 1'b0}; // 3*denominator
        next_quotient = 32'b0;
        next_remainder = 32'b0;
        next_bit_index = 5'b0;
    end else if (busy) begin
        // Step through the division algorithm
        s0 = {remainder, numerator[31:30]};    // Shift in the next 2 bits of the quotient
        s1 = s0 - {2'b0, denominator};        // Compute numerator - denominator
        s2 = s0 - {1'b0, denominator,1'b0};   // Compute numerator - 2*denominator
        s3 = s0 - denominator3;               // Compute numerator - 3*denominator
        if (!s3[33]) begin
            next_quotient = {quotient[29:0], 2'b11};
            next_remainder = s3[31:0];
        end else if (!s2[33]) begin
            next_quotient = {quotient[29:0], 2'b10};
            next_remainder = s2[31:0];
        end else if (!s1[33]) begin
            next_quotient = {quotient[29:0], 2'b01};
            next_remainder = s1[31:0];
        end else begin
            next_quotient = {quotient[29:0], 2'b00};
            next_remainder = s0[31:0];
        end
        next_bit_index = bit_index + 1'b1;
        next_numerator = {numerator[29:0], 2'b00};

        if (bit_index == 5'd15) begin
            // Division is done after 16
            next_busy = 1'b0;
            next_p4_valid = 1'b1;
        end
    end

    if (divider_valid) begin
        if (mod_mode)
            divider_result = sign ? -remainder : remainder;  // Remainder is negated if the result is negative
        else
            divider_result = sign ? -quotient : quotient;   // Quotient is negated if the result is negative
    end 

    if (reset) begin
        next_busy = 1'b0;
        next_p4_valid = 1'b0;
    end

end

always_ff @(posedge clock) begin
    numerator <= next_numerator;
    denominator <= next_denominator;
    denominator3 <= next_denominator3;
    quotient <= next_quotient;
    remainder <= next_remainder;
    bit_index <= next_bit_index;
    busy <= next_busy;
    mod_mode <= next_mod_mode;
    sign <= next_sign;
    divider_valid <= next_p4_valid;
    divider_reg_d <= next_reg_d;
end

endmodule
