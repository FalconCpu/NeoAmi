`timescale 1ns/1ps

// GEMMA top level registers
//
// Implements the top level memory-mapped registers for the GEMMA

module gemma_regs (
    input logic         clock,
    input logic         reset,

    // CPU interface
    input logic         aux_gemma_req,       // Request signal from the CPU to read/write registers
    input logic         aux_gemma_write,     // Indicates whether the CPU request is a write operation
    input logic [15:0]  aux_gemma_addr,      // Index of the register to read/write
    input logic [31:0]  aux_gemma_wdata,     // Data to write to the register if it's a write operation
    output logic [31:0] aux_gemma_rdata,     // Data read from the register if it's a read operation

    // Control signals
    output logic [3:0]  stage_start,         // One bit per processing unit. Writing a 1 to a bit starts the corresponding processing unit.
    input logic [3:0]   stage_valid,         // One bit per processing unit. A bit is set to 1 when the corresponding processing unit is busy
    input logic [3:0]   stage_busy,          // One bit per processing unit. A bit is set to 1 when the corresponding processing unit is busy
    output logic [3:0]  stage_auto,
    output logic [25:0] output_ptr,          // The destination write pointer for the triangle setup stage. 
    output logic [15:0] clip_x1,
    output logic [15:0] clip_y1,
    output logic [15:0] clip_x2,
    output logic [15:0] clip_y2,             // The clipping rectangle for the triangle setup stage.
    output logic [25:0] texture_addr,        // The base address of the texture in main memory. Used in the triangle setup stage for textured triangles.
    output logic [15:0] texture_stride,      // The stride of the texture in bytes

    input logic         inc_output_ptr       // Signal from the triangle setup stage to increment the output pointer after writing data to main memory
);


always_ff @(posedge clock) begin
    // =============================================================
    //                   Write logic
    // =============================================================
    stage_start <= 4'h0; // Clear the stage_start register after each write. This is a pulse register.

    if (aux_gemma_req && aux_gemma_write)
        case (aux_gemma_addr)
            16'h0000: stage_start <= aux_gemma_wdata[3:0];
            16'h0004: begin end    // Status register. Read-only.
            16'h0008: stage_auto <= aux_gemma_wdata[3:0];
            16'h000C: output_ptr <= aux_gemma_wdata[25:0];
            16'h0010: clip_x1 <= aux_gemma_wdata[15:0];
            16'h0014: clip_y1 <= aux_gemma_wdata[15:0];
            16'h0018: clip_x2 <= aux_gemma_wdata[15:0];
            16'h001C: clip_y2 <= aux_gemma_wdata[15:0];
            16'h0020: texture_addr <= aux_gemma_wdata[25:0];
            16'h0024: texture_stride <= aux_gemma_wdata[15:0];
            default: begin end
        endcase

    // =============================================================
    //                   Read logic
    // =============================================================
    if (aux_gemma_req && !aux_gemma_write)
        case (aux_gemma_addr)
            16'h0000: aux_gemma_rdata <= 32'h0;
            16'h0004: aux_gemma_rdata <= {28'b0, stage_busy};
            16'h0008: aux_gemma_rdata <= {28'b0, stage_auto};
            16'h000C: aux_gemma_rdata <= {6'b0, output_ptr};
            16'h0010: aux_gemma_rdata <= {16'b0, clip_x1};
            16'h0014: aux_gemma_rdata <= {16'b0, clip_y1};
            16'h0018: aux_gemma_rdata <= {16'b0, clip_x2};
            16'h001C: aux_gemma_rdata <= {16'b0, clip_y2};
            16'h0020: aux_gemma_rdata <= {6'b0, texture_addr};
            16'h0024: aux_gemma_rdata <= {16'b0, texture_stride};
            default: aux_gemma_rdata <= 32'b0;
        endcase

    // =============================================================
    //                 AutoStart logic
    // =============================================================
    if (stage_auto[0] && !stage_busy[0] && stage_valid[0] && !stage_valid[1])
        stage_start[1] <= 1'b1; 
    if (stage_auto[1] && !stage_busy[1] && stage_valid[1] && !stage_valid[2])
        stage_start[2] <= 1'b1;
    if (stage_auto[2] && !stage_busy[2] && stage_valid[2] && !stage_valid[3])
        stage_start[3] <= 1'b1;
    if (stage_auto[3] && !stage_busy[3] && stage_valid[3])
        stage_start[3] <= 1'b1;

    if (inc_output_ptr)
        output_ptr <= output_ptr + 26'd64;

    // =============================================================
    //                 Reset logic
    // =============================================================
    if (reset) begin
        stage_start <= 4'h0;
        stage_auto <= 4'h0;
        output_ptr <= 26'h0;
        clip_x1 <= 16'h0;
        clip_y1 <= 16'h0;
        clip_x2 <= 16'd640;
        clip_y2 <= 16'd480;
        texture_addr <= 26'h0;
        texture_stride <= 16'h0;
    end
end


wire unused = &{aux_gemma_wdata[31:26]};

endmodule
