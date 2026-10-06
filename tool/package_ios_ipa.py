"""Package a compiled iPhone app for personal signing; this does not sign it."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import stat
import tempfile
import zipfile


def package_ipa(app: Path, output: Path) -> dict:
    app = app.resolve(strict=True)
    output = output.resolve()
    if app.suffix != '.app' or not app.is_dir():
        raise ValueError('Input must be a compiled .app directory.')
    if output.suffix != '.ipa' or output.is_relative_to(app):
        raise ValueError('Output must be an .ipa outside the app bundle.')
    with (app / 'Info.plist').open('rb') as source:
        info = plistlib.load(source)
    if info.get('CFBundleSupportedPlatforms') != ['iPhoneOS']:
        raise ValueError('An iPhone device build is required; simulator builds cannot be installed.')
    executable = info.get('CFBundleExecutable', '')
    if not executable or Path(executable).name != executable or '/' in executable or '\\' in executable:
        raise ValueError('The compiled bundle has no valid executable name.')
    required = [app / executable, app / 'Frameworks/App.framework/App',
                app / 'Frameworks/Flutter.framework/Flutter']
    mach_o_magic = {b'\xcf\xfa\xed\xfe', b'\xfe\xed\xfa\xcf',
                    b'\xca\xfe\xba\xbe', b'\xbe\xba\xfe\xca',
                    b'\xca\xfe\xba\xbf', b'\xbf\xba\xfe\xca'}
    for binary in required:
        with binary.open('rb') as source:
            if source.read(4) not in mach_o_magic:
                raise ValueError(f'Not a compiled Mach-O binary: {binary.relative_to(app)}')
    paths = [app, *sorted(app.rglob('*'))]
    for path in paths:
        if path.is_symlink() and not path.resolve(strict=True).is_relative_to(app):
            raise ValueError('App bundle contains a symlink outside the bundle.')
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(dir=output.parent, suffix='.ipa.tmp', delete=False) as temporary:
        staged = Path(temporary.name)
    try:
        with zipfile.ZipFile(staged, 'w', zipfile.ZIP_DEFLATED) as archive:
            for path in paths:
                name = f'Payload/{app.name}'
                if path != app:
                    name += '/' + path.relative_to(app).as_posix()
                if path.is_symlink():
                    entry = zipfile.ZipInfo(name)
                    entry.create_system = 3
                    entry.external_attr = (stat.S_IFLNK | 0o777) << 16
                    archive.writestr(entry, os.readlink(path).encode('utf-8'))
                else:
                    archive.write(path, name)
        with zipfile.ZipFile(staged) as archive:
            if archive.testzip() is not None:
                raise ValueError('IPA ZIP integrity check failed.')
        os.replace(staged, output)
    finally:
        staged.unlink(missing_ok=True)
    metadata = {
        'filename': output.name,
        'sha256': hashlib.sha256(output.read_bytes()).hexdigest(),
        'bytes': output.stat().st_size,
        'bundle_id': info['CFBundleIdentifier'],
        'version': info['CFBundleShortVersionString'],
        'build_number': info['CFBundleVersion'],
        'minimum_ios': info.get('MinimumOSVersion'),
        'signing': 'Unsigned build; must be signed before iPhone installation',
        'device_installation_verified': False,
    }
    output.with_suffix('.json').write_text(json.dumps(metadata, indent=2) + '\n', encoding='utf-8')
    return metadata


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', type=Path, default=Path('build/ios/iphoneos/Runner.app'))
    parser.add_argument('--output', type=Path, default=Path('build/ios/ipa/pharmacy-companion-unsigned.ipa'))
    args = parser.parse_args()
    print(json.dumps(package_ipa(args.app, args.output), indent=2))


if __name__ == '__main__':
    main()
