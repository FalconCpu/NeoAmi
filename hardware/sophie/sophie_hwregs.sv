`timescale 1ns / 1ps

// Module for the hardware registers
//
// This creates a 64kb block sitting at address 0xE0000000 in the CPU address space.
//
// ADDRESS   REGISTER       R/W  DESCRIPTION
// E0000000  SEVEN_SEG      R/W  6 digit hexadecimal seven segment display
// E0000004  LEDR           R/W  10 LEDs
// E0000008  SW             R    10 Switches
// E000000C  KEY            R    4 Push buttons
// E0000010  UART_TX        R/W  Write = byte of data to transmit, read = number of slots free in fifo
// E0000014  UART_RX        R    1 byte of data from the uart, -1 if no data
// E0000018  MOUSE_X        R    Mouse X coordinate
// E000001C  MOUSE_Y        R    Mouse Y coordinate
// E0000020  MOUSE_BUTTONS  R    Mouse buttons (bit 0 = left, bit 1 = right, bit 2 = middle)
// E0000024  KEYBOARD       R    Keyboard data (-1 if no data)
// E0000028  TIMER          RW   Timer, count in milliseconds
// E000002C  I2C_OUT        W    I2C Data to send (24 bits). Reads 0=Ready, 1=Busy, 2=Error
// E0000030  SIMULATION     R    Reads as 1 in simulation, 0 in hardware
// E0000034  OVERFLOW       R    bit 0 = uart tx fifo overflow, bit 1 = uart rx fifo overflow, bit 2 = keyboard fifo overflow

// verilator lint_off PINCONNECTEMPTY


module sophie_hwregs (
    input  logic clock,
    input  logic reset,

    // Connection to the CPU bus
    input  logic        aux_hwregs_req,     // Request a read or write
    input  logic        aux_hwregs_write,   // 1 = write, 0 = read
    input  logic [15:0] aux_hwregs_addr,    // Address of data to read/write
    input  logic [3:0]  aux_hwregs_strb,    // For a write, which bytes to write.
    input  logic [31:0] aux_hwregs_wdata,   // Data to write
    output logic [31:0] aux_hwregs_rdata,   // Data read from memory

    // Connections to the chip pins
    output logic [6:0]	HEX0,
	output logic [6:0]	HEX1,
	output logic [6:0]	HEX2,
	output logic [6:0]	HEX3,
	output logic [6:0]	HEX4,
	output logic [6:0]	HEX5,
	input  logic [3:0]	KEY,
	output logic [9:0]	LEDR,
    input  logic [9:0]  SW,
    output logic        UART_TX,
    input  logic        UART_RX,
    inout               PS2_CLK,
    inout               PS2_DAT,
    inout               PS2_CLK2,
    inout               PS2_DAT2,
    inout               SDA,
    output              SCL,
    output logic [9:0]  mouse_x,
    output logic [9:0]  mouse_y,
    input  logic [31:0] cpu_pc             // Current CPU PC (for capture on seven seg)
);

logic [23:0] seven_seg;
logic [7:0]  fifo_tx_data;
logic        fifo_tx_complete;
logic        fifo_tx_not_empty;
logic [11:0] fifo_tx_slots_free;
logic [7:0]  fifo_rx_data;
logic        fifo_rx_not_empty;
logic [7:0]  uart_rx_data;
logic        uart_rx_complete;
logic [31:0] timer;
logic [2:0]  mouse_buttons;

logic [7:0]  keyboard_code;
logic        keyboard_strobe;
logic [7:0]  key_read_data;
logic        key_read_valid;
logic        i2c_busy;
logic        i2c_ack_error;
logic        i2c_start;
logic [23:0] i2c_data;
logic [17:0] milli_counter;

logic [23:0] captured_pc;
logic        prev_key0;
logic [2:0]  fifo_overflow, latched_fifo_overflow;

// synthesis translate_off
logic [7:0] uart_input[0:65535];
integer uart_input_len;
integer uart_input_index;
integer fh;
initial begin
    fh = $fopen("uart_log.bin","rb");
    uart_input_len = $fread(uart_input, fh);
    $fclose(fh);
    fh =  $fopen("rtl_uart.log", "wb");
    uart_input_index = 0;
end
// synthesis translate_on

always_ff @(posedge clock) begin
    aux_hwregs_rdata <= 32'b0;
    i2c_start <= 1'b0;
    latched_fifo_overflow <= fifo_overflow | latched_fifo_overflow;

    // Increment the millisecond timer
    if (milli_counter == 124999) begin
        milli_counter <= 0;
        timer <= timer + 1;
    end else
        milli_counter <= milli_counter + 1'b1;

    if (aux_hwregs_req && aux_hwregs_write) begin
        // Write to hardware registers
        case(aux_hwregs_addr)
            16'h0000: begin
                if (aux_hwregs_wdata[23:0] != seven_seg)
                    $display("[%t] 7SEG = %06X", $time, aux_hwregs_wdata[23:0]);
                if (aux_hwregs_strb[0]) seven_seg[7:0] <= aux_hwregs_wdata[7:0];
                if (aux_hwregs_strb[1]) seven_seg[15:8] <= aux_hwregs_wdata[15:8];
                if (aux_hwregs_strb[2]) seven_seg[23:16] <= aux_hwregs_wdata[23:16];
            end
            16'h0004: begin
                if (aux_hwregs_wdata[9:0] != LEDR)
                    $display("[%t] LED = %03X", $time, aux_hwregs_wdata[9:0]);
                if (aux_hwregs_strb[0])  LEDR[7:0] <= aux_hwregs_wdata[7:0];
                if (aux_hwregs_strb[1])  LEDR[9:8] <= aux_hwregs_wdata[9:8];
            end
            16'h0010: begin 
                // Writes to the UART TX are handled by the FIFO
                // synthesis translate_off
                $write("%c", aux_hwregs_wdata[7:0]);
                $fwrite(fh, "%c", aux_hwregs_wdata[7:0]);
                // synthesis translate_on
            end 
            16'h0028: begin
                if (aux_hwregs_strb[0])  timer[7:0] <= aux_hwregs_wdata[7:0];
                if (aux_hwregs_strb[1])  timer[15:8] <= aux_hwregs_wdata[15:8];
                if (aux_hwregs_strb[2])  timer[23:16] <= aux_hwregs_wdata[23:16];
                if (aux_hwregs_strb[3])  timer[31:24] <= aux_hwregs_wdata[31:24];
            end
            16'h002C: begin
                // I2C data out register
                i2c_data <= aux_hwregs_wdata[23:0];
                i2c_start <= 1'b1;
            end
            16'h0034: begin
                latched_fifo_overflow <= aux_hwregs_wdata[2:0];
            end
            default: begin end
        endcase

    end else if (aux_hwregs_req && !aux_hwregs_write) begin
        // Read from hardware registers
        case(aux_hwregs_addr)
            16'h0000: aux_hwregs_rdata <= {8'h00, seven_seg}; 
            16'h0004: aux_hwregs_rdata <= {22'b0, LEDR};
            16'h0008: aux_hwregs_rdata <= {22'b0, SW};
            16'h000C: aux_hwregs_rdata <= {28'b0, KEY};
            16'h0010: aux_hwregs_rdata <= {20'b0, fifo_tx_slots_free};
            16'h0014: begin
                aux_hwregs_rdata <= fifo_rx_not_empty ? {24'b0, fifo_rx_data} : 32'hffffffff;
                // synthesis translate_off
                aux_hwregs_rdata <= (uart_input_index < uart_input_len) ? {24'b0, uart_input[uart_input_index]} : 32'hffffffff;
                uart_input_index <= uart_input_index + 1;
                // synthesis translate_on
            end
            16'h0018: aux_hwregs_rdata <= {22'b0, mouse_x};
            16'h001C: aux_hwregs_rdata <= {22'b0, mouse_y};
            16'h0020: aux_hwregs_rdata <= {29'b0, mouse_buttons};
            16'h0024: aux_hwregs_rdata <= key_read_valid ? {24'b0, key_read_data} : 32'hffffffff;
            16'h0028: aux_hwregs_rdata <= timer;
            16'h002C: aux_hwregs_rdata <= {30'b0, i2c_ack_error, i2c_busy};
            16'h0030: begin
                        aux_hwregs_rdata <= 32'h00000000; // SIMULATION register
                        // synthesis translate_off
                        aux_hwregs_rdata <= 32'h00000001;
                        // synthesis translate_on
                      end
            16'h0034: aux_hwregs_rdata <= {29'b0, latched_fifo_overflow};
            default:  aux_hwregs_rdata <= 32'b0;
        endcase
    end

    if (reset) begin
        seven_seg <= 24'h000000;
        LEDR <= 10'b0;
        timer <= 0;
        latched_fifo_overflow <= 3'b0;
    end
end

always_ff @(posedge clock) begin
    // Capture the CPU PC when KEY0 is pressed
    if (KEY[1]==0 && prev_key0==1) begin
        // Key 0 pressed
        captured_pc <= cpu_pc[23:0];
    end
    prev_key0 <= KEY[1];
end


seven_seg  seven_seg_inst (
    .seven_seg_data(KEY[1] ? seven_seg : captured_pc[23:0]),
    .HEX0(HEX0),
    .HEX1(HEX1),
    .HEX2(HEX2),
    .HEX3(HEX3),
    .HEX4(HEX4),
    .HEX5(HEX5)
  );

uart  uart_inst (
    .clock(clock),
    .reset(reset),
    .UART_RX(UART_RX),
    .UART_TX(UART_TX),
    .rx_complete(uart_rx_complete),
    .rx_data(uart_rx_data),
    .tx_valid(fifo_tx_not_empty),
    .tx_data(fifo_tx_data),
    .tx_complete(fifo_tx_complete)
  );

wire tx_strobe = aux_hwregs_req && aux_hwregs_write && aux_hwregs_addr[15:0] == 16'h0010;

byte_fifo  uart_tx_fifo (
    .clk(clock),
    .reset(reset),
    .write_enable(tx_strobe),
    .write_data(aux_hwregs_wdata[7:0]),
    .read_enable(fifo_tx_complete),
    .read_data(fifo_tx_data),
    .slots_free(fifo_tx_slots_free),
    .not_empty(fifo_tx_not_empty),
    .overflow(fifo_overflow[0])
  );

wire rx_strobe = aux_hwregs_req && !aux_hwregs_write && aux_hwregs_addr[15:0] == 16'h0014;

byte_fifo  uart_rx_fifo (
    .clk(clock),
    .reset(reset),
    .write_enable(uart_rx_complete),
    .write_data(uart_rx_data),
    .read_enable(rx_strobe),
    .read_data(fifo_rx_data),
    .slots_free(),
    .not_empty(fifo_rx_not_empty),
    .overflow(fifo_overflow[1])
  );

mouse_interface  mouse_interface_inst (
    .clock(clock),
    .reset(reset),
    .PS2_CLK(PS2_CLK),
    .PS2_DAT(PS2_DAT),
    .mouse_x(mouse_x),
    .mouse_y(mouse_y),
    .mouse_buttons(mouse_buttons)
  );  

keyboard_if  keyboard_if_inst (
    .clock(clock),
    .reset(reset),
    .PS2_CLK2(PS2_CLK2),
    .PS2_DAT2(PS2_DAT2),
    .keyboard_code(keyboard_code),
    .keyboard_strobe(keyboard_strobe)
  );

wire key_read_strobe = aux_hwregs_req && !aux_hwregs_write && aux_hwregs_addr[15:0] == 16'h002C;

byte_fifo  keyboard_rx_fifo (
    .clk(clock),
    .reset(reset),
    .write_enable(keyboard_strobe),
    .write_data(keyboard_code),
    .read_enable(key_read_strobe),
    .read_data(key_read_data),
    .slots_free(),
    .not_empty(key_read_valid),
    .overflow(fifo_overflow[2])
  );

i2c_master  i2c_master_inst (
    .clock(clock),
    .reset(reset),
    .SDA(SDA),
    .SCL(SCL),
    .start(i2c_start),
    .data_in(i2c_data),
    .busy(i2c_busy),
    .ack_error(i2c_ack_error)
  );

wire unused = &{cpu_pc[31:24]};

endmodule
