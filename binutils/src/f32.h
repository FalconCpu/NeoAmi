typedef const char* String;

typedef struct Token {
    int   kind;
    String text;
    int   value;
    int   flags;
 } Token;

#define FLAG_DEFINED 1


// Instruction format encodings
#define KIND_ALU   0x10
#define KIND_ALUI  0x11
#define KIND_LD    0x12
#define KIND_ST    0x13
#define KIND_BRA   0x14
#define KIND_JMP   0x15
#define KIND_JMPR  0x16
#define KIND_LDU   0x17
#define KIND_LDPC  0x18
#define KIND_MUL   0x19
#define KIND_MULI  0x1A
#define KIND_CFG   0x1B
#define KIND_IDX   0x1C
#define KIND_FPU   0x1D

// Output formats
enum output_format {
    FORMAT_HEX,
    FORMAT_BINARY
};

// Label struct for storing label definitions and their addresses.
struct Label {
    String name;
    int value;
    struct Label* next; 
};


// lex.c
void open_file(const char* filename);
Token** read_line();

// assemble.c
void assemble_file(String filename);
void backpatch_labels(void);
void output_code(const char* filename, enum output_format format);

// load_file.c
void load_file(const char* filename, int base_address);

// disassemble.c
String find_label(int address);
String disassemble_line(int instr, int pc);
void disassemble_code(void);

// emulator.c
void execute_code(void);

// Utils.c
void error(const char* fmt, ...);
void fatal(const char* fmt, ...) __attribute__((noreturn));
void* xmalloc(int size);
void* xrealloc(void* ptr, size_t size);
String replace_suffix(const char* filename, const char* new_suffix);
#define new(T) ((T*)xmalloc(sizeof(T)))
#define new_array(T, n) ((T*)xmalloc(sizeof(T) * (n)))
#define resize_array(ptr, T, n) ptr=((T*)xrealloc(ptr, sizeof(T) * (n)))
#define assert(expr) if (!(expr)) fatal("Assertion failed: %s", #expr)