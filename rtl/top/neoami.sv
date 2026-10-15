`timescale 1ns/1ns


module neoami(

	//////////// Audio //////////
	input 		          		AUD_ADCDAT,
	inout 		          		AUD_ADCLRCK,
	inout 		          		AUD_BCLK,
	output		          		AUD_DACDAT,
	inout 		          		AUD_DACLRCK,
	output		          		AUD_XCK,

	//////////// CLOCK //////////
	input 		          		CLOCK2_50,
	input 		          		CLOCK3_50,
	input 		          		CLOCK4_50,
	input 		          		CLOCK_50,

	//////////// SDRAM //////////
	output		    [12:0]		DRAM_ADDR,
	output		     [1:0]		DRAM_BA,
	output		          		DRAM_CAS_N,
	output		          		DRAM_CKE,
	output		          		DRAM_CLK,
	output		          		DRAM_CS_N,
	inout 		    [15:0]		DRAM_DQ,
	output		          		DRAM_LDQM,
	output		          		DRAM_RAS_N,
	output		          		DRAM_UDQM,
	output		          		DRAM_WE_N,

	//////////// I2C for Audio and Video-In //////////
	output		          		FPGA_I2C_SCLK,
	inout 		          		FPGA_I2C_SDAT,

	//////////// SEG7 //////////
	output		     [6:0]		HEX0,
	output		     [6:0]		HEX1,
	output		     [6:0]		HEX2,
	output		     [6:0]		HEX3,
	output		     [6:0]		HEX4,
	output		     [6:0]		HEX5,

	//////////// KEY //////////
	input 		     [3:0]		KEY,

	//////////// LED //////////
	output		     [9:0]		LEDR,

	//////////// PS2 //////////
	inout 		          		PS2_CLK,
	inout 		          		PS2_CLK2,
	inout 		          		PS2_DAT,
	inout 		          		PS2_DAT2,

	//////////// SW //////////
	input 		     [9:0]		SW,

	//////////// VGA //////////
	output		          		VGA_BLANK_N,
	output		     [7:0]		VGA_B,
	output		          		VGA_CLK,
	output		     [7:0]		VGA_G,
	output		          		VGA_HS,
	output		     [7:0]		VGA_R,
	output		          		VGA_SYNC_N,
	output		          		VGA_VS,

	//////////// GPIO_0, GPIO_0 connect to GPIO Default //////////
	inout 		    [35:0]		GPIO_0,

	//////////// GPIO_1, GPIO_1 connect to GPIO Default //////////
	inout 		    [35:0]		GPIO_1
);


// Aux bus interface for reading/writing the instruction memory
logic         aux_irom_req;
logic         aux_irom_write;
logic [15:0]  aux_irom_addr;
logic [31:0]  aux_irom_wdata;
logic [31:0]  aux_irom_rdata;
logic         aux_irom_rvalid;

// Aux bus interface for reading/writing the data memory
logic        cpu_aux_req;
logic        cpu_aux_write;
logic [31:0] cpu_aux_addr;
logic [31:0] cpu_aux_wdata;
logic [3:0]  cpu_aux_strb;
logic [4:0]  cpu_aux_rd;
logic        cpu_aux_rvalid;
logic [31:0] cpu_aux_rdata;
logic [4:0]  cpu_aux_rdest;

wire UART_TX;
wire UART_RX;
assign GPIO_0[0] = UART_TX;
assign UART_RX = GPIO_0[1];
assign GPIO_0[35:1] = 35'bz;


//=======================================================
//  PLL and reset
//=======================================================
logic clock;
logic reset;
logic locked;

pll  pll_inst (
    .refclk(CLOCK_50),
    .rst(1'b0),
    .outclk_0(clock),
    .outclk_1(DRAM_CLK),
    .locked(locked)
  );
always_ff @(posedge clock)
	reset <= ~locked || !KEY[0];

//=======================================================
//  CPU
//=======================================================
logic [31:0] cpu_pc;

logic         dcache_sdramw_req;
logic         dcache_sdramw_ack;
logic [25:0]  dcache_sdramw_addr;
logic [127:0] dcache_sdramw_data;
logic [15:0]  dcache_sdramw_strb;

logic         dcache_sdramr_req;
logic         dcache_sdramr_ack;
logic [25:0]  dcache_sdramr_addr;
logic  [1:0]  dcache_sdramr_rvalid;
logic [31:0]  dcache_sdramr_rdata;


cpu  cpu_inst (
    .clock(clock),
    .reset(reset),
    .aux_irom_req(aux_irom_req),
    .aux_irom_write(aux_irom_write),
    .aux_irom_addr(aux_irom_addr),
    .aux_irom_wdata(aux_irom_wdata),
    .aux_irom_rdata(aux_irom_rdata),
    .aux_irom_rvalid(aux_irom_rvalid),
    .cpu_aux_req(cpu_aux_req),
    .cpu_aux_write(cpu_aux_write),
    .cpu_aux_addr(cpu_aux_addr),
    .cpu_aux_wdata(cpu_aux_wdata),
    .cpu_aux_strb(cpu_aux_strb),
    .cpu_aux_rd(cpu_aux_rd),
    .cpu_aux_rvalid(cpu_aux_rvalid),
    .cpu_aux_rdata(cpu_aux_rdata),
    .cpu_aux_rdest(cpu_aux_rdest),
    .dcache_sdramw_req(dcache_sdramw_req),
    .dcache_sdramw_ack(dcache_sdramw_ack),
    .dcache_sdramw_addr(dcache_sdramw_addr),
    .dcache_sdramw_data(dcache_sdramw_data),
    .dcache_sdramw_strb(dcache_sdramw_strb),
    .dcache_sdramr_req(dcache_sdramr_req),
    .dcache_sdramr_ack(dcache_sdramr_ack),
    .dcache_sdramr_addr(dcache_sdramr_addr),
    .dcache_sdramr_rvalid(dcache_sdramr_rvalid),
    .dcache_sdramr_rdata(dcache_sdramr_rdata),
    .cpu_pc(cpu_pc)
  );

//=======================================================
//  SDRAM controller
//=======================================================
logic         icache_sdram_req=1'b0;
logic         icache_sdram_ack;
logic [25:0]  icache_sdram_addr;
logic [1:0]   icache_sdram_rvalid;
logic [31:0]  icache_sdram_rdata;

logic         vga_sdram_req;
logic         vga_sdram_ack;
logic [25:0]  vga_sdram_addr;
logic [7:0]   vga_sdram_tag;
logic [1:0]   vga_sdram_rvalid;
logic [31:0]  vga_sdram_rdata;
logic [7:0]   vga_sdram_rtag;

logic        gemma_sdram_req;
logic        gemma_sdram_ack;
logic        gemma_sdram_write;
logic [25:0] gemma_sdram_addr;
logic [7:0]  gemma_sdram_tag;
logic [127:0] gemma_sdram_wdata;
logic [15:0] gemma_sdram_strb;
logic [1:0]  gemma_sdram_rvalid;
logic [7:0]  gemma_sdram_rtag;
logic [31:0] gemma_sdram_rdata;

logic         audio_sdram_req;
logic         audio_sdram_ready;
logic [25:0]  audio_sdram_address;
logic         audio_sdram_rvalid;
logic [25:0]  audio_sdram_raddress;
logic [31:0]  audio_sdram_rdata;
logic         audio_sdram_complete;



  sdram  sdram_inst (
    .clock(clock),
    .reset(reset),
    .dcache_sdramw_req(dcache_sdramw_req),
    .dcache_sdramw_ack(dcache_sdramw_ack),
    .dcache_sdramw_addr(dcache_sdramw_addr),
    .dcache_sdramw_data(dcache_sdramw_data),
    .dcache_sdramw_strb(dcache_sdramw_strb),
    .dcache_sdramr_req(dcache_sdramr_req),
    .dcache_sdramr_ack(dcache_sdramr_ack),
    .dcache_sdramr_addr(dcache_sdramr_addr),
    .dcache_sdramr_rvalid(dcache_sdramr_rvalid),
    .dcache_sdramr_rdata(dcache_sdramr_rdata),
    .icache_sdram_req(icache_sdram_req),
    .icache_sdram_ack(icache_sdram_ack),
    .icache_sdram_addr(icache_sdram_addr),
    .icache_sdram_rvalid(icache_sdram_rvalid),
    .icache_sdram_rdata(icache_sdram_rdata),
    .vga_sdram_req(vga_sdram_req),
    .vga_sdram_ack(vga_sdram_ack),
    .vga_sdram_addr(vga_sdram_addr),
    .vga_sdram_tag(vga_sdram_tag),
    .vga_sdram_rvalid(vga_sdram_rvalid),
    .vga_sdram_rdata(vga_sdram_rdata),
    .vga_sdram_rtag(vga_sdram_rtag),
    .gemma_sdram_req(gemma_sdram_req),
    .gemma_sdram_ack(gemma_sdram_ack),
    .gemma_sdram_write(gemma_sdram_write),
    .gemma_sdram_addr(gemma_sdram_addr),
    .gemma_sdram_tag(gemma_sdram_tag),
    .gemma_sdram_wdata(gemma_sdram_wdata),
    .gemma_sdram_strb(gemma_sdram_strb),
    .gemma_sdram_rvalid(gemma_sdram_rvalid),
    .gemma_sdram_rtag(gemma_sdram_rtag),
    .gemma_sdram_rdata(gemma_sdram_rdata),
    .audio_sdram_req(audio_sdram_req),
    .audio_sdram_ready(audio_sdram_ready),
    .audio_sdram_address(audio_sdram_address),
    .audio_sdram_rvalid(audio_sdram_rvalid),
    .audio_sdram_raddress(audio_sdram_raddress),
    .audio_sdram_rdata(audio_sdram_rdata),
    .audio_sdram_complete(audio_sdram_complete),
    .DRAM_ADDR(DRAM_ADDR),
    .DRAM_BA(DRAM_BA),
    .DRAM_CAS_N(DRAM_CAS_N),
    .DRAM_CKE(DRAM_CKE),
    .DRAM_CS_N(DRAM_CS_N),
    .DRAM_DQ(DRAM_DQ),
    .DRAM_LDQM(DRAM_LDQM),
    .DRAM_RAS_N(DRAM_RAS_N),
    .DRAM_UDQM(DRAM_UDQM),
    .DRAM_WE_N(DRAM_WE_N)
  );

//=======================================================
//  SOPHIE
//=======================================================

logic            aux_iris_req;
logic [15:0]     aux_iris_addr;
logic [31:0]     aux_iris_wdata;
logic [9:0]      ypos;

logic            aux_gemma_req;
logic            aux_gemma_write;
logic [15:0]     aux_gemma_addr;
logic [31:0]     aux_gemma_wdata;
logic [31:0]     aux_gemma_rdata;

logic [9:0] mouse_x;
logic [9:0] mouse_y;
logic [25:0] vga_obj_list;


sophie  sophie_inst (
    .clock(clock),
    .reset(reset),
    .cpu_aux_req(cpu_aux_req),
    .cpu_aux_write(cpu_aux_write),
    .cpu_aux_addr(cpu_aux_addr),
    .cpu_aux_wdata(cpu_aux_wdata),
    .cpu_aux_strb(cpu_aux_strb),
    .cpu_aux_dest(cpu_aux_rd),
    .cpu_aux_rvalid(cpu_aux_rvalid),
    .cpu_aux_rdata(cpu_aux_rdata),
    .cpu_aux_rdest(cpu_aux_rdest),
    .aux_irom_req(aux_irom_req),
    .aux_irom_write(aux_irom_write),
    .aux_irom_addr(aux_irom_addr),
    .aux_irom_wdata(aux_irom_wdata),
    .aux_irom_rdata(aux_irom_rdata),
    .aux_iris_req(aux_iris_req),
    .aux_iris_addr(aux_iris_addr),
    .aux_iris_wdata(aux_iris_wdata),
    .aux_gemma_req(aux_gemma_req),
    .aux_gemma_write(aux_gemma_write),
    .aux_gemma_addr(aux_gemma_addr),
    .aux_gemma_wdata(aux_gemma_wdata),
    .aux_gemma_rdata(aux_gemma_rdata),
    .ypos(ypos),
    .HEX0(HEX0),
    .HEX1(HEX1),
    .HEX2(HEX2),
    .HEX3(HEX3),
    .HEX4(HEX4),
    .HEX5(HEX5),
    .KEY(KEY),
    .LEDR(LEDR),
    .SW(SW),
    .UART_TX(UART_TX),
    .UART_RX(UART_RX),
    .PS2_CLK(PS2_CLK),
    .PS2_DAT(PS2_DAT),
    .PS2_CLK2(PS2_CLK2),
    .PS2_DAT2(PS2_DAT2),
    .SDA(FPGA_I2C_SDAT),
    .SCL(FPGA_I2C_SCLK),
    .sd_cs(GPIO_0[28]),
    .sd_sclk(GPIO_0[22]),
    .sd_mosi(GPIO_0[26]),
    .sd_miso(GPIO_0[20]),
    .AUD_XCK(AUD_XCK),
    .AUD_BCLK(AUD_BCLK),
    .AUD_DACLRCK(AUD_DACLRCK),
    .AUD_DACDAT(AUD_DACDAT),
    .audio_sdram_req(audio_sdram_req),
    .audio_sdram_ready(audio_sdram_ready),
    .audio_sdram_address(audio_sdram_address),
    .audio_sdram_rvalid(audio_sdram_rvalid),
    .audio_sdram_raddress(audio_sdram_raddress),
    .audio_sdram_rdata(audio_sdram_rdata),
    .audio_sdram_complete(audio_sdram_complete),
    .mouse_x(mouse_x),
    .mouse_y(mouse_y),
    .cpu_pc(cpu_pc),
    .vga_obj_list(vga_obj_list)
  );

// =======================================================
//                           IRIS
// =======================================================

 iris  iris_inst (
    .clock(clock),
    .reset(reset),
    .VGA_BLANK_N(VGA_BLANK_N),
    .VGA_B(VGA_B),
    .VGA_CLK(VGA_CLK),
    .VGA_G(VGA_G),
    .VGA_HS(VGA_HS),
    .VGA_R(VGA_R),
    .VGA_SYNC_N(VGA_SYNC_N),
    .VGA_VS(VGA_VS),
    .ypos(ypos),
    .vga_obj_list(vga_obj_list),
    .aux_iris_req(aux_iris_req),
    .aux_iris_addr(aux_iris_addr),
    .aux_iris_wdata(aux_iris_wdata),
    .vga_sdram_ready(vga_sdram_ack),
    .vga_sdram_req(vga_sdram_req),
    .vga_sdram_addr(vga_sdram_addr),
    .vga_sdram_tag(vga_sdram_tag),
    .vga_sdram_rvalid(vga_sdram_rvalid),
    .vga_sdram_rdata(vga_sdram_rdata),
    .vga_sdram_rtag(vga_sdram_rtag)
  ); 



// ======================================================
//                           GEMMA
// ======================================================

gemma  gemma_inst (
    .clock(clock),
    .reset(reset),
    .aux_gemma_req(aux_gemma_req),
    .aux_gemma_write(aux_gemma_write),
    .aux_gemma_addr(aux_gemma_addr),
    .aux_gemma_wdata(aux_gemma_wdata),
    .aux_gemma_rdata(aux_gemma_rdata),
    .gemma_sdram_req(gemma_sdram_req),
    .gemma_sdram_ack(gemma_sdram_ack),
    .gemma_sdram_write(gemma_sdram_write),
    .gemma_sdram_addr(gemma_sdram_addr),
    .gemma_sdram_wdata(gemma_sdram_wdata),
    .gemma_sdram_tag(gemma_sdram_tag),
    .gemma_sdram_strb(gemma_sdram_strb),
    .gemma_sdram_rvalid(gemma_sdram_rvalid),
    .gemma_sdram_rtag(gemma_sdram_rtag),
    .gemma_sdram_rdata(gemma_sdram_rdata)
  );


endmodule
