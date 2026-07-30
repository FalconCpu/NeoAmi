
call fplcomp files.fplprj || exit /b
C:\intelFPGA_lite\24.1std\quartus\bin64\quartus_pgm.exe --quiet -c 1 ..\..\fpga\NeoAmi.cdf  || exit /b
host_interface