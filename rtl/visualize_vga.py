#!/usr/bin/env python3
"""
Simple VGA output visualizer.
Reads vga_output.txt and displays the rendered image.
"""

from PIL import Image
import numpy as np

def visualize_vga(filename="vga_output.txt"):
    """Read VGA output file and create an image."""
    
    print(f"Reading {filename}...")
    
    # Read all pixels
    pixels = []
    max_x = 0
    max_y = 0
    
    with open(filename, 'r') as f:
        for line in f:
            parts = line.strip().split()
            if len(parts) == 5:
                x, y, r, g, b = map(int, parts)
                pixels.append((x, y, r, g, b))
                max_x = max(max_x, x)
                max_y = max(max_y, y)
    
    print(f"Found {len(pixels)} pixels")
    print(f"Image dimensions: {max_x + 1} x {max_y + 1}")
    
    # Create image array
    width = max_x + 1
    height = max_y + 1
    img_array = np.zeros((height, width, 3), dtype=np.uint8)
    
    # Fill in pixels
    for x, y, r, g, b in pixels:
        img_array[y, x] = [r, g, b]
    
    # Create and save image
    img = Image.fromarray(img_array, 'RGB')
    # img.save("vga_output.png")
    # print("Saved image to vga_output.png")
    
    # Display image
    img.show()
    
    return img

if __name__ == "__main__":
    import sys
    
    filename = sys.argv[1] if len(sys.argv) > 1 else "vga_output.txt"
    visualize_vga(filename)
