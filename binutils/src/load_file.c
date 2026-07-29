#define _CRT_SECURE_NO_WARNINGS
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include "f32.h"

int* code_buffer = NULL;
int code_size = 0;
int code_capacity = 0;

struct Label *labels = NULL;

#define ROM_SIZE 0x10000 // 64KB ROM size limit

/**
 * Adds a label to the labels list. 
 */

static void add_label(const char* name, int address) {
    struct Label* label = malloc(sizeof(struct Label));
    label->name = _strdup(name);
    label->value = address;
    label->next = labels;
    labels = label;
}


/**
 * Load label definitions from a .labels file if it exists.
 * The .labels file has the format: address: label_name
 */

void load_labels(const char* filename, int base_address) {
    String label_filename = replace_suffix(filename, ".labels");
    FILE* fh = fopen(label_filename, "r");
    if (!fh)
        return; // Labels file is optional, silently skip if not present
    
    char line[256];
    while (fgets(line, sizeof(line), fh)) {
        // Parse line format: "00000000: label_name"
        unsigned int address;
        char name[256];
        if (sscanf(line, "%x: %s", &address, name) == 2) {
            add_label(name, address + base_address);
        }
    }
    fclose(fh);
}

/**
 * Checks if a string ends with a given suffix. Returns 1 if it does, 0 otherwise.
 */
int string_ends_with(String str, String suffix) {
    size_t str_len = strlen(str);
    size_t suffix_len = strlen(suffix);
    if (suffix_len > str_len)
        return 0;
    return strcmp(str + str_len - suffix_len, suffix) == 0;
}

/**
 * Loads a file in binary format.
 */

static void load_file_binary(const char* filename) {
    FILE* fh = fopen(filename, "rb");
    if (!fh) {
        error("Failed to open file: %s", filename);
        return;
    }
    fseek(fh, 0, SEEK_END);
    long file_size = ftell(fh);
    fseek(fh, 0, SEEK_SET);

    if (file_size % 4 != 0) {
        error("File size must be a multiple of 4 bytes: %s", filename);
        fclose(fh);
        return;
    }

    int num_instructions = file_size / 4;
    code_buffer = new_array(int, ROM_SIZE/4);
    if (num_instructions > ROM_SIZE/4) {
        error("File too large to fit in ROM: %s", filename);
        num_instructions = ROM_SIZE/4; // Truncate to fit
    }
    fread(code_buffer, 4, num_instructions, fh);
    code_size = num_instructions;
    fclose(fh);
}

/**
 * Loads a file in hexadecimal format (one instruction per line).
 */

static void load_file_hex(const char* filename) {
    FILE* fh = fopen(filename, "r");
    if (!fh) {
        error("Failed to open file: %s", filename);
        return;
    }
    code_capacity = ROM_SIZE/4;
    code_buffer = new_array(int, code_capacity);
    code_size = 0;
    char line[256];
    while (fgets(line, sizeof(line), fh)) {
        if (code_size >= code_capacity) {
            error("File too large to fit in ROM: %s", filename);
            break; 
        }
        code_buffer[code_size++] = (int)strtoul(line, NULL, 16);
    }   
    fclose(fh);
}

/** 
 * Load the contents of a file into a buffer. 
 */

 void load_file(const char* filename, int base_address) {
    if (string_ends_with(filename, ".hex"))
        load_file_hex(filename);
    else if (string_ends_with(filename, ".bin"))
        load_file_binary(filename);
    else 
        fatal("Unknown file format: %s", filename);
    
    load_labels(filename, base_address);
}

