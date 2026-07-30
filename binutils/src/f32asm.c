#include <stdio.h>
#include <string.h>
#include "f32.h"

extern int num_errors;

int main(int argc, char *argv[]) {
    char* output_filename = "asm.hex";
    enum output_format format = FORMAT_HEX;
    int num_input_files = 0;

    for(int i=1; i<argc; i++) {
        String arg = argv[i];
        if (!strcmp(arg, "-o")) {
            if (i+1 < argc)
                output_filename = argv[++i];
            else
                fatal("Expected filename after -o");

        } else if (!strcmp(arg, "-b") || !strcmp(arg, "--binary") ) {
            format = FORMAT_BINARY;

        } else if (!strcmp(arg, "-hex") || !strcmp(arg, "--hex") ) {
            format = FORMAT_HEX;

        } else if (!strcmp(arg, "-h") || !strcmp(arg, "--help")) {
            printf("Usage: f32asm [options] <input_files>\n");
            printf("Options:\n");
            printf("  -o <file>       Output filename (default: asm.hex)\n");
            printf("  --hex           Output in hexadecimal format (default)\n");
            printf("  -b, --binary    Output in binary format\n");
            printf("  -h, --help      Show this help message\n");
            return 0;

        } else if (arg[0] == '-') {
            fatal("Unknown option: %s", arg);
        } else {
            assemble_file(argv[i]);
            num_input_files++;
        }
    }

    if (num_input_files == 0) {
        assemble_file("example.f32"); // For debugger - add a default input file if none specified
        // fatal("No input files specified");
    }

    backpatch_labels();

    if (num_errors ==0 )
        output_code(output_filename, format);
    else
        printf("Assembly failed with %d error(s)\n", num_errors);
    return num_errors > 0 ? 1 : 0;
}
