
// synopsys translate_off
`timescale 1 ps / 1 ps
// synopsys translate_on
module dcache_ram (
	input	[3:0]   byteena_a,
	input	        clock,
	input	[31:0]  data,
	input	[10:0]  rdaddress,
	input	        rden,
	input	[10:0]  wraddress,
	input	        wren,
	output reg[31:0]  q
);

logic [31:0] ram [0:2047]; // 2048 words of 32 bits each

always_ff @(posedge clock) begin
	if (wren) begin
		// Write data to the RAM, applying byte enables
		for (int i = 0; i < 4; i++) 
			if (byteena_a[i]) 
				ram[wraddress][i*8 +: 8] <= data[i*8 +: 8];
	end

	if (rden)
		// Read data from the RAM
		q <= ram[rdaddress];
end


endmodule
