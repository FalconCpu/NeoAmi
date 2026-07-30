#define _CRT_SECURE_NO_WARNINGS
#include <stdio.h>
#include <string.h>
#include "f32.h"

extern int line_number;
extern int num_errors;

/**
 * Buffer to store the assembled machine code
 */

int* code_buffer = NULL;
int code_size = 0;
int code_capacity = 0;

void emit(int instruction) {
    if (code_size >= code_capacity) {
        code_capacity *= 2;
        resize_array(code_buffer, int, code_capacity);
    }
    code_buffer[code_size++] = instruction;
}

/**
 * Assemble an instruction in form R from its fields. 
 */

int format_R(int k, int i, int c, int d, int a, int b) {
    assert(k >= 0 && k < 32);
    assert(i >= 0 && i < 8);
    assert(c >= 0 && c < 256);
    assert(d >= 0 && d < 32);
    assert(a >= 0 && a < 32);
    assert(b >= 0 && b < 32);
    return (k << 26) | (i << 23) | (d << 18) | (a << 13) | (c << 5) |  b;
}

/**
 * Assemble an instruction in form I from its fields. 
 */

int format_I(int k, int i, int d, int a, int n) {
    assert(k >= 0 && k < 32);
    assert(i >= 0 && i < 8);
    assert(d >= 0 && d < 32);
    assert(a >= 0 && a < 32);
    if (n<-0x1000 || n>0xfff) {
        error("Immediate value out of range I: %d", n);
        n = 0;
    }
    return (k << 26) | (i << 23) | (d << 18) | (a << 13) | (n & 0x1fff);
}

/**
 * Assemble an instruction in form B from its fields. 
 */
int format_B(int k, int i, int a, int b, int n) {
    assert(k >= 0 && k < 32);
    assert(i >= 0 && i < 8);
    assert(b >= 0 && b < 32);
    assert(a >= 0 && a < 32);
    if (n<-0xfff || n>0xfff) {
        error("Immediate value out of range B: %d", n);
        n = 0;
    }
    return (k << 26) | (i << 23) | ((n&31) << 18) | (a << 13) | (n & 0x1fe0) | b;
}

/**
 * Assemble an instruction in form J from its fields. 
 */
int format_J(int k, int d, int n) {
    assert(k >= 0 && k < 32);
    assert(d >= 0 && d < 32);
    if (n<-0x1000000 || n>0xfffff) {
        error("Immediate value out of range J: %d", n);
        n = 0;
    }
    int b = (n&31);
    int a = (n>>5) & 0x1f;
    int i = (n>>10) & 0x7;
    int c = (n>>13) & 0xff;
    return (k << 26) | (i << 23) | (d << 18) | (a << 13) | (c << 5) | b;
}

/**
 * Combine bytes into a 32-bit word
 */

static int partialWord = 0;
static int numBytes = 0;

static void emit_byte(int b) {
    partialWord = partialWord | ((b & 0xff) << (numBytes * 8));
    numBytes++;
    if (numBytes == 4) {
        emit(partialWord);
        partialWord = 0;
        numBytes = 0;
    }
}

static void flush_bytes() {
    if (numBytes > 0) {
        emit(partialWord);
        partialWord = 0;
        numBytes = 0;
    }
}

/**
 * Emit constant data - used for pseudo-ops like dcb, dch, dcw
 */

static void emit_bytes(Token**line) {
    int i = 1;
    while (1) {
        if (line[i]->kind == '#') {
            int value = line[i]->value;
            if (value < 0 || value > 255)
                error("Byte value out of range (0..255): %d", value);
            emit_byte(value);
        } else if (line[i]->kind == '"') {
            // Handle string literal
            String str = line[i]->text;
            for (int j = 0; str[j]; j++)
                emit_byte(str[j]);
        } else {
            error("Expected byte value, got: %s", line[i]->text);
        }
        i++;
        if (line[i] && line[i]->kind == ',')
            i++; // Skip comma
        else
        break;
    }

    if (line[i]!=0)
        error("Unexpected token after byte values: %s", line[i]->text);
    flush_bytes();
}

static void emit_half_words(Token**line) {
    int i = 1;
    while (1) {
        if (line[i]->kind == '#') {
            int value = line[i]->value;
            if (value < -0x8000 || value > 0x7fff)
                error("Half-word value out of range (-32768..32767): %d", value);
            emit_byte(value & 0xff);
            emit_byte((value >> 8) & 0xff);
        } else {
            error("Expected half-word value, got: %s", line[i]->text);
        }
        i++;
        if (line[i] && line[i]->kind == ',')
            i++; // Skip comma
        else
        break;
    }

    if (line[i]!=0)
        error("Unexpected token after half-word values: %s", line[i]->text);
}

static void emit_words(Token**line) {
    int i = 1;
    while (1) {
        if (line[i]->kind == '#') {
            int value = line[i]->value;
            emit(value);
        } else {
            error("Expected word value, got: %s", line[i]->text);
        }
        i++;
        if (line[i] && line[i]->kind == ',')
            i++; // Skip comma
        else
            break;
    }

    if (line[i]!=0)
        error("Unexpected token after word values: %s", line[i]->text);
}

static void emit_constants(Token **line) {
    if (line[0]->value==0)
        emit_bytes(line);
    else if (line[0]->value==1)
        emit_half_words(line);
    else if (line[0]->value==2)
        emit_words(line);
    else
        error("Unknown data type: %s", line[0]->text);
}

/** 
 * Check if token sequence matches a format string. 
 * Where the format string is a sequence of token kinds
 * Special case : "0" can be matched to either a register('$') or immediate('#') in the format string
 */

int match_format(Token** line, char* format) {
    int i;
    for (i=0; line[i]; i++) {
        Token* t = line[i];
        if (t->kind == '#' && t->value == 0) {
            if (format[i] != '#' && format[i] != '$')
                return 0;
        } else {
            if (t->kind != format[i])
                return 0;
        }
    }
    return format[i] == '\0'; // Ensure format string is fully matched    
}

/**
 * Check a value is in the range 0..31 (Used for shift amounts)
 */

 int check_32(int n) {
    if (n < 0 || n > 31) {
        error("Value out of range (0..31): %d", n);
        return 0;
    }
    return n;
}

/**
 * Report a malformed instruction error, printing the tokens for the line.
 */
void report_malformed(Token** line) {
    printf("ERROR line %d: Unrecognized instruction", line_number);
    for (int i=0; line[i]; i++) {
        Token* t = line[i];
        printf(" %s", t->text);
    }
    printf("\n");
    num_errors++;
}

/**
 * Emit instructions to load an immediate value into a register.
 * Uses a single instruction if the value fits in 13 bits, otherwise uses two instructions.
 */

void emit_load_immediate(int d, int n) {
    if (n >= -0xfff && n <= 0xfff) {
        emit(format_I(KIND_ALUI, 1, d, 0, n)); // ori $d,$0,#n
    } else {
        emit(format_J(KIND_LDU, d, n>>11)); // ldu $d, upper bits of n
        int lower = n & 0x7ff;
        if (lower!=0)
            emit(format_I(KIND_ALUI, 1, d, d, lower)); // ori $d,$d,#lower
    }
}

/**
 * Define a label with its address. Checks for redefinition errors.
 */

void define_label(Token* label, int address) {
    if (label->flags & FLAG_DEFINED) {
        error("Label redefined: %s", label->text);
    } else {
        label->value = address;
        label->flags |= FLAG_DEFINED; // Mark label as defined
    }
}

/**
 * Define a constant with its value. Checks for redefinition errors.
 */

void define_constant(Token* label, int value) {
    if (label->flags & FLAG_DEFINED) {
        error("Label redefined: %s", label->text);
    } else {
        label->kind = '#'; // Mark token as a constant
        label->value = value;
    }
}

/**
 * Emit n words of value 0 (used for reserving space for uninitialized data with the `ds` pseudo-op)
 */
static void emit_space(int n) {
    for (int i=0; i<n/4; i++)
        emit(0);
}

/**
 * Structure to keep track of label references that need to be backpatched after all labels are defined.
 */

struct LabelRef {
    int line_number; // Line number where the label is referenced (for error reporting)
    Token* label;    // The label being referenced
    int address;     // The address of the instruction that needs to be backpatched
    struct LabelRef* next; // Next reference in the linked list
};

struct LabelRef* label_refs = NULL; // Linked list of label references

int label_ref(Token* label) {
    struct LabelRef* ref = new(struct LabelRef);
    ref->line_number = line_number;
    ref->label = label;
    ref->address = code_size*4; // Address of the instruction that will reference the label
    ref->next = label_refs;
    label_refs = ref;
    return 0; // Return value is not used
}


/**
 * Assemble line
 */

void assemble_line(Token** line) {

    #define MATCH(fmt) else if (match_format(line, fmt))
    #define V0 line[0]->value
    #define V1 line[1]->value
    #define V2 line[2]->value
    #define V3 line[3]->value
    #define V4 line[4]->value
    #define V5 line[5]->value

    if (line[0] == NULL)        return; // Empty line
    MATCH("l:")       define_label(line[0], code_size*4);
    MATCH("l=#")      define_constant(line[0], V2);
    MATCH("D$,$")     emit(format_I(KIND_ALU, 1, V1, V3, 0));  // `ld $d,$a` is encoded as `or $d,$a,$0`
    MATCH("D$,#")     emit_load_immediate(V1, V3);
    MATCH("D$,l")     emit(format_J(KIND_LDPC, V1, label_ref(line[3])));
    MATCH("A$,$,$")   emit(format_R(KIND_ALU, V0, 0, V1, V3, V5));
    MATCH("A$,$,#")   emit(format_I(KIND_ALUI, V0, V1, V3, V5));
    MATCH("A$,$")     emit(format_R(KIND_ALU, V0, 0, V1, V1, V3));
    MATCH("A$,#")     emit(format_I(KIND_ALUI, V0, V1, V1, V3));
    MATCH("H$,$,$")   emit(format_R(KIND_ALU, 3, V0, V1, V3, V5));
    MATCH("H$,$,#")   emit(format_R(KIND_ALUI, 3, V0, V1, V3, check_32(V5)));
    MATCH("H$,#")     emit(format_R(KIND_ALUI, 3, V0, V1, V1, V3));
    MATCH("L$,$[#]")  emit(format_I(KIND_LD, V0, V1, V3, V5));
    MATCH("S$,$[#]")  emit(format_B(KIND_ST, V0, V3, V1, V5));
    MATCH("B$,$,l")   emit(format_B(KIND_BRA, V0, V1, V3, label_ref(line[5])));
    MATCH("b$,$,l")   emit(format_B(KIND_BRA, V0, V3, V1, label_ref(line[5]))); // Branch with swapped registers
    MATCH("Jl")       emit(format_J(KIND_JMP, 0, label_ref(line[1])));
    MATCH("jl")       emit(format_J(KIND_JMP, 30, label_ref(line[1]))); // jsr is just a jmp to the label with link register $30
    MATCH("j$,l")     emit(format_J(KIND_JMP, V1, label_ref(line[3])));
    MATCH("r")        emit(format_I(KIND_JMPR, 0, 0, 30, 0)); // ret is just a jmpr to the address in $30
    MATCH("J$[#]")    emit(format_I(KIND_JMPR, 0, 0, V1, V3));
    MATCH("j$[#]")    emit(format_I(KIND_JMPR, 0, 30, V1, V3));
    MATCH("j$,$[#]")  emit(format_I(KIND_JMPR, 0, V1, V3, V5));
    MATCH("C$,!")     emit(format_I(KIND_CFG, 0, V1, 0, V3));   // Read from config register
    MATCH("C!,$")     emit(format_I(KIND_CFG, 1, 0, V3, V1));   // Write to config register
    MATCH("C$,!,$")   emit(format_I(KIND_CFG, 1, V1, V5, V3));  // Read/Write to config register
    MATCH("Y#")       emit(format_I(KIND_CFG, 3, 0, 0, V1));    // System call
    MATCH("E")        emit(format_I(KIND_CFG, 2, 0, 0, V0));     // Return from exception (rte)
    MATCH("M$,$,$")   emit(format_R(KIND_MUL, V0, 0, V1, V3, V5)); // mul $d,$a,$b
    MATCH("M$,$")     emit(format_R(KIND_MUL, V0, 0, V1, V1, V3)); // mul $d,$d,$b
    MATCH("M$,$,#")   emit(format_I(KIND_MULI, V0, V1, V3, V5));    // mul $d,$a,#
    MATCH("M$,#")     emit(format_I(KIND_MULI, V0, V1, V1, V3));    // mul $d,$d,$b
    MATCH("n")        emit(format_I(KIND_ALU, 1, 0, 0, 0));     // nop is just an alias for `or $0,$0,$0`
    MATCH("I$,$,$")   emit(format_R(KIND_IDX, V0, 0, V1, V3, V5)); // idx $d,$a,$b
    MATCH("F$,$,$")   emit(format_R(KIND_FPU, V0, 0, V1, V3, V5)); // Floating point operations
    MATCH("F$,$")     emit(format_R(KIND_FPU, V0, 0, V1, V1, V3));
    MATCH("s#")       emit_space(V1);
    else if (line[0]->kind == 'd') emit_constants(line);
    else report_malformed(line);
}

/**
 * Assembles a single file. Reads the file line by line,
 * tokenizes it, and processes the tokens.
 */

 void assemble_file(String filename) {
    if (code_buffer == NULL) {
        code_capacity = 1024;
        code_buffer = new_array(int, code_capacity);
    }

    open_file(filename);
    Token** line;
    while ((line = read_line()) != NULL)
        assemble_line(line);
}


/**
 * Backpatches label references in the code buffer after all lines have 
 * been processed and all labels have been defined.
 */

void backpatch_labels() {
    for(struct LabelRef* ref = label_refs; ref; ref = ref->next) {
        if ((ref->label->flags & FLAG_DEFINED) == 0) {
            line_number = ref->line_number;
            error("Undefined label: %s", ref->label->text);
            ref->label->value = 0; // Default to address 0 for undefined labels
        }

        // Disassemble the instruction at ref->address to determine its format 
        int instruction = code_buffer[ref->address/4];
        int k = instruction >> 26;
        int i = (instruction >> 23) & 0x7;
        int d = (instruction >> 18) & 0x1f;
        int a = (instruction >> 13) & 0x1f;
        int b = instruction & 0x1f;

        int offset = (ref->label->value - ref->address) / 4; // Calculate offset in instructions

        switch(k) {
            case KIND_BRA:
                code_buffer[ref->address/4] = format_B(k, i, a, b, offset);
                break;

            case KIND_JMP:
            case KIND_LDPC:
                code_buffer[ref->address/4] = format_J(k, d, offset);
                break;

            case 0:
                code_buffer[ref->address/4] = ref->label->value; // Absolute address dcw instruction
                break;

            default:
                error("Invalid label reference kind: %d", k);
        }
    }
}





extern Token** hash_table; // Grab the hash table of tokens from lex.c to output labels
extern int hash_size;

/**
 * Output a .labels file containing the addresses of all defined labels. 
 * This is useful for debugging and for use by the disassembler.
 */

static void output_labels(String filename) {
    String label_filename = replace_suffix(filename, ".labels");
    FILE* fh = fopen(label_filename, "w");
    if (!fh)
        return; // If we can't write the label file, just skip it without error
    for(int i=0; i<hash_size; i++) {
        Token* t = hash_table[i];
        if (t && t->kind=='l' && (t->flags & FLAG_DEFINED)) 
            fprintf(fh, "%08x: %s\n", t->value, t->text);
    }
}

/**
 * Outputs the assembled code to a file in the specified format.
 */

void output_code(const char* filename, enum output_format format) {
    if (format == FORMAT_HEX) {
        FILE* fh = fopen(filename, "w");
        if (!fh)
            fatal("Could not open output file: %s", filename);
        for (int i=0; i<code_size; i++) {
            fprintf(fh, "%08x\n", code_buffer[i]);
        }
        fclose(fh);
    } else if (format == FORMAT_BINARY) {
        FILE* fh = fopen(filename, "wb");
        if (!fh)
            fatal("Could not open output file: %s", filename);
        fwrite(code_buffer, sizeof(int), code_size, fh);
        fclose(fh);
    } else {
        fatal("Unknown output format");
    }

    output_labels(filename); // Also output the label file
}