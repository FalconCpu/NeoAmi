`timescale 1ns/1ns

// PC module
//
// Maintains the program counter (PC) and sends requests to the icache 

module cpu_pc (
    input logic         clock,
    input logic         reset,

    // PC output
    input logic         p0_ready,          // Indicates that the icache is ready for the next instruction address
    output logic [31:0] p0_pc,             // Current program counter value

    // Control signals
    input logic         p4_jump_taken,     // A jump instruction was taken
    input logic [31:0]  p4_jump_target     // The target address of the jump instruction
);

logic [31:0] pc;                  // Register to hold the current PC value


always_comb begin
    if (reset) begin                        // At reset set PC to 0xFFFF0000, but do not request an instruction
        p0_pc   = 32'hFFFF_0000;
    end else if (p4_jump_taken) begin       // A jump was taken, set the PC to the jump target and request the next instruction
        p0_pc   = p4_jump_target;           // (We don't need to check the FIFO here, because it will be flushed on a jump)
    end else if (!p0_ready) begin           // Icache is not ready 
        p0_pc   = pc;                       // to drain before requesting the next instruction 
    end else begin                          // Normal operation, increment the PC by 4 and request the next instruction
        p0_pc   = pc + 4;
    end
end        

always_ff @(posedge clock) begin
    pc <= p0_pc;
end

// synthesis translate_off
// In simulation, a jump to address zero is treated as a halt instruction
integer finish_count;

always @(posedge clock) begin
    finish_count <= finish_count - 1;
    if (p4_jump_taken && p4_jump_target == 32'h0) 
        finish_count <= 4;
    if (finish_count == 1) begin
        $display("Simulation completed at time %t PC=%h", $time, pc);
        $finish;
    end
end
// synthesis translate_on

endmodule
