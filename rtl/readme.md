# NeoAmi

This is the top level of the hardware description language (HDL) source code for the NeoAmi project. 

The key directories are:

* top
    The top level of the NeoAmi system, which instantiates all the other modules and connects them together.
* cpu
    The CPU core, a RISC cpu based loosely on RISC-V, but with a custom instruction set and a 32-bit data bus.
* sdram
    SDRAM controller for the NeoAmi system, which handles all memory accesses to the external SDRAM chip.
* iris (Integrated Raster Image System)
    The graphics subsystem, which handles all graphics rendering and display output.
* sophie ((System Organisation and Peripheral Hardware IntEgration)
    The system glue logic, which handles all peripheral access and memory mapping.
* testcases
    Test cases for the NeoAmi system, which can be run in simulation to verify the functionality of the system.
