# Assembler executable
add_executable(f32asm f32asm.c lex.c utils.c assemble.c)
add_executable(f32dis f32dis.c utils.c disassemble.c load_file.c)
add_executable(f32emu f32emu.c utils.c load_file.c disassemble.c execute.c)
add_executable(host_interface host_interface.c)

# Include directories
target_include_directories(f32asm PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})

