#!/usr/bin/env python3
"""
IRIS Scene Generator
Converts human-readable triangle descriptions into IRIS binary object format.
"""

import struct
import math
from typing import List, Tuple, Optional
from dataclasses import dataclass


@dataclass
class Vertex:
    """Represents a 3D vertex with color."""
    x: float
    y: float
    z: float
    r: float  # 0-255
    g: float  # 0-255
    b: float  # 0-255


@dataclass
class Triangle:
    """Represents a Gouraud-shaded triangle."""
    v1: Vertex
    v2: Vertex
    v3: Vertex
    clip_x1: int = 0
    clip_x2: int = 1024
    

def s12_4_to_int(value: float) -> int:
    """Convert a float to S12.4 fixed point (16-bit signed, 4 fractional bits)."""
    # Clamp to valid range: -2048.0 to +2047.9375
    value = max(-2048.0, min(2047.9375, value))
    return int(value * 16) & 0xFFFF


def u12_4_to_int(value: float) -> int:
    """Convert a float to U12.4 fixed point (16-bit unsigned, 4 fractional bits)."""
    # Clamp to valid range: 0 to 4095.9375
    value = max(0.0, min(4095.9375, value))
    return int(value * 16) & 0xFFFF


def float_to_fp16(value: float) -> int:
    """
    Convert a float to custom FP16 format.
    Bits [15:14] = exponent, bits [13:0] = mantissa (2's complement)
    
    exponent = 0: value = mantissa * 2^-12  (range -2 to +2, resolution 1/4096)
    exponent = 1: value = mantissa * 2^-9   (range -16 to +16, resolution 1/512)
    exponent = 2: value = mantissa * 2^-6   (range -128 to +128, resolution 1/64)
    exponent = 3: value = mantissa * 2^-3   (range -1024 to +1024, resolution 1/8)
    """
    if value == 0:
        return 0
    
    # Determine which exponent range to use
    abs_val = abs(value)
    
    if abs_val < 2.0:
        exp = 0
        shift = 12
    elif abs_val < 16.0:
        exp = 1
        shift = 9
    elif abs_val < 128.0:
        exp = 2
        shift = 6
    else:
        exp = 3
        shift = 3
    
    # Calculate mantissa
    mantissa = int(value * (1 << shift))
    
    # Clamp mantissa to 14-bit signed range
    mantissa = max(-8192, min(8191, mantissa))
    
    # Pack into 16-bit value
    mantissa_bits = mantissa & 0x3FFF
    return (exp << 14) | mantissa_bits


def sort_vertices(tri: Triangle) -> Tuple[Vertex, Vertex, Vertex]:
    """
    Sort triangle vertices by Y coordinate (top, middle, bottom).
    Returns (top, middle, bottom) vertices.
    """
    vertices = [tri.v1, tri.v2, tri.v3]
    vertices.sort(key=lambda v: v.y)
    return vertices[0], vertices[1], vertices[2]


def calculate_slope(x1: float, y1: float, x2: float, y2: float) -> float:
    """Calculate DX/DY slope between two points."""
    dy = y2 - y1
    if abs(dy) < 0.001:  # Avoid division by zero
        return 0.0
    return (x2 - x1) / dy


def encode_triangle(tri: Triangle, next_addr: int = 0) -> bytes:
    """
    Encode a triangle into IRIS binary object format (64 bytes).
    """
    # Sort vertices by Y coordinate
    v_top, v_mid, v_bot = sort_vertices(tri)
    
    # Determine YTOP and YBOT (integer scanlines)
    ytop = int(math.floor(v_top.y))
    ybot = int(math.ceil(v_bot.y))
    
    # Calculate X slopes
    # We need to determine which edge is left and which is right
    # Check if middle vertex is on the right side
    dx_top_to_bot = calculate_slope(v_top.x, v_top.y, v_bot.x, v_bot.y)
    x_at_mid_y = v_top.x + dx_top_to_bot * (v_mid.y - v_top.y)
    
    right_edge = v_mid.x > x_at_mid_y
    
    if right_edge:
        # Middle vertex is on the right
        dx1_dy = calculate_slope(v_top.x, v_top.y, v_bot.x, v_bot.y)  # Left edge
        dx2_dy = calculate_slope(v_top.x, v_top.y, v_mid.x, v_mid.y)  # Right edge (top half)
        dx3_dy = calculate_slope(v_mid.x, v_mid.y, v_bot.x, v_bot.y)  # Right edge (bottom half)
    else:
        # Middle vertex is on the left
        dx1_dy = calculate_slope(v_top.x, v_top.y, v_mid.x, v_mid.y)  # Left edge (top half)
        dx2_dy = calculate_slope(v_top.x, v_top.y, v_bot.x, v_bot.y)  # Right edge
        dx3_dy = calculate_slope(v_mid.x, v_mid.y, v_bot.x, v_bot.y)  # Left edge (bottom half)
    
    # Calculate Z slopes (depth)
    # Find DZ/DX and DZ/DY using plane equation
    # For a plane: Z = Z0 + DZ/DX * (X - X0) + DZ/DY * (Y - Y0)
    # We have three points, so we can solve for the slopes
    
    # Vector from v_top to v_mid
    dx1 = v_mid.x - v_top.x
    dy1 = v_mid.y - v_top.y
    dz1 = v_mid.z - v_top.z
    
    # Vector from v_top to v_bot
    dx2 = v_bot.x - v_top.x
    dy2 = v_bot.y - v_top.y
    dz2 = v_bot.z - v_top.z
    
    # Solve for DZ/DX and DZ/DY
    denom = dx1 * dy2 - dx2 * dy1
    if abs(denom) > 0.001:
        dz_dx = (dz1 * dy2 - dz2 * dy1) / denom
        dz_dy = (dx1 * dz2 - dx2 * dz1) / denom
    else:
        dz_dx = 0.0
        dz_dy = 0.0
    
    # Calculate color slopes (same method as Z)
    # For R channel
    dr1 = v_mid.r - v_top.r
    dr2 = v_bot.r - v_top.r
    if abs(denom) > 0.001:
        dr_dx = (dr1 * dy2 - dr2 * dy1) / denom
        dr_dy = (dx1 * dr2 - dx2 * dr1) / denom
    else:
        dr_dx = 0.0
        dr_dy = 0.0
    
    # For G channel
    dg1 = v_mid.g - v_top.g
    dg2 = v_bot.g - v_top.g
    if abs(denom) > 0.001:
        dg_dx = (dg1 * dy2 - dg2 * dy1) / denom
        dg_dy = (dx1 * dg2 - dx2 * dg1) / denom
    else:
        dg_dx = 0.0
        dg_dy = 0.0
    
    # For B channel
    db1 = v_mid.b - v_top.b
    db2 = v_bot.b - v_top.b
    if abs(denom) > 0.001:
        db_dx = (db1 * dy2 - db2 * dy1) / denom
        db_dy = (dx1 * db2 - dx2 * db1) / denom
    else:
        db_dx = 0.0
        db_dy = 0.0
    
    # Build the 64-byte object
    obj = bytearray(64)
    
    # FLAGS (offset 0x00): U16 - Mode = 10 (Gouraud shaded triangle), RIGHT_EDGE flag
    flags = 0x0002  # Mode = 10 (Gouraud shaded)
    if right_edge:
        flags |= 0x0010  # Set RIGHT_EDGE flag
    struct.pack_into('<H', obj, 0x00, flags)
    
    # CLIP_X1 (offset 0x02): U16
    struct.pack_into('<H', obj, 0x02, tri.clip_x1)
    
    # CLIP_X2 (offset 0x04): U16
    struct.pack_into('<H', obj, 0x04, tri.clip_x2)
    
    # YTOP (offset 0x06): U16
    struct.pack_into('<H', obj, 0x06, ytop & 0xFFFF)
    
    # YBOT (offset 0x08): U16
    struct.pack_into('<H', obj, 0x08, ybot & 0xFFFF)
    
    # X1, Y1 (offset 0x0A, 0x0C): S12.4
    struct.pack_into('<H', obj, 0x0A, s12_4_to_int(v_top.x))
    struct.pack_into('<H', obj, 0x0C, s12_4_to_int(v_top.y))
    
    # X2, Y2 (offset 0x0E, 0x10): S12.4
    struct.pack_into('<H', obj, 0x0E, s12_4_to_int(v_mid.x))
    struct.pack_into('<H', obj, 0x10, s12_4_to_int(v_mid.y))
    
    # DX1/DY, DX2/DY, DX3/DY (offset 0x12, 0x14, 0x16): FP16
    struct.pack_into('<H', obj, 0x12, float_to_fp16(dx1_dy))
    struct.pack_into('<H', obj, 0x14, float_to_fp16(dx2_dy))
    struct.pack_into('<H', obj, 0x16, float_to_fp16(dx3_dy))
    
    # Z1 (offset 0x18): S12.4
    struct.pack_into('<H', obj, 0x18, s12_4_to_int(v_top.z))
    
    # DZ/DX, DZ/DY (offset 0x1A, 0x1C): FP16
    struct.pack_into('<H', obj, 0x1A, float_to_fp16(dz_dx))
    struct.pack_into('<H', obj, 0x1C, float_to_fp16(dz_dy))
    
    # Reserved (offset 0x1E): U16
    struct.pack_into('<H', obj, 0x1E, 0)
    
    # R1, DR/DX, DR/DY (offset 0x20, 0x22, 0x24): U12.4, FP16, FP16
    struct.pack_into('<H', obj, 0x20, u12_4_to_int(v_top.r))
    struct.pack_into('<H', obj, 0x22, float_to_fp16(dr_dx))
    struct.pack_into('<H', obj, 0x24, float_to_fp16(dr_dy))
    
    # G1, DG/DX, DG/DY (offset 0x26, 0x28, 0x2A): U12.4, FP16, FP16
    struct.pack_into('<H', obj, 0x26, u12_4_to_int(v_top.g))
    struct.pack_into('<H', obj, 0x28, float_to_fp16(dg_dx))
    struct.pack_into('<H', obj, 0x2A, float_to_fp16(dg_dy))
    
    # B1, DB/DX, DB/DY (offset 0x2C, 0x2E, 0x30): U12.4, FP16, FP16
    struct.pack_into('<H', obj, 0x2C, u12_4_to_int(v_top.b))
    struct.pack_into('<H', obj, 0x2E, float_to_fp16(db_dx))
    struct.pack_into('<H', obj, 0x30, float_to_fp16(db_dy))
    
    # TEX_STRIDE (offset 0x32): U16
    struct.pack_into('<H', obj, 0x32, 0)
    
    # TEX_ADDR (offset 0x34): U32
    struct.pack_into('<I', obj, 0x34, 0)
    
    # NEXT (offset 0x3C): U32
    struct.pack_into('<I', obj, 0x3C, next_addr)
    
    return bytes(obj)


def encode_scene(triangles: List[Triangle], base_addr: int = 0x10000) -> bytes:
    """
    Encode a list of triangles into a linked list of IRIS objects.
    
    Args:
        triangles: List of Triangle objects
        base_addr: Base memory address where the scene will be loaded
    
    Returns:
        Binary data containing all encoded objects
    """
    # Sort triangles by YTOP (minimum Y coordinate)
    sorted_tris = sorted(triangles, key=lambda t: min(t.v1.y, t.v2.y, t.v3.y))
    
    # Encode each triangle
    scene_data = bytearray()
    
    for i, tri in enumerate(sorted_tris):
        # Calculate address of next object (0 if last)
        if i < len(sorted_tris) - 1:
            next_addr = base_addr + (i + 1) * 64
        else:
            next_addr = 0
        
        # Encode triangle and append to scene data
        obj_data = encode_triangle(tri, next_addr)
        scene_data.extend(obj_data)
    
    return bytes(scene_data)


def scene_to_hex(scene_data: bytes, bytes_per_line: int = 16) -> str:
    """Convert binary scene data to hex string format."""
    lines = []
    for i in range(0, len(scene_data), bytes_per_line):
        chunk = scene_data[i:i+bytes_per_line]
        hex_bytes = ' '.join(f'{b:02X}' for b in chunk)
        lines.append(f'{i:04X}: {hex_bytes}')
    return '\n'.join(lines)


def scene_to_verilog_hex(scene_data: bytes) -> str:
    """Convert binary scene data to Verilog $readmemh format (32-bit little endian, one per line)."""
    lines = []
    # Pad to multiple of 4 bytes if needed
    padded_data = scene_data + b'\x00' * ((4 - len(scene_data) % 4) % 4)
    
    # Read 32-bit values in little endian format
    for i in range(0, len(padded_data), 4):
        value = struct.unpack('<I', padded_data[i:i+4])[0]
        lines.append(f'{value:08x}')
    
    return '\n'.join(lines)


def main():
    """Example usage: create a simple test scene."""
    
    # Example: Create a simple scene with two triangles
    
    # Triangle 1: Red to green to blue gradient
    tri1 = Triangle(
        v1=Vertex(x=100.0, y=100.0, z=10.0, r=255.0, g=0.0, b=0.0),    # Red
        v2=Vertex(x=200.0, y=200.0, z=10.0, r=0.0, g=255.0, b=0.0),    # Green
        v3=Vertex(x=50.0, y=200.0, z=10.0, r=0.0, g=0.0, b=255.0),     # Blue
        clip_x1=0,
        clip_x2=640
    )
    
    # Triangle 2: White to black gradient, slightly in front
    tri2 = Triangle(
        v1=Vertex(x=300.0, y=50.0, z=5.0, r=255.0, g=255.0, b=255.0),  # White
        v2=Vertex(x=400.0, y=250.0, z=5.0, r=128.0, g=128.0, b=128.0),  # Gray
        v3=Vertex(x=250.0, y=250.0, z=5.0, r=0.0, g=0.0, b=0.0),        # Black
        clip_x1=0,
        clip_x2=640
    )
    
    # Encode scene
    triangles = [tri1, tri2]
    scene_data = encode_scene(triangles, base_addr=0x10000)
    
    # Output hex dump
    print("IRIS Scene Data (64 bytes per object):")
    print("=" * 70)
    print(scene_to_hex(scene_data))
    print("=" * 70)
    print(f"\nTotal size: {len(scene_data)} bytes ({len(triangles)} triangles)")
    print(f"First object at: 0x10000")
    
    # Also save to binary file
    with open('scene.bin', 'wb') as f:
        f.write(scene_data)
    print("\nBinary data saved to: scene.bin")
    
    # Save to hex file (for easy loading into simulators)
    with open('scene.hex', 'w') as f:
        f.write(scene_to_hex(scene_data))
    print("Hex dump saved to: scene.hex")
    
    # Save to Verilog-compatible hex file
    with open('scene_verilog.hex', 'w') as f:
        f.write(scene_to_verilog_hex(scene_data))
    print("Verilog hex (32-bit LE) saved to: scene_verilog.hex")


if __name__ == '__main__':
    main()
