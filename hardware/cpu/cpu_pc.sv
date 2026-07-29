`timescale 1ns/1ns

// PC module
//
// Maintains the program counter (PC) and sends requests to the icache 

module cpu_pc (
    input logic         clock,
    input logic         reset,

    // PC output
    output logic        p0_req,            // Request to icache for the next instruction address
    output logic [31:0] p0_pc,             // Current program counter value

    // Control signals
    input logic         p1_fifo_full,      // The instruction FIFO is full - stall the PC
    input logic         p4_jump_taken,     // A jump instruction was taken
    input logic [31:0]  p4_jump_target     // The target address of the jump instruction
);

logic [31:0] pc;                  // Register to hold the current PC value


always_comb begin
    if (reset) begin                        // At reset set PC to 0xFFFF0000, but do not request an instruction
        p0_pc   = 32'hFFFF_0000;
        p0_req  = 1'b1;
    end else if (p4_jump_taken) begin       // A jump was taken, set the PC to the jump target and request the next instruction
        p0_pc   = p4_jump_target;           // (We don't need to check the FIFO here, because it will be flushed on a jump)
        p0_req  = 1'b1;
    end else if (p1_fifo_full) begin        // The instruction FIFO is full, so hold the current PC value and wait for the FIFO
        p0_pc   = pc;                       // to drain before requesting the next instruction 
        p0_req  = 1'b0;
    end else begin                          // Normal operation, increment the PC by 4 and request the next instruction
        p0_pc   = pc + 4;
        p0_req  = 1'b1;
    end
end        

always_ff @(posedge clock) begin
    pc <= p0_pc;
end

// synthesis translate_off
// In simulation, a jump to address zero is treated as a halt instruction
always @(posedge clock) begin
    if (p4_jump_taken && p4_jump_target == 32'h0) begin
        $display("Simulation completed at time %t PC=%h", $time, pc);
        @(posedge clock);
        @(posedge clock);
        @(posedge clock);
        $finish;
    end
end
// synthesis translate_on

endmodule
