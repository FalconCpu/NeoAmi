`timescale 1ns / 1ps

// Copper module interface for SDRAM requests and data handling
//
// Instructions are 32 bits wide
// Bits [31:28] = opcode
// Bits [27:0] = operands
//
// Opcodes:
// 0x0 = WAIT
// 0x1 = WRITE
// others - reserved for future opcodes
//
// Opcode WAIT (0x0) : Wait until the raster beam has reached a specific position
// Bits [11:0] = horizontal position   (Signed 12 bit)
// Bits [27:12] = vertical position (Signed 12 bit)
// vertical and horizontal blanks are included in the coordinate system as negative coordinates
// Note - location (0,0) is the top-left corner of the screen. Start of vblank is (-160, -45)
//
// Opcode WRITE (0x1) : Write data to MMIO register
// Bits [19:0] = register address offset from an implied 0xE0000000 base address 
// The following word contains the data to write to the specified register
// The copper only supports writing 32-bit values to registers
//
// The copper begins executing instructions when the `start_of_frame` signal is asserted,
// The first instruction is fetched from address specified by `copperlist_addr` register
// NOTE: This value must be aligned to a 16-byte boundary
//
// The copper executes instructions sequentially. A "Wait forever" can be implemented using a WAIT instruction with coordinates
// that will never be reached (typically 0x7FF,0x7FF)

module copper (
    input  logic        clock,
    input  logic        reset,

    // Connections to the aux bus
    output logic        copper_aux_req,
    input  logic        copper_aux_ack,
    output logic [19:0] copper_aux_addr,
    output logic [31:0] copper_aux_wdata,

    // Vga timimgs  
    input  logic signed [9:0]  ypos,
    input  logic signed [10:0] xpos,
    input  logic        start_of_frame,

    // copperlist address
    input  logic [25:0] copperlist_addr,

    // Connections to SDRAM
    output logic        copper_sdram_req,
    input  logic        copper_sdram_ack,
    output logic [25:0] copper_sdram_addr,
    input  logic [1:0]  copper_sdram_rvalid,
    input  logic [31:0] copper_sdram_rdata
);


localparam OPCODE_WAIT  = 4'h0;
localparam OPCODE_WRITE = 4'h1;

// ===========================================================
// Fifo to hold copper instructions before they are executed
// ===========================================================

logic [31:0] instr;
logic        instr_valid;
logic [5:0]  slots_free;
logic        advance;
logic        copper_enabled;

sophie_word_fifo  word_fifo_inst (
    .clock(clock),
    .reset(reset || start_of_frame),
    .write_data(copper_sdram_rdata),
    .write_en(copper_sdram_rvalid!=2'b00),
    .read_data(instr),
    .read_valid(instr_valid),
    .read_en(advance),
    .slots_free(slots_free)
  );


// ===========================================================
// State machine to request instructions from SDRAM
// ===========================================================

logic [1:0]  request_state, next_request_state;
logic [25:0] next_copper_sdram_addr;
localparam REQUEST_IDLE      = 2'd0;
localparam REQUEST_SEND_REQ  = 2'd1;
localparam REQUEST_WAIT_DATA = 2'd2;

always_comb begin
    next_request_state = request_state;
    next_copper_sdram_addr = copper_sdram_addr;

    case (request_state)
        REQUEST_IDLE: begin
            // Wait until there are enough free slots in the FIFO to hold a complete burst from the SDRAM
            if (slots_free > 8) 
                next_request_state = REQUEST_SEND_REQ;
        end

        REQUEST_SEND_REQ: begin
            // Send a request to SDRAM and wait for acknowledgment
            if (copper_sdram_ack)
                next_request_state = REQUEST_WAIT_DATA;
        end

        REQUEST_WAIT_DATA: begin
            // Wait until the SDRAM burst is complete
            if (copper_sdram_rvalid == 2'b11) begin
                next_request_state = REQUEST_IDLE;
                next_copper_sdram_addr = copper_sdram_addr + 16;
            end
        end
    endcase

    if (reset || start_of_frame) begin
        next_request_state = REQUEST_IDLE;
        next_copper_sdram_addr = copperlist_addr;
    end
end

always_ff @(posedge clock) begin
    request_state <= next_request_state;
    copper_sdram_addr <= next_copper_sdram_addr;
    copper_sdram_req <= (next_request_state == REQUEST_SEND_REQ) && copper_enabled;
    if (reset || start_of_frame)
        copper_enabled = copperlist_addr != 26'b0;
end

// ===========================================================
// State machine to execute copper instructions
// ===========================================================

logic [1:0]  execute_state, next_execute_state;
logic [19:0] next_aux_addr;
logic [31:0] next_aux_wdata;
logic        next_aux_req;
logic signed [9:0]  wait_ypos;
logic signed [10:0] wait_xpos;

localparam EXECUTE_FETCH_INSTR   = 2'd0;
localparam EXECUTE_FETCH_DATA    = 2'd1;
localparam EXECUTE_WAIT_ACK      = 2'd2;


always_comb begin
    next_execute_state = execute_state;
    next_aux_addr = copper_aux_addr;
    next_aux_wdata = copper_aux_wdata;
    next_aux_req = copper_aux_req;
    wait_ypos = instr[21:12];
    wait_xpos = xpos[10:0];
    advance = 1'b0;

    if (instr_valid) case (execute_state)
        EXECUTE_FETCH_INSTR: 
            case (instr[31:28])
                OPCODE_WAIT:
                    if (ypos>=wait_ypos || (wait_ypos == ypos && xpos>=wait_xpos))
                        advance = 1'b1;

                OPCODE_WRITE: begin
                    next_aux_addr = instr[19:0];
                    advance = 1'b1;
                    next_execute_state = EXECUTE_FETCH_DATA;
                end

                default: 
                    advance = 1'b1; // Default - ignore unknown opcodes
            endcase

        EXECUTE_FETCH_DATA: begin
            if (instr_valid) begin
                next_aux_wdata = instr;
                next_aux_req = 1'b1;
                next_execute_state = EXECUTE_WAIT_ACK;
            end
        end

        EXECUTE_WAIT_ACK: begin
            if (copper_aux_ack) begin
                next_aux_req = 1'b0;
                next_execute_state = EXECUTE_FETCH_INSTR;
            end
        end
    endcase


    if (reset || start_of_frame) begin
        next_aux_req = 1'b0;
        next_execute_state = EXECUTE_FETCH_INSTR;
    end
end

always_ff @(posedge clock) begin
    execute_state <= next_execute_state;
    copper_aux_req <= next_aux_req;
    copper_aux_addr <= next_aux_addr;
    copper_aux_wdata <= next_aux_wdata;
end

endmodule
