#define _CRT_SECURE_NO_WARNINGS
#include <stdlib.h>
#include <stdio.h>
#include <stdarg.h>
#include <string.h>
#include "f32.h"

// Utility functions for error handling and memory allocation.

int line_number = 0;
int num_errors = 0;


/**
 * Prints an error message formatted like printf 
 */
void error(const char* fmt, ...) {
    va_list args;
    va_start(args, fmt);
    printf("ERROR line %d: ", line_number);
    vprintf(fmt, args);
    printf("\n");
    num_errors++;
    va_end(args);
}

/**
 * Prints a fatal error message and exits the program.
 */
void fatal(const char* fmt, ...) {
    va_list args;
    va_start(args, fmt);
    if (line_number > 0)
        printf("FATAL line %d: ", line_number);
    else
        printf("FATAL: ");
    vprintf(fmt, args);
    printf("\n");
    va_end(args);
    exit(1);
}

/**
 * Allocates memory and checks for allocation failure. Exits the program if allocation fails.
 */
void* xmalloc(int size) {
    void* ptr = calloc(1,size);
    if (!ptr) {
        fatal("Out of memory");
    }
    return ptr;
}

/**
 * Reallocates memory and checks for allocation failure. Exits the program if allocation fails.
 */
void* xrealloc(void* ptr, size_t size) {
    void* new_ptr = realloc(ptr, size);
    if (!new_ptr) {
        fatal("Out of memory");
    }
    return new_ptr;
}


/**
 * Replaces the suffix of a filename with a new suffix.
 * If the filename has no suffix, the new suffix is appended.
 * The returned string is dynamically allocated and should be freed by the caller.
 */

String replace_suffix(String str, String new_suffix) {
    size_t str_len = strlen(str);

    // Find the last dot in the string
    char* last_dot = strrchr(str, '.');
    size_t base_len = last_dot ? (size_t)(last_dot - str) : str_len;
    size_t new_len = base_len + strlen(new_suffix) + 1; // +1 for null terminator
    char* new_str = xmalloc(new_len);
    strncpy(new_str, str, base_len);
    new_str[base_len] = '\0'; // Null-terminate the base part
    strcat(new_str, new_suffix); // Append the new suffix
    return new_str;
}