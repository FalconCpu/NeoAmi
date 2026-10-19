`timescale 1ns/1ns

// Simple SPI master module for interfacing with an SD card
//
// Commands are sent as 48-bit values over the SPI interface to the SD card
// 


module spi_master (
    input  logic        clock,
    input  logic        reset,

    input  logic        sdcard_enable,      // Assert the CS (Chip Select) for the SD card
    input  logic        sdcard_clk_fast,    // Select fast clock speed for the SD card
    input  logic [47:0] sdcard_cmd,         // SD card command to be sent over SPI
    output logic        sdcard_cmd_ack,     // Acknowledge for the SD card command

    output logic        sdcard_rx_valid,    // Indicates that the data received from the SD card is valid
    output logic [7:0]  sdcard_rx,          // Data received from the SD card over SPI

    // SD card SPI interface signals
    output logic        SD_CS,
    output logic        SD_SCLK,
    output logic        SD_MOSI,
    input  logic        SD_MISO
);

// =======================================================================
//                Clock divider for generating the SPI clock
// =======================================================================
// Generate a slow speed SPI clock from the system clock
// Signals are driven on the falling edge of the SPI clock, and sampled on the rising edge.

logic [7:0] clk_divider;
logic [2:0] bit_counter;
logic [2:0] byte_counter;

always_ff @(posedge clock) begin
    if (reset) begin
        clk_divider <= 8'd0;
        bit_counter <= 3'd0;
        byte_counter <= 3'd0;
    end else begin
        if (sdcard_clk_fast)
            clk_divider <= {clk_divider[7:5]+1'b1, 5'b0};
        else
            clk_divider <= clk_divider + 8'd1;
        if (clk_divider == 8'hFF || (clk_divider[7:5] == 3'h7 && sdcard_clk_fast)) begin
            bit_counter <= bit_counter + 3'd1;
            if (bit_counter == 3'd7)
                byte_counter <= byte_counter + 3'd1;
        end
    end
    
    // Drive the SPI clock only when the SD card is selected
    SD_SCLK <= clk_divider[7] & !SD_CS;
end

// =======================================================================
//                Output shift register
// =======================================================================

logic [47:0] shift_reg;

always_ff @(posedge clock) begin
    sdcard_cmd_ack <= 1'b0;
    SD_MOSI <= shift_reg[47];

    if (clk_divider==8'h0) begin
        if (bit_counter==3'd0 && byte_counter==3'd0) begin
            if (sdcard_cmd[31:0]!=32'hffffffff) begin
                // Only accept a command if the lower 32 bits are not all ones 
                // This is to allow the CPU to load the command register in two separate writes.
                shift_reg <= sdcard_cmd;
                sdcard_cmd_ack <= 1'b1;
            end
            SD_CS <= !sdcard_enable;
        end else 
            shift_reg <= {shift_reg[46:0], 1'b1};
    end

    if (reset) 
        shift_reg <= 48'hffffffffffff;
    
end

// =======================================================================
//                Input shift register
// =======================================================================

always_ff @(posedge clock) begin
    sdcard_rx_valid <= 1'b0;
    if (clk_divider==8'h80) begin      // Sample on the rising edge of the SPI clock
        sdcard_rx <= {sdcard_rx[6:0], SD_MISO};
        if (bit_counter==3'd7)
            sdcard_rx_valid <= 1'b1;
    end
end


endmodule
