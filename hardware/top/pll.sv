`timescale 1ns/1ns

module pll(
	input  logic refclk,
	input  logic rst,
	output logic outclk_0,
	output logic outclk_1,
	output logic locked
);

// For simulation just model as a passthrough
assign outclk_0 = refclk;
assign outclk_1 = refclk;

logic [2:0] counter;
initial begin
    counter = 0;
    locked = 0;
end

always_ff @(posedge refclk or posedge rst) begin
    if (rst) begin
        counter <= 0;
        locked <= 0;
    end else if (counter < 5) begin
        counter <= counter + 1;
        locked <= 0;
    end else begin
        locked <= 1; // Lock after 5 cycles
    end
end


endmodule
