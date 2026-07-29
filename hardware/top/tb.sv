
module tb;

  // Parameters

  //Ports
  reg AUD_ADCDAT;
  wire AUD_ADCLRCK;
  wire AUD_BCLK;
  wire AUD_DACDAT;
  wire AUD_DACLRCK;
  wire AUD_XCK;
  reg CLOCK2_50;
  reg CLOCK3_50;
  reg CLOCK4_50;
  reg CLOCK_50;
  wire [12:0] DRAM_ADDR;
  wire [1:0] DRAM_BA;
  wire DRAM_CAS_N;
  wire DRAM_CKE;
  wire DRAM_CLK;
  wire DRAM_CS_N;
  wire [15:0] DRAM_DQ;
  wire DRAM_LDQM;
  wire DRAM_RAS_N;
  wire DRAM_UDQM;
  wire DRAM_WE_N;
  wire FPGA_I2C_SCLK;
  wire FPGA_I2C_SDAT;
  wire [6:0] HEX0;
  wire [6:0] HEX1;
  wire [6:0] HEX2;
  wire [6:0] HEX3;
  wire [6:0] HEX4;
  wire [6:0] HEX5;
  reg [3:0] KEY;
  wire [9:0] LEDR;
  wire PS2_CLK;
  wire PS2_CLK2;
  wire PS2_DAT;
  wire PS2_DAT2;
  reg [9:0] SW;
  wire VGA_BLANK_N;
  wire [7:0] VGA_B;
  wire VGA_CLK;
  wire [7:0] VGA_G;
  wire VGA_HS;
  wire [7:0] VGA_R;
  wire VGA_SYNC_N;
  wire VGA_VS;
  wire [35:0] GPIO_0;
  wire [35:0] GPIO_1;

  falcon  falcon_inst (
    .AUD_ADCDAT(AUD_ADCDAT),
    .AUD_ADCLRCK(AUD_ADCLRCK),
    .AUD_BCLK(AUD_BCLK),
    .AUD_DACDAT(AUD_DACDAT),
    .AUD_DACLRCK(AUD_DACLRCK),
    .AUD_XCK(AUD_XCK),
    .CLOCK2_50(CLOCK2_50),
    .CLOCK3_50(CLOCK3_50),
    .CLOCK4_50(CLOCK4_50),
    .CLOCK_50(CLOCK_50),
    .DRAM_ADDR(DRAM_ADDR),
    .DRAM_BA(DRAM_BA),
    .DRAM_CAS_N(DRAM_CAS_N),
    .DRAM_CKE(DRAM_CKE),
    .DRAM_CLK(DRAM_CLK),
    .DRAM_CS_N(DRAM_CS_N),
    .DRAM_DQ(DRAM_DQ),
    .DRAM_LDQM(DRAM_LDQM),
    .DRAM_RAS_N(DRAM_RAS_N),
    .DRAM_UDQM(DRAM_UDQM),
    .DRAM_WE_N(DRAM_WE_N),
    .FPGA_I2C_SCLK(FPGA_I2C_SCLK),
    .FPGA_I2C_SDAT(FPGA_I2C_SDAT),
    .HEX0(HEX0),
    .HEX1(HEX1),
    .HEX2(HEX2),
    .HEX3(HEX3),
    .HEX4(HEX4),
    .HEX5(HEX5),
    .KEY(KEY),
    .LEDR(LEDR),
    .PS2_CLK(PS2_CLK),
    .PS2_CLK2(PS2_CLK2),
    .PS2_DAT(PS2_DAT),
    .PS2_DAT2(PS2_DAT2),
    .SW(SW),
    .VGA_BLANK_N(VGA_BLANK_N),
    .VGA_B(VGA_B),
    .VGA_CLK(VGA_CLK),
    .VGA_G(VGA_G),
    .VGA_HS(VGA_HS),
    .VGA_R(VGA_R),
    .VGA_SYNC_N(VGA_SYNC_N),
    .VGA_VS(VGA_VS),
    .GPIO_0(GPIO_0),
    .GPIO_1(GPIO_1)
  );


micron_sdram  micron_sdram_inst (
    .Clk(DRAM_CLK),
    .Cke(DRAM_CKE),
    .Cs_n(DRAM_CS_N),
    .Ras_n(DRAM_RAS_N),
    .Cas_n(DRAM_CAS_N),
    .We_n(DRAM_WE_N),
    .Addr(DRAM_ADDR),
    .Ba(DRAM_BA),
    .Dq(DRAM_DQ),
    .Dqm({DRAM_UDQM, DRAM_LDQM})
  );

always begin
    CLOCK_50 = 1'b0;
    #4;
    CLOCK_50 = 1'b1;
    #4;
end

initial begin
    $dumpfile("falcon_tb.vcd");
    // $dumpvars(0, tb_falcon);
    $dumpvars(2, tb);
    // Initialize inputs

    #16000000;
    //#100000
    $finish;
end

// VGA output logging
integer vga_file;
integer x_pos;
integer y_pos;
reg prev_hs;
reg prev_vs;

initial begin
    vga_file = $fopen("vga_output.txt", "w");
    x_pos = 0;
    y_pos = -100;
    prev_hs = 1'b1;
    prev_vs = 1'b1;
end

always @(posedge VGA_CLK) begin
    // Detect rising edge of VGA_VS (start of new frame)
    if (prev_vs == 1'b0 && VGA_VS == 1'b1) begin
        y_pos <= -33;   // Reset y position to start of frame (including back porch)
        x_pos <= -48;   // Reset x position to start of line (including back porch)
    end
    // Detect falling edge of VGA_HS (end of line)
    else if (prev_hs == 1'b0 && VGA_HS == 1'b1) begin
        y_pos <= y_pos + 1;
        x_pos <= -48;
    end
    // Normal pixel - write to file if in active display region
    else begin
        if (x_pos>=0 && x_pos<640 && y_pos>=0 && y_pos<480) 
            $fwrite(vga_file, "%0d %0d %0d %0d %0d\n", x_pos, y_pos, VGA_R, VGA_G, VGA_B);
        x_pos <= x_pos + 1;
    end
    
    // Update previous sync signals
    prev_hs <= VGA_HS;
    prev_vs <= VGA_VS;
end

// Close file at end of simulation
final begin
    $fclose(vga_file);
end


endmodule
