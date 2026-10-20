"""Export Xenon 2000 actor sprite sheets as flat binary files for the FPGA.

Sprites are described by sections of actors.ini (ImageFilename, TileWidth,
TileHeight, HotspotX/Y, AnimationRate, ...).  To export more sprites, add the
section name to SPRITES below (optionally with per-row names in ROW_NAMES).

Outputs (in --out DIR, default "export"):
    sprites.bin          uint8; every frame of every sprite back to back, each
                         frame stored as [h][w] palette indices, 0 = transparent.
                         Sheets are cut row-major: frame = row * columns + col.
    sprites_palette.bin  uint32 [256], 0x00RRGGBB little-endian, one palette shared
                         by all sprites (entry 0 unused).
    sprites.json         per sprite: byte offset into sprites.bin, frame size,
                         frame count, sheet layout, hotspot, animation rate and
                         the remaining actors.ini properties.
    sprites_preview.png  contact sheet decoded from the exported files.

Usage: python export_sprites.py [--out DIR] [--game DIR] [--no-verify]
"""
import configparser
import json
import os
import sys

import numpy as np
from PIL import Image

GAME_DIR = r"C:\Program Files (x86)\The Bitmap Brothers\Xenon 2000 - Project PCF"
MAGENTA = (255, 0, 255)

# actors.ini sections to export, in output order.
SPRITES = [
    "Ship",
    "ShipEngine",
    "Missile",
    "Pod",
    "Drone",
    "Rusher",
    "SpeedPickup",
    "ShieldPickup",
    "WeaponPickup",
    "CloakPickup",
    "DivePickup",
    "ScorePickup",
    "ClonePickup",
    "WingtipPickup",
    "MissilePickup",
    "LaserPickup",
    "LifePickup",
    "SmallStandardAsteroid",
    "MediumStandardAsteroid",
    "BigStandardAsteroid",
    "SmallHighDensityAsteroid",
    "MediumHighDensityAsteroid",
    "BigHighDensityAsteroid",
    "SmallIndestuctibleAsteroid",
    "MediumIndestuctibleAsteroid",
    "BigIndestuctibleAsteroid",
    "SmallExplosion",
    "MediumExplosion",
    "BigExplosion",
    "Clone",
    "Wingtip"
]

# Optional names for the rows of a sprite sheet, for the benefit of game code.
ROW_NAMES = {
    "Ship": ["normal", "cloaked", "dive"],
}

KNOWN_KEYS = {"Type", "ImageFilename", "TileWidth", "TileHeight", "HotspotX", "HotspotY", "AnimationRate"}


def number(s):
    for conv in (int, float):
        try:
            return conv(s)
        except ValueError:
            pass
    return s


def load_sheet(game_dir, section):
    """Return (layout dict, [frame RGB arrays]) for an actors.ini section."""
    fw, fh = int(section["TileWidth"]), int(section["TileHeight"])
    path = os.path.join(game_dir, "graphics", "24bit", section["ImageFilename"])
    img = np.asarray(Image.open(path).convert("RGB"))
    H, W = img.shape[:2]
    assert W % fw == 0 and H % fh == 0, f"{path}: {W}x{H} is not a multiple of {fw}x{fh}"
    cols, rows = W // fw, H // fh
    frames = [img[r * fh:(r + 1) * fh, c * fw:(c + 1) * fw] for r in range(rows) for c in range(cols)]
    return dict(frame_width=fw, frame_height=fh, columns=cols, rows=rows), frames


def quantize(rgb):
    """rgb: (N,3) uint8. Returns (palette[256,3], indices[N]) with index 0 = transparent."""
    opaque = ~np.all(rgb == MAGENTA, axis=1)
    q = Image.fromarray(rgb[opaque].reshape(-1, 1, 3)).quantize(
        255, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
    pal = np.zeros((256, 3), np.uint8)
    qp = np.array(q.getpalette()[:255 * 3], np.uint8).reshape(-1, 3)
    pal[1:1 + len(qp)] = qp
    idx = np.zeros(len(rgb), np.uint8)
    idx[opaque] = np.asarray(q).reshape(-1) + 1
    return pal, idx


def verify(pal, idx, rgb):
    transp = np.all(rgb == MAGENTA, axis=1)
    mismatch = int((transp != (idx == 0)).sum())
    err = np.abs(pal[idx].astype(int) - rgb.astype(int))[~transp].mean()
    print(f"verify: transparency mismatches = {mismatch}, mean abs colour error = {err:.2f}/255")


def preview(pal, sprites, data, out):
    """Contact sheet decoded purely from the exported arrays."""
    sheets = []
    for s in sprites:
        fw, fh, cols, rows = s["frame_width"], s["frame_height"], s["columns"], s["rows"]
        raw = data[s["offset"]:s["offset"] + s["num_frames"] * s["frame_size"]].reshape(rows * cols, fh, fw)
        sheet = np.full((rows * fh, cols * fw, 3), 40, np.uint8)
        for n, f in enumerate(raw):
            r, c = divmod(n, cols)
            dst = sheet[r * fh:(r + 1) * fh, c * fw:(c + 1) * fw]
            dst[f > 0] = pal[f][f > 0]
        sheets.append(sheet)
    canvas = np.full((sum(s.shape[0] for s in sheets), max(s.shape[1] for s in sheets), 3), 40, np.uint8)
    y = 0
    for s in sheets:
        canvas[y:y + s.shape[0], :s.shape[1]] = s
        y += s.shape[0]
    Image.fromarray(canvas).resize((canvas.shape[1] * 2, canvas.shape[0] * 2), Image.NEAREST).save(
        os.path.join(out, "sprites_preview.png"))


def write_manifest(path, sprites):
    """FPL source listing every frame in sprites.bin as Image(offset, width, height).

    Also emits SPRITE_<NAME> constants giving the index of each sprite's first frame."""
    lines = ["# Generated by export_sprites.py - do not edit.",
             "# Image(offset into sprites.bin, width, height), one entry per frame.", ""]
    first, entries = 0, []
    for s in sprites:
        const = "SPRITE_" + "".join("_" + c if c.isupper() and i else c for i, c in enumerate(s["name"])).upper()
        lines.append(f"const {const} = {first}")
        for n in range(s["num_frames"]):
            entries.append((s["offset"] + n * s["frame_size"], s["frame_width"], s["frame_height"], s["name"]))
        first += s["num_frames"]
    lines += ["", f"const NUM_SPRITE_FRAMES = {len(entries)}", "", "const spriteManifest = const Array<Image>["]
    for i, (off, w, h, name) in enumerate(entries):
        sep = "," if i < len(entries) - 1 else " ]"
        lines.append(f"    Image({off}, {w}, {h}){sep}".ljust(36) + f"# {name}")
    with open(path, "w", newline="\n") as f:
        f.write("\n".join(lines) + "\n")


def main():
    argv = sys.argv[1:]
    opts = {"--out": "export", "--game": GAME_DIR,
            "--manifest": os.path.join(os.path.dirname(os.path.abspath(__file__)), "sprite_manifest.fpl")}
    for opt in opts:
        if opt in argv:
            i = argv.index(opt)
            opts[opt] = argv[i + 1]
            del argv[i:i + 2]
    out, game = opts["--out"], opts["--game"]

    actors = configparser.ConfigParser(strict=False)
    actors.optionxform = str
    actors.read(os.path.join(game, "actors.ini"))

    infos, chunks = [], []
    pos = 0
    for name in SPRITES:
        sec = actors[name]
        info, frames = load_sheet(game, sec)
        size = info["frame_width"] * info["frame_height"]
        info.update(
            name=name,
            source=sec["ImageFilename"],
            type=sec.get("Type"),
            num_frames=len(frames),
            frame_size=size,
            offset=pos,
            hotspot=[int(sec["HotspotX"]), int(sec["HotspotY"])],
            animation_rate=float(sec["AnimationRate"]),
            properties={k: number(v) for k, v in sec.items() if k not in KNOWN_KEYS},
        )
        if name in ROW_NAMES:
            assert len(ROW_NAMES[name]) == info["rows"], f"{name}: ROW_NAMES does not match sheet rows"
            info["row_names"] = ROW_NAMES[name]
        pos += len(frames) * size
        infos.append(info)
        chunks.extend(f.reshape(-1, 3) for f in frames)

    rgb = np.concatenate(chunks)
    pal, data = quantize(rgb)

    os.makedirs(out, exist_ok=True)
    data.tofile(os.path.join(out, "sprites.bin"))
    ((pal[:, 0].astype("<u4") << 16) | (pal[:, 1].astype("<u4") << 8) | pal[:, 2]).astype("<u4").tofile(
        os.path.join(out, "sprites_palette.bin"))
    with open(os.path.join(out, "sprites.json"), "w") as f:
        json.dump({"palette": "sprites_palette.bin", "data": "sprites.bin", "sprites": infos}, f, indent=2)

    write_manifest(opts["--manifest"], infos)

    print(f"{len(infos)} sprite(s), {sum(i['num_frames'] for i in infos)} frames, {len(data)} bytes")
    if "--no-verify" not in sys.argv:
        verify(pal, data, rgb)
        preview(pal, infos, data, out)
    print("written to", os.path.abspath(out))


if __name__ == "__main__":
    main()
