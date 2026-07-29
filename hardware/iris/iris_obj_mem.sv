`timescale 1 ps / 1 ps

module iris_obj_mem (
	input     	      clock,
	input	[31:0]    data,
	input	[8:0]     rdaddress,
	input	[11:0]    wraddress,
	input	          wren,
	output reg[255:0] q
);

logic [255:0] mem[0:511];

always_ff @(posedge clock) begin
	if (wren)
		mem[wraddress[11:3]][wraddress[2:0]*32 +: 32] <= data;
	q <= mem[rdaddress];
end

endmodule
