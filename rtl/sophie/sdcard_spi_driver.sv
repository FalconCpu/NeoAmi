`timescale 1ns/1ns

module sdcard_spi_driver (
    input  logic         clock,     // 50MHz clock
    input  logic         reset,

    input  logic         send_cmd,
    input  logic         expect_data,
    input  logic [47:0]  cmd_packet,  // 48-bit CMD0 packet (MSB first)
    input  logic [9:0]   response_length,  // Length of the response in bytes
    output logic         response_valid,
    output logic [7:0]  response_data,

    output logic         sd_cs,
    output logic         sd_sclk,
    output logic         sd_mosi,
    input  logic         sd_miso
);

logic [7:0]   clk_div;
logic [47:0]  cmd_shift_reg;
logic [5:0]   tx_bit_count;            // Counts the number of bits transmitted in the command

logic [7:0]  rx_shift_reg;             // Shift register for receiving response bits
logic [2:0]   rx_bit_count;            // Counts the number of bits received in the response
logic [9:0]   rx_byte_count;           // Counts the number of bytes received in the response

typedef enum logic [1:0] {
    TX_IDLE,
    TX_TRANSMITTING
} TxState;
TxState tx_state;


typedef enum logic [1:0] {
    RX_IDLE,
    RX_WAIT_START,
    RX_RECEIVING,
    RX_WAIT_START_DATA
} RxState;
RxState rx_state;


always_ff @(posedge clock) begin

    if (send_cmd) begin
        cmd_shift_reg <= cmd_packet;
        rx_byte_count <= response_length;
        tx_bit_count <= 6'd0;
        tx_state <= TX_TRANSMITTING;
    end

    if (expect_data) begin
        rx_byte_count <= response_length;
        rx_state <= RX_WAIT_START_DATA;
    end

    // Shift the command register on each clock cycle
    clk_div <= clk_div + 8'd1;
    sd_sclk <= clk_div[7];
    response_valid <= 1'b0;

    if (clk_div==8'd0) begin        
        // We output data on the falling edge of the clock
        sd_cs <= !(tx_state!=TX_IDLE || rx_state!=RX_IDLE || rx_byte_count!=10'd0);
        if (tx_state == TX_TRANSMITTING) begin
            sd_mosi <= cmd_shift_reg[47];
            cmd_shift_reg <= {cmd_shift_reg[46:0], 1'b1};
            tx_bit_count <= tx_bit_count + 6'd1;
            if (tx_bit_count == 6'd47) begin
                // Transmission of the command is complete, prepare to receive the response
                tx_state <= TX_IDLE;
                rx_state <= RX_WAIT_START;
                rx_bit_count <= 3'd0;
            end
        end else begin
            sd_mosi <= 1'b1; // Idle state for MOSI when not transmitting
        end

    end else if (clk_div==8'd128) begin
        // Sample the response on the rising edge of the clock
        case (rx_state)
            RX_IDLE: begin
                // Do nothing in RX_IDLE state
            end
            RX_WAIT_START: begin
                if (sd_miso == 1'b0) begin
                    // Start bit of the response detected
                    rx_state <= RX_RECEIVING;
                    rx_shift_reg <= {rx_shift_reg[6:0], sd_miso};
                    rx_bit_count <= 3'd1;
                end
            end
            RX_RECEIVING: begin
                rx_shift_reg <= {rx_shift_reg[6:0], sd_miso};
                rx_bit_count <= rx_bit_count + 3'd1;
                if (rx_bit_count == 3'd7) begin
                    response_valid <= 1'b1;
                    rx_byte_count <= rx_byte_count - 10'd1;
                    if (rx_byte_count==10'd1)
                        rx_state <= RX_IDLE;
                end
            end
            RX_WAIT_START_DATA: begin
                if (sd_miso == 1'b0) begin
                    // Start bit of the response detected
                    rx_state <= RX_RECEIVING;
                    rx_shift_reg <= {rx_shift_reg[6:0], sd_miso};
                    rx_bit_count <= 3'd0;
                end
            end
            default: begin
                // Should not happen
                rx_state <= RX_IDLE; 
            end
        endcase
    end

    if (reset) begin
        clk_div <= 8'd0;
        response_valid <= 1'b0;
        tx_state <= TX_IDLE;
        rx_state <= RX_IDLE;
        rx_byte_count <= 10'd0;
    end
end

assign response_data = rx_shift_reg;

endmodule
