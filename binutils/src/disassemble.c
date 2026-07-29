#include <stdio.h>
#include <string.h>
#include "f32.h"

extern int code_size;
extern int* code_buffer;
extern struct Label* labels;


/**
 * Finds a label name for a given address. 
 * Returns the label name if found, or a hexadecimal string of the address if not found.
 */

String find_label(int address) {
    static char buf[32];
    for (struct Label* label = labels; label; label = label->next)
        if (label->value == address)
            return label->name;
    
    snprintf(buf, sizeof(buf), "0x%08x", address);
    return buf;
}


static String get_cfg(int cfg_num) {
    const char* cfg_regs[] = {
        "!version","!status","!epc","!ecause","!edata","!estatus",
        "!escratch","!timer","!mpu_clear","!mpu_data" };

    if (cfg_num >= 0 && cfg_num < 10)
        return cfg_regs[cfg_num];
    else {
        static char buf[16];
        snprintf(buf, sizeof(buf), "!%d", cfg_num);
        return buf;
    }
}

/**
 * Disassemble one instruction into a human-readable assembly format. 
 */

String disassemble_line(int instr, int pc) {
    int k = instr >> 26;
    int i = (instr >> 23) & 0x7;
    int d = (instr >> 18) & 0x1f;
    int a = (instr >> 13) & 0x1f;
    int c = (instr >> 5) & 0xff;
    int b = instr & 0x1f;
    int imm13 = (c << 5) | b;
    if (imm13 & 0x1000) // Sign-extend 13-bit immediate
        imm13 |= ~0x1fff;
    int imm13d = (c << 5) | d;
    if (imm13d & 0x1000) // Sign-extend 13-bit immediate
        imm13d |= ~0x1fff;
    int imm21 = (c<<13) | (i<<10) | (a<<5) | b;
    if (imm21 & 0x100000) // Sign-extend 21-bit immediate
        imm21 |= ~0x1fffff;

    static char line[256];
    
    // Helper macro for formatting output
    #define FMT(...) snprintf(line, sizeof(line), __VA_ARGS__)
    
    switch(k) {
    case KIND_ALU: { // 0x10 - Register ALU operations
        const char* ops[] = {"and", "or", "xor", "???", "add", "sub", "clt", "cltu"};
        if (i==1 && b==0) { // Move immediate to register (special case of ALU with i=1 and b=0)
            FMT("ld $%d, $%d", d, a);
        } else if (i == 3) { // Shift operations
            const char* shifts[] = {"lsl", "???", "lsr", "asr"};
            int shift_type = c & 3;
            FMT("%s $%d, $%d, $%d", shifts[shift_type], d, a, b);
        } else {
            FMT("%s $%d, $%d, $%d", ops[i], d, a, b);
        }
        break;
    }
    
    case KIND_ALUI: { // 0x11 - Immediate ALU operations
        const char* ops[] = {"and", "or", "xor", "???", "add", "sub", "clt", "cltu"};
        if (i==1 && a==0) { // Move immediate to register (special case of ALUI with i=1 and a=0)
            FMT("ld $%d, %d", d, imm13);
        } else if (i == 3) { // Shift operations
            const char* shifts[] = {"lsl", "???", "lsr", "asr"};
            int shift_type = c & 3;
            FMT("%s $%d, $%d, %d", shifts[shift_type], d, a, imm13);
        } else {
            FMT("%s $%d, $%d, %d", ops[i], d, a, imm13);
        }
        break;
    }
    
    case KIND_LD: { // 0x12 - Load from memory
        const char* loads[] = {"ldb", "ldh", "ldw"};
        if (i < 3) {
            FMT("%s $%d, $%d[%d]", loads[i], d, a, imm13);
        } else {
            FMT("??? 0x%08x", instr);
        }
        break;
    }
    
    case KIND_ST: { // 0x13 - Store to memory
        const char* stores[] = {"stb", "sth", "stw"};
        if (i < 3) {
            FMT("%s $%d, $%d[%d]", stores[i], b, a, imm13d);
        } else {
            FMT("??? 0x%08x", instr);
        }
        break;
    }
    
    case KIND_BRA: { // 0x14 - Branch instructions
        const char* branches[] = {"beq", "bne", "blt", "bge", "bltu", "bgeu"};
        if (i < 6) {
            int target = pc + (imm13d << 2);
            FMT("%s $%d, $%d, %s", branches[i], a, b, find_label(target));
        } else {
            FMT("??? 0x%08x", instr);
        }
        break;
    }
    
    case KIND_JMP: { // 0x15 - Jump (and link)
        int target = pc + (imm21 << 2);
        if (d == 0) {
            FMT("jmp %s", find_label(target));
        } else if (d == 30) {
            FMT("jsr %s", find_label(target));
        } else {
            FMT("jsr $%d, %s", d, find_label(target));
        }
        break;
    }
    
    case KIND_JMPR: { // 0x16 - Jump register (and link)
        if (d == 0 && a == 30 && imm13 == 0) {
            FMT("ret");
        } else if (d == 0) {
            FMT("jmp $%d[%d]", a, imm13);
        } else {
            FMT("jsr $%d, $%d[%d]", d, a, imm13);
        }
        break;
    }
    
    case KIND_LDU: { // 0x17 - Load upper immediate
        FMT("ld $%d, %s", d, find_label(imm21<<11));
        break;
    }
    
    case KIND_LDPC: { // 0x18 - Load PC-relative
        int addr = pc + (imm21 << 2);
        FMT("ldpc $%d, 0x%x", d, addr);
        break;
    }
    
    case KIND_MUL: { // 0x19 - Multiply/divide register operations
        const char* mops[] = {"mul", "mulhu", "mulhs", "mulhsu", "divu", "divs", "modu", "mods"};
        FMT("%s $%d, $%d, $%d", mops[i], d, a, b);
        break;
    }
    
    case KIND_MULI: { // 0x1A - Multiply/divide immediate operations
        const char* mops[] = {"mul", "mulhs", "mulhu", "mulhsu", "divu", "divs", "remu", "rems"};
        FMT("%s $%d, $%d, %d", mops[i], d, a, imm13);
        break;
    }
    
    case KIND_CFG: { // 0x1B - Configuration register access

        if (i == 0) {
            FMT("cfg $%d, %s", d, get_cfg(imm13));
        } else if (i == 1 && d == 0) {
            FMT("cfg %s, $%d", get_cfg(imm13), a);
        } else if (i == 1) {
            FMT("cfg $%d, %s, $%d", d, get_cfg(imm13), a);
        } else if (i == 2) {
            FMT("rte");
        } else if (i == 3) {
            FMT("sys %d", imm13);
        } else {
            FMT("??? 0x%08x", instr);
        }
        break;
    }
    
    case KIND_IDX: { // 0x1C - Indexed operations with bounds check
        const char* idxops[] = {"idx1", "idx2", "idx4"};
        if (i < 3) {
            FMT("%s $%d, $%d, $%d", idxops[i], d, a, b);
        } else {
            FMT("??? 0x%08x", instr);
        }
        break;
    }
    
    case KIND_FPU: { // 0x1D - Floating point operations
        const char* fpops[] = {"fadd", "fsub", "fmul", "fdiv", "???", "fcmp", "ftoi", "itof"};
        if (i < 8 && i != 4) {
            if (i == 6 || i == 7) {
                // ftoi and itof only use two operands
                FMT("%s $%d, $%d", fpops[i], d, a);
            } else {
                FMT("%s $%d, $%d, $%d", fpops[i], d, a, b);
            }
        } else {
            FMT("??? 0x%08x", instr);
        }
        break;
    }
    
    default:
        FMT("??? 0x%08x", instr);
        break;
    }
    
    return line;
}


/**
 * Disassemble the entire code buffer and print it to stdout.
 */
void disassemble_code() {
    for (int pc = 0; pc < code_size * 4; pc += 4) {
        for (struct Label* label = labels; label; label = label->next)
            if (label->value == pc)
                printf("%08x:          %s:\n", pc, label->name);

        int instr = code_buffer[pc/4];
        String line = disassemble_line(instr, pc);
        printf("%08x: %08x %s\n", pc, instr, line);
    }
}