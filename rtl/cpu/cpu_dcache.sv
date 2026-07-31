`timescale 1ns/1ns

/*
              DATA CACHE

This module implements an 8kb direct-mapped write-through data cache, 
with 16-byte cache lines, and write coalescing for store instructions. 

It interfaces with the CPU on one side, and the SDRAM controller on the other side.

Writes to the SDRAM are sent as 128-bit bursts in a single beat, with a 16-bit
strobe indicating which bytes are valid. Writes must be aligned to 16-byte boundaries.

Reads are also requested as 128-bit bursts, but the data is returned in 32-bit
chunks over multiple beats, with a 2-bit signal indicating the position of the
current beat within the burst. Reads must be aligned to 4-byte boundaries, but do
not need to be aligned to cache line boundaries. The sdram controller will return the
addressed 32-bit word in the first beat of the burst, and the remaining beats will
contain the rest of the cache line, in order, wrapping around as necessary.

An address is broken down as follows:
[25:13] Tag (13 bits)
[12:4]  Index (selects one of 512 cache lines)
[3:2]   Word offset within cache line
[1:0]   Byte offset within word (must be always 0)

*/



module cpu_dcache(
    input logic         clock,
    input logic         reset,
    
    // Interface to CPU
    input  logic        dcache_req,
    output logic        dcache_ack,
    input  logic        dcache_write,
    input  logic [25:0] dcache_addr,
    input  logic [31:0] dcache_wdata,
    input  logic [3:0]  dcache_strb,
    input  logic [4:0]  dcache_dest,
    output logic        dcache_rvalid,
    output logic [31:0] dcache_rdata,
    output logic [4:0]  dcache_rdest,
    
    // Write Interface to SDRAM
    output logic         dcache_sdramw_req,     // Request write burst to SDRAM
    input logic          dcache_sdramw_ack,     // SDRAM is ready to accept write burst
    output logic [25:0]  dcache_sdramw_addr,    
    output logic [127:0] dcache_sdramw_data,
    output logic [15:0]  dcache_sdramw_strb,

    // Read Interface to SDRAM
    output logic         dcache_sdramr_req,     // Request read burst from SDRAM
    input logic          dcache_sdramr_ack,     // SDRAM accepted read request
    output logic [25:0]  dcache_sdramr_addr,    // Address for read burst
    input logic  [1:0]   dcache_sdramr_rvalid,   // 01=first beat, 10=middle beats, 11=last beat
    input logic [31:0]   dcache_sdramr_rdata     // Data from SDRAM read burst
);

// =======================================================
//                  Control signals
// =======================================================
// The cache is organised into several sub-state machines - the cache RAMs, writeback buffer, etc
// The control signals below are used to coordinate these sub-modules
// The main state machine at the bottom of the file generates commands to the others

logic do_write_cache;       // Signal to write CPU data into the cache
logic do_write_to_buffer;   // Signal to write CPU data into the write buffer
logic do_update_tag;        // Signal to update the tag for a cache line
logic do_read_request;      // Signal to issue a read request to SDRAM
logic do_send_buffer;       // Signal to send the write buffer to SDRAM

// =======================================================
//             Latched transaction signals
// =======================================================
// These hold the current request being processed
logic        this_req;
logic        this_write;
logic [25:0] this_addr;
logic [31:0] this_wdata;
logic [3:0]  this_strb;
logic [4:0]  this_dest;

logic        next_dcache_rvalid;
logic [31:0] next_dcache_rdata;
logic [4:0]  next_dcache_rdest;


// =======================================================
//                  TAG RAM
// =======================================================
logic [13:0] tag_ram [0:511];       // 1 bit valid + 14-bit tag for each cache line

logic [13:0] cache_tag;         // Tag for the currently accessed cache line (latched at the time of the request)

always_ff @(posedge clock) begin
    // Update the tag for a cache line when signaled to do so
    if (do_update_tag) 
        tag_ram[this_addr[12:4]] <= {1'b1, this_addr[25:13]};

    // Lookup the tag for the requested cache line when accepting a new request from the CPU
    if (dcache_ack)       
        cache_tag <= tag_ram[dcache_addr[12:4]];    // Read the tag for the requested cache line
end

initial begin
    // Invalidate all cache lines at startup
    for (int i=0; i<512; i++) 
        tag_ram[i] = 14'b0; 
end

// =======================================================
//                  DATA RAM
// =======================================================
// I struggled to get Quartus to correctly infer the RAMs for the data array
// So I'm instantiating the block ram directly
//
// The Data ram can be written to by both the CPU (for cache hits) and the SDRAM
// These can never happen at the same time - guaranteed by the main state machine logic
// 
// Since the SDRAM returns data in 4 32-bit beats we need to keep track of the index
// within the cache line where the incoming data should be written, allowing for 
// wrapping around at the end of the cache line. 
//
// The data ram is read when a new transaction is accepted from the CPU

logic [31:0] cache_data;         // Data for the currently accessed cache line (latched at the time of the request)

logic [10:0] write_index;        // Index of the cache line to read from SDRAM on a cache miss (latched at the time of the request)
logic        data_ram_wren;      // Write enable for the data RAM (asserted when writing to cache or receiving data from SDRAM)
logic [10:0] data_ram_wraddress;
logic [3:0]  data_ram_byteena_a;
logic [31:0] data_ram_data;

always_comb begin
    if (do_write_cache) begin
        data_ram_wren = 1'b1;
        data_ram_wraddress = this_addr[12:2];
        data_ram_byteena_a = this_strb;
        data_ram_data = this_wdata;
    end else if (dcache_sdramr_rvalid != 2'b00) begin
        data_ram_wren = 1'b1;
        data_ram_wraddress = write_index;
        data_ram_byteena_a = 4'b1111;
        data_ram_data = dcache_sdramr_rdata;
    end else begin
        data_ram_wren = 1'b0;
        data_ram_wraddress = 11'bx;
        data_ram_byteena_a = 4'bx;
        data_ram_data = 32'bx;
    end
end

always_ff @(posedge clock) begin
    if (dcache_sdramr_rvalid != 2'b00)
        write_index <= {write_index[10:2], write_index[1:0] + 1'b1};

    if (do_read_request)
        write_index <= this_addr[12:2];

    // synthesis translate_off
    if (do_write_cache && dcache_sdramr_rvalid!=2'd0)
        $display("ERROR %t: Attempting to write to cache at the same time as receiving data from SDRAM!", $time);
    // synthesis translate_on
end


dcache_ram  dcache_ram_inst (
    .clock(clock),
    .byteena_a(data_ram_byteena_a),
    .data(data_ram_data),
    .wraddress(data_ram_wraddress),
    .wren(data_ram_wren),
    .rden(dcache_ack),
    .rdaddress(dcache_addr[12:2]),
    .q(cache_data)
  );
    
// =======================================================
//             SDRAM READ REQUEST
// =======================================================

always_ff @(posedge clock) begin
    // Clear read request once acknowledged by SDRAM
    if (dcache_sdramr_ack) begin
        dcache_sdramr_req <= '0; 
        dcache_sdramr_addr <= 26'bx;
    end

    // Initiate a new read request when signaled to do so
    if (do_read_request) begin
        dcache_sdramr_req <= '1;
        dcache_sdramr_addr <= {this_addr[25:2], 2'b00};
        // synthesis translate_off
        if (dcache_sdramr_req && !dcache_sdramr_ack)
            $display("ERROR %t: Attempting to send read request to SDRAM while previous request is still pending!", $time);
        // synthesis translate_on
    end 

    if (reset)
        dcache_sdramr_req <= '0;
end

// =======================================================
//             Latch the incoming transaction
// =======================================================
// Latch in the transaction from the CPU when we are ready
// (this_* signals already declared above)

always_ff @(posedge clock) begin
    if (dcache_ack) begin
        this_req   <= dcache_req;
        this_write <= dcache_write;
        this_addr  <= dcache_addr;
        this_wdata <= dcache_wdata;
        this_strb  <= dcache_strb;
        this_dest  <= dcache_dest;
    end 
end

wire cache_hit = cache_tag[13] && cache_tag[12:0] == this_addr[25:13];

// =======================================================
//             Write buffer
// =======================================================
// The write buffer is used to coalesce multiple writes
// to the same cache line

logic [127:0] buffer_data;    // Buffer for coalescing writes to the same cache line
logic [15:0]  buffer_strb;    // Byte strobe for the write buffer, indicating which bytes are valid
logic [25:0]  buffer_addr;    // Address of the cache line being written to (aligned to 16 bytes)
logic         buffer_valid;   // Indicates whether the write buffer contains valid data

always_ff @(posedge clock) begin
    // Clear the buffer once it's sent to SDRAM
    if (do_send_buffer) begin
        buffer_valid <= 1'b0;
        buffer_data  <= 128'bx;
        buffer_strb  <= 16'b0;
        buffer_addr  <= 26'bx;
    end

    // Write the incoming CPU request into the buffer, coalescing with existing data
    if (do_write_to_buffer) begin
        buffer_addr <= {this_addr[25:4], 4'b0000}; // Align address to cache line
        buffer_valid <= 1'b1;
        
        for (int i=0; i<4; i++) begin
            if (this_strb[i]) begin
                buffer_data[(this_addr[3:2]*32 + 8*i) +: 8] <= this_wdata[(i*8) +: 8]; 
                buffer_strb[(this_addr[3:2]*4 + i)] <= 1'b1; 
            end
        end
    end

    if (reset) begin
        buffer_valid <= 1'b0;
        buffer_strb <= 16'b0;
    end
end

// =======================================================
//             SDRAM WRITE INTERFACE
// =======================================================
// Send the write buffer to SDRAM when signaled to do so

always_ff @(posedge clock) begin
    // Clear write request once acknowledged by SDRAM
    if (dcache_sdramw_ack) begin
        dcache_sdramw_req <= '0; 
        dcache_sdramw_data <= 128'bx;
        dcache_sdramw_strb <= 16'bx;
        dcache_sdramw_addr <= 26'bx;
    end 
    
    // Send buffer to SDRAM when requested
    if (do_send_buffer) begin
        dcache_sdramw_req <= '1; // Assert write request to SDRAM
        dcache_sdramw_data <= buffer_data;
        dcache_sdramw_strb <= buffer_strb;
        dcache_sdramw_addr <= buffer_addr;
        // synthesis translate_off
        if (buffer_valid == '0)
            $display("ERROR %t: Attempting to send invalid buffer to SDRAM!", $time);
        if (dcache_sdramw_req && !dcache_sdramw_ack)
            $display("ERROR %t: Attempting to send buffer to SDRAM while previous write is still pending!", $time);
        // synthesis translate_on
    end

    if (reset)
        dcache_sdramw_req <= '0;
end

// =======================================================
//             Read from write buffer logic
// =======================================================
// Allow reading from the write buffer (to handle store instructions
// that haven't been sent to SDRAM yet).)

// Check for read from the write buffer
logic         write_buffer_match;   // The address being accessed matches the address in the write buffer
logic         write_buffer_rvalid;  // The addressed data is in the buffer
logic [31:0]  write_buffer_rdata;   // The addressed data from the buffer

always_comb begin
    // Check for read from the write buffer - valid if the buffer contains data for the same 
    // cache line, and all bytes being read are valid in the buffer
    write_buffer_match  = buffer_valid && (buffer_addr[25:4] == this_addr[25:4]);
    write_buffer_rvalid = ((buffer_strb[(this_addr[3:2]*4) +: 4] | ~this_strb) == 4'hf);
    write_buffer_rdata = buffer_data[(this_addr[3:2]*32) +: 32];
end

// =======================================================
//             Byte extraction logic
// =======================================================
// Extract the correct bytes from the cache line based on byte enables

logic [31:0] rdata; // Raw rdata read from the cache before applying byte enables

always_comb begin
    if (next_dcache_rvalid) begin
        next_dcache_rdest = this_dest;
        case(this_strb) 
            4'b0001: next_dcache_rdata = {{24{rdata[7]}}, rdata[7:0]};
            4'b0010: next_dcache_rdata = {{24{rdata[15]}}, rdata[15:8]};
            4'b0100: next_dcache_rdata = {{24{rdata[23]}}, rdata[23:16]};
            4'b1000: next_dcache_rdata = {{24{rdata[31]}}, rdata[31:24]};
            4'b0011: next_dcache_rdata = {{16{rdata[15]}}, rdata[15:0]};
            4'b1100: next_dcache_rdata = {{16{rdata[31]}}, rdata[31:16]};
            4'b1111: next_dcache_rdata = rdata;
            default: next_dcache_rdata = 32'bx; // Invalid byte enable pattern
        endcase
    end else begin
        next_dcache_rdata = 32'bx;
        next_dcache_rdest = 5'bx;
    end
end

always_ff @(posedge clock) begin
    dcache_rvalid <= next_dcache_rvalid;
    dcache_rdata  <= next_dcache_rdata;
    dcache_rdest  <= next_dcache_rdest;
end


// =======================================================
//             Main state machine logic
// =======================================================

localparam READY = 2'd0,        // Ready to process requests
           WRITEBACK = 2'd1,    // Waiting for write burst to complete after sending a dirty cache line to SDRAM
           LOADING = 2'd2,      // Waiting for read burst to complete after requesting a cache line from SDRAM
           WAIT = 2'd3;         // Wait one cycle for cache to update after writing to it
logic [1:0] state, next_state;           


always_comb begin
    do_send_buffer = 0;
    do_write_to_buffer = 0;
    do_write_cache = 0;
    do_update_tag = 0;
    do_read_request = 0;

    next_state = state;
    rdata = 32'bx;
    next_dcache_rvalid = 1'b0;
    dcache_ack = 1'b0;

    case (state)
        READY: begin

            // ---------------  WRITE REQUEST ---------------
            if (this_req && this_write) begin
                if (buffer_valid==1'b0 || write_buffer_match) begin
                    // If buffer is empty or already contains data for the same cache line,
                    // coalesce the write into the buffer
                    do_write_to_buffer = '1; 
                    do_write_cache = cache_hit;
                    dcache_ack = '1;

                end else if (dcache_sdramw_req==1'b0) begin
                    // Buffer contains data for a different cache line, but SDRAM is free to accept a new write, 
                    // so send the existing buffer to SDRAM and write the new request into the buffer
                    do_send_buffer = '1;
                    do_write_cache = cache_hit;
                    do_write_to_buffer = '1;
                    dcache_ack = '1;

                end else begin
                    // Buffer contains data for a different cache line, but SDRAM is busy with a previous write 
                    // Stall until SDRAM is free to accept this buffer, and don't accept the new request from the
                    // CPU until then
                end


            // ---------------  READ REQUEST ---------------
            end else if (this_req && !this_write) begin
                if (cache_hit) begin
                    // Cache hit - return data from cache
                    next_dcache_rvalid = '1;
                    rdata  = cache_data;
                    dcache_ack = '1;

                end else if (write_buffer_match && write_buffer_rvalid) begin
                    // Hit on the write buffer - return data from there
                    next_dcache_rvalid = '1;
                    rdata = write_buffer_rdata;
                    dcache_ack = '1;

                end else if (write_buffer_match && !write_buffer_rvalid) begin
                    // Address matches the write buffer but the relevant bytes aren't valid.
                    // We need to write the buffer to SDRAM, then read it back to get the most up-to-date data
                    if (!dcache_sdramw_req) begin
                        // SDRAM is free to accept a new write, so send the buffer to SDRAM and transition to WRITEBACK state to wait for it to be written
                        do_send_buffer = '1;
                        next_state = WRITEBACK;
                    end 

                end else begin
                    // Cache miss - request cache line from SDRAM and transition to LOADING state to wait for it
                    do_read_request = '1;
                    do_update_tag = '1;
                    next_state = LOADING;
                end

            // ---------------  NO REQUEST ---------------
            end else begin
                dcache_ack = '1;
            end
        end

        WRITEBACK: begin
            // Wait for the write burst to complete, then initiate the new read request
            if (dcache_sdramw_ack) begin
                do_read_request = '1;
                do_update_tag = '1;
                next_state = LOADING;
            end
        end

        LOADING: begin
            // The first beat of the burst will contain the requested word
            if (dcache_sdramr_rvalid == 2'b01) begin
                rdata = dcache_sdramr_rdata;
                next_dcache_rvalid = '1;
            end

            // Once the entire burst has been received, we can transition back to READY state
            if (dcache_sdramr_rvalid == 2'b11) begin
                next_state = WAIT;
            end
        end

        WAIT: begin
            // Wait one cycle for the cache to update after writing to it, then transition back to READY state
            dcache_ack = '1;
            next_state = READY;
        end

        default: 
            next_state = READY;
    endcase

    if (reset) begin
        next_state = READY;
    end
end

always_ff @(posedge clock) 
    state <= next_state;


wire unused = &{this_addr[1:0]};

endmodule
