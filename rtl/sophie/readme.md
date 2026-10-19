# SOPHIE (System Organisation and Peripheral Hardware IntEgration)

SOPHIE is the "glue" for the system. It is responsible for arbitrating access to the memory bus, decoding the memory addresses and routing the requests to the appropriate peripheral.

Simpler peripherals (such as UART) are implemented directly in the SOPHIE block, while more complex peripherals (such as IRIS the VGA adapter) are implemented as separate modules, and SOPHIE simply routes the requests to them.

SOPHIE does not control access to the main SDRAM - that is handled by a separate dedicated SDRAM controller. 

Possible later additions would be a DMA controller to allow peripherals to access memory directly without going through the CPU, and a "Copper" co-processor to allow sequencing of operations on the peripherals without CPU intervention.


## Address Map

|--------------------|----------------|---------------------------------|
| Address Range      | Peripheral     | Description                     |
|--------------------|----------------|---------------------------------|
| 00000000 - 03FFFFFF|  SDRAM (64MB)  | Main system memory              | 
| 04000000 - DFFFFFFF|  Reserved      |                                 |    
| E0000000 - E000FFFF|  SOPHIE        | Basic Memory-mapped I/O         |
| E0001000 - E0001FFF|  IRIS          | Video graphics controller (VGA) |
| E0002000 - E0002FFF|  IRIS          | Pallette RAM                    |
| E0003000 - E0003FFF|  IRIS          | Texture RAM                     |
| E0004000 - E0007FFF|  GEMMA         | Graphics co-processor           |
| FFFF0000 - FFFFFFFF|  BOOT-ROM      | Boot ROM (64KB)                 |
|--------------------|----------------|---------------------------------|

## Peripheral Register Map


| ADDRESS   | REGISTER      | R/W  | DESCRIPTION
|-----------|---------------|------|---------------------------------
| E0000000  | SEVEN_SEG     | R/W  | 6 digit hexadecimal seven segment display
| E0000004  | LEDR          | R/W  | 10 LEDs
| E0000008  | SW            | R    | 10 Switches
| E000000C  | KEY           | R    | 4 Push buttons
| E0000010  | UART_TX       | R/W  | Write = byte of data to transmit, read = number of slots free in fifo
| E0000014  | UART_RX       | R    | 1 byte of data from the uart, -1 if no data
| E0000018  | MOUSE_X       | R    | Mouse X coordinate
| E000001C  | MOUSE_Y       | R    | Mouse Y coordinate
| E0000020  | MOUSE_BUTTONS | R    | Mouse buttons (bit 0 = left, bit 1 = right, bit 2 = middle)
| E0000024  | KEYBOARD      | R    | Keyboard data (-1 if no data)
| E0000028  | TIMER         | RW   | Timer, count in milliseconds
| E000002C  | I2C_OUT       | W    | I2C Data to send (24 bits). Reads 0=Ready, 1=Busy, 2=Error
| E0000030  | SIMULATION    | R    | Reads as 1 in simulation, 0 in hardware
| E0000034  | OVERFLOW      | R    | bit 0 = uart tx fifo overflow, bit 1 = uart rx fifo overflow, bit 2 = keyboard fifo overflow
| E0000040  | SPI_DATA      | R/W  | SD card SPI: write = start an 8 bit transfer with this byte, read = last byte received
| E0000044  | SPI_CTRL      | R/W  | SD card SPI: bit 0 = CS asserted (W) / busy (R), bit 1 = CS asserted (R), bits 15:8 = clock divider
| E0000200  | AUDIO_ADDRESS | R/W  | Start address for audio channel 0; channel registers repeat every 0x20 bytes
| E0000204  | AUDIO_LENGTH  | R/W  | Sample length; writing starts playback
| E0000208  | AUDIO_VOLUME  | R/W  | Right volume in bits 23:16, left volume in bits 7:0
| E000020C  | AUDIO_PITCH   | R/W  | Playback pitch; 0x10000 is the nominal rate
| E0000210  | AUDIO_LOOP_ADDRESS | R/W | Loop start address
| E0000214  | AUDIO_LOOP_LENGTH  | R/W | Loop length; zero disables looping


## SD Card (SPI)

A minimal SPI master (`spi_master.sv`, mode 0, MSB first) connects to the SD card. All protocol handling is in software.

- SPI_CTRL write: bit 0 = 1 asserts chip select (SD_CS low); bits 15:8 = divider, SCLK period = 2*(divider+1) system clocks. Reset: CS deasserted, divider 255.
- SPI_CTRL read: bit 0 = busy, bit 1 = CS asserted, bits 15:8 = divider.
- To transfer a byte: wait until SPI_CTRL bit 0 is 0, write the byte to SPI_DATA, wait for busy to clear, read SPI_DATA for the received byte. To receive, send 0xFF.
- SD init: with CS deasserted send >=74 clocks (10 x 0xFF), then assert CS and send CMD0 etc.
