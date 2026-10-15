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

    // Interface to object memory
    output logic            objfetch_req,
    output logic [11:0]     objfetch_addr,
    output logic [31:0]     objfetch_wdata,

    input  logic            obj_finished,
    input  logic [7:0]      obj_finished_index,

    // Interface to registers

    input logic [25:0]      vga_obj_list,


    // Interface to sdram
    input logic         objfetch_sdram_ready,    // SDRAM is ready for a req_valid
    output  logic         objfetch_sdram_req,      // Request memory
    output  logic [25:0]  objfetch_sdram_addr,     // Address
    output  logic [5:0]   objfetch_sdram_tag,      // Tag to identify request
    input logic [1:0]   objfetch_sdram_rvalid,   // 00:No data, 01:First word, 10:Mid burst, 11:Last word
    input logic [31:0]  objfetch_sdram_rdata,    // Read data
    input logic [5:0]   objfetch_sdram_rtag      // Tag identifying which request this data is for
);

// =========================================================================
//   State machine
// =========================================================================

logic [25:0] obj_pointer, next_obj_pointer;

logic [2:0] state, next_state;
localparam STATE_IDLE = 3'd0,
           STATE_READY = 3'd1,
           STATE_REQUEST = 3'd2,
           STATE_WAIT  = 3'd3 ;





// =========================================================================
//   Track free slots
// =========================================================================

logic [255:0] free_slots;
logic [7:0]   free_slot_index, next_free_slot_index;
logic         has_free_slot;

always_comb begin
    next_free_slot_index = free_slot_index;
    if (has_free_slot==1'b0)
        next_free_slot_index = next_free_slot_index + 1;
end

always_ff @(posedge clock) begin
    if (obj_finished)
        free_slots[obj_finished_index] <= 1'b1;
    
    free_slot_index <= next_free_slot_index;
    has_free_slot <= free_slots[next_free_slot_index];

    if (reset || ypos==-9'd5) begin
        free_slot_index <= 8'd0;
        free_slots <= 256'hFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
    end
end



endmodule
