`timescale 1ns/1ns
// Audio Register Map
// where X is 0..7 for 8 audio channels
// 0xE0000200     AUDIO_ADDRESS        start address of sample
// 0xE0000204     AUDIO_VOLUME         (right in high 16 bits, left in low 16 bits)
// 0xE000020C     AUDIO_FREQUENCY      sample rate. 0x10000=48kHz, 0x8000=24kHz, 0x4000=12kHz etc
// 0xE0000210     AUDIO_END_ADDR       end address of sample
// 0xE0000214     AUDIO_LOOP_ADDR      address to loop back to
// 0xE0000218     AUDIO_OUT            output sample (read-only)
// The above registers repeat *8
//
//
// Internal structure:
// 
// A single on-chip memory is used to store the state of all 8 audio channels. A state 
// machine cycles through each channel, fetching samples from memory, updating accumulators, and handling looping and output.
//
// The internal memory is allocated as follows (_ = channel index)
// address   function
//   0x0_0    Start address
//   0x0_1    Volume (right in high 16 bits, left in low 16 bits)
//   0x0_2    Frequency
//   0x0_3    Length
//   0x0_4    Loop position (index to loop back to, -1 if no loop)
//   0x0_5    Audio out (read-only - current sample)
//   0x0_6    Current position - integer bits
//   0x0_7    Current position - fractional bits (16 bit resolution)
//   0x0_8    cache-tag 0
//   0x0_9    cache-tag 1
//   0x1_0:7  Data cache
//
// The first half of this internal memory is mapped into MMIO registers for CPU access - at address 0xE0000400-0xE00007FF
// (Byte access is not supported - all accesses must be 32-bit aligned)
// 
// Writing to start address triggers the audio channel to start playing from the specified address.


module audio (
    input logic        clock,
    input logic        reset,

    // Memory-mapped register interface
    input  logic        hwregs_request,     // Request a read or write
    input  logic        hwregs_write,       // 1 = write, 0 = read
    input  logic [15:0] hwregs_addr,        // Address of data to read/write
    input  logic [31:0] hwregs_wdata,       // Data to write
    output logic [31:0] hwregs_rdata,       // Data read

    // I2S interface to audio codec
    output logic        AUD_XCK,            // MCLK
    output logic        AUD_BCLK,           // BCLK
    output logic        AUD_DACLRCK,        // LRCLK
    output logic        AUD_DACDAT,         // DACDAT

    // SDRAM interface (externally wired to always read bursts)
    output logic         sdram_request,  // Request memory
    input  logic         sdram_ack,      // SDRAM is ready for a request
    output logic [25:0]  sdram_address,  // Address
    input  logic [1:0]   sdram_rvalid,   // Read data valid
    input  logic [31:0]  sdram_rdata     // Read data
);

localparam NUM_CHANNELS     = 16;
localparam REG_ADDR         = 4'h0;
localparam REG_VOLUME       = 4'h1;
localparam REG_FREQUENCY    = 4'h2;
localparam REG_LENGTH       = 4'h3;
localparam REG_LOOP_POS     = 4'h4;
localparam REG_AUDIO_OUT    = 4'h5;
localparam REG_CUR_POS      = 4'h6;
localparam REG_CUR_FRAC     = 4'h7;
localparam REG_CACHE_TAG0   = 4'h8;
localparam REG_CACHE_TAG1   = 4'h9;

logic [3:0]              channel, next_channel;


// =================================================================
//               Local register RAM
// =================================================================
// 512 * 32 bit register memory - used to store audio channel registers for 16 channels,
// 16 registers per channel, and 4*16 bytes of waveform cache per channel
//
// This dual ported memory can be accessed by both the CPU and the audio processing logic internally

logic [31:0] regs[0:511];    // 8 registers per channel * 8 channels

// Writing to the address field triggers the start signal for the corresponding channel
logic [NUM_CHANNELS-1:0] start_signals;
logic                    start_signal_ack;



// CPU-side access
logic [31:0] rdata;
logic        rdata_valid;

always_ff @(posedge clock) begin
    // verilator lint_off BLKSEQ
    rdata_valid <= hwregs_request && !hwregs_write && hwregs_addr[15:10]==6'h1;
    if (hwregs_request && hwregs_write && hwregs_addr[15:10]==6'h1)
        regs[{1'b0, hwregs_addr[9:2]}] = hwregs_wdata;
    if (hwregs_request && hwregs_write && hwregs_addr[15:10]==6'h1 && hwregs_addr[5:2]==REG_ADDR)
        start_signals[hwregs_addr[9:6]] <= 1'b1;
    rdata <= regs[{1'b0, hwregs_addr[9:2]}];

    if (start_signal_ack)
        start_signals[channel] <= 1'b0;
    if (reset)
        start_signals <= 'b0;
end

initial begin
    integer i;
    for (i = 0; i < 512; i = i + 1)
        regs[i] = 32'hFFFFFFFF;
end

assign hwregs_rdata = rdata_valid ? rdata : 32'b0;

// Local access to registers by the audio processing logic
logic [8:0]   reg_addr;
logic [31:0]  reg_wdata;
logic         reg_wren;
logic [31:0]  reg_rdata;

always_ff @(posedge clock) begin
    if (reg_wren)
        regs[reg_addr] = reg_wdata;
    reg_rdata <= regs[reg_addr];
end



// ================================================================
//         Sample accumulators       
// ================================================================
// Keep a running sum of the audio samples for left and right channels
// 
// The accumulators are 19 bits wide to provide 3 bits of headroom beyond the 16-bit audio samples
// This allows for accumulation without immediate risk of overflow.
// The sample_strobe signal indicates when a new sample is available and should be accumulated.

logic signed [18:0] sample_left;       // Left audio sample - 16 bit of sample + 3 bits of headroom
logic signed [18:0] sample_right;      // Right audio sample - 16 bit of sample + 3 bits of headroom
logic               sample_strobe;     // The I2S has consumed the sample data - signal to begin processing the next sample

logic signed [15:0] next_sample_data;  // New data from the audio state machine
logic               inc_sample_left;
logic               inc_sample_right;


logic signed [15:0] sample_left_saturated;  // Left audio sample after saturation to 16 bits
logic signed [15:0] sample_right_saturated; // Right audio sample after saturation to 16 bits

always_ff @(posedge clock) begin
    if (reset || sample_strobe) begin
        sample_left <= 19'b0;
        sample_right <= 19'b0;
    end else begin
        if (inc_sample_left)
            sample_left <= sample_left + {{3{next_sample_data[15]}}, next_sample_data};
        if (inc_sample_right)
            sample_right <= sample_right + {{3{next_sample_data[15]}}, next_sample_data};
    end

    // Saturate the samples to 16 bits
    sample_left_saturated <= (sample_left > 19'sh0FFFF) ? 16'h7FFF :
                             (sample_left <-19'sh08000) ? 16'h8000 :
                              sample_left[15:0];
    sample_right_saturated <= (sample_right > 19'sh0FFFF) ? 16'h7FFF :
                              (sample_right < 19'sh08000) ? 16'h8000 :
                              sample_right[15:0];
end


// =================================================================
//                    Multiplier
// =================================================================

logic signed [15:0]  mult_a;
logic signed [15:0]  mult_b;
logic signed [31:0]  mult_result;

always_ff @(posedge clock) begin
    mult_result <= mult_a * mult_b;
end


// =================================================================
//                    State Machine
// =================================================================

logic [4:0]  state, next_state;
logic [3:0]  fetch_state, next_fetch_state;
logic [25:0] address, next_address;
logic [31:0] frequency, next_frequency;
logic [31:0] length, next_length;
logic [31:0] loop_pos, next_loop_pos;
logic [15:0] volume_left, next_volume_left;
logic [15:0] volume_right, next_volume_right;
logic [31:0] current_position, next_current_position;
logic [31:0] current_fractional, next_current_fractional;
logic [25:0] fetch_address, next_fetch_address;
logic [25:0] fetch_cache_address, next_fetch_cache_address;
logic        start_fetch, next_start_fetch;
logic [7:0]  fetch_data, next_fetch_data;
logic        fetch_data_valid, next_fetch_data_valid;
logic [1:0]  fetch_count, next_fetch_count;
logic        next_sdram_request;
logic [25:0] next_sdram_address;

localparam STATE_CHECK_START = 5'h00;
localparam STATE_LOAD_POS    = 5'h02;
localparam STATE_LOAD_FRAC   = 5'h03;
localparam STATE_LOAD_ADDR   = 5'h04;
localparam STATE_LOAD_VOL    = 5'h05;
localparam STATE_LOAD_FREQ   = 5'h06;
localparam STATE_LOAD_LOOP   = 5'h07;
localparam STATE_LOAD_LENGTH = 5'h08;
localparam STATE_FETCH_DATA = 5'h09;
localparam STATE_MULT = 5'h0A;
localparam STATE_ADD_L      = 5'h0B;
localparam STATE_ADD_R      = 5'h0C;
localparam STATE_STORE_POS  = 5'h0D;
localparam STATE_STORE_FRAC = 5'h0E;
localparam STATE_FINISHED   = 5'h1f;

localparam FETCH_STATE_IDLE          = 4'h0;
localparam FETCH_STATE_SEND_REQ      = 4'h1;
localparam FETCH_STATE_RCV_DATA      = 4'h2;
localparam FETCH_STATE_RCV_COMPLETE = 4'h3;
localparam FETCH_STATE_DATA          = 4'h4;

always_comb begin
    next_state   = state;
    next_fetch_state = fetch_state;
    next_channel = channel;
    next_fetch_address = fetch_address;
    next_fetch_cache_address = fetch_cache_address;
    next_address = address;
    next_frequency = frequency;
    next_length = length;
    next_loop_pos = loop_pos;
    next_volume_left = volume_left;
    next_volume_right = volume_right;
    next_current_position = current_position;
    next_current_fractional = current_fractional;
    next_fetch_data_valid = fetch_data_valid;
    next_fetch_data = fetch_data;
    next_fetch_count = fetch_count;
    next_start_fetch = 1'b0;
    mult_a       = 16'hx;
    mult_b       = 16'hx;
    reg_addr     = 9'hx;
    reg_wdata    = 32'hx;
    reg_wren     = 1'b0;
    start_signal_ack = 1'b0;
    next_sdram_request = 1'b0;
    next_sdram_address = sdram_address;
    next_sample_data = 16'hx;
    inc_sample_left = 1'b0; 
    inc_sample_right = 1'b0; 
    

    // ----------------------------------------------------
    //            Audio Channel State Machine
    // ----------------------------------------------------

    case (state)
        STATE_CHECK_START: begin
            if (start_signals[channel]) begin
                next_current_position = 32'b0;
                next_current_fractional = 32'b0;
                reg_addr = {1'b0, channel, REG_ADDR};
                next_state = STATE_LOAD_ADDR;
                start_signal_ack = 1'b1;
            end else begin
                reg_addr = {1'b0, channel, REG_CUR_POS};
                next_state = STATE_LOAD_POS;
            end
        end

        STATE_LOAD_POS: begin
            next_current_position = reg_rdata;
            if (reg_rdata==32'hFFFFFFFF) begin
                next_state = STATE_FINISHED;
            end else begin
                reg_addr = {1'b0, channel, REG_CUR_FRAC};
                next_state = STATE_LOAD_FRAC;
            end
        end

        STATE_LOAD_FRAC: begin
            next_current_fractional = reg_rdata;
            reg_addr = {1'b0, channel, REG_ADDR};
            next_state = STATE_LOAD_ADDR;
        end

        STATE_LOAD_ADDR: begin
            next_address = reg_rdata[25:0];
            reg_addr = {1'b0, channel, REG_VOLUME};
            next_state = STATE_LOAD_VOL;
        end

        STATE_LOAD_VOL: begin
            next_volume_left = reg_rdata[15:0];
            next_volume_right = reg_rdata[31:16];

            reg_addr = {1'b0, channel, REG_FREQUENCY};
            next_state = STATE_LOAD_FREQ;
        end
        
        STATE_LOAD_FREQ: begin
            next_frequency = reg_rdata;
            reg_addr = {1'b0, channel, REG_LOOP_POS};
            next_state = STATE_LOAD_LOOP;
        end

        STATE_LOAD_LOOP: begin
            next_loop_pos = reg_rdata;
            reg_addr = {1'b0, channel, REG_LENGTH};
            next_state = STATE_LOAD_LENGTH;
        end

        STATE_LOAD_LENGTH: begin
            next_length = reg_rdata;

            next_fetch_address = address + current_position[25:0];
            next_start_fetch = 1'b1;
            next_state = STATE_FETCH_DATA;
        end

        STATE_FETCH_DATA: begin
            if (fetch_data_valid && !start_fetch) begin
                next_state = STATE_MULT;
            end else begin
                next_state = STATE_FETCH_DATA;
            end
        end


        STATE_MULT: begin 
            mult_a = {{8{fetch_data[7]}}, fetch_data};
            mult_b = volume_left;
            next_current_fractional = current_fractional + frequency;

            reg_addr = {1'b0, channel, REG_AUDIO_OUT};
            reg_wren = 1'b1;
            reg_wdata = {{24{fetch_data[7]}}, fetch_data};
            next_state = STATE_ADD_L;
        end

        STATE_ADD_L: begin 
            next_sample_data = mult_result[15:0];
            inc_sample_left = 1'b1;
            mult_a = {{8{fetch_data[7]}}, fetch_data};
            mult_b = volume_right;
            next_current_position = current_position + {16'b0,current_fractional[31:16]};
            next_state = STATE_ADD_R;
        end

        STATE_ADD_R: begin 
            next_sample_data = mult_result[15:0];
            inc_sample_right = 1'b1;
            reg_wren = 1'b1;
            reg_wdata = {{24{fetch_data[7]}}, fetch_data};
            if (current_position >= length) begin
                if (loop_pos != 32'hffffffff) begin
                    next_current_position = current_position - loop_pos;
                end else begin
                    next_current_position = 32'hffffffff;
                end
            end
            next_state = STATE_STORE_POS;
        end
            
        STATE_STORE_POS: begin 
            reg_addr = {1'b0, channel, REG_CUR_POS};
            reg_wren = 1'b1;
            reg_wdata = next_current_position;
            next_state = STATE_STORE_FRAC;
        end

        STATE_STORE_FRAC: begin 
            reg_addr = {1'b0, channel, REG_CUR_FRAC};
            reg_wren = 1'b1;
            reg_wdata = {16'b0, next_current_fractional[15:0]};
            next_state = STATE_FINISHED;
        end


        STATE_FINISHED: begin
            if (channel!=4'd15) begin
                next_channel = channel + 4'd1;
                next_state = STATE_CHECK_START;
            end else begin
                // Wait for the sample strobe for the next sample
                next_state = STATE_FINISHED;
            end
        end

        default: begin
            next_state = STATE_FINISHED;
        end
    endcase


    // ----------------------------------------------------
    //             Fetch State Machine
    // ----------------------------------------------------

    case (fetch_state)
        FETCH_STATE_IDLE: begin
            if (start_fetch) begin
                reg_addr = {1'b0, channel, fetch_address[4] ? REG_CACHE_TAG1 : REG_CACHE_TAG0 };
                next_fetch_data_valid = 1'b0;
                next_fetch_state = FETCH_STATE_SEND_REQ;
            end
        end

        FETCH_STATE_SEND_REQ: begin
            if (reg_rdata[25:4]==fetch_address[25:4]) begin
                // Hit in cache - so no need to request data from SDRAM
                reg_addr = {1'b1, channel, 1'b0, fetch_address[4:2]};
                next_fetch_state = FETCH_STATE_DATA;

            end else begin
                // Miss in cache - request data from SDRAM
                next_sdram_request = 1'b1;
                next_sdram_address = fetch_address;
                reg_addr = {1'b0, channel, fetch_address[4] ? REG_CACHE_TAG1 : REG_CACHE_TAG0 };
                if (sdram_ack) begin
                    reg_wren = 1'b1;    // Update cache tag with fetch address
                    reg_wdata = {6'b0,fetch_address};
                    next_fetch_count = 2'b0;
                    next_fetch_state = FETCH_STATE_RCV_DATA;
                end else begin
                    // Stay in this state until SDRAM acknowledges the request
                    reg_addr = {1'b0, channel, fetch_address[4] ? REG_CACHE_TAG1 : REG_CACHE_TAG0 };
                    next_fetch_state = FETCH_STATE_SEND_REQ;
                end
            end
        end

        FETCH_STATE_RCV_DATA: begin
            if (sdram_rvalid!=2'b00) begin
                reg_addr = {1'b1, channel, 1'b0, fetch_address[4], fetch_count};
                reg_wren = 1'b1;
                reg_wdata = sdram_rdata;
                next_fetch_count = fetch_count + 1'b1;
                if (sdram_rvalid==2'b11)
                    next_fetch_state = FETCH_STATE_RCV_COMPLETE;
            end
        end

        FETCH_STATE_RCV_COMPLETE: begin
            reg_addr = {1'b1, channel, 1'b0, fetch_address[4:2]};
            next_fetch_state = FETCH_STATE_DATA;
        end

        FETCH_STATE_DATA: begin
            next_fetch_data_valid = 1'b1;
            next_fetch_data = reg_rdata[fetch_address[1:0]*8 +: 8];
            next_fetch_state = FETCH_STATE_IDLE;
        end

        default: begin
            next_fetch_state = FETCH_STATE_IDLE;
        end
    endcase



    if (reset || sample_strobe) begin
        next_fetch_state = FETCH_STATE_IDLE;
        next_state = STATE_CHECK_START;
        next_channel = 4'h0;
    end
end


always_ff @(posedge clock) begin
    state   <= next_state;
    fetch_state <= next_fetch_state;
    channel <= next_channel;
    address <= next_address;
    frequency <= next_frequency;
    length <= next_length;
    loop_pos <= next_loop_pos;
    volume_left <= next_volume_left;
    volume_right <= next_volume_right;
    current_position <= next_current_position;
    current_fractional <= next_current_fractional;
    start_fetch <= next_start_fetch;
    fetch_address <= next_fetch_address;
    fetch_cache_address <= next_fetch_cache_address;
    fetch_data <= next_fetch_data;
    fetch_data_valid <= next_fetch_data_valid;
    fetch_count <= next_fetch_count;
    sdram_request <= next_sdram_request;
    sdram_address <= next_sdram_address;
end





// =================================================================
//                          I2S Output
// =================================================================

i2s_output  i2s_output_inst (
    .clock(clock),
    .reset(reset),
    .sample_left(sample_left_saturated),
    .sample_right(sample_right_saturated),
    .sample_strobe(sample_strobe),      // Driven high for one clock when samples have been consumed
    .AUD_MCLK(AUD_XCK),
    .AUD_BCLK(AUD_BCLK),
    .AUD_LRCLK(AUD_DACLRCK),
    .AUD_DACDAT(AUD_DACDAT)
  );

wire unused = &{hwregs_addr[1:0], mult_result[15:0]};

endmodule
