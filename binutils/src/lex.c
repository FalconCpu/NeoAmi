#define _CRT_SECURE_NO_WARNINGS
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <ctype.h>
#include "f32.h"

extern int line_number;
static String current_scope = "";

/** 
 * Predefined tokens for keywords and operators
 */

static Token predefined_tokens[] = {
    {'$', "$0",   0, 0},
    {'$', "$1",   1, 0},
    {'$', "$2",   2, 0},
    {'$', "$3",   3, 0},
    {'$', "$4",   4, 0},
    {'$', "$5",   5, 0},
    {'$', "$6",   6, 0},
    {'$', "$7",   7, 0},
    {'$', "$8",   8, 0},
    {'$', "$9",   9, 0},
    {'$', "$10", 10, 0},
    {'$', "$11", 11, 0},
    {'$', "$12", 12, 0},
    {'$', "$13", 13, 0},
    {'$', "$14", 14, 0},
    {'$', "$15", 15, 0},
    {'$', "$16", 16, 0},
    {'$', "$17", 17, 0},
    {'$', "$18", 18, 0},
    {'$', "$19", 19, 0},
    {'$', "$20", 20, 0},
    {'$', "$21", 21, 0},
    {'$', "$22", 22, 0},
    {'$', "$23", 23, 0},
    {'$', "$24", 24, 0},
    {'$', "$25", 25, 0},
    {'$', "$26", 26, 0},
    {'$', "$27", 27, 0},
    {'$', "$28", 28, 0},
    {'$', "$29", 29, 0},
    {'$', "$30", 30, 0},
    {'$', "$31", 31, 0},
    {'$', "$sp", 31, 0},

    {'!', "!version",   0x0, 0},
    {'!', "!status",    0x1, 0},
    {'!', "!epc",       0x2, 0},
    {'!', "!ecause",    0x3, 0},
    {'!', "!edata",     0x4, 0},
    {'!', "!estatus",   0x5, 0},
    {'!', "!escratch",  0x6, 0},
    {'!', "!timer",     0x7, 0},
    {'!', "!mpu_clear", 0x8, 0},
    {'!', "!mpu_data",  0x9, 0},

    {'A', "and",  0, 0},
    {'A', "or",   1, 0},
    {'A', "xor",  2, 0},
    {'A', "add",  4, 0},
    {'A', "sub",  5, 0},
    {'A', "clt",  6, 0},
    {'A', "cltu", 7, 0},
    {'D', "ld",   0, 0},   // ld is an alias for add with $0 as the first operand
    {'n', "nop",  0, 0},    // nop is an alias for add with $0 as both operands

    {'H', "lsl",  0, 0},
    {'H', "lsr",  2, 0},
    {'H', "asr",  3, 0},

    {'B', "beq",  0, 0},
    {'B', "bne",  1, 0},
    {'B', "blt",  2, 0},
    {'B', "bge",  3, 0},
    {'B', "bltu", 4, 0},
    {'B', "bgeu", 5, 0},
    {'b', "bgt",  2, 0},  // bgt and ble are just aliases for blt and bge with operands swapped
    {'b', "ble",  3, 0},
    {'b', "bgtu", 4, 0},
    {'b', "bleu", 5, 0},
    {'J', "jmp",  0, 0},
    {'j', "jsr",  0, 0},    // jsr is just an alias for jmp with link $30
    {'r', "ret",  0, 0},    // ret is just an alias for jmp with target $30

    {'M', "mul",    0, 0},
    {'M', "mulhu",  1, 0},
    {'M', "mulhs",  2, 0},
    {'M', "mulhsu", 3, 0},
    {'M', "divu",    4, 0},
    {'M', "divs",   5, 0},
    {'M', "modu",    6, 0},
    {'M', "mods",   7, 0},

    {'S', "stb", 0, 0},
    {'S', "sth", 1, 0},
    {'S', "stw", 2, 0},
    {'L', "ldb", 0, 0},
    {'L', "ldh", 1, 0},
    {'L', "ldw", 2, 0},
    {'I', "idx1", 0, 0},
    {'I', "idx2", 1, 0},
    {'I', "idx4", 2, 0},

    {'C', "cfg", 0, 0},
    {'Y', "sys", 0, 0},
    {'E', "rte", 0, 0},

    {'s', "ds", 0, 0},      // ds is a pseudo-op for defining a space of uninitialized data
    {'d', "dcb", 0, 0},     // dcb is a pseudo-op for defining a byte array initialized with the data
    {'d', "dch", 1, 0},     // dch is a pseudo-op for defining a half-word array initialized with data
    {'d', "dcw", 2, 0},     // dcw is a pseudo-op for defining a word array initialized with the data

    {'[', "[", 0, 0},
    {']', "]", 0, 0},
    {',', ",", 0, 0},
    {':', ":", 0, 0},
    {'=', "=", 0, 0},
    
    {0,0,0,0}
};


/**
 * Hash table for all tokens seen in the source code. 
 */
int     hash_size = 1024;
int     hash_count = 0;
Token** hash_table = NULL;

static int hash_function(String str) {
    unsigned long hash = 5381;
    int c;
    while ((c = *str++))
        hash = ((hash << 5) + hash) + c; /* hash * 33 + c */
    return hash & (hash_size-1);
}

static void hash_add(Token* token) {
    if (hash_count*4 >= hash_size*3) {
        // Hash table is more than 75% full - resize it
        Token** old_table = hash_table;
        int old_size = hash_size;
        hash_size *= 2;
        hash_table = new_array(Token*, hash_size);
        hash_count = 0;
        for (int i = 0; i < old_size; i++)
            if(old_table[i])
                hash_add(old_table[i]);
        free(old_table);
    }

    int index = hash_function(token->text);
    while(hash_table[index])
        index = (index + 1) & (hash_size-1);
    
    hash_table[index] = token;
    hash_count++;
}

static Token* hash_find(String text) {
    int index = hash_function(text);
    while(hash_table[index]) {
        if (strcmp(hash_table[index]->text, text) == 0)
            return hash_table[index];
        index = (index + 1) & (hash_size-1);
    }
    return NULL;
}

static Token* new_token(int kind, int value, String text) {
    Token* token = new(Token);
    token->kind = kind;
    token->flags = 0;
    token->value = value;
    token->text = _strdup(text);
    hash_add(token);
    return token;
}

static void init_hash_table() {
    hash_size = 1024;
    hash_count = 0;
    hash_table = new_array(Token*, hash_size);
    for (int i = 0; predefined_tokens[i].kind != 0; i++)
        hash_add(&predefined_tokens[i]);
}

/**
 * String builder for constructing token text while lexing.
 */

static char* str = NULL;
static int str_len = 0;
static int str_capacity = 0;

static void str_append(char c) {
    if (str_len + 1 >= str_capacity) {
        str_capacity *= 2;
        resize_array(str, char, str_capacity);
    }
    str[str_len++] = c;
    str[str_len] = '\0';
}

static void str_clear() {
    str_len = 0;
    if (str)
        str[0] = '\0';
}

/**
 * File reading
 */

static FILE* fh = NULL;
static int current_char = 0;

static int next_char() {
    int ret = current_char;
    current_char = fgetc(fh);
    return ret;
}

static String read_word() {
    // Read a word consisting of alphanumeric characters, underscores, and dots
    // If the first character is a slash also allow / ( ) , in the name
    // to allow for compiler labels such as  /foo/bar(int,int)

    str_clear();
    str_append(next_char());

    int is_slash_name = (str[0] == '/'); // Check if the first character is a slash

    while (isalnum(current_char) || current_char == '.' || current_char == '_' || current_char == '@' ||
       (is_slash_name && (current_char == '/' || current_char == '(' || current_char == ')' || current_char == ','))) 
        str_append(next_char());
    return str;
}

static String read_local_label() {
    // Local labels need to be qualified with the current global label to ensure uniqueness. 
    str_clear();
    for(const char *p = current_scope; *p; p++)
        str_append(*p);

    str_append(next_char()); // Get the '.' at the beginning of the local label

    while (isalnum(current_char) || current_char == '_' || current_char == '@')
        str_append(next_char());
    return str;
}


static String read_punctuation() {
    str_clear();
    str_append(next_char());
    return str;
}

static String read_char_literal() {
    str_clear();
    str_append(next_char()); // Consume the opening quote
    
    int ch = next_char();
    if (ch == '\\') { 
        // Escape sequence
        str_append(ch);
        str_append(next_char()); // Append the character after the backslash for error reporting
    } else if (ch == EOF || ch == '\n') {
        error("Unterminated character literal");
    } else {
        str_append(ch);
    }
    
    // Consume closing quote
    if (current_char == '\'') {
        str_append(next_char());
    } else {
        error("Expected closing quote in character literal");
    }
    return str;
}

static int evaluate_char_literal(String str) {
    if (str[1] == '\\') {
        // Escape sequence
        switch(str[2]) {
            case 'n':  return '\n';
            case 't':  return '\t';
            case 'r':  return '\r';
            case '\\': return '\\';
            case '\'': return '\'';
            case '0':  return '\0';
            default:
                error("Unknown escape sequence: \\%c", str[1]);
                return str[1];
        }
    } else {
        return str[1];
    }
}

static char read_char_with_escape() {
    int ch = next_char();
    if (ch == '\\') {
        int esc = next_char();
        switch(esc) {
            case 'n': return '\n';
            case 't': return '\t';
            case 'r': return '\r';
            case '\\': return '\\';
            case '\'': return '\'';
            case '"': return '"';
            case '0': return '\0';
            default:
                error("Unknown escape sequence: \\%c", esc);
                return esc;
        }
    } else {
        return ch;
    }
}

static int is_global_label(Token *token) {
    // A label is considered global if it does not contain a dot
    if (token->kind != 'l')
        return 0;
    for (const char* p = token->text; *p; p++) {
        if (*p == '.')
            return 0;
    }
    return 1;
}

static String read_string_literal() {
    str_clear();
    next_char(); // Consume the opening quote
    
    while (current_char != EOF && current_char != '"') {
        int ch = read_char_with_escape();
        str_append(ch);
    }
    
    // Consume closing quote
    if (current_char == '"') {
        next_char();
    } else {
        error("Unterminated string literal");
    }
    return str;
}


void open_file(const char* filename) {
    if (hash_table==0)
        init_hash_table();
    if (str == NULL) {
        str_capacity = 64;
        str = new_array(char, str_capacity);
    }

    fh = fopen(filename, "r");
    if (!fh)
        fatal("Could not open file: %s", filename);
    line_number = 1;
    current_char = fgetc(fh);
}


/**
 * Skips whitespace and comments in the input file. 
 * Comments start with # or ; and continue until the end of the line.
 */
static void skip_whitespace_and_comments() {
    while (current_char != EOF) {
        if (current_char == '#' || current_char == ';') {
            // Skip comment until end of line
            while (current_char != EOF && current_char != '\n')
                next_char();
        } else if (current_char == ' ' || current_char == '\t' || current_char == '\r') {
            next_char();
        } else {
            break;
        }
    }
}

/**
 * Converts a string to an integer. Handles decimal and hexadecimal (0x)
 */

 static int my_atoi(String str) {
    int minus = 0;
    if (*str == '-') {
        minus = 1;
        str++;
    }
    int value = 0;
    if (str[0] == '0' && str[1] == 'x') {
        // Hexadecimal
        for (int i = 2; str[i]; i++) {
            if (str[i] >= '0' && str[i] <= '9')
                value = value * 16 + (str[i] - '0');
            else if (str[i] >= 'a' && str[i] <= 'f')
                value = value * 16 + (str[i] - 'a' + 10);
            else if (str[i] >= 'A' && str[i] <= 'F')
                value = value * 16 + (str[i] - 'A' + 10);
            else {
                error("Invalid hexadecimal number: %s", str);
                break;
            }
        }
    } else {
        // Decimal
        value = atoi(str);
    }
    return minus ? -value : value;
}

/**
 * Lexing function
 */

Token* next_token() {
    skip_whitespace_and_comments();

    if (current_char == EOF)
        return NULL;

    if (current_char == '\n') {
        next_char();
        return 0;
    }

    Token* ret = 0;

    if (current_char == '$' || current_char == '!') {
        // Register token
        String word = read_word();
        ret = hash_find(word);
        if (!ret) {
            error("Unknown register: %s", word);
            ret = hash_find("$1"); // Default to $1 for unknown registers
        }

    } else if (isalpha(current_char) || current_char == '_' || current_char=='/' || current_char=='@') {
        // Identifier or keyword
        String word = read_word();
        ret = hash_find(word);
        if (!ret)
            ret = new_token('l', 0, word); // New label

    } else if (current_char == '.') {
        // Local label
        String word = read_local_label();
        ret = hash_find(word);
        if (!ret)
            ret = new_token('l', 0, word); // New label
    
    } else if (isdigit(current_char) || current_char == '-') {
        // Number literal
        String word = read_word();
        ret = hash_find(word);
        if (!ret)
            ret = new_token('#', my_atoi(word), word); // New number literal

    } else if (current_char == '\'') {
        // Character literal
        String word = read_char_literal();
        ret = hash_find(word);
        if (!ret)
            ret = new_token('#', evaluate_char_literal(word), word); // New character literal

    } else if (current_char == '"') {
        // String literal
        String word = read_string_literal();
        ret = hash_find(word);
        if (!ret)
            ret = new_token('"', 0, word); // New string literal

    } else {
        // Punctuation
        String punct = read_punctuation();
        ret = hash_find(punct);
        if (!ret) {
            error("Unknown token: %s", punct);
            ret = hash_find(","); // Default to comma for unknown punctuation
        }
    }
    return ret;
}


/**
 * Reads a line of tokens until a newline or EOF is reached. 
 * Returns an array of tokens, terminated by a NULL pointer.
 */

#define MAX_TOKENS_PER_LINE 64

Token** read_line() {
    static Token* tokens[MAX_TOKENS_PER_LINE];
    if (current_char == EOF)
        return NULL;

    line_number++;
    int count = 0;
    while (count < MAX_TOKENS_PER_LINE-1) {
        Token* token = next_token();
        if (!token)
            break;
        tokens[count++] = token;
    }
    tokens[count] = NULL;
 
    if (count==2 && is_global_label(tokens[0]) && tokens[1]->kind == ':') {
        // This is a global label definition. This defines a new scope for local labels
        current_scope = tokens[0]->text;
    }
 
    return tokens;
}