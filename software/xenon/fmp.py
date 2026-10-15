"""Mappy FMP reader and renderer for Xenon 2000.

Usage:
    python fmp.py [file.fmp] [--out DIR] [--view]

Writes map_<layer>.png strips (split into pages) and optionally opens a
scrollable viewer (tkinter) showing the composited map.
"""
import struct
import sys
import os
import numpy as np
from PIL import Image

DEFAULT = r"C:\Program Files (x86)\The Bitmap Brothers\Xenon 2000 - Project PCF\levels\xenon2000.FMP"


def read_fmp(path):
    d = open(path, "rb").read()
    assert d[:4] == b"FORM" and d[8:12] == b"FMAP"
    chunks = {}
    pos = 12
    while pos + 8 <= len(d):
        cid = d[pos:pos + 4].decode("ascii")
        ln = struct.unpack(">I", d[pos + 4:pos + 8])[0]
        chunks[cid] = d[pos + 8:pos + 8 + ln]
        pos += 8 + ln
    h = chunks["MPHD"]
    (vh, vl, endian, _, w, hgt, _, _, bw, bh, depth, bss, nbs, nbg) = struct.unpack("<BBBBHHHHHHHHHH", h[:24])
    hdr = dict(width=w, height=hgt, bw=bw, bh=bh, depth=depth, bss=bss, nbs=nbs, nbg=nbg)

    bpp = depth // 8
    gfx = np.frombuffer(chunks["BGFX"], np.uint8)[: nbg * bw * bh * bpp].reshape(nbg, bh, bw, bpp)

    blocks = []
    bk = chunks["BKDT"]
    for i in range(nbs):
        o = i * bss
        bg, fg1, fg2, fg3, u1, u2 = struct.unpack("<iiiiii", bk[o:o + 24])
        u3, u4 = struct.unpack("<hh", bk[o + 24:o + 28])
        u5, u6, u7, flags = bk[o + 28:o + 32]
        blocks.append(dict(offs=(bg, fg1, fg2, fg3), user=(u1, u2, u3, u4, u5, u6, u7), flags=flags))

    layers = {}
    for name in ("BODY", "LYR1", "LYR2"):
        if name in chunks:
            layers[name] = np.frombuffer(chunks[name], "<i2").reshape(hgt, w)
    return hdr, gfx, blocks, layers


def render(hdr, gfx, blocks, layer, rows, key=None):
    """Render rows [r0, r1) of a layer to an RGB(A) array."""
    r0, r1 = rows
    w, bw, bh = hdr["width"], hdr["bw"], hdr["bh"]
    bpp = gfx.shape[3]
    img = np.zeros(((r1 - r0) * bh, w * bw, 4), np.uint8)
    tilesize = bw * bh * bpp
    for y in range(r0, r1):
        for x in range(w):
            v = int(layer[y, x])
            if v <= 0:
                continue  # empty (block 0) or animation (not present in this file)
            blk = blocks[v // hdr["bss"]]
            for n, off in enumerate(blk["offs"]):
                if off <= 0 and n > 0:
                    continue
                t = gfx[off // tilesize]
                rgb = t
                dst = img[(y - r0) * bh:(y - r0 + 1) * bh, x * bw:(x + 1) * bw]
                mask = ~np.all(rgb == (255, 0, 255), axis=2)  # magenta = transparent
                dst[mask, :3] = rgb[mask]
                dst[mask, 3] = 255
    return img


GALAXY = os.path.join(os.path.dirname(DEFAULT), "..", "graphics", "24bit", "galaxy2.bmp")
_galaxy = []


def starfield(width, height, y0):
    """Tile the galaxy backdrop (scrolls with the map for this static render)."""
    if not _galaxy:
        _galaxy.append(np.asarray(Image.open(GALAXY).convert("RGB")))
    g = _galaxy[0]
    ys = (np.arange(height) + y0) % g.shape[0]
    xs = np.arange(width) % g.shape[1]
    return g[ys][:, xs]


LAYER_NAMES = ("BODY", "LYR1", "LYR2")


def composite(hdr, gfx, blocks, layers, rows, backdrop=True, only=None):
    """only: a layer name (BODY/LYR1/LYR2) to draw just that layer, or None for all."""
    h = (rows[1] - rows[0]) * hdr["bh"]
    w = hdr["width"] * hdr["bw"]
    out = starfield(w, h, rows[0] * hdr["bh"]) if backdrop else np.zeros((h, w, 3), np.uint8)
    for name in LAYER_NAMES:
        if name not in layers or (only and name != only):
            continue
        im = render(hdr, gfx, blocks, layers[name], rows)
        m = im[..., 3] > 0
        out[m] = im[m][:, :3]
    return out


def main():
    argv = sys.argv[1:]
    opts = {}
    for opt in ("--out", "--layer"):
        if opt in argv:
            i = argv.index(opt)
            opts[opt] = argv[i + 1]
            del argv[i:i + 2]
    args = [a for a in argv if not a.startswith("--")]
    path = args[0] if args else DEFAULT
    out = opts.get("--out", "out")
    only = opts.get("--layer")
    if only:
        only = {"0": "BODY", "1": "LYR1", "2": "LYR2"}.get(only, only.upper())
        if only not in LAYER_NAMES:
            sys.exit(f"--layer must be one of {LAYER_NAMES} (or 0/1/2)")
        out = os.path.join(out, only)
    os.makedirs(out, exist_ok=True)
    hdr, gfx, blocks, layers = read_fmp(path)
    print(hdr)
    for n, l in layers.items():
        nz = l[l > 0]
        print(n, "non-empty cells:", nz.size, "distinct blocks:", np.unique(nz).size)

    page = 64  # rows per PNG page
    for r0 in range(0, hdr["height"], page):
        rows = (r0, min(r0 + page, hdr["height"]))
        rgb = composite(hdr, gfx, blocks, layers, rows, backdrop=not only, only=only)
        if rgb.any():
            Image.fromarray(rgb).save(os.path.join(out, f"map_{r0:04d}.png"))
    print("pages written to", os.path.abspath(out))

    if "--view" in sys.argv:
        view(hdr, gfx, blocks, layers, only)


def view(hdr, gfx, blocks, layers, only=None):
    import tkinter as tk
    from PIL import ImageTk
    H = hdr["height"]
    root = tk.Tk()
    root.title("Xenon 2000 map (Up/Down/PgUp/PgDn/Home/End to scroll; map starts at bottom)")
    cv = tk.Canvas(root, width=hdr["width"] * hdr["bw"], height=900)
    cv.pack()
    state = {"row": H - 28, "only": only}
    photo = [None]

    def draw():
        r0 = max(0, min(H - 28, state["row"]))
        state["row"] = r0
        rgb = composite(hdr, gfx, blocks, layers, (r0, r0 + 28), backdrop=False, only=state["only"])
        photo[0] = ImageTk.PhotoImage(Image.fromarray(rgb))
        cv.delete("all")
        cv.create_image(0, 0, anchor="nw", image=photo[0])
        root.title(f"Xenon 2000 map - rows {r0}..{r0 + 28} - layer {state['only'] or 'ALL'} (keys 0/1/2 = BODY/LYR1/LYR2, a = all)")

    keys = {"Up": -4, "Down": 4, "Prior": -28, "Next": 28}
    for k, dlt in keys.items():
        root.bind(f"<{k}>", lambda e, d=dlt: (state.update(row=state["row"] + d), draw()))
    root.bind("<Home>", lambda e: (state.update(row=0), draw()))
    root.bind("<End>", lambda e: (state.update(row=H), draw()))
    for key, name in (("0", "BODY"), ("1", "LYR1"), ("2", "LYR2"), ("a", None)):
        root.bind(key, lambda e, n=name: (state.update(only=n), draw()))
    draw()
    root.mainloop()


if __name__ == "__main__":
    main()
