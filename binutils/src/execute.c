#define _CRT_SECURE_NO_WARNINGS
#include <stdio.h>
#include <string.h>
#include "f32.h"

extern int code_size;
extern int* code_buffer;
extern struct Label* labels;
extern FILE *trace_file;
extern FILE *regs_file;
static FILE *uart_file = NULL; // File for simulating UART output, initialized on first use
extern int timeout;

/**
 * State of the CPU
 */

static int regs[32];
static int pc = 0;
static int memory[16*1024*1024]; // 64MB of memory, word-addressable

static int cfg_epc;
static int cfg_status;
static int cfg_ecause;
static int cfg_edata;
static int cfg_estatus;
static int cfg_escratch;
static int cfg_timer;
static int cfg_mpu_clear;
static int cfg_mpu_data;
static int raising_exception = 0;
static int this_instr;

static int seven_seg_display = 0; // Current value of the seven-segment display HWREG
static int led_display = 0; // Current value of the LED display HWREG

#define CAUSE_INSTR_ACCESS_FAULT 0x01
#define CAUSE_ILLEGAL_INSTR      0x02
#define CAUSE_BREAKPOINT         0x03
#define CAUSE_LOAD_MISALIGNED    0x04
#define CAUSE_LOAD_ACCESS_FAULT  0x05
#define CAUSE_STORE_MISALIGNED   0x06
#define CAUSE_STORE_ACCESS_FAULT 0x07
#define CAUSE_SYSTEM_CALL        0x08
#define CAUSE_INDEX_OVERFLOW     0x09
#define CAUSE_ADDRESS_ERROR      0x0A


/**
 * Parameters for the emulator, set from command-line arguments
 */

extern int code_size;
extern int* code_buffer;
extern struct Label* labels;

/**
 * sets a register value, and outputs to the trace and regs files if enabled
 */

static void set_reg(int reg, int value) {
    if (reg == 0)
        return; // Register $0 is hardwired to 0
    if (raising_exception)
        return; // Don't modify registers while raising an exception
    if (regs_file)
        fprintf(regs_file, "$%2d = %08x\n", reg, value);
    if (trace_file)
        fprintf(trace_file, " $%d=0x%08x", reg, value);
    regs[reg] = value;
}

/**
 * Raises an exception with the given cause and data. 
 * This will set the appropriate !e* registers, switch to supervisor mode,
 * and jump to the exception handler.
 */

static int raise_exception(int cause, int data) {
    raising_exception = 1;
    cfg_epc = pc;
    cfg_ecause = cause;
    cfg_edata = data;
    cfg_estatus = cfg_status;
    cfg_status = 0x1; // Set supervisor mode and disable interrupts
    if (trace_file)
        fprintf(trace_file, " EXCEPTION %02x %08x", cause, data);
    pc = 0xFFFF0000;    // Jump to address 0xFFFF0004 after accounting for the pc increment in the main loop
    return 0; // Dummy return value for use in expressions like "return raise_exception(...)"
}

/**
 * Evaluate an ALU instruction and return the result.
 */

static int alu_op(int op, int a, int b) {
    switch(op) {
        case 0: return a & b; // and
        case 1: return a | b; // or
        case 2: return a ^ b; // xor
        case 4: return a + b; // add
        case 5: return a - b; // sub
        case 6: return a < b; // clt signed
        case 7: return (int)((unsigned)a < (unsigned)b); // clt unsigned
        default: fatal("Invalid ALU operation: %d", op);
    }
}

/**
 * Evaluate a shift instruction and return the result.
 */

static int shift_op(int op, int a, int b) {
    switch(op) {
        case 0: return a << b; // lsl
        case 2: return (unsigned)a >> b; // lsr
        case 3: return a >> b; // asr
        default: return 0;
    }
}

/**
 * Evaluate a floating point operation and return the result as an integer bit pattern
 */

static int fpu_op(int op, int a, int b) {
    float fa = *(float*)&a;
    float fb = *(float*)&b;
    float result;

    switch(op) {
        case 0: result = fa + fb; break;
        case 1: result = fa - fb; break;
        case 2: result = fa * fb; break;
        case 3: result = fa / fb; break;
        case 5: { // fcmp
            if (fa < fb) return -1;
            else if (fa > fb) return 1;
            else return 0;
        }
        case 6: return (int)fa; // ftoi
        case 7: result = (float)a; break; // itof
        default: fatal("Invalid FPU operation: %d", op);
    }
    return *(int*)&result;
}

/**
 * Evaluate a branch instruction and return whether the branch should be taken.
 */
static int bra_op(int op, int a, int b) {
    switch(op) {
        case 0: return a == b; // beq
        case 1: return a != b; // bne
        case 2: return (int)a < (int)b; // blt signed
        case 3: return (int)a >= (int)b; // bge signed
        case 4: return (unsigned)a < (unsigned)b; // blt unsigned
        case 5: return (unsigned)a >= (unsigned)b; // bge unsigned
        default: return raise_exception(CAUSE_ILLEGAL_INSTR, this_instr);
    }   
}


/**
 * Evaluate a multiplication/division operation and return the result.
 */

static int mul_op(int op, int a, int b) {
    switch(op) {
        case 0: return a * b; // mul
        case 1: return (unsigned)((((unsigned long long)(unsigned)a * (unsigned long long)(unsigned)b)) >> 32); // mulh
        case 2: return (int)(((long long)a * (long long)b) >> 32); // mulhs
        case 3: return (int)(((long long)a * (unsigned long long)(unsigned)b) >> 32); // mulhsu
        case 4: // divu - unsigned division
            if (b == 0) return -1; // RISC-V: division by zero returns -1
            return (unsigned)a / (unsigned)b;
        case 5: // divs - signed division
            if (b == 0) return -1; // RISC-V: division by zero returns -1
            if (a == (int)0x80000000 && b == -1) return a; // RISC-V: overflow returns INT_MIN
            return (int)a / (int)b;
        case 6: // modu - unsigned modulo
            if (b == 0) return a; // RISC-V: remainder by zero returns dividend
            return (unsigned)a % (unsigned)b;
        case 7: // mods - signed modulo
            if (b == 0) return a; // RISC-V: remainder by zero returns dividend
            if (a == (int)0x80000000 && b == -1) return 0; // RISC-V: overflow remainder returns 0
            return (int)a % (int)b;
        default: fatal("Invalid multiplication/division operation: %d", op);
    }
}

/**
 * Read HWREGS and return the value.
 */

static int read_hwreg(int reg) {
    switch(reg) {
        case 0x00: return seven_seg_display; // Seven-segment display register
        case 0x04: return led_display; // LED register
        case 0x10: return 0x3ff;  // UART space free in simulated UART output buffer (always return "full" for simplicity)
        case 0x30: return 1; // SIMULATION REGISTER - return 1 to indicate we're running in the simulator (will read as 0 in the actual hardware)
        default: return 0; // Reading from invalid or write-only HWREGs returns 0
    }
}

/**
 * Read a word from memory at the given address. 
 * Handles memory-mapped I/O and invalid memory accesses.
 */

static int read_memory(int address) {
    unsigned int addr = (unsigned)address;
    if (addr<0x4000000)
        // Address in main memory
        return memory[addr/4];

    else if (addr >= 0xE0000000U && addr < 0xE0001000U)
        // Address in HWREGS
        return read_hwreg(addr & 0xffff);

    else if (addr >= 0xFFFF0000U) {
        // Address in Boot ROM
        return code_buffer[(addr & 0xffff) /4];
    
    } else {
        return raise_exception(CAUSE_ADDRESS_ERROR, address);
    }
}



/**
 * Write HWREGS
 */

static void write_hwreg(int reg, int value) {
    switch(reg) {
        case 0x00:  // Seven-segment display register
                if (value != seven_seg_display) {
                    seven_seg_display = value & 0xFFFFFF;
                    printf("7SEG=%06x\n", value & 0xFFFFFF);
                }
            break;
        case 0x04:  // LED register - print the value to the console
                if (value != led_display) {
                    led_display = value & 0x3FF;
                    printf("LED=");
                    for(int i=9; i>=0; i--) {
                        printf("%d", (led_display >> i) & 1);
                    }
                }
                break;
        case 0x10:  // UART output register - write the value to the simulated UART output file
                fputc(value & 0xFF, uart_file);
                printf("%c", value & 0xFF); // Also print the character to the console for convenience
                break;
        default: break; // Writing to invalid or read-only HWREGs has no effect
    }
}





/**
 * Write a word to memory at the given address.
 */

static void write_memory(int address, int value) {
    unsigned int addr = (unsigned)address;
    if (addr<0x4000000)
        // Address in main memory
        memory[addr/4] = value;

    else if (addr >= 0xFFFF0000U) {
        // Address in program memory
        code_buffer[(addr & 0xFFFF)/4] = value;

    } else if (addr >= 0xE0000000U && addr < 0xE0001000U) {
        // Address in program memory
        write_hwreg(addr & 0xFFFF, value);

    } else {
        raise_exception(CAUSE_ADDRESS_ERROR, address);
    }
    if (trace_file)
        fprintf(trace_file, " [0x%08x]=0x%08x", address, value);
}


/**
 * Read a word from memory at the given address.
 * Handles different load sizes (byte, half-word, word) and sign-extends the result as needed.
 */

static int load_op(int op, int base, int offset) {
    int addr = base + offset;
    int word_addr = addr & ~0x3;
    int shift_amt = 8*(addr % 4);

    switch(op) {
        case 0: { // ldb
            int word = read_memory(word_addr);
            int byte = (word >> shift_amt) & 0xFF;
            if (byte & 0x80) // Sign-extend the byte
                byte |= ~0xFF;
            return byte;
        }
        case 1: { // ldh
            if (addr % 2 != 0)
                return raise_exception(CAUSE_LOAD_MISALIGNED, addr);
            int word = read_memory(word_addr);
            int half = (word >> shift_amt) & 0xFFFF;
            if (half & 0x8000) // Sign-extend the half-word
                half |= ~0xFFFF;
            return half;
        }
        case 2: // ldw
            if (addr % 4 != 0)
                return raise_exception(CAUSE_LOAD_MISALIGNED, addr);
            return read_memory(addr);

        default:
            return raise_exception(CAUSE_ILLEGAL_INSTR, this_instr);
    }
}

/**
 * Store a word to memory at the given address, 
 * handling different store sizes (byte, half-word, word).
 */
static void store_op(int op, int base, int offset, int value) {
    int addr = base + offset;
    int word_addr = addr & ~0x3;
    int shift_amt = 8*(addr % 4);

    switch(op) {
        case 0: { // stb
            int word = read_memory(word_addr);
            word &= ~(0xFF << shift_amt); // Clear the target byte
            word |= (value & 0xFF) << shift_amt; // Set the target byte
            write_memory(word_addr, word);
            break;
        }
        case 1: { // sth
            if (addr % 2 != 0) {
                raise_exception(CAUSE_STORE_MISALIGNED, addr);
                return;
            }
            int word = read_memory(addr & ~0x3);
            word &= ~(0xFFFF << shift_amt); // Clear the target half-word
            word |= (value & 0xFFFF) << shift_amt; // Set the target half-word
            write_memory(word_addr, word);
            break;
        }
        case 2: // stw
            if (addr % 4 != 0) {
                raise_exception(CAUSE_STORE_MISALIGNED, addr);
                return;
            }
            write_memory(addr, value);
            break;

        default:
            raise_exception(CAUSE_ILLEGAL_INSTR, this_instr);
            return;
    }
}

/**
 * Store a value to a configuration register. 
 */

static void write_cfg(int reg, int value) {
    switch(reg) {
        case 1: cfg_status = value & 0xFF; break;
        case 2: cfg_epc = value; break;
        case 3: cfg_ecause = value & -0xff; break;
        case 4: cfg_edata = value; break;
        case 5: cfg_estatus = value & -0xff; break;
        case 6: cfg_escratch = value; break;
        case 7: cfg_timer = value; break;
        case 8: cfg_mpu_clear = value; break;   // NOT YET IMPLEMENTED - should clear the MPU if value is 0
        case 9: cfg_mpu_data = value; break;
        default: break; // Writing to invalid or read-only config registers has no effect
    }
}

/**
 * Read a value from a configuration register.
 */

static int read_cfg(int reg) {
    switch(reg) {
        case 0: return 0x00020000; // version
        case 1: return cfg_status;
        case 2: return cfg_epc;
        case 3: return cfg_ecause;
        case 4: return cfg_edata;
        case 5: return cfg_estatus;
        case 6: return cfg_escratch;
        case 7: return cfg_timer;
        case 8: return cfg_mpu_clear;
        case 9: return cfg_mpu_data;
        default: return 0; // Reading from invalid or write-only config registers returns 0
    }
}


/**
 * Execute a single instruction
 */

static void execute_instruction(int instr) {
    int k = instr >> 26;
    int i = (instr >> 23) & 0x7;
    int d = (instr >> 18) & 0x1f;
    int a = (instr >> 13) & 0x1f;
    int c = (instr >> 5) & 0xff;
    int b = instr & 0x1f;
    int imm13 = instr & 0x1fff;
    if (imm13 & 0x1000) // Sign-extend the immediate
        imm13 |= ~0x1fff;
    int imm13d = (c << 5) | d;
    if (imm13d & 0x1000) // Sign-extend 13-bit immediate
        imm13d |= ~0x1fff;
    int imm21 = (c<<13) | (i<<10) | (a<<5) | b;
    if (imm21 & 0x100000) // Sign-extend 21-bit immediate
        imm21 |= ~0x1fffff;

    if (trace_file)
        fprintf(trace_file, "%08x: %08x %-30s", pc, instr, disassemble_line(instr, pc));

    switch(k) {
        case KIND_ALU: { // 0x10 - Register ALU operations
            if (i==3)  // Shift operations are a special case of ALU with i=3
                set_reg(d, shift_op(c&3, regs[a], regs[b]));
            else
                set_reg(d, alu_op(i, regs[a], regs[b]));
            break;
        }
        
        case KIND_ALUI: { // 0x11 - Immediate ALU operations
            if (i==3)  // Shift operations are a special case of ALUI with i=3
                set_reg(d, shift_op(c&3, regs[a], imm13));
            else
                set_reg(d, alu_op(i, regs[a], imm13));
            break;
        }

        case KIND_BRA:  {
            if (bra_op(i, regs[a], regs[b])) {
                pc += (imm13d << 2);
                if (trace_file)
                    fprintf(trace_file, " -> %s", find_label(pc));
                pc -= 4; // Adjust for the automatic pc increment 
            }
            break;
        }

        case KIND_JMP: {
            if (d != 0)
                set_reg(d, pc + 4); // Store return address in $d
            pc += (imm21 << 2);
            if (trace_file)
                fprintf(trace_file, " -> %s", find_label(pc));
            pc -= 4; // Adjust for the automatic pc increment
            break;
        }

        case KIND_JMPR:  {
            int target = regs[a] + imm13*4;
            if (d != 0)
                set_reg(d, pc + 4); // Store return address in $d
            pc = target;
            if (trace_file)
                fprintf(trace_file, " -> %s", find_label(pc));
            pc -= 4; // Adjust for the automatic pc increment
            break;
        }

        case KIND_IDX: {
            if (regs[a] >= regs[b] || regs[a] < 0) {
                raise_exception(CAUSE_INDEX_OVERFLOW, regs[a]);
            } else {
                set_reg(d, regs[a] << i); // Return byte offset of the indexed element
            }
            break;
        }

        case KIND_MUL:  {
            set_reg(d, mul_op(i, regs[a], regs[b]));
            break;
        }

        case KIND_MULI:  {
            set_reg(d, mul_op(i, regs[a], imm13));
            break;
        }

        case KIND_LDPC:  {
            int target = pc + (imm21 << 2);
            set_reg(d, target);
            break;
        }

        case KIND_LDU:  {
            set_reg(d, imm21 << 11);
            break;
        }

        case KIND_LD: {
            int value = load_op(i, regs[a], imm13);
            set_reg(d, value);
            break;
        }

        case KIND_ST:  {
            store_op(i, regs[a], imm13d, regs[b]);
            break;
        }

        case KIND_CFG:  {
            switch(i) {
                case 0: // Read from config register
                    set_reg(d, read_cfg(imm13));
                    break;

                case 1: {// Read/Write to config register
                    int tmp = read_cfg(imm13);
                    write_cfg(imm13, regs[a]);
                    set_reg(d, tmp);
                    break;
                }

                case 2: // Return from exception (rte)
                    pc = cfg_epc;
                    if (trace_file)
                        fprintf(trace_file, " -> %s", find_label(pc));
                    cfg_status = cfg_estatus;
                    pc -= 4; // Adjust for the automatic pc increment
                    break;

                case 3: // System call (sys)
                    raise_exception(CAUSE_SYSTEM_CALL, imm13);
                    break;

                default:
                    raise_exception(CAUSE_ILLEGAL_INSTR, this_instr);
            }
            break;
        }
        
        case KIND_FPU: { // 0x1D - Floating point operations
            set_reg(d, fpu_op(i, regs[a], regs[b]));
            break;
        }
        
        default: 
            raise_exception(CAUSE_ILLEGAL_INSTR, this_instr);
            break;
    }

    if (trace_file)
        fprintf(trace_file, "\n");
}


/**
 * Main execution loop
 */

void execute_code() {
    if (uart_file == NULL) {
        uart_file = fopen("sim_uart.log", "w");
        if (uart_file == NULL) {
            error("Failed to open uart_output.txt for writing");
            return;
        }
    }

    pc = 0xFFFF0000; // Start execution at the reset vector
    while (pc < code_size * 4) {
        raising_exception = 0;
        if (pc==0) {
            // Reached address 0 - treat this as a special "halt" instruction to stop execution
            if (trace_file)                fprintf(trace_file, "HALT\n");
            break;  
        }

        this_instr = read_memory(pc);
        if (!raising_exception) // If fetching the instruction caused an exception, don't try to execute it
            execute_instruction(this_instr);
        pc += 4;

        if (timeout-- <= 0) {
            error("Execution timed out");
            break;
        }

    }
}