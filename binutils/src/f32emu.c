#define _CRT_SECURE_NO_WARNINGS
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include "f32.h"

int   timeout = 1000000; // Default timeout of 1 million cycles
FILE *trace_file = NULL;
FILE *regs_file = NULL;

int main(int argc, const char *argv[]) {
    String trace_filename = NULL;
    String regs_filename = NULL;
    String input_filename = NULL;

    for (int i=1; i<argc; i++) {
        String arg = argv[i];
        if (!strcmp(arg, "-h") || !strcmp(arg, "--help")) {
            printf("Usage: f32emu [options] filename\n");
            printf("Options:\n");
            printf("  -t <file>, --trace <file>   Output execution trace to file\n");
            printf("  -r <file>, --regs <file>    Output final register state to file\n");
            printf("  --timeout <n>               Set maximum number of cycles (default: 1000000)\n");
            printf("  -h, --help                  Show this help message\n");
            return 0;
        
        } else if (!strcmp(arg, "-t") || !strcmp(arg, "--trace")) {
            if (i+1 < argc)
                trace_filename = argv[++i];
            else
                fatal("Expected filename after -t/--trace");

        } else if (!strcmp(arg, "-r") || !strcmp(arg, "--regs")) {
            if (i+1 < argc)
                regs_filename = argv[++i];
            else
                fatal("Expected filename after -r/--regs");

        } else if (!strcmp(arg, "--timeout")) {
            if (i+1 < argc)
                timeout = atoi(argv[++i]);
            else
                fatal("Expected number after --timeout");

        } else if (arg[0] == '-') {
            fatal("Unknown option: %s", arg);
        } else {
            if (input_filename)
                fatal("Multiple input files specified: %s", arg);
            input_filename = arg;
        }
    }

    if (input_filename == NULL) {
        printf("No input file specified.\n");
        return 0;
    }

    if (trace_filename) {
        trace_file = fopen(trace_filename, "w");
        if (!trace_file)
            fatal("Could not open trace file: %s", trace_filename);
    }

    if (regs_filename) {
        regs_file = fopen(regs_filename, "w");
        if (!regs_file)
            fatal("Could not open regs file: %s", regs_filename);
    }


    load_file(input_filename, 0xFFFF0000);
    execute_code();
    return 0;
}
