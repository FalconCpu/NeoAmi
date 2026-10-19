`timescale 1ns/1ns

// IRIS - Object Fetch module
//
// Fetches an object from the SDRAM and loads it into the object memory
//
// Keep a track of which slots are free and which are occupied
// when we see a free slot, and we have an object to fetch, we request a fetch from SDRAM
// for the next object and store it into the free slot
//
// We begin fetching for the next frame 5 lines before the frame starts

module iris_objfetch ( 
    input  logic            clock,
    input  logic            reset,
    input  logic [9:0]      ypos,
    input  logic            start_of_line,

    // Signals from object walker to indicate finished objects
    input  logic            obj_finished,
    input  logic [7:0]      obj_finished_index,

    // Signals to object walker to write fetched objects into object memory
    output logic            objfetch_wren,
    output logic [11:0]     objfetch_addr,
    output logic [31:0]     objfetch_wdata,

    // Sophie register with base address of the VGA object list
    input logic [25:0]      vga_obj_list,

    // Interface to sdram
    output  logic           objfetch_sdram_req,      // Request memory
    input logic             objfetch_sdram_ack,      // SDRAM acknowledges the request
    output  logic [25:0]    objfetch_sdram_addr,     // Address
    output  logic [5:0]     objfetch_sdram_tag,      // Tag to identify request
    input logic [1:0]       objfetch_sdram_rvalid,   // 00:No data, 01:First word, 10:Mid burst, 11:Last word
    input logic [31:0]      objfetch_sdram_rdata,    // Read data
    input logic [5:0]       objfetch_sdram_rtag      // Tag identifying which request this data is for
);

// =========================================================================
//                          Start of frame signal
// =========================================================================
// We start processing for the next frame 5 lines before the frame starts

wire start_of_frame = (ypos == -9'd5) && start_of_line;

// =========================================================================
//                          Track free slots
// =========================================================================
// Keep one bit per slot - 1 means free, 0 means occupied
// 
// A simple polling mechanism is used to find the next free slot

logic [255:0] free_slots;
logic [7:0]   free_slot_index, next_free_slot_index;
logic         found_free_slot;
logic         load_started;

always_comb begin
    next_free_slot_index = free_slot_index;
    if (found_free_slot==1'b0)
        next_free_slot_index = next_free_slot_index + 1;
end

always_ff @(posedge clock) begin
    // When the object fetcher finishes processing an object, mark the slot as free
    if (obj_finished)
        free_slots[obj_finished_index] <= 1'b1;

    // When the object fetcher starts loading a new object, mark the slot as occupied
    if (load_started)
        free_slots[free_slot_index] <= 1'b0;

    free_slot_index <= next_free_slot_index;
    found_free_slot <= free_slots[next_free_slot_index];

    if (reset || start_of_frame) begin
        free_slot_index <= 8'd0;
        free_slots <= 256'hFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
    end
end



// =========================================================================
//   State machine
// =========================================================================

logic [25:0] obj_pointer, next_obj_pointer;     // Source address of the next object in SDRAM
logic [11:0] next_objfetch_addr;                // Destination address in the object fetch buffer
logic [2:0]  state, next_state;
logic        next_objfetch_sdram_req;           // SDRAM control signal
logic [25:0] next_objfetch_sdram_addr;          // SDRAM control signal
logic [5:0]  next_objfetch_sdram_tag;           // SDRAM control signal


localparam STATE_READY    = 3'd0,
           STATE_REQUEST0 = 3'd1,
           STATE_REQUEST1 = 3'd2,
           STATE_REQUEST2 = 3'd3,
           STATE_WAIT_DATA= 3'd4,
           STATE_BLANK    = 3'd5;

always_comb begin
    next_obj_pointer         = obj_pointer;
    next_state               = state;
    next_objfetch_addr       = objfetch_addr;
    objfetch_wren            = 1'b0;
    objfetch_wdata           = 32'bx;
    next_objfetch_sdram_req  = 1'b0;
    next_objfetch_sdram_addr = 26'bx;
    next_objfetch_sdram_tag  = 6'bx;
    next_objfetch_sdram_req  = objfetch_sdram_req;
    next_objfetch_sdram_addr = objfetch_sdram_addr;
    next_objfetch_sdram_tag  = objfetch_sdram_tag;
    load_started             = 1'b0;

    // Clear request signal once acknowledged
    if (objfetch_sdram_ack)
        next_objfetch_sdram_req = 1'b0;

    // State machine
    case (state)
        STATE_READY: begin
            if (found_free_slot && obj_pointer != 26'd0) begin
                // Start fetching the next object from SDRAM
                next_objfetch_sdram_req = 1'b1;
                next_objfetch_sdram_addr = obj_pointer;
                next_objfetch_sdram_tag = 6'b0;
                next_objfetch_addr      = {free_slot_index, 4'b0};
                load_started            = 1'b1;
                next_state = STATE_REQUEST0;
            end else if (found_free_slot && obj_pointer == 26'd0) begin
                // No valid object to fetch, move to blank state
                load_started            = 1'b1;
                next_objfetch_addr      = {free_slot_index, 4'd2};   // Write yo CLIP_Y2 field
                next_state = STATE_BLANK;
            end
        end

        STATE_REQUEST0: begin
            if (objfetch_sdram_ack) begin
                // Fetch the second burst from SDRAM
                next_objfetch_sdram_req = 1'b1;
                next_objfetch_sdram_addr = obj_pointer + 26'h10;
                next_objfetch_sdram_tag = 6'b0;
                next_state = STATE_REQUEST1;
            end
        end

        STATE_REQUEST1: begin
            if (objfetch_sdram_ack) begin
                // Fetch the third burst from SDRAM
                next_objfetch_sdram_req = 1'b1;
                next_objfetch_sdram_addr = obj_pointer + 26'h20;
                next_objfetch_sdram_tag = 6'b0;
                next_state = STATE_REQUEST2;
            end
        end

        STATE_REQUEST2: begin
            if (objfetch_sdram_ack) begin
                // Fetch the final burst from SDRAM
                next_objfetch_sdram_req = 1'b1;
                next_objfetch_sdram_addr = obj_pointer + 26'h30;
                next_objfetch_sdram_tag = 6'b1;
                next_state = STATE_WAIT_DATA;
            end
        end

        STATE_WAIT_DATA: begin
            // Wait for the final burst of data from SDRAM before proceeding
            if (objfetch_sdram_rvalid==2'b11 && objfetch_sdram_rtag == 6'b1) begin
                // The next pointer is the final word of the final burst
                next_obj_pointer = objfetch_sdram_rdata[25:0];
                next_state = STATE_READY;
            end
        end

        STATE_BLANK: begin
            // Write blank state to object memory
            objfetch_wren      = 1'b1;
            objfetch_wdata     = 32'b0;
            next_state = STATE_READY;
        end

        default: begin
            // Default case to handle unexpected states
            next_state = STATE_READY;
        end
    endcase

    // Pass received data onto the object memory
    if (objfetch_sdram_rvalid!=2'b0) begin
        objfetch_wren      = 1'b1;
        objfetch_wdata     = objfetch_sdram_rdata;
        next_objfetch_addr = objfetch_addr + 1'b1;
    end

    // At start of a new frame, initialize the object pointer and state
    if (reset || start_of_frame) begin
        next_obj_pointer = vga_obj_list;
        next_state = STATE_READY;
        next_objfetch_sdram_req = 1'b0;
    end

end



always_ff @(posedge clock) begin
    obj_pointer <= next_obj_pointer;        // Start 
    state <= next_state;
    objfetch_addr <= next_objfetch_addr;
    objfetch_sdram_req <= next_objfetch_sdram_req;
    objfetch_sdram_addr <= next_objfetch_sdram_addr;
    objfetch_sdram_tag <= next_objfetch_sdram_tag;
end






endmodule
