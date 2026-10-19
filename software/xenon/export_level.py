"""Convert the Xenon 2000 FMP level into flat binary files for the FPGA.

Outputs (in --out DIR, default "export"):
    tiles.bin    uint8  [num_tiles][32][32]   palette index per pixel, 0 = transparent
    palette.bin  uint32 [256]                 0x00RRGGBB, little-endian; entry 0 unused
    tilemap.bin  uint16 [2][1024][20]         layer 0 = BODY (slow background),
                                              layer 1 = LYR1 (terrain); little-endian
                                              tile index, 0 = empty
    spawns.bin   records of <uint16 row, uint8 col, uint8 type>, little-endian,
                 sorted by row descending (the level scrolls from the bottom up)
    level.json   dimensions, counts and spawn type names

Usage: python export_level.py [file.fmp] [--out DIR] [--no-verify]
"""
import json
import os
import struct
import sys

import numpy as np
from PIL import Image

import fmp

LAYERS = ("BODY", "LYR1")
# MARKER_FIRST, MARKER_LAST = 1, 40  # editor placeholder blocks (spawn markers)
MARKER_FIRST, MARKER_LAST = 1, 1  # editor placeholder blocks (spawn markers)
MAGENTA = (255, 0, 255)

SPAWN_NAMES = {
    1: "Shield pickup", 2: "Speed pickup", 3: "Weapon pickup", 4: "Cloak pickup",
    5: "Dive pickup", 6: "Score pickup", 7: "Clone pickup", 8: "Wingtips pickup",
    9: "Homing missile pickup", 10: "Laser pickup",
    11: "Static wall hugger", 12: "Moving wall hugger",
    13: "Asteroid grade 0 small", 14: "Asteroid grade 0 medium", 15: "Asteroid grade 0 large",
    16: "Asteroid grade 1 small", 17: "Asteroid grade 1 medium", 18: "Asteroid grade 1 large",
    19: "Asteroid grade 2 small", 20: "Asteroid grade 2 medium", 21: "Asteroid grade 2 large",
    22: "Rusher (down)", 23: "Pod", 24: "Homer", 25: "Drones",
    26: "Loner grade 0", 27: "Loner grade 1", 28: "Loner grade 2",
    29: "Checkpoint", 30: "Warp start", 31: "Warp end", 32: "Rusher (up)",
    33: "Rushers (right)", 34: "Rushers (left)", 35: "Boss",
    36: "Organic gun (right)", 37: "Organic gun (left)",
}


def build(hdr, gfx, blocks, layers):
    bss, w, h = hdr["bss"], hdr["width"], hdr["height"]
    tilesize = hdr["bw"] * hdr["bh"] * (hdr["depth"] // 8)

    grids, spawns = {}, []
    for name in LAYERS:
        raw = layers[name].astype(np.int32)
        assert (raw >= 0).all() and (raw % bss == 0).all(), "animated/odd cells not supported"
        grids[name] = raw // bss
    for name in LAYERS:
        g = grids[name]
        # marker = (g >= MARKER_FIRST) & (g <= MARKER_LAST)
        # if name != "LYR1":
        #     assert not marker.any(), f"markers unexpectedly present in {name}"
        #     continue
        # for y, x in zip(*np.nonzero(marker)):
        #     spawns.append((int(y), int(x), int(g[y, x])))
        # g[marker] = 0
    spawns.sort(key=lambda s: (-s[0], s[1]))

    used = sorted({int(b) for g in grids.values() for b in np.unique(g) if b})
    for b in used:
        assert all(o == 0 for o in blocks[b]["offs"][1:]), f"block {b} has foreground tiles"

    # Unique RGB tile images, then one shared palette
    rgb_ids, rgb_tiles = {}, []
    block_rgb = {}
    for b in used:
        t = np.ascontiguousarray(gfx[blocks[b]["offs"][0] // tilesize])
        key = t.tobytes()
        if key not in rgb_ids:
            rgb_ids[key] = len(rgb_tiles)
            rgb_tiles.append(t)
        block_rgb[b] = rgb_ids[key]
    rgb = np.stack(rgb_tiles)
    opaque = ~np.all(rgb == MAGENTA, axis=3)

    px = rgb[opaque]
    im = Image.fromarray(px.reshape(-1, 1, 3))
    q = im.quantize(255, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
    idx = np.asarray(q).reshape(-1).astype(np.uint8) + 1
    pal = np.zeros((256, 3), np.uint8)
    qp = np.array(q.getpalette()[:255 * 3], np.uint8).reshape(-1, 3)
    pal[1:1 + len(qp)] = qp

    indexed = np.zeros(opaque.shape, np.uint8)
    indexed[opaque] = idx

    # Final tile table: tile 0 is fully transparent; drop duplicates after quantising
    tiles = [np.zeros(indexed.shape[1:], np.uint8)]
    seen = {tiles[0].tobytes(): 0}
    rgb_to_final = []
    for t in indexed:
        k = t.tobytes()
        if k not in seen:
            seen[k] = len(tiles)
            tiles.append(t)
        rgb_to_final.append(seen[k])
    lut = np.zeros(hdr["nbs"], np.uint16)
    for b in used:
        lut[b] = rgb_to_final[block_rgb[b]]
    tilemap = np.stack([lut[grids[n]] for n in LAYERS]).astype("<u2")

    return np.stack(tiles), pal, tilemap, spawns, block_rgb, grids


def verify(hdr, gfx, blocks, tiles, pal, tilemap, grids, out):
    """Reload nothing from memory-only state: compare decoded cells with the originals."""
    tilesize = hdr["bw"] * hdr["bh"] * 3
    err_sum = err_n = bad_alpha = 0
    for li, name in enumerate(LAYERS):
        g = grids[name]
        for b in np.unique(g[g > 0]):
            orig = gfx[blocks[int(b)]["offs"][0] // tilesize].astype(int)
            n_cells = int((g == b).sum())
            ti = int(tilemap[li][g == b][0])
            t = tiles[ti]
            dec = pal[t].astype(int)
            o_transp = np.all(orig == MAGENTA, axis=2)
            bad_alpha += n_cells * int((o_transp != (t == 0)).sum())
            m = ~o_transp
            err_sum += n_cells * int(np.abs(dec[m] - orig[m]).sum())
            err_n += n_cells * int(m.sum()) * 3
    print(f"verify: transparency mismatches = {bad_alpha}, mean abs colour error = {err_sum / max(err_n, 1):.2f}/255")

    # Preview straight from the exported arrays: backdrop + BODY + LYR1 (no parallax)
    r0, r1 = 704, 768
    canvas = fmp.starfield(hdr["width"] * 32, (r1 - r0) * 32, r0 * 32).copy()
    for li in range(len(LAYERS)):
        for y in range(r0, r1):
            for x in range(hdr["width"]):
                ti = tilemap[li, y, x]
                if ti:
                    t = tiles[ti]
                    dst = canvas[(y - r0) * 32:(y - r0 + 1) * 32, x * 32:(x + 1) * 32]
                    dst[t > 0] = pal[t][t > 0]
    Image.fromarray(canvas).save(os.path.join(out, "preview.png"))


def main():
    argv = sys.argv[1:]
    out = "export"
    if "--out" in argv:
        i = argv.index("--out")
        out = argv[i + 1]
        del argv[i:i + 2]
    do_verify = "--no-verify" not in argv
    args = [a for a in argv if not a.startswith("--")]
    path = args[0] if args else fmp.DEFAULT

    hdr, gfx, blocks, layers = fmp.read_fmp(path)
    tiles, pal, tilemap, spawns, _, grids = build(hdr, gfx, blocks, layers)

    os.makedirs(out, exist_ok=True)
    tiles.tofile(os.path.join(out, "tiles.bin"))
    ((pal[:, 0].astype("<u4") << 16) | (pal[:, 1].astype("<u4") << 8) | pal[:, 2]).astype("<u4").tofile(
        os.path.join(out, "palette.bin"))
    tilemap.tofile(os.path.join(out, "tilemap.bin"))
    with open(os.path.join(out, "spawns.bin"), "wb") as f:
        for row, col, typ in spawns:
            f.write(struct.pack("<HBB", row, col, typ))
    info = dict(
        tile_width=32, tile_height=32, num_tiles=int(len(tiles)),
        map_width=hdr["width"], map_height=hdr["height"],
        layers=list(LAYERS), num_spawns=len(spawns),
        spawn_names={str(k): v for k, v in SPAWN_NAMES.items()},
    )
    with open(os.path.join(out, "level.json"), "w") as f:
        json.dump(info, f, indent=2)

    print(f"tiles: {len(tiles)} ({tiles.nbytes} bytes), tilemap: {tilemap.nbytes} bytes, spawns: {len(spawns)}")
    counts = {}
    for _, _, t in spawns:
        counts[t] = counts.get(t, 0) + 1
    unnamed = [t for t in counts if t not in SPAWN_NAMES]
    if unnamed:
        print("WARNING: spawn types without a name:", unnamed)
    if do_verify:
        verify(hdr, gfx, blocks, tiles, pal, tilemap, grids, out)
    print("written to", os.path.abspath(out))


if __name__ == "__main__":
    main()
