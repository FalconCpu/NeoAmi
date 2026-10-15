"""Export a full-screen image in the FPGA "incremental HAM" format.

Byte format (one byte per pixel):
    bit 7 = 0 : palette pixel, bits [6:0] index a 128-entry palette
    bit 7 = 1 : delta pixel, relative to the previous pixel on the line
                bits [6:4] = channel mask (bit6 = R, bit5 = G, bit4 = B)
                bits [3:0] = delta code: 0 -> +8, 1..7 -> +1..+7, 8..15 -> -8..-1
                (so -8..+8 excluding 0); selected channels get the same
                delta, clamped to 0..255.  Mask 000 = no change (repeat).
Every scanline must start with a palette pixel (no state crosses lines).

Outputs (in --out DIR, default "export"), for each image NAME:
    NAME_ham.bin          uint8 [height][width]
    NAME_ham_palette.bin  uint32 [256], 0x00RRGGBB (only entries 0..127 used)
    NAME_ham_preview.png  decoded from the exported files with decode()

Usage: python export_backdrop_ham.py [--out DIR] [--game DIR]
"""
import os
import sys

import numpy as np
from PIL import Image

from export_backdrop import GAME_DIR, IMAGES

PAL_SIZE = 128


def delta_value(code):
    """Delta code (0..15) -> signed delta."""
    return np.where(code == 0, 8, np.where(code < 8, code, code - 16))


def decode(data, pal):
    """Reference decoder. data: uint8 [h][w]; pal: uint32 [>=128]. Returns uint8 [h][w][3]."""
    h, w = data.shape
    assert not (data[:, 0] & 0x80).any(), "every line must start with a palette pixel"
    out = np.zeros((h, w, 3), np.int16)
    prev = np.zeros((h, 3), np.int16)
    for x in range(w):
        b = data[:, x].astype(np.int16)
        p = pal[b & 0x7F]
        palrgb = np.stack([(p >> 16) & 255, (p >> 8) & 255, p & 255], axis=-1).astype(np.int16)
        d = delta_value(b & 15)
        mask = np.stack([(b >> 6) & 1, (b >> 5) & 1, (b >> 4) & 1], axis=-1)
        deltargb = np.clip(prev + mask * d[:, None], 0, 255)
        cur = np.where((b & 0x80)[:, None] != 0, deltargb, palrgb)
        out[:, x] = cur
        prev = cur
    return out.astype(np.uint8)


def make_palette(rgb):
    q = Image.fromarray(rgb).quantize(PAL_SIZE, method=Image.Quantize.MAXCOVERAGE, dither=Image.Dither.NONE)
    qp = np.array(q.getpalette()[:PAL_SIZE * 3], np.uint8).reshape(-1, 3)
    pal = np.zeros((PAL_SIZE, 3), np.uint8)
    pal[:len(qp)] = qp
    return pal


def encode(rgb, pal):
    """Greedy encoder, all rows in parallel. Returns uint8 [h][w]."""
    h, w = rgb.shape[:2]
    src = rgb.astype(np.int32)
    palc = pal.astype(np.int32)

    # delta candidates: code 0x80 | mask<<4 | dcode, for mask 1..7 and dcode 0..15
    codes = np.array([0x80 | (m << 4) | d for m in range(1, 8) for d in range(16)] + [0x80], np.int32)
    cmask = np.stack([(codes >> 6) & 1, (codes >> 5) & 1, (codes >> 4) & 1], axis=-1)
    cdelta = delta_value(codes & 15)
    cdelta = np.where((codes & 0x70) == 0, 0, cdelta)  # mask 000 = no change

    out = np.zeros((h, w), np.uint8)
    prev = np.zeros((h, 3), np.int32)
    for x in range(w):
        t = src[:, x]
        # palette candidates
        pd = ((palc[None] - t[:, None]) ** 2).sum(-1)
        pi = pd.argmin(1)
        pbest = pd[np.arange(h), pi]
        if x == 0:
            out[:, 0] = pi
            prev = palc[pi]
            continue
        cand = np.clip(prev[:, None] + cmask[None] * cdelta[None, :, None], 0, 255)
        dd = ((cand - t[:, None]) ** 2).sum(-1)
        di = dd.argmin(1)
        dbest = dd[np.arange(h), di]
        use_delta = dbest <= pbest
        out[:, x] = np.where(use_delta, codes[di], pi).astype(np.uint8)
        prev = np.where(use_delta[:, None], cand[np.arange(h), di], palc[pi])
    return out


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

    for name, src in IMAGES.items():
        rgb = np.asarray(Image.open(os.path.join(game, "graphics", "24bit", src)).convert("RGB"))
        h, w = rgb.shape[:2]
        pal = make_palette(rgb)
        data = encode(rgb, pal)

        pal32 = np.zeros(256, "<u4")
        pal32[:PAL_SIZE] = (pal[:, 0].astype("<u4") << 16) | (pal[:, 1].astype("<u4") << 8) | pal[:, 2]
        data.tofile(os.path.join(out, f"{name}_ham.bin"))
        pal32.tofile(os.path.join(out, f"{name}_ham_palette.bin"))

        # Round-trip from the written files
        pal_in = np.fromfile(os.path.join(out, f"{name}_ham_palette.bin"), "<u4")
        data_in = np.fromfile(os.path.join(out, f"{name}_ham.bin"), np.uint8).reshape(h, w)
        dec = decode(data_in, pal_in)
        Image.fromarray(dec).save(os.path.join(out, f"{name}_ham_preview.png"))
        err = np.abs(dec.astype(int) - rgb.astype(int))
        npal = int(((data_in & 0x80) == 0).sum())
        nrep = int(((data_in & 0xF0) == 0x80).sum())
        print(f"{name}: {w}x{h}, mean err {err.mean():.3f}, max {err.max()}, "
              f"palette px {npal} ({100 * npal / data_in.size:.2f}%), mask-000 repeats {nrep}")
    print("written to", os.path.abspath(out))


if __name__ == "__main__":
    main()
