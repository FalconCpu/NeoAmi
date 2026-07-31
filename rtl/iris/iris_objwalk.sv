`timescale 1ns/1ns

// Iris Object Walker
//
// Walk through the objects in the scene and determine which ones are active on the current scanline
//
//
// Each object is represented by a 64-byte structure in memory. The object cache is 256 bits wide, 
// so each object takes 2 lines in the cache. 
//
// The object structure is as follows:
//   | Offset       | Field      | Format |
//   |--------------|------------|--------|
//   |   15:0       | FLAGS      | U16    |
//   |   31:16      | CLIP_X1    | U16    |
//   |   47:32      | CLIP_X2    | U16    |
//   |   63:48      | CLIP_Y1    | U16    |
//   |   79:64      | CLIP_Y2    | U16    |
//   |   95:80      | X1         | S12.4  |
//   |  111:96      | Y1         | S12.4  |
//   |  127:112     | X2         | S12.4  |
//   |  143:128     | Y2         | S12.4  |
//   |  159:144     | DX1/DY     | FP16   |
//   |  175:160     | DX2/DY     | FP16   |
//   |  191:176     | DX3/DY     | FP16   |
//   |  207:192     | Z1         | S12.4  |
//   |  223:208     | DZ/DX      | FP16   |
//   |  239:224     | DZ/DY      | FP16   |
//   |  255:240     | reserved   | U16    |

//   |   15:0       | R1         | U12.5  |
//   |   31:16      | DR/DX      | FP16   |
//   |   47:32      | DR/DY      | FP16   |
//   |   63:48      | G1         | U12.5  |
//   |   79:64      | DG/DX      | FP16   |
//   |   95:80      | DG/DY      | FP16   |
//   |  111:96      | B1         | U12.5  |
//   |  127:112     | DB/DX      | FP16   |
//   |  143:128     | DB/DY      | FP16   |
//   |  159:144     | TEX_STRIDE | U16    |
//   |  192:160     | TEX_ADDR   | U32    |
//   |  255:224     | NEXT       | U32    |
//
// Flags: Bi


module iris_objwalk (
    input logic            clock,           // 125 MHz system clock
    input logic            reset,

    input logic            start_of_line,   // Start of line signal from the timing generator
    input logic [9:0]      ypos,

    // Aux interface
    input logic            aux_iris_req,
    input logic [11:0]     aux_iris_addr,
    input logic [31:0]     aux_iris_wdata,

    // Object list interface
    output logic        span_valid,
    input  logic        span_ready,
    output logic [7:0]  span_flags,
    output logic [9:0]  span_x1,          // Start X coordinate
    output logic [9:0]  span_x2,          // End X coordinate
    output logic [23:0] span_z,
    output logic [23:0] span_dzdx,
    output logic [23:0] span_r,
    output logic [23:0] span_drdx,
    output logic [23:0] span_g,
    output logic [23:0] span_dgdx,
    output logic [23:0] span_b,
    output logic [23:0] span_dbdx,
    output logic [25:0] span_texaddr,
    output logic [15:0] span_texstride
);

logic [8:0] obj_index, next_obj_index;
logic [255:0] obj_data;

logic        next_span_valid;
logic [7:0]  next_span_flags;
logic [9:0]  next_span_x1;
logic [9:0]  next_span_x2;
logic [23:0] next_span_z;
logic [23:0] next_span_dzdx;
logic [23:0] next_span_r;
logic [23:0] next_span_drdx;
logic [23:0] next_span_g;
logic [23:0] next_span_dgdx;
logic [23:0] next_span_b;
logic [23:0] next_span_dbdx;
logic [25:0] next_span_texaddr;
logic [15:0] next_span_texstride;


// ===============================================================
//              Floating point to fixed point conversion
// ===============================================================
// Some of the object fields are stored in FP16 format. 
// A convenience function to convert them to S12.12 format for easier processing.
function automatic [23:0] fp16_to_s12_12(input logic [15:0] fp16);
    if (fp16[15:14]==2'b00)
        return {{10{fp16[13]}}, fp16[13:0]}; 
    else if (fp16[15:14]==2'b01)
        return {{7{fp16[13]}}, fp16[13:0], 3'b100}; 
    else if (fp16[15:14]==2'b10)
        return {{4{fp16[13]}}, fp16[13:0], 6'b100_000}; 
    else
        return {{1{fp16[13]}}, fp16[13:0], 9'b100_000_000};     
endfunction



// ===============================================================
//              Extract fields from the object data
// ===============================================================
// The object date is read from the object memory 256 bits wide. 
// Extract the fields and label them for easier access.
// We also convert all fixed point values to S12.12 format for easier processing
//
// Note: Since the object is split into two halves, we must take care to only
// use the fields from the half that is currently being processed

wire [15:0] ram0_flags = obj_data[15:0];
wire [15:0] ram0_clip_x1 = obj_data[31:16];
wire [15:0] ram0_clip_x2 = obj_data[47:32];
wire [9:0]  ram0_clip_y1 = obj_data[57:48];
wire [9:0]  ram0_clip_y2 = obj_data[73:64];
wire [23:0] ram0_x1 = {obj_data[95:80], 8'hff};
wire [23:0] ram0_y1 = {obj_data[111:96], 8'hff};
wire [23:0] ram0_x2 = {obj_data[127:112], 8'hff};
wire [23:0] ram0_y2 = {obj_data[143:128], 8'hff};
wire [23:0] ram0_dx1_dy = fp16_to_s12_12(obj_data[159:144]);
wire [23:0] ram0_dx2_dy = fp16_to_s12_12(obj_data[175:160]);
wire [23:0] ram0_dx3_dy = fp16_to_s12_12(obj_data[191:176]);
wire [23:0] ram0_z1 = {obj_data[207:192], 8'hff};
wire [23:0] ram0_dz_dx = fp16_to_s12_12(obj_data[223:208]);
wire [23:0] ram0_dz_dy = fp16_to_s12_12(obj_data[239:224]);

wire [23:0] ram1_r1 = {obj_data[15:0], 8'hff};
wire [23:0] ram1_dr_dx = fp16_to_s12_12(obj_data[31:16]);
wire [23:0] ram1_dr_dy = fp16_to_s12_12(obj_data[47:32]);
wire [23:0] ram1_g1 = {obj_data[63:48], 8'hff};
wire [23:0] ram1_dg_dx = fp16_to_s12_12(obj_data[79:64]);
wire [23:0] ram1_dg_dy = fp16_to_s12_12(obj_data[95:80]);
wire [23:0] ram1_b1 = {obj_data[111:96], 8'hff};
wire [23:0] ram1_db_dx = fp16_to_s12_12(obj_data[127:112]);
wire [23:0] ram1_db_dy = fp16_to_s12_12(obj_data[143:128]);
wire [15:0] ram1_tex_stride = obj_data[159:144];
wire [25:0] ram1_tex_addr = obj_data[185:160];

//   |   15:0       | FLAGS      | U16    |
//   |   31:16      | CLIP_X1    | U16    |
//   |   47:32      | CLIP_X2    | U16    |
//   |   63:48      | CLIP_Y1    | U16    |
//   |   79:64      | CLIP_Y2    | U16    |
//   |   95:80      | X1         | S12.4  |
//   |  111:96      | Y1         | S12.4  |
//   |  127:112     | X2         | S12.4  |
//   |  143:128     | Y2         | S12.4  |
//   |  159:144     | DX1/DY     | FP16   |
//   |  175:160     | DX2/DY     | FP16   |
//   |  191:176     | DX3/DY     | FP16   |
//   |  207:192     | Z1         | S12.4  |
//   |  223:208     | DZ/DX      | FP16   |
//   |  239:224     | DZ/DY      | FP16   |
//   |  255:240     | R1         | U12.5  |
//   |   15:0       | DR/DX      | FP16   |
//   |   31:16      | DR/DY      | FP16   |
//   |   47:32      | G1         | U12.5  |
//   |   63:48      | DG/DX      | FP16   |
//   |   79:64      | DG/DY      | FP16   |
//   |   95:80      | B1         | U12.5  |
//   |  111:96      | DB/DX      | FP16   |
//   |  127:112     | DB/DY      | FP16   |
//   |  143:128     | TEX_STRIDE | U16    |
//   |  175:144     | TEX_ADDR   | U32    |
//   |  223:176     | reserved   | U48    |
//   |  255:224     | NEXT       | U32    |





// ===============================================================
//                       Multiply-Accumulate unit
// ===============================================================
// calculates (mult_a1 * mult_a2) + (mult_b1 * mult_b2) + mult_c
// All parameters in S12.12 Fixed point format
// With a latency of 2 cycles

logic signed [23:0] mult_a1, mult_a2, mult_b1, mult_b2, mult_c;
logic signed [23:0] lat_mult_a1, lat_mult_a2, lat_mult_b1, lat_mult_b2;
logic signed [23:0] mult_c_dly;
logic signed [47:0] mult_p1, mult_p2;
logic signed [27:0] mac_out;        // S16.12 output

// verilator lint_off BLKSEQ
always_ff @(posedge clock) begin
    // First pipeline stage
    lat_mult_a1 <= mult_a1; 
    lat_mult_a2 <= mult_a2;
    lat_mult_b1 <= mult_b1;
    lat_mult_b2 <= mult_b2;
    mult_c_dly <= mult_c;

    // Second pipeline stage
    mult_p1 = lat_mult_a1 * lat_mult_a2;
    mult_p2 = lat_mult_b1 * lat_mult_b2;
    mac_out <= mult_p1[39:12] + mult_p2[39:12] + {{4{mult_c_dly[23]}},mult_c_dly}; 
end

wire unused_ok = &{mult_p1[47:40], mult_p1[11:0], mult_p2[47:40], mult_p2[11:0]}; // Silence unused signal warnings


// ===============================================================
//                       Main State machine
// ===============================================================
logic [3:0] state, next_state;
logic signed [23:0] next_dy1, this_dy1;    // y1-ypos in S12.12 format
logic signed [23:0] next_dy2, this_dy2;    // y2-ypos in S12.12 format
logic signed [23:0] next_dx1, this_dx1;    // x1-xpos in S12.12 format
logic signed [15:0] tmp;

`define STATE_END 4'hf

always_comb begin
    next_obj_index = obj_index;
    mult_a1 = 24'hx;
    mult_a2 = 24'hx;
    mult_b1 = 24'hx;
    mult_b2 = 24'hx;
    mult_c  = 24'hx;
    next_dy1 = this_dy1;
    next_dy2 = this_dy2;
    next_dx1 = this_dx1;
    next_span_flags = span_flags;
    next_span_valid = span_valid;
    next_span_x1 = span_x1;
    next_span_x2 = span_x2;
    next_span_z = span_z;
    next_span_dzdx = span_dzdx;
    next_span_r = span_r;
    next_span_drdx = span_drdx;
    next_span_g = span_g;
    next_span_dgdx = span_dgdx;
    next_span_b = span_b;
    next_span_dbdx = span_dbdx;
    next_span_texaddr = span_texaddr;
    next_span_texstride = span_texstride;
    tmp = 16'hx;

    next_state = (state==4'hF) ? 4'hF : state+1'b1;




    case(state)
    0: begin
        // Check if the current object is active on this scanline
        if (ypos >= ram0_clip_y1 && ypos < ram0_clip_y2) begin
            // The object is active on this scanline, extract the fields and output them
            next_span_flags = ram0_flags[7:0];

            // Calulate left edge of this scanline
            next_dy1 = {2'b0,ypos,12'hFFF} - ram0_y1;
            next_dy2 = {2'b0,ypos,12'hFFF} - ram0_y2;
            mult_b1 = 24'h0;
            mult_b2 = 24'h0;
            if (next_dy2<0 || ram0_flags[4]==1'b1) begin
                // Above the mid vertex, or mid vertex is on the right - so calc left edge relative to x1,y1
                mult_a1 = ram0_dx1_dy;
                mult_a2 = next_dy1;
                mult_c  = ram0_x1;
            end else begin
                // Below the mid vertex and mid vertex is on the left - so calc left edge relative to x2,y2
                mult_a1 = ram0_dx3_dy;
                mult_a2 = next_dy2;
                mult_c  = ram0_x2;
            end
        end else begin
            // Move to the next object
            next_obj_index = obj_index + 9'd2;
            if(obj_index == 9'd510) 
                next_state = `STATE_END; // Finished processing all objects, wait for the next line
            else
                next_state = 4'h0; // Continue processing the next object
        end
    end

    1: begin
        // Calculate the right edge of this scanline
        if (this_dy2<0 || ram0_flags[4]==1'b0) begin
            // Above the mid vertex, or mid vertex is on the left - so calc left edge relative to x1,y1
            mult_a1 = ram0_dx2_dy;
            mult_a2 = this_dy1;
            mult_b1 = 24'h0;
            mult_b2 = 24'h0;
            mult_c  = ram0_x1;
        end else begin
            // Below the mid vertex and mid vertex is on the right - so calc left edge relative to x2,y2
            mult_a1 = ram0_dx3_dy;
            mult_a2 = next_dy2;
            mult_b1 = 24'h0;
            mult_b2 = 24'h0;
            mult_c  = ram0_x2;
        end
        next_state = 4'h2;
    end

    2: begin
        // Clip the left edge to the clip rectangle
        tmp = mac_out[27:12];

        if (tmp > ram0_clip_x2) begin
            // Object is completely clipped, move to the next object
            next_state = 4'd14;
        end
        if (tmp < ram0_clip_x1)
            tmp = ram0_clip_x1;
        next_span_x1 = tmp[9:0];
    end

    3: begin
        // Clip the right edge to the clip rectangle
        tmp = mac_out[27:12];
        if (tmp < ram0_clip_x1) begin
            // Object is completely clipped, move to the next object
            next_state = 4'd14;
        end
        if (tmp > ram0_clip_x2)
            tmp = ram0_clip_x2;
        next_span_x2 = tmp[9:0];

        // Calculate the Z value at the left edge of this scanline
        next_dx1 = {2'b0,span_x1,12'hFFF} - ram0_x1;
        mult_a1 = ram0_dz_dx;
        mult_a2 = next_dx1;
        mult_b1 = ram0_dz_dy;
        mult_b2 = this_dy1;
        mult_c  = ram0_z1;
        next_span_dzdx = ram0_dz_dx;
        next_span_flags = ram0_flags[7:0];

        // Move the RAM onto the next half of the object for the color and texture data
        next_obj_index = obj_index + 9'd1;
    end

    4: begin
        // Calculate the R value at the left edge of this scanline
        mult_a1 = ram1_dr_dx;
        mult_a2 = this_dx1;
        mult_b1 = ram1_dr_dy;
        mult_b2 = this_dy1;
        mult_c  = ram1_r1;
        next_span_drdx = ram1_dr_dx;
    end

    5: begin
        // Calculate the G value at the left edge of this scanline
        mult_a1 = ram1_dg_dx;
        mult_a2 = this_dx1;
        mult_b1 = ram1_dg_dy;
        mult_b2 = this_dy1;
        mult_c  = ram1_g1;
        next_span_dgdx = ram1_dg_dx;

        // Load the Z value into the span output
        next_span_z = mac_out[23:0];
    end

    6: begin
        // Calculate the B value at the left edge of this scanline
        mult_a1 = ram1_db_dx;
        mult_a2 = this_dx1;
        mult_b1 = ram1_db_dy;
        mult_b2 = this_dy1;
        mult_c  = ram1_b1;
        next_span_dbdx = ram1_db_dx;

        // Load the R value into the span output
        next_span_r = mac_out[23:0];
    end

    7: begin
        // Load the G value into the span output
        next_span_g = mac_out[23:0];
        next_span_texaddr = ram1_tex_addr[25:0];
        next_span_texstride = ram1_tex_stride;
    end

    8: begin
        // Load the B value into the span output
        next_span_b = mac_out[23:0];
        next_span_valid = 1'b1;
    end

    9: begin
        // Wait for the span to be accepted
        if (span_ready) begin
            next_span_valid = 1'b0;
            next_obj_index = obj_index + 9'd1;
            if(obj_index == 9'd511) 
                next_state = `STATE_END; // Finished processing all objects, wait for the next line
            else
                next_state = 4'h0; // Continue processing the next object
        end else
            next_state = 4'h9; // Stay in this state until the span is accepted
    end

    14: begin
        // Move on to the next object
        next_obj_index = (obj_index & 9'h1FE) + 9'd2;
        if((obj_index & 9'h1FE) == 9'd510) 
            next_state = `STATE_END;
        else
            next_state = 4'h0;
    end

    default: begin
        // Wait for the next line to start, then reset the object index and state
        next_state = 4'hf;
    end

    endcase


    // Reset
    if (reset || (start_of_line && ypos<480)) begin
        next_obj_index = 0;
        next_state = 4'h0;
        next_span_valid = 1'b0;
    end
end

// ===============================================================
//                       Registers
// ===============================================================

always_ff @(posedge clock) begin
    state <= next_state;
    this_dy1 <= next_dy1;
    this_dy2 <= next_dy2;
    this_dx1 <= next_dx1;
    obj_index <= next_obj_index;
    state <= next_state;
    span_valid <= next_span_valid;
    span_flags <= next_span_flags;
    span_x1 <= next_span_x1;
    span_x2 <= next_span_x2;
    span_z <= next_span_z;
    span_dzdx <= next_span_dzdx;
    span_r <= next_span_r;
    span_drdx <= next_span_drdx;
    span_g <= next_span_g;
    span_dgdx <= next_span_dgdx;
    span_b <= next_span_b;
    span_dbdx <= next_span_dbdx;
    span_texaddr <= next_span_texaddr;
    span_texstride <= next_span_texstride;
end


// ===============================================================
//                       Object Memory
// ===============================================================

iris_obj_mem  iris_obj_mem_inst (
    .clock(clock),
    .data(aux_iris_wdata),
    .wraddress(aux_iris_addr[11:0]),
    .wren(aux_iris_req),
    .rdaddress(next_obj_index),
    .q(obj_data)
  );

endmodule
