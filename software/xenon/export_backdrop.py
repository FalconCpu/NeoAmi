"""Export full-screen Xenon 2000 images (e.g. the galaxy backdrop) for the FPGA.

Each image gets its own 255-colour palette (index 0 is never used, so it stays
free for "transparent"), so it can live in its own colour bank.  To export more
images add an entry to IMAGES.

Outputs (in --out DIR, default "export"), for each image NAME:
    NAME.bin          uint8 [height][width] palette indices
    NAME_palette.bin  uint32 [256], 0x00RRGGBB little-endian (entry 0 unused)
    NAME_preview.png  decoded from the exported files
and one backdrop.json describing them.

Usage: python export_backdrop.py [--out DIR] [--game DIR]
"""
import json
import os
import sys

import numpy as np
from PIL import Image

GAME_DIR = r"C:\Program Files (x86)\The Bitmap Brothers\Xenon 2000 - Project PCF"

# name -> source file in graphics\24bit
IMAGES = {
    "backdrop": "galaxy2.bmp",
}


def quantize(rgb):
    """rgb: (H,W,3). Returns (palette[256,3], indices[H,W]) using indices 1..255.

    Max-coverage rather than median-cut: median-cut spends its entries on the
    dark nebula and flattens the bright star cores (max error 172 vs 6)."""
    q = Image.fromarray(rgb).quantize(255, method=Image.Quantize.MAXCOVERAGE, dither=Image.Dither.NONE)
    pal = np.zeros((256, 3), np.uint8)
    qp = np.array(q.getpalette()[:255 * 3], np.uint8).reshape(-1, 3)
    pal[1:1 + len(qp)] = qp
    return pal, np.asarray(q).astype(np.uint8) + 1


def main():
    argv = sys.argv[1:]
    opts = {"--out": "export", "--game": GAME_DIR}
    for opt in opts:
        if opt in argv:
            i = argv.index(opt)
            opts[opt] = argv[i + 1]
            del argv[i:i + 2]
    out, game = opts["--out"], opts["--game"]
    os.makedirs(out, exist_ok=True)

    infos = []
    for name, src in IMAGES.items():
        rgb = np.asarray(Image.open(os.path.join(game, "graphics", "24bit", src)).convert("RGB"))
        h, w = rgb.shape[:2]
        pal, idx = quantize(rgb)

        idx.tofile(os.path.join(out, f"{name}.bin"))
        ((pal[:, 0].astype("<u4") << 16) | (pal[:, 1].astype("<u4") << 8) | pal[:, 2]).astype("<u4").tofile(
            os.path.join(out, f"{name}_palette.bin"))

        # Round-trip from the written files
        pal_in = np.fromfile(os.path.join(out, f"{name}_palette.bin"), "<u4")
        idx_in = np.fromfile(os.path.join(out, f"{name}.bin"), np.uint8).reshape(h, w)
        dec = np.stack([(pal_in[idx_in] >> 16) & 255, (pal_in[idx_in] >> 8) & 255, pal_in[idx_in] & 255],
                       axis=-1).astype(np.uint8)
        Image.fromarray(dec).save(os.path.join(out, f"{name}_preview.png"))
        err = np.abs(dec.astype(int) - rgb.astype(int)).mean()
        print(f"{name}: {w}x{h}, {len(np.unique(idx))} colours used, "
              f"zero indices = {int((idx == 0).sum())},               mean abs error = {err:.2f}/255")
        infos.append(dict(name=name, source=src, width=w, height=h, data=f"{name}.bin",
                                        palette=f"{name}_palette.bin"))

    with open(os.path.join(out, "backdrop.json"), "w") as f:
        json.dump({"images": infos}, f, indent=2)
    print("written to", os.path.abspath(out))


if __name__ == "__main__":
    main()
