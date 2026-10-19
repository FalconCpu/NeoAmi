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
    output  logic [7:0]   sdram_tag,      // Tag for the request
    input  logic [1:0]   sdram_rvalid,   // Read data valid
    input  logic [31:0]  sdram_rdata,    // Read data
    input  logic [7:0]   sdram_rtag      // Tag for the read data
);

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
logic        sample_strobe;
logic signed [15:0] sample_data;       
logic        sample_data_valid_left;
logic        sample_data_valid_right;


logic [15:0] sample_left_saturated;  // Left audio sample after saturation to 16 bits
logic [15:0] sample_right_saturated; // Right audio sample after saturation to 16 bits

always_ff @(posedge clock) begin
    if (reset || sample_strobe) begin
        sample_left <= 19'b0;
        sample_right <= 19'b0;
    end else begin
        if (sample_data_valid_left)
            sample_left <= sample_left + {3'b0, sample_data};
        if (sample_data_valid_right)
            sample_right <= sample_right + {3'b0, sample_data};
    end

    // Saturate the samples to 16 bits
    sample_left_saturated <= (sample_left > 19'sh0FFFF) ? 16'h7FFF :
                             (sample_left < 19'sh00000) ? 16'h0000 :
                              sample_left[15:0];
    sample_right_saturated <= (sample_right > 19'sh0FFFF) ? 16'h7FFF :
                              (sample_right < 19'sh00000) ? 16'h0000 :
                              sample_right[15:0];

end

// =================================================================
//                          Registers
// =================================================================
// Handle MMIO read and write accesses to the audio registers

logic [31:0] regs[0:63];    // 8 registers per channel * 8 channels
logic [31:0] rdata;
logic        rdata_valid;

assign hwregs_rdata = rdata_valid ? rdata : 32'b0;

// verilator lint_off BLKSEQ
always_ff @(posedge clock) begin
    rdata_valid <= hwregs_request && !hwregs_write && hwregs_addr[15:8]==8'h2;
    if (hwregs_request && hwregs_write && hwregs_addr[15:8]==8'h2)
        regs[hwregs_addr[7:2]] = hwregs_wdata;
    rdata <= regs[hwregs_addr[7:2]];
end

// =================================================================
//                    Local access to registers
// =================================================================

logic [5:0]   reg_addr;
logic [31:0]  reg_wdata;
logic         reg_wren;
logic [31:0]  reg_rdata;

always_ff @(posedge clock) begin
    if (reg_wren)
        regs[reg_addr] = reg_wdata;
    reg_rdata <= regs[reg_addr];
end


// =================================================================
//                    Waveform Cache
// =================================================================
// Store 32 bytes of waveform data for each channel
// This is written to by the sdram read logic

logic [31:0] waveform_cache[0:63];  // 8 channels, 32 bytes each
logic [26:0] waveform_cache_tag[0:15];  // 1 bit valid, 26 bit address
logic [25:0] sdram_raddr;
logic [5:0]  sdram_read_index;

always_ff @(posedge clock) begin
    if (sdram_rvalid!=2'b0) begin
        waveform_cache[sdram_read_index] <= sdram_rdata;
        waveform_cache_tag[sdram_read_index[5:2]] <= {sdram_rvalid==2'b11, sdram_raddr[25:0]};   // Set valid bit when line is complete
        sdram_read_index <= sdram_read_index + 1;
    end
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

logic [3:0]  state, next_state;

always_comb begin
    next_state = state;
    mult_a = 16'hx;
    mult_b = 16'hx;
    reg_addr = 6'hx;
    reg_wdata = 32'hx;
    reg_wren = 1'b0;
end


always_ff @(posedge clock) begin
    state <= next_state;
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

wire unused = &{hwregs_addr[1:0]};

endmodule
