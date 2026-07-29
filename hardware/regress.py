#!/usr/bin/python3
import os
import subprocess
import re
import argparse
from collections import defaultdict

# Color escape codes
RED = "\033[1;31m"
GREEN = "\033[1;32m"
RESET = "\033[0m"

# Regex for register writes
scalar_reg_re = re.compile(r"\$\s*(\d+)\s*=\s*([0-9a-fA-F]+)")
vector_reg_re = re.compile(r"&\s*(\d+)\s*=\s*([0-9a-fA-F]+)")

# Regex for simulation time
sim_time_re = re.compile(r"Simulation finished at time\s+([\d.]+)\s*ns")

def parse_writes(filename):
    """Parse a register write log into ({scalar_reg: [values]}, {vector_reg: [values]})"""
    scalar_writes = defaultdict(list)
    vector_writes = defaultdict(list)
    with open(filename) as f:
        for line in f:
            # Check for scalar register write
            m = scalar_reg_re.search(line)
            if m:
                reg = int(m.group(1))
                val = int(m.group(2), 16)
                scalar_writes[reg].append(val)
                continue
            
            # Check for vector register write
            m = vector_reg_re.search(line)
            if m:
                reg = int(m.group(1))
                val = int(m.group(2), 16)
                vector_writes[reg].append(val)
    return scalar_writes, vector_writes

def compare_traces(golden_file, rtl_file, verbose=True):
    """Compare two register write logs."""
    golden_scalar, golden_vector = parse_writes(golden_file)
    rtl_scalar, rtl_vector = parse_writes(rtl_file)

    # Compare scalar registers
    all_scalar_regs = sorted(set(golden_scalar.keys()) | set(rtl_scalar.keys()))
    scalar_mismatches = []

    for r in all_scalar_regs:
        g_seq = golden_scalar.get(r, [])
        r_seq = rtl_scalar.get(r, [])
        if g_seq != r_seq:
            scalar_mismatches.append((r, g_seq, r_seq))
            if verbose:
                print(f"  Scalar Register ${r}:")
                print(f"    Golden: {[f'0x{v:08x}' for v in g_seq]}")
                print(f"    RTL:    {[f'0x{v:08x}' for v in r_seq]}")

    # Compare vector registers
    all_vector_regs = sorted(set(golden_vector.keys()) | set(rtl_vector.keys()))
    vector_mismatches = []

    for r in all_vector_regs:
        g_seq = golden_vector.get(r, [])
        r_seq = rtl_vector.get(r, [])
        if g_seq != r_seq:
            vector_mismatches.append((r, g_seq, r_seq))
            if verbose:
                print(f"  Vector Register &{r}:")
                print(f"    Golden: {[f'0x{v:032x}' for v in g_seq]}")
                print(f"    RTL:    {[f'0x{v:032x}' for v in r_seq]}")

    return scalar_mismatches + vector_mismatches

def has_uart_output():
    """Check if UART logs exist and have non-zero size."""
    try:
        sim_size = os.path.getsize("sim_uart.log") if os.path.exists("sim_uart.log") else 0
        rtl_size = os.path.getsize("rtl_uart.log") if os.path.exists("rtl_uart.log") else 0
        return sim_size > 0 or rtl_size > 0
    except OSError:
        return False

def compare_uart_output(verbose=True):
    """Compare UART output from simulation and RTL."""
    try:
        with open("sim_uart.log", "rb") as f:
            sim_uart = f.read()
    except FileNotFoundError:
        sim_uart = b""
    
    try:
        with open("rtl_uart.log", "rb") as f:
            rtl_uart = f.read()
    except FileNotFoundError:
        rtl_uart = b""
    
    if sim_uart != rtl_uart:
        if verbose:
            print(f"  UART output mismatch:")
            print(f"    Sim UART ({len(sim_uart)} bytes): {sim_uart[:100]}")
            print(f"    RTL UART ({len(rtl_uart)} bytes): {rtl_uart[:100]}")
        return False
    return True

def extract_sim_time(vvp_log_content):
    """Extract simulation time from vvp.log content."""
    match = sim_time_re.search(vvp_log_content)
    if match:
        time_str = match.group(1)
        # Convert to float and then to int for display
        return int(float(time_str))
    return None

def run_simulation(test_file, verbose):
    """Run assembler, RTL simulation, and CPU emulator for a test file.
    
    Returns a tuple (passed, sim_time) where:
    - passed is True if the test passed, False otherwise
    - sim_time is the simulation time in ns (or None if not available)
    """
    base_name = os.path.splitext(os.path.basename(test_file))[0]

    # Run assembler
    result = subprocess.run(["f32asm.exe", test_file])
    if result.returncode != 0:
        print(f"{test_file} {RED}FAIL ASM{RESET}")
        return False, None

    # Run RTL simulation
    vvplog = open("vvp.log","w")
    try:
        subprocess.run(["vvp", "a.out"], check=True, stdout=vvplog, stderr=subprocess.STDOUT)
    except subprocess.CalledProcessError:
        print(f"{test_file} {RED}FAIL RTL{RESET}")
        return False, None
    vvplog.close()
    vvp = open("vvp.log").read()
    
    # Extract simulation time
    sim_time = extract_sim_time(vvp)
    time_str = f" ({sim_time})" if sim_time is not None else ""
    
    if "ERROR" in vvp or "FAIL" in vvp:
        print(f"{test_file} {RED}FAIL RTL ASSERT{RESET}")
        if verbose:
            # Print the error lines from vvp.log
            for line in vvp.splitlines():
                if "ERROR" in line or "FAIL" in line:
                    print(f"  {line}")
        return False, sim_time

    # Run CPU emulation
    simlog = open("sim.log","w")
    try:
        subprocess.run(["f32emu", "-r", "sim_reg.log", "asm.hex"], check=True, stdout=simlog, stderr=subprocess.STDOUT)
    except subprocess.CalledProcessError:
        print(f"{test_file} {RED}FAIL SIM{RESET}")
        return False, sim_time

    # Compare logs - use UART if available, otherwise use register writes
    if has_uart_output():
        if not compare_uart_output(verbose):
            print(f"{test_file} {RED}FAIL UART{RESET}")
            return False, sim_time
        print(f"{test_file} {GREEN}PASS{RESET}{time_str}")
    else:
        mismatches = compare_traces("sim_reg.log", "rtl_reg.log", verbose)
        if mismatches:
            print(f"{test_file} {RED}FAIL{RESET}")
            return False, sim_time
        print(f"{test_file} {GREEN}PASS{RESET}{time_str}")
    
    return True, sim_time

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Run CPU model regression tests.")
    parser.add_argument("test_file", nargs="?", type=str, help="Path to a specific test case file (.f32).")
    parser.add_argument("-all", "--all", action="store_true", help="Run tests from both 'testcases' and 'longer_tests' directories.")
    args = parser.parse_args()

    all_pass = True

    if args.test_file:
        passed, sim_time = run_simulation(args.test_file, verbose=True)
        if not passed:
            all_pass = False
    else:
        # Determine which directories to scan
        test_dirs = ["testcases"]
        if args.all:
            test_dirs.append("longer_tests")
        
        total_sim_time = 0
        test_count = 0
        
        for test_dir in test_dirs:
            if not os.path.exists(test_dir):
                continue
                
            for filename in sorted(os.listdir(test_dir)):
                if filename.endswith(".f32"):
                    test_file = os.path.join(test_dir, filename)
                    passed, sim_time = run_simulation(test_file, verbose=False)
                    if not passed:
                        all_pass = False
                    if sim_time is not None:
                        total_sim_time += sim_time
                    test_count += 1
        
        # Print summary
        print(f"\nTotal simulation time: {total_sim_time} ns")