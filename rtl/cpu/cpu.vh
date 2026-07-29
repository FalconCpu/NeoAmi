
`define KIND_ALU  6'h10
`define KIND_ALUI 6'h11
`define KIND_LD   6'h12
`define KIND_ST   6'h13
`define KIND_BRA  6'h14
`define KIND_JMP  6'h15
`define KIND_JMPR 6'h16
`define KIND_LDU  6'h17
`define KIND_LDPC 6'h18
`define KIND_MUL  6'h19
`define KIND_MULI 6'h1A
`define KIND_CFG  6'h1B
`define KIND_IDX  6'h1C
`define KIND_FPU  6'h1D

`define ALU_AND  3'b000
`define ALU_OR   3'b001
`define ALU_XOR  3'b010
`define ALU_LD   3'b011
`define ALU_ADD  3'b100
`define ALU_SUB  3'b101
`define ALU_CLT  3'b110
`define ALU_CLTU 3'b111

`define SHIFT_LSL 3'b000
`define SHIFT_LSR 3'b010
`define SHIFT_ASR 3'b011
`define SHIFT_PC  3'b100    // Generate the address of the next instruction (used for jump and link instructions)

`define BRANCH_BEQ  3'b000
`define BRANCH_BNE  3'b001
`define BRANCH_BLT  3'b010
`define BRANCH_BGE  3'b011
`define BRANCH_BLTU 3'b100
`define BRANCH_BGEU 3'b101
`define BRANCH_JMP  3'b110
`define BRANCH_JMPR 3'b111

`define MULT_MUL    3'b000
`define MULT_MULH   3'b001
`define MULT_MULHS  3'b010
`define MULT_MULHSU 3'b011

`define CFGREG_VERSION  0
`define CFGREG_STATUS   1
`define CFGREG_EPC      2
`define CFGREG_ECAUSE   3
`define CFGREG_EDATA    4
`define CFGREG_ESTATUS  5
`define CFGREG_ESCRATCH 6
`define CFGREG_TIMER    7
`define CFGREG_MPU_CLR  8
`define CFGREG_MPU_DATA 9
`define CFGREG_IPC      10
`define CFGREG_ICAUSE   11
`define CFGREG_IDATA    12
`define CFGREG_ISTATUS  13
`define CFGREG_ISCRATCH 14
`define CFGREG_INTVEC   15
`define CFGREG_ICACHE   16

`define CAUSE_INS_FAULT      8'h01
`define CAUSE_ILLEGAL        8'h02
`define CAUSE_BREAKPOINT     8'h03
`define CAUSE_LOAD_MISALIGN  8'h04
`define CAUSE_LOAD_ACCESS    8'h05
`define CAUSE_STORE_MISALIGN 8'h06
`define CAUSE_STORE_ACCESS   8'h07
`define CAUSE_SYS            8'h08
`define CAUSE_INDEX          8'h09
