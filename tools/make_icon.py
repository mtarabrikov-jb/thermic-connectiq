#!/usr/bin/env python3
"""Builds a private launcher icon for the widget from a logo you supply.

The repository ships a neutral icon. This script writes an icon into the git-ignored
private/ directory, where the build picks it up instead (see README, "Branding").
Only use a logo you are entitled to use; the result stays on your machine.

It expects a wide logo made of an emblem followed by a wordmark. A 40x40 launcher icon
has room for the emblem only, so the SVG is rendered large, the emblem is cut out (the
first group of occupied columns, up to the gap before the wordmark) and scaled down.

The fenix 6 series has a 64-colour display. A brand colour outside that palette is
dithered into speckles by the resource compiler, and transparency ends up binary anyway.
So the output is deliberately crisp: every pixel is either transparent or the palette
orange #FF5500, the same colour the level ring uses.

Requires inkscape and Pillow.

usage: make_icon.py [logo.svg] [output.png] [size]
"""
import pathlib
import subprocess
import sys
import tempfile

from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parent.parent
DEFAULT_SVG = ROOT / 'private' / 'logo.svg'
DEFAULT_OUT = ROOT / 'private' / 'widget' / 'resources' / 'drawables' / 'launcher_icon.png'
DRAWABLES_XML = '<drawables>\n    <bitmap id="LauncherIcon" filename="launcher_icon.png" />\n</drawables>\n'
PALETTE_ORANGE = (0xFF, 0x55, 0x00, 255)
RENDER_WIDTH = 4800
PADDING = 1


def main():
    svg = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_SVG
    out = pathlib.Path(sys.argv[2]) if len(sys.argv) > 2 else DEFAULT_OUT
    size = int(sys.argv[3]) if len(sys.argv) > 3 else 40

    with tempfile.TemporaryDirectory() as tmp:
        big = pathlib.Path(tmp) / 'logo.png'
        subprocess.run(['inkscape', str(svg), '--export-type=png', '--export-filename=' + str(big),
                        '-w', str(RENDER_WIDTH)], check=True, capture_output=True)
        image = Image.open(big).convert('RGBA')

    width, height = image.size
    alpha = image.getchannel('A')
    columns = [x for x in range(width) if alpha.crop((x, 0, x + 1, height)).getbbox()]
    start = end = columns[0]
    for a, b in zip(columns, columns[1:]):
        if b - a > width * 0.01:
            break
        end = b
    top, bottom = alpha.crop((start, 0, end + 1, height)).getbbox()[1::2]
    emblem = image.crop((start, top, end + 1, bottom))

    side = max(emblem.size)
    square = Image.new('RGBA', (side, side), (0, 0, 0, 0))
    square.paste(emblem, ((side - emblem.width) // 2, (side - emblem.height) // 2))
    inner = size - 2 * PADDING
    small = square.resize((inner, inner), Image.LANCZOS)

    icon = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    source, target = small.load(), icon.load()
    for y in range(inner):
        for x in range(inner):
            if source[x, y][3] >= 128:
                target[x + PADDING, y + PADDING] = PALETTE_ORANGE

    out.parent.mkdir(parents=True, exist_ok=True)
    icon.save(out)
    xml = out.parent / 'drawables.xml'
    if not xml.exists():
        xml.write_text(DRAWABLES_XML, encoding='utf-8')
    print('wrote %s, %dx%d' % (out, size, size))


if __name__ == '__main__':
    main()
