#include <stdio.h>
#include <string.h>
#include "f32.h"

int main(int argc, char *argv[]) {
    if (argc < 2) {
        printf("Usage: f32dis filename\n");
        return 0;
    }

    load_file(argv[1],0);
    disassemble_code();
    return 0;
}
