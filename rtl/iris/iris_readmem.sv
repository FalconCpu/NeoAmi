`timescale 1ns/1ns

// VGA Texture Fetch 
//
// Takes a stream of read requests, and fetches the corresponding data from a cache.
// If the data is not in the cache then it issues a read request to SDRAM 


module iris_readmem(
    input  logic         clock,
    input  logic         reset,

    // Input stream of read requests from the graphics engine
    output logic         readmem_ready,   // We can accept a req_valid
    input  logic         readmem_req,     // A transaction is ready to be processed
    input  logic [15:0]  readmem_mode,    // bit 0: 0=texture fetch, 1=solid color
    input  logic [25:0]  readmem_addr,    // Address to read or data to pass through (for solid color)
    input  logic [23:0]  readmem_z,       // Z coordinate for z-buffering
    input  logic [9:0]   readmem_x,       // Pixel X coordinate
    input  logic [8:0]   readmem_bright,  // Brightness level 

    // Output stream to palette stage
    output  logic         palette_req,
    output  logic [15:0]  palette_mode,       // Mode. Bit 1: Transparency enabled,  bits 3:2=palette bank, 4=Cacheable
    output  logic [7:0]   palette_color_index,      // Color index
    output  logic [9:0]   palette_x,          // Destination address (passed through)
    output  logic [8:0]   palette_bright,     // Brightness level 
    output  logic [23:0]  palette_z,          // Depth value of the pixel (passed through)

    // SDRAM interface - bursts of 4 words per transaction
    input  logic         readmem_sdram_ready,    // SDRAM is ready for a req_valid
    output logic         readmem_sdram_req,      // Request memory
    output logic [25:0]  readmem_sdram_addr,     // Address
    output logic [5:0]   readmem_sdram_tag,      // Tag to identify request
    input  logic [1:0]   readmem_sdram_rvalid,   // 00:No data, 01:First word, 10:Mid burst, 11:Last word
    input  logic [31:0]  readmem_sdram_rdata,    // Read data
    input  logic [5:0]   readmem_sdram_rtag      // Tag identifying which request this data is for
);



// synthesis translate_off
integer log_file;
initial 
    log_file = $fopen("vga_readmem.log", "w");
// synthesis translate_on

// =================================================================
//                   Cache
// =================================================================
// Direct mapped cache with 512 lines, each of 16 bytes (4 words).
//
// Address breakdown 
// 25:12 Tag
// 12:4  Line index
// 3:2   Word within a line
// 1:0   Byte offset within a 32 bit word

logic [31:0] cache_ram[0:2047];  
logic [14:0] cache_tag_ram[0:511]; // Tag for each line in the cache

integer i;
initial begin
    for (i=0; i<512; i=i+1) 
        cache_tag_ram[i] = 15'b0;
end 


// =================================================================
//                   Transaction queue
// =================================================================
// Maintain a queue of in-flight transactions. 

logic        fifo_write_enable;
logic        fifo_nearly_full;
logic [59:0] fifo_write_data;
logic        fifo_read_enable;
logic        fifo_read_valid;
logic [59:0] fifo_read_data;

word_fifo  word_fifo_inst (
    .clock(clock),
    .reset(reset),
    .write_enable(fifo_write_enable),
    .fifo_nearly_full(fifo_nearly_full),
    .write_data(fifo_write_data),
    .read_enable(fifo_read_enable),
    .read_valid(fifo_read_valid),
    .read_data(fifo_read_data)
  );

// =================================================================
//                   SDRAM request queue
// =================================================================

logic [2:0]   sdram_queue_write_ptr;
logic [2:0]   sdram_queue_read_ptr;
logic [25:0]  sdram_queue_addr[0:7];
logic [31:0]  sdram_data_valid;
logic [31:0]  sdram_data[0:31];
wire  [2:0]   sdram_queue_slots_free = sdram_queue_read_ptr - sdram_queue_write_ptr - 3'd1;
wire          sdram_queue_nearly_full = (sdram_queue_slots_free <= 3'd3);

// =================================================================
// First pipeline stage - accept request and lookup in cache
// =================================================================
logic         p1_req;
logic [15:0]  p1_mode;
logic [25:0]  p1_addr;
logic [23:0]  p1_z;
logic [9:0]   p1_x;
logic [8:0]   p1_bright;
logic [14:0]  p1_fetched_tag;
logic [31:0]  p1_fetched_data;

assign readmem_ready = !fifo_nearly_full && !sdram_queue_nearly_full;

always_ff @(posedge clock) begin
    p1_req  <= readmem_req && readmem_ready;
    p1_mode <= readmem_mode;
    p1_addr <= readmem_addr;
    p1_z    <= readmem_z;
    p1_x    <= readmem_x;
    p1_bright <= readmem_bright;
    p1_fetched_tag <= cache_tag_ram[readmem_addr[12:4]];
    p1_fetched_data <= cache_ram[readmem_addr[12:2]];
end

wire [7:0] p1_extracted_byte = p1_fetched_data[ (p1_addr[1:0]*8) +: 8 ];

// ===========================================================================
// Second pipeline stage - check if cache hit, and if not issue SDRAM request
// ===========================================================================

logic send_sdram_request;
logic [25:0] sdram_head_of_queue_addr;
logic        sdram_queue_not_empty;

wire [4:0]  out_mode = {p1_mode[4:2], p1_mode[7], p1_mode[0]}; 

always_comb begin
    sdram_head_of_queue_addr = sdram_queue_addr[sdram_queue_write_ptr-3'd1];
    sdram_queue_not_empty = (sdram_queue_write_ptr != sdram_queue_read_ptr);


    if (p1_req==1'b0) begin
        // No request - do nothing
        send_sdram_request = 1'b0;
        fifo_write_enable = 1'b0;
        fifo_write_data   = 60'bx;

    end else if (p1_fetched_tag[14] && p1_fetched_tag[13:0] == p1_addr[25:12] && p1_mode[4]) begin
        // Cache hit - just add to FIFO
        send_sdram_request = 1'b0;
        fifo_write_enable = 1'b1;
        fifo_write_data   = {3'bx, p1_extracted_byte, p1_bright, out_mode, p1_z, p1_x,1'b1};

    end else if (p1_addr[25:4] == sdram_head_of_queue_addr[25:4] ) begin // && sdram_queue_not_empty
        // This address is currently being fetched from SDRAM - we can service the request once the data arrives
        send_sdram_request = 1'b0;
        fifo_write_enable = 1'b1;
        fifo_write_data   = {4'bx, sdram_queue_write_ptr-3'd1, p1_addr[3:0], p1_bright, out_mode, p1_z, p1_x,1'b0};
    
    end else begin
        // Cache miss - need to issue SDRAM request
        send_sdram_request = 1'b1;
        fifo_write_enable = 1'b1;
        fifo_write_data   = {4'bx, sdram_queue_write_ptr, p1_addr[3:0], p1_bright, out_mode, p1_z, p1_x,1'b0};
    end
end

always_ff @(posedge clock) begin
    if (send_sdram_request) begin
        sdram_queue_addr[sdram_queue_write_ptr] <= {p1_addr[25:2], p1_mode[4], 1'b0}; // Align address to start of cache line, and store cacheable bit in bit 1
        sdram_queue_write_ptr <= sdram_queue_write_ptr + 3'd1;
    end

    if (reset) begin
        sdram_queue_write_ptr <= 3'd0;
    end
end

// ===========================================================================
//             Send requests to SDRAM and handle responses
// ===========================================================================

logic [25:0] sdram_read_addr;  // Address of data to be received from SDRAM
wire [2:0]  sdram_read_index = readmem_sdram_rtag[2:0]; // Transactions index in queue
wire [25:0] this_read_addr = readmem_sdram_rvalid==2'b01 ? sdram_queue_addr[sdram_read_index] : sdram_read_addr;

always_ff @(posedge clock) begin

    // Send requests to SDRAM
    if (readmem_sdram_req && !readmem_sdram_ready) begin
        // Waiting for SDRAM to accept request - hold values steady

    end else if (sdram_queue_not_empty) begin
        readmem_sdram_req  <= 1'b1;
        readmem_sdram_addr <= sdram_queue_addr[sdram_queue_read_ptr] & 26'h3FFFFC; // Align to start of cache line
        readmem_sdram_tag  <= {2'b0,sdram_queue_addr[sdram_queue_read_ptr][1], sdram_queue_read_ptr};
        sdram_queue_read_ptr <= sdram_queue_read_ptr + 3'd1;
        // synthesis translate_off
        $fdisplay(log_file, "Time %t: SDRAM REQ addr=%06h tag=%h", $time, sdram_queue_addr[sdram_queue_read_ptr], {2'b0, sdram_queue_read_ptr});
        // synthesis translate_on
    
    end else begin
        readmem_sdram_req <= 1'b0;
        readmem_sdram_addr <= 26'bx;
        readmem_sdram_tag <= 6'bx;
    end

    // Handle incoming data from SDRAM
    if (readmem_sdram_rvalid==2'd0) begin
        // No data - do nothing

    end else begin
        // Received data from SDRAM - store in cache and mark as valid
        sdram_data[{sdram_read_index, this_read_addr[3:2]}] <= readmem_sdram_rdata;
        sdram_data_valid[{sdram_read_index, this_read_addr[3:2]}] <= 1'b1;
        if (readmem_sdram_rtag[3]) begin
            // This transaction is for a cacheable address - update the cache
            cache_ram[this_read_addr[12:2]] <= readmem_sdram_rdata;
            cache_tag_ram[this_read_addr[12:4]] <= {readmem_sdram_rvalid==2'd3, this_read_addr[25:12]};
        end
        sdram_read_addr <= {this_read_addr[25:4],this_read_addr[3:2]+1'b1, 2'b00}; // Increment address for next word in burst
    end 

    // Clear out SDRAM data valid bits when new write requests are sent
    if (send_sdram_request) begin
        sdram_data_valid[sdram_queue_write_ptr*4 +: 4] <= 4'b0;
    end

    if (reset) begin
        sdram_queue_read_ptr <= 3'd0;
        sdram_data_valid <= 32'b0;
    end
end

// ===========================================================================
//  Process transactions at the head of the FIFO and send to palette stage
// ===========================================================================

logic        fifo_cache_hit;
logic [9:0]  fifo_read_x;
logic [23:0] fifo_read_z;
logic [4:0]  fifo_read_mode;
logic [8:0]  fifo_read_bright;
logic [10:0]  fifo_read_value;

always_comb begin
    {fifo_read_value, fifo_read_bright, fifo_read_mode, fifo_read_z, fifo_read_x,fifo_cache_hit} = fifo_read_data;
    if (fifo_read_valid==1'b0) begin
        // No transaction to process
        palette_req = 1'b0;
        palette_mode = 16'bx;
        palette_color_index = 8'bx;
        palette_x = 10'bx;
        palette_bright = 9'bx;
        palette_z = 24'bx;
        fifo_read_enable = 1'b0;

    end else if (fifo_cache_hit) begin
        // Data was in cache - just pass through
        palette_req = 1'b1;
        palette_mode = {11'bx,fifo_read_mode};
        palette_color_index = fifo_read_value[7:0];
        palette_x = fifo_read_x;
        palette_bright = fifo_read_bright;
        palette_z = fifo_read_z;
        fifo_read_enable = 1'b1;

    end else if (sdram_data_valid[fifo_read_value[6:2]]) begin
        // Data was not in cache - this transaction was waiting for an SDRAM response. The actual data value is in the sdram_data array, and the mode/coord/brightness info is in the FIFO
        palette_req = 1'b1;
        palette_mode = {11'bx,fifo_read_mode};
        palette_color_index = sdram_data[fifo_read_value[6:2]][ (fifo_read_value[1:0]*8) +: 8 ];
        palette_x = fifo_read_x;
        palette_bright = fifo_read_bright;
        palette_z = fifo_read_z;
        fifo_read_enable = 1'b1;

    end else begin
        // Data not in cache, and SDRAM response has not yet arrived - keep waiting
        palette_req = 1'b0;
        palette_mode = 16'bx;
        palette_color_index = 8'bx;
        palette_x = 10'bx;
        palette_bright = 9'bx;
        palette_z = 24'bx;
        fifo_read_enable = 1'b0;
    end
end



wire unused = &{sdram_head_of_queue_addr[3:0], this_read_addr[1:0], fifo_read_value[10:8], readmem_sdram_rtag[5:4],
            readmem_mode[15:5], p1_mode};

endmodule
