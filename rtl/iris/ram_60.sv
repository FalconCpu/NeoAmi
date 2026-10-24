`timescale 1 ps / 1 ps

module ram_60 (
	input	  clock,
	input	[59:0]  data,
	input	[4:0]  rdaddress,
	input	[4:0]  wraddress,
	input	  wren,
	output	[59:0]  q
);

logic [59:0] mem [31:0];

always_ff @(posedge clock) begin
	if (wren)
		mem[wraddress] <= data;
end

assign q = mem[rdaddress];

endmodule
