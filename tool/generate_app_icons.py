"""Generate the pharmacy launcher artwork. Requires Pillow (development only)."""

from pathlib import Path
import json
from xml.etree import ElementTree

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
BRANDING = ROOT / 'assets' / 'branding'
RES = ROOT / 'android' / 'app' / 'src' / 'main' / 'res'
IOS = ROOT / 'ios' / 'Runner' / 'Assets.xcassets' / 'AppIcon.appiconset'
TEAL = '#087E78'
WHITE = '#FFFFFF'
MINT = '#BDEDD9'

# Shared closed vector paths in a 108-unit canvas: pestle, rim, bowl and foot.
# Keep the complete symbol within Android's central adaptive-icon safe area.
PESTLE = [('M', 48, 44), ('L', 65, 27),
          ('C', 68, 24, 72, 24, 75, 27),
          ('C', 78, 30, 78, 34, 75, 37),
          ('L', 68, 44), ('Z',)]
RIM = [('M', 28, 46), ('L', 80, 46),
       ('C', 84, 46, 84, 52, 80, 52), ('L', 28, 52),
       ('C', 24, 52, 24, 46, 28, 46), ('Z',)]
BOWL = [('M', 29, 55), ('L', 79, 55),
        ('C', 77, 69, 68, 77, 54, 77),
        ('C', 40, 77, 31, 69, 29, 55), ('Z',)]
FOOT = [('M', 44, 79), ('L', 64, 79),
        ('C', 66, 79, 67, 81, 67, 83), ('L', 41, 83),
        ('C', 41, 81, 42, 79, 44, 79), ('Z',)]
CROSS = [('M', 51, 58), ('L', 57, 58), ('L', 57, 62),
         ('L', 61, 62), ('L', 61, 68), ('L', 57, 68),
         ('L', 57, 72), ('L', 51, 72), ('L', 51, 68),
         ('L', 47, 68), ('L', 47, 62), ('L', 51, 62), ('Z',)]
SHAPES = [(MINT, PESTLE), (WHITE, RIM), (WHITE, BOWL), (WHITE, FOOT)]


def path_data(commands):
    return ' '.join(str(value) for command in commands for value in command)


def polygon(commands):
    points = []
    for command in commands:
        if command[0] in ('M', 'L'):
            points.append(tuple(command[1:]))
        elif command[0] == 'C':
            start = points[-1]
            x1, y1, x2, y2, x3, y3 = command[1:]
            for step in range(1, 49):
                t = step / 48
                u = 1 - t
                points.append((u**3 * start[0] + 3*u*u*t*x1 + 3*u*t*t*x2 + t**3*x3,
                               u**3 * start[1] + 3*u*u*t*y1 + 3*u*t*t*y2 + t**3*y3))
    return points


def draw_path(image, commands, color, viewport):
    scale = image.width / (viewport[1] - viewport[0])
    points = [((x - viewport[0])*scale, (y - viewport[0])*scale)
              for x, y in polygon(commands)]
    ImageDraw.Draw(image).polygon(points, fill=color)


def render(size, *, rounded=False, monochrome=False, viewport=(12, 96)):
    canvas = Image.new('RGB', (size*4, size*4), TEAL if not monochrome else '#E1EFE5')
    if not monochrome:
        # Subtle diagonal shading is repeated by the Android background vector.
        pixels = Image.new('RGB', (256, 256))
        start, end = (17, 151, 137), (4, 99, 101)
        rows = []
        for y in range(256):
            for x in range(256):
                amount = (x + y) / 510
                rows.append(tuple(round(a + (b - a)*amount) for a, b in zip(start, end)))
        pixels.putdata(rows)
        pixels = pixels.resize(canvas.size, Image.Resampling.BICUBIC)
        canvas = pixels.copy()
    for color, commands in SHAPES:
        draw_path(canvas, commands, '#20534A' if monochrome else color, viewport)
    # Erase a medical cross from the bowl; monochrome uses the same negative space.
    mask = Image.new('L', canvas.size)
    draw_path(mask, CROSS, 255, viewport)
    if monochrome:
        canvas.paste('#E1EFE5', mask=mask)
    else:
        canvas.paste(pixels, mask=mask)
    if rounded:
        alpha = Image.new('L', canvas.size)
        ImageDraw.Draw(alpha).rounded_rectangle(
            (0, 0, canvas.width-1, canvas.height-1), radius=canvas.width*.22, fill=255)
        canvas.putalpha(alpha)
    return canvas.resize((size, size), Image.Resampling.LANCZOS)


def write(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text + '\n', encoding='utf-8')


def android_vector(monochrome=False):
    paths = []
    for color, commands in SHAPES:
        # The cross is a transparent cutout in the bowl in both icon variants.
        data = path_data(commands)
        if commands is BOWL:
            data += ' ' + path_data(CROSS)
        paths.append(f'    <path android:fillColor="{WHITE if monochrome else color}" '
                     f'android:fillType="evenOdd" android:pathData="{data}" />')
    return ('<?xml version="1.0" encoding="utf-8"?>\n'
            '<vector xmlns:android="http://schemas.android.com/apk/res/android"\n'
            '    android:width="108dp" android:height="108dp"\n'
            '    android:viewportWidth="108" android:viewportHeight="108">\n'
            + '\n'.join(paths) + '\n</vector>')


def main():
    BRANDING.mkdir(parents=True, exist_ok=True)
    svg_paths = []
    for color, commands in SHAPES:
        data = path_data(commands)
        if commands is BOWL:
            data += ' ' + path_data(CROSS)
        svg_paths.append(f'  <path fill="{color}" fill-rule="evenodd" d="{data}"/>')
    write(BRANDING / 'pharmacy.svg',
          '<svg xmlns="http://www.w3.org/2000/svg" viewBox="12 12 84 84">\n'
          '  <title>Pharmacy Companion: mortar and pestle with medical cross</title>\n'
          '  <defs><linearGradient id="teal" x2="1" y2="1">'
          '<stop stop-color="#119789"/><stop offset="1" stop-color="#046365"/>'
          '</linearGradient></defs>\n'
          '  <path fill="url(#teal)" d="M12 12H96V96H12Z"/>\n'
          + '\n'.join(svg_paths) + '\n</svg>')
    master = render(1024)
    master.save(BRANDING / 'pharmacy.png', optimize=True)
    catalog = json.loads((IOS / 'Contents.json').read_text())
    for entry in catalog['images']:
        size = round(float(entry['size'].split('x')[0]) * float(entry['scale'][:-1]))
        master.resize((size, size), Image.Resampling.LANCZOS).save(IOS / entry['filename'])
    legacy = render(1024, rounded=True)
    for density, size in [('mdpi', 48), ('hdpi', 72), ('xhdpi', 96),
                          ('xxhdpi', 144), ('xxxhdpi', 192)]:
        legacy.resize((size, size), Image.Resampling.LANCZOS).save(
            RES / f'mipmap-{density}' / 'ic_launcher.png')
    write(RES / 'drawable' / 'ic_launcher_foreground.xml', android_vector())
    write(RES / 'drawable' / 'ic_launcher_monochrome.xml', android_vector(monochrome=True))
    write(RES / 'drawable' / 'ic_launcher_background.xml', '''<?xml version="1.0" encoding="utf-8"?>
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:aapt="http://schemas.android.com/aapt"
    android:width="108dp" android:height="108dp"
    android:viewportWidth="108" android:viewportHeight="108">
    <path android:pathData="M0,0H108V108H0Z">
        <aapt:attr name="android:fillColor">
            <gradient android:startX="0" android:startY="0" android:endX="108"
                android:endY="108" android:type="linear"
                android:startColor="#119789" android:endColor="#046365" />
        </aapt:attr>
    </path>
</vector>''')
    for api in (26, 33):
        themed = '\n    <monochrome android:drawable="@drawable/ic_launcher_monochrome" />' if api == 33 else ''
        write(RES / f'mipmap-anydpi-v{api}' / 'ic_launcher.xml',
              '<?xml version="1.0" encoding="utf-8"?>\n'
              '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
              '    <background android:drawable="@drawable/ic_launcher_background" />\n'
              '    <foreground android:drawable="@drawable/ic_launcher_foreground" />'
              + themed + '\n</adaptive-icon>')
    # A local review sheet; never a shipped asset or seeded application fixture.
    review = Image.new('RGB', (740, 300), '#F0F5F4')
    for x, label, mode in [(28, 'iOS', 'ios'), (270, 'Android circle', 'android'),
                           (512, 'Android themed', 'themed')]:
        icon = render(200, monochrome=mode == 'themed',
                      viewport=(18, 90) if mode != 'ios' else (12, 96))
        alpha = Image.new('L', icon.size)
        draw = ImageDraw.Draw(alpha)
        if mode == 'ios':
            draw.rounded_rectangle((0, 0, 199, 199), radius=44, fill=255)
        else:
            draw.ellipse((0, 0, 199, 199), fill=255)
        review.paste(icon, (x, 30), alpha)
        ImageDraw.Draw(review).text((x, 245), label, fill='#183A36')
    (ROOT / 'build' / 'icon-review').mkdir(parents=True, exist_ok=True)
    review.save(ROOT / 'build' / 'icon-review' / 'platform-icons.png')
    # Validate generated files and the existing iOS catalog mappings.
    for entry in catalog['images']:
        image = Image.open(IOS / entry['filename'])
        size = round(float(entry['size'].split('x')[0]) * float(entry['scale'][:-1]))
        assert image.size == (size, size) and image.mode == 'RGB'
    for file in RES.rglob('ic_launcher*.xml'):
        ElementTree.parse(file)
    print('Generated 15 iOS PNGs, 5 Android PNGs, adaptive/themed vectors and SVG master.')


if __name__ == '__main__':
    main()
