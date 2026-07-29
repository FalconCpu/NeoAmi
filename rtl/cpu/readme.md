# CPU overview

The F32 CPU is a RISC cpu, inspired by the RISC-V architecture, but to my own ISA.

Like most RISC architectures, it has a fixed instruction length of 32 bits, and a load/store architecture, 32 registers (with register 0 hardwired to 0).

# Instruction format

The instruction format is as follows:

| 31-26  | 25-23 | 22-18 | 17-13 | 12-5  | 4-0    |
|--------|-------|-------|-------|-------|--------|
| K      | I     |   D   |   A   |  C    |   B    |

Where:
- K: 6 bits, major-opcode 
- I: 3 bits, minor-opcode
- D: 5 bits, destination register
- A: 5 bits, source register A
- C: 8 bits, immediate value or instruction-specific data
- B: 5 bits, source register B

The major-opcode (K) determines the general category of the instruction, while the minor-opcode (I) specifies the exact operation within that category. The destination register (D) is where the result of the operation will be stored, and source registers A and B provide the operands for the instruction. 

Immediate values are produced by concatenating the C field with other fields depending on the instruction, to give either a 13 bit or 21 bit value. The C field always forms the most significant part of the immediate value. Immediate values are sign-extended to 32 bits (bit 12 of the instruction is always the sign bit of the immediate value).

Major opcodes are as follows:
| K    | Name | Imm   | Description                                    |
|------|------|-------|------------------------------------------------|
| 0x10 | ALU  | none  | ALU operations between registers               | 
| 0x11 | ALUI | CB    | ALU operations between register and immediate  |
| 0x12 | LD   | CB    | Load from memory                               |
| 0x13 | ST   | CD    | Store to memory                                | 
| 0x14 | BRA  | CD    | Branch instructions, target=PC+4+imm<<2        | 
| 0x15 | JMP  | CIAB  | Jump (and link), target=PC+4+imm<<2            |
| 0x16 | JMPR | CB    | Jump (and link), target=reg[A]+imm<<2          |
| 0x17 | LDU  | CIAB  | Load register with imm<<11                     |
| 0x18 | LDPC | CIAB  | Load register with PC + imm<<2                 |
| 0x19 | MUL  | none  | Mult/Divide operations between registers       | 
| 0x1A | MULI | CB    | Mult/Divide operations between register and imm|
| 0x1B | CFG  | CB    | Configuration register access                  | 
| 0x1C | IDX  | none  | If reg[A]<reg[B] then reg[D]=reg[A]<<i, else trap| 
| 0x1D | FPU  | none  | Floating point operations between registers    | 

# Instruction set

The full instruction set is as follows:-


|Mnemonic         | K / I / C       | Description
|-----------------|-----------------|---------------------------
|and \$d, \$a, \$b   | 010000 000      | \$d = \$a & \$b
|or  \$d, \$a, \$b   | 010000 001      | \$d = \$a \| \$b
|xor \$d, \$a, \$b   | 010000 010      | \$d = \$a ^ \$b
|lsl \$d, \$a, \$b   | 010000 011 00   | \$d = \$a << \$b
|lsr \$d, \$a, \$b   | 010000 011 10   | \$d = \$a >> \$b (signed)
|asr \$d, \$a, \$b   | 010000 011 11   | \$d = \$a >> \$b (unsigned)
|add \$d, \$a, \$b   | 010000 100      | \$d = \$a + \$b
|sub \$d, \$a, \$b   | 010000 101      | \$d = \$a - \$b
|clt \$d, \$a, \$b   | 010000 110      | \$d = \$a < \$b  (signed)
|cltu \$d, \$a, \$b  | 010000 111      | \$d = \$a < \$b  (unsigned)
|and \$d, \$a, s13  | 010001 000      | \$d = \$a & imm
|or  \$d, \$a, s13  | 010001 001      | \$d = \$a \| imm
|xor \$d, \$a, s13  | 010001 010      | \$d = \$a ^ imm
|lsl \$d, \$a, s13  | 010001 011 00   | \$d = \$a << imm
|lsr \$d, \$a, s13  | 010001 011 10   | \$d = \$a >> imm (signed)
|asr \$d, \$a, s13  | 010001 011 11   | \$d = \$a >> imm (unsigned)
|add \$d, \$a, s13  | 010001 100      | \$d = \$a + imm
|sub \$d, \$a, s13  | 010001 101      | \$d = \$a - imm
|clt \$d, \$a, s13  | 010001 110      | \$d = \$a < imm (signed)
|cltu \$d, \$a, s13 | 010001 111      | \$d = \$a < imm (unsigned)
|ldu \$d, s21      | 010111          | \$d = s21<<12
|ldpc \$d, s21     | 011000          | \$d = PC + 4*offset
|ldb \$d, \$a[$s13] | 010010 000      | \$d = MEM[$a + s13] (byte)
|ldh \$d, \$a[$s13] | 010010 001      | \$d = MEM[$a + s13] (halfword)
|ldw \$d, \$a[$s13] | 010010 010      | \$d = MEM[$a + s13] (word)
|stb \$b, \$a[$s13] | 010011 010      | MEM[$a + s13] = \$d (word)
|sth \$b, \$a[$s13] | 010011 011      | MEM[$a + s13] = \$d (halfword)
|stw \$b, \$a[$s13] | 010011 100      | MEM[$a + s13] = \$d (word)
|beq \$a, \$b, label| 010100 000      | if ($a == \$b) PC=label
|bne \$a, \$b, label| 010100 001      | if ($a != \$b) PC=label
|blt \$a, \$b, label| 010100 010      | if ($a < \$b)  PC=label (signed)
|bltu \$a, \$b,label| 010100 011      | if ($a < \$b)  PC=label (unsigned)
|bgt \$a, \$b, label| 010100 100      | if ($a > \$b)  PC=label (signed)
|bgtu \$a, \$b,label| 010100 101      | if ($a > \$b)  PC=label (unsigned)
|jmp label        | 010101          | PC = label
|jmp \$d, label    | 010101          | \$d = PC+4; PC=label
|jmpr \$a[s13]     | 010110          | PC = \$a + s13
|jsr label        | 010101          | R30 = PC+4; PC=label
|ret              | 010110          | PC = R30
|mul \$d, \$a, \$b   | 011001 000      | \$d = \$a * \$b
|mulhs \$d, \$a, \$b | 011001 001      | \$d = high 32 bits of (\$a * \$b) (signed)
|mulhu \$d, \$a, \$b | 011001 010      | \$d = high 32 bits of (\$a * \$b) (unsigned)
|mulhsu \$d, \$a, \$b | 011001 011     | \$d = high 32 bits of (\$a * \$b) (signed*unsigned)
|divu \$d, \$a, \$b  | 011001 100      | \$d = \$a / \$b (unsigned)
|divs \$d, \$a, \$b  | 011001 101      | \$d = \$a / \$b (signed)
|modu \$d, \$a, \$b  | 011001 110      | \$d = \$a % \$b (unsigned)
|mods \$d, \$a, \$b  | 011001 111      | \$d = \$a % \$b (signed)
|mul \$d, \$a,  s13 | 011001 000      | \$d = \$a * s13
|mulhs \$d, \$a, s13 | 011001 001     | \$d = high 32 bits of (\$a * s13) (signed)
|mulhu \$d, \$a, s13 | 011001 010     | \$d = high 32 bits of (\$a * s13) (unsigned)
|mulhsu \$d, \$a, s13 | 011001 011    | \$d = high 32 bits of (\$a * s13) (signed*unsigned)
|divu \$d, \$a, s13 | 011001 100      | \$d = \$a / s13 (unsigned)
|divs \$d, \$a, s13 | 011001 101      | \$d = \$a / s13 (signed)
|modu \$d, \$a, s13 | 011001 110      | \$d = \$a % s13 (unsigned)
|mods \$d, \$a, s13 | 011001 111      | \$d = \$a % s13 (signed)
|idx1 \$d, \$a, \$b  | 011100 000      | if \$a < \$b then \$d=\$a  else TRAP
|idx2 \$d, \$a, \$b  | 011100 001      | if \$a < \$b then \$d=\$a*2 else TRAP
|idx4 \$d, \$a, \$b  | 011100 010      | if \$a < \$b then \$d=\$a*4 else TRAP
|fadd \$d, \$a, \$b  | 011101 000      | \$d = float($a) + float($b)
|fsub \$d, \$a, \$b  | 011101 001      | \$d = float($a) - float($b)
|fmul \$d, \$a, \$b  | 011101 010      | \$d = float($a) * float($b)
|fdiv \$d, \$a, \$b  | 011101 011      | \$d = float($a) / float($b)
|fcmp \$d, \$a, \$b  | 011101 101      | \$d = float($a) <=> float($b) : -1/0/+1
|ftoi \$d, \$a      | 011101 110      | \$d = int(float($a))
|itof \$d, \$a      | 011101 111      | \$d = float(int($a))
|cfg  \$d, !reg    | 011011 000      | Read from configuration register. \$d=!reg
|cfg  !reg, \$a    | 011011 001      | Write to configuration register   !reg=$a
|cfg  \$d, !reg, \$a| 011011 001      | Atomically read and write config register.   \$d=!reg; !reg=$b
|rte              | 011011 010      | Return from exception.  \$PC=!evec; !status=!estatus
|rti              | 011011 010      | Return from interrupt.  \$PC=!intvec; !status=!istatus
|sys s13          | 011011 011      | Trigger a system call exception with code s13

The assembler has a pseudo-instruction `ld` which can be used to load a register with another register, to load a 32 bit immediate value into a register, or load a PC-relative address into a register. The assembler will automatically choose the appropriate instruction encoding (either as a OR immediate, LDU or LDPC instruction or sequence). eg
    ld \$5, 0x12345678   # Will be assembled as an LDU followed by an OR immediate
    ld \$6, label        # Will be assembled as an LDPC instruction
    ld \$7, \$8           # Will be assembled as an OR between \$8 and 0.

# Exceptions

The CPU has a set of configuration registers that control various aspects of the CPU's behavior, as follows:

| Register   |Number  | Width | Description
|------------|--------|-------|-------------------------
| !version   | 0x0    |  32   | Reads as 0x00020000 on Falcon7
| !status    | 0x1    |  8    | Status register. See table below for bit definitions
| !epc       | 0x2    |  32   | Set to the PC of the instruction that caused the exception
| !ecause    | 0x3    |  8    | Reason for the exception (see table below)
| !edata     | 0x4    |  32   | Additional data about the exception (eg bad address)
| !estatus   | 0x5    |  8    | Status register at time of exception
| !escratch  | 0x6    |  32   | Scratch register for use by exception handlers
| !timer     | 0x7    |  32   | Timer register. Decrements every clock cycle. Trigger interrupt when reaches 0.
| !mpu_clear | 0x8    |  8    | Write 0 to this register to clear the MPU. (other values reserved)
| !mpu_data  | 0x9    |  32   | Write to this register add a memory region to the MPU

When an exception occurs, the CPU:
   * sets !epc register to the address of the instruction that caused the exception
   * sets !ecause register to a code indicating the reason for the exception
   * sets !edata to additional data about the exception (eg the bad address for a memory access fault). 
   * sets !estatus to the value of the !status register at the time of the exception
   * Sets the supervisor mode, and clears the interrupt enable  bits in the !status register 
   * Jumps to the address 0xFFFF0004, where the exception handler is expected to be located.

Exception Causes (!ecause register):-
| Value | Description                 | Value in !edata
|-------|-----------------------------|----------------
| 0x01  | instruction access fault    | address of the instruction that caused the fault
| 0x02  | illegaal instruction        | instruction word that caused the exception
| 0x03  | breakpoint                  | instruction word of the breakpoint instruction that was hit
| 0x04  | load address misaligned     | address that caused the misaligned access
| 0x05  | load access fault           | address that caused the access fault
| 0x06  | store address misaligned    | address that caused the misaligned access
| 0x07  | store access fault          | address that caused the access fault
| 0x08  | system call                 | system call code (the immediate value in the syscall instruction)
| 0x09  | index overflow              | value of the index that was out of bounds
| 0x0A  | address error               | address that caused the fault
| 0x0B  | Interrupt                   | interrupt source number

Interrupt Sources:-
| Value | Description
|-------|-----------------------------
| 0x01  | timer interrupt

Status Register (!status and !estatus registers):-
| Bit | Name            | Description
|-----|-----------------|-------------------------------
|  0  | SUPERVISOR_MODE | Processor is in Supervisor Mode
|  1  | INTERUPT_ENABLE | Interrupt Enable (1=enabled)





