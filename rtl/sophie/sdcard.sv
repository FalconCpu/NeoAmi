`timescale 1ns/1ns

// SD Card interface module



module sdcard (
    input logic         clock,
    input logic         reset,

    // Interface to Sophie registers
	output logic        sdcard_busy,

	input logic         sdcard_start_read,
    input logic         sdcard_start_write,
	input logic [8:0]   sdcard_sector,

	output logic [8:0]  sdcard_byte_addr,
    input logic [31:0]  sdcard_wdata,
    output logic [31:0] sdcard_rdata,
	output logic        sdcard_read_strobe,
	output logic        sdcard_write_strobe,

    // Connection to the actual SD IOs
    output logic         sd_cs,
    output logic         sd_sclk,
    output logic         sd_mosi,
    input  logic         sd_miso

);

// ================================================================
//                  SDCARD state machine
// ================================================================

logic [4:0] seq_state;
logic [15:0] startup_timer;

logic        sdcard_send_cmd;
logic [47:0] sdcard_cmd_packet;
logic        sdcard_response_valid;
logic [7:0]  sdcard_response_data;
logic [9:0]  sdcard_response_length;
logic        sdcard_expect_data;

always @(posedge clock) begin
	sdcard_send_cmd <= 1'b0;
	sdcard_expect_data <= 1'b0;
	sdcard_read_strobe <= 1'b0;
	sdcard_write_strobe <= 1'b0;

	case (seq_state)
		5'd0: begin
			// Wait for the startup timer to expire before sending the first command
			startup_timer <= startup_timer + 1;
			if (startup_timer == 16'hFFFF)
				seq_state <= seq_state + 5'd1;
		end
		5'd1: begin
			// Send CMD0 to the SD card
			sdcard_cmd_packet <= 48'h400000000095;
			sdcard_response_length <= 10'd1; // CMD0 response length is 1 byte
			sdcard_send_cmd <= 1'b1;
			seq_state <= seq_state + 5'd1;
		end
		5'd2: begin
			// Expecting R1 response with idle bit set (0x01)
			if (sdcard_response_valid)
				if (sdcard_response_data==8'h01)
					seq_state <= seq_state + 5'd1;
				else
					seq_state <= 5'd31; // Error state if CMD0 response is not as expected
		end
		5'd3: begin
			// Send CMD8 to the SD card
			sdcard_cmd_packet <= 48'h48000001AA87;
			sdcard_response_length <= 10'd5; 
			sdcard_send_cmd <= 1'b1;
			seq_state <= seq_state + 5'd1;
		end
		5'd4: begin
			// Expecting R7 response from CMD8 - Expect 01 00 00 01 AA
			if (sdcard_response_valid)
				if (sdcard_response_data==8'h01)
					seq_state <= seq_state + 5'd1;
				else
					seq_state <= 5'd31; // Error state if CMD8 response is not as expected
		end
		5'd5: begin
			if (sdcard_response_valid)
				if (sdcard_response_data==8'h00)
					seq_state <= seq_state + 5'd1;
				else
					seq_state <= 5'd31;
		end
		5'd6: begin
			if (sdcard_response_valid)
				if (sdcard_response_data==8'h00)
					seq_state <= seq_state + 5'd1;
				else
					seq_state <= 5'd31;
		end
		5'd7: begin
			if (sdcard_response_valid)
				if (sdcard_response_data==8'h01)
					seq_state <= seq_state + 5'd1;
				else
					seq_state <= 5'd31;
		end
		5'd8: begin
			if (sdcard_response_valid)
				if (sdcard_response_data==8'hAA)
					seq_state <= seq_state + 5'd1;
				else
					seq_state <= 5'd31;
		end
		5'd9: begin
			// Send cmd 55 to the SD card
			sdcard_cmd_packet <= 48'h770000000065;
			sdcard_response_length <= 10'd1;
			sdcard_send_cmd <= 1'b1;
			seq_state <= seq_state + 5'd1;
		end
		5'd10: begin
			// Expecting R1 response from CMD55
			if (sdcard_response_valid)
				if (sdcard_response_data==8'h01)
					seq_state <= seq_state + 5'd1;
				else
					seq_state <= 5'd31;
		end
		5'd11: begin
			// Send ACMD41 to the SD card
			sdcard_cmd_packet <= 48'h694000000077; // ACMD41 command
			sdcard_response_length <= 10'd1;
			sdcard_send_cmd <= 1'b1;
			seq_state <= seq_state + 5'd1;
		end
		5'd12: begin
			// We should get a zero response from ACMD41 indicating the card is ready
			// Non-zero means the card is still initializing
			if (sdcard_response_valid)
				if (sdcard_response_data==8'h00)
					seq_state <= seq_state + 5'd1;
				else
					seq_state <= 5'd9; // Loop back to CMD55/ACMD41 sequence if card is not ready
		end
		5'd13: begin
			// Now try to read a sector from the SD card
			sdcard_cmd_packet <= 48'h5100000000FF; // CMD17 command to read a single block
			sdcard_response_length <= 10'd1;
			sdcard_expect_data <= 1'b1;
			sdcard_send_cmd <= 1'b1;
			seq_state <= seq_state + 5'd1;
		end
		5'd14: begin
			// Expect the card to respond back with a 00
			sdcard_byte_addr <= 9'd0; // Initialize byte address for reading data
			if (sdcard_response_valid) begin
				if (sdcard_response_data==8'h00) begin
					seq_state <= seq_state + 5'd1;
					sdcard_response_length <= 10'd515; // 1 byte header + 512 bytes data + 2 bytes CRC
					sdcard_expect_data <= 1'b1; // Signal to start receiving data from the SD card
				end else
					seq_state <= 5'd31; 
			end
		end
		5'd15: begin
			// The sdcard should send the data next.
			if (sdcard_response_valid) begin
				sdcard_rdata[sdcard_byte_addr[1:0]*8 +: 8] <= sdcard_response_data;
				sdcard_read_strobe <= sdcard_byte_addr[1:0] == 2'd3;
				sdcard_byte_addr <= sdcard_byte_addr + 9'd1;
			end
			
		end


		5'd31: begin
			// Error state
			seq_state <= 5'd0; // Retry after error
		end

	endcase

	if (reset) begin
		seq_state <= 5'd0;
        startup_timer <= 16'd0;
    end

	sdcard_busy <= (seq_state != 5'd15);

	if (sdcard_start_read)
		seq_state <= 5'd13;
end



// ================================================================
//                  SDCARD spi driver
// ================================================================

sdcard_spi_driver  sdcard_spi_driver_inst (
    .clock(clock),
    .reset(reset),
    .send_cmd(sdcard_send_cmd),
    .expect_data(sdcard_expect_data),
    .cmd_packet(sdcard_cmd_packet),
    .response_length(sdcard_response_length),
    .response_valid(sdcard_response_valid),
    .response_data(sdcard_response_data),
    .sd_cs(sd_cs),
    .sd_sclk(sd_sclk),
    .sd_mosi(sd_mosi),
    .sd_miso(sd_miso)
  );

endmodule
