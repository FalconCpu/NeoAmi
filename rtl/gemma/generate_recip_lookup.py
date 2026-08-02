#!/usr/bin/env python3
"""
Generate reciprocal lookup table for gemma_fast_recip.sv

This script generates a 1024-entry lookup table for fast reciprocal approximation.
The input is normalized to [1.0, 2.0) and represented by a 10-bit index.
The output is a 10-bit approximation of the reciprocal.

Input format: 10-bit index representing normalized mantissa (1.0 to ~2.0)
Output format: 10-bit reciprocal value
"""

def generate_recip_lookup():
    """Generate reciprocal lookup table with 1024 entries."""
    
    lookup_table = []
    
    for i in range(1024):
        # The index represents a normalized value in the range [1.0, 2.0)
        # Index i represents: 1.0 + i/1024
        # This gives us values from 1.0 (i=0) to 1.9990234375 (i=1023)
        input_value = 1.0 + (i / 1024.0)
        
        # Calculate the reciprocal
        reciprocal = 1.0 / input_value
        
        # The reciprocal will be in the range (0.5, 1.0]
        # We need to represent this as a 11-bit value
        # Scale by 2048 to convert to integer representation
        # Then subtract 1024 to remove the leading 1 bit (since we only need the fractional part)
        if i==0:
            recip_int = 0 # Special case for input_value = 1.0, reciprocal = 1.0
        else:
            recip_int = int(round(reciprocal * 4096.0)) & 0x3FF  # Keep only the lower 10 bits
                
        lookup_table.append(recip_int)
    
    return lookup_table


def write_hex_file(lookup_table, filename='recip_lookup.hex'):
    """Write lookup table to hex file for $readmemh."""
    
    with open(filename, 'w') as f:
        for i, value in enumerate(lookup_table):
            # Write as 3-digit hex (10 bits requires 3 hex digits)
            f.write(f"{value:03x}\n")
    
    print(f"Generated {filename} with {len(lookup_table)} entries")


def print_statistics(lookup_table):
    """Print statistics about the lookup table."""
    
    print("\n=== Lookup Table Statistics ===")
    print(f"Number of entries: {len(lookup_table)}")
    print(f"Min value: {min(lookup_table)} (0x{min(lookup_table):03x})")
    print(f"Max value: {max(lookup_table)} (0x{max(lookup_table):03x})")
    
    # Calculate some sample values
    print("\n=== Sample Values ===")
    sample_indices = [0, 255, 511, 767, 1023]
    print(f"{'Index':<6} {'Input':>10} {'1/Input':>10} {'LUT Value':>10} {'LUT as float':>12} {'Error':>10}")
    print("-" * 70)
    
    for i in sample_indices:
        input_val = 1.0 + (i / 1024.0)
        true_recip = 1.0 / input_val
        lut_val = 1024 + lookup_table[i]
        if i==0: lut_val = 2048
        lut_as_float = lut_val / 2048.0
        error = abs(lut_as_float - true_recip)
        rel_error = (error / true_recip) * 100
        
        print(f"{i:<6} {input_val:>10.6f} {true_recip:>10.6f} {lut_val:>10} "
              f"{lut_as_float:>12.9f} {rel_error:>9.4f}%")
    
    # Calculate average and max error
    errors = []
    for i in range(1024):
        input_val = 1.0 + (i / 1024.0)
        true_recip = 1.0 / input_val
        lut_as_float = (1024+lookup_table[i]) / 2048
        if i==0: lut_as_float = 1.0
        rel_error = abs((lut_as_float - true_recip) / true_recip) * 100
        errors.append(rel_error)
    
    print(f"\n=== Error Analysis ===")
    print(f"Average relative error: {sum(errors)/len(errors):.4f}%")
    print(f"Maximum relative error: {max(errors):.4f}%")
    print(f"Approximate precision: ~{10 - (max(errors)/100 * 10):.1f} bits")


def main():
    print("Generating reciprocal lookup table...")
    
    # Generate the lookup table
    lookup_table = generate_recip_lookup()
    
    # Write to hex file
    write_hex_file(lookup_table, 'recip_lookup.hex')
    
    # Print statistics
    print_statistics(lookup_table)
    
    print("\n✓ Lookup table generation complete!")
    print("  File: recip_lookup.hex")
    print("  Use with: $readmemh(\"recip_lookup.hex\", recip_lookup);")


if __name__ == "__main__":
    main()
