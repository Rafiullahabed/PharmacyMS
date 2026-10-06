"""Package mobile Flutter source and an already verified debug APK; no build/publish."""
from pathlib import Path
import hashlib
import json
import zipfile
import shutil

root = Path(__file__).resolve().parents[1]
version_line = next(line for line in (root / 'pubspec.yaml').read_text().splitlines()
                    if line.startswith('version:'))
version = version_line.split(':', 1)[1].strip()
delivery = root / 'build' / 'delivery'
delivery.mkdir(parents=True, exist_ok=True)
source = delivery / f'pharmacy-companion-{version}-source.zip'
apk_source = root / 'build' / 'app' / 'outputs' / 'flutter-apk' / 'app-debug.apk'
if not apk_source.is_file():
    raise SystemExit('Build and verify the normal lib/main.dart debug APK first.')
apk = delivery / f'pharmacy-companion-{version}-debug.apk'
shutil.copy2(apk_source, apk)

folders = ['lib', 'test', 'integration_test', 'tool', 'assets', 'docs',
           'explainations', 'android', 'ios', 'linux', 'macos', 'windows', 'web']
files = ['pubspec.yaml', 'pubspec.lock', 'analysis_options.yaml', 'README.md',
         'IMPLEMENTATION_STATUS.md', '.metadata', '.gitignore']
excluded = {'.gradle', '.dart_tool', 'build', '.cxx', '.symlinks', 'ephemeral',
            'Pods', 'DerivedData', '__pycache__'}
generated = {'local.properties', 'Generated.xcconfig', 'flutter_export_environment.sh',
             'GeneratedPluginRegistrant.java', 'key.properties'}
paths = [root / file for file in files]
for folder in folders:
    paths.extend(path for path in (root / folder).rglob('*') if path.is_file()
                 and not (excluded & set(path.relative_to(root).parts))
                 and path.name not in generated
                 and path.suffix.lower() not in {'.jks', '.keystore', '.pyc'})
with zipfile.ZipFile(source, 'w', zipfile.ZIP_DEFLATED) as archive:
    for path in sorted(set(paths)):
        if path.is_file():
            archive.write(path, path.relative_to(root).as_posix())
    count = len(archive.namelist())

def info(path):
    return {'filename': path.name, 'bytes': path.stat().st_size,
            'sha256': hashlib.file_digest(path.open('rb'), 'sha256').hexdigest()}

manifest = {'app_version': version, 'database_schema': 5, 'backup_format': 1,
            'build_type': 'debug; development key, not a signed release',
            'source_files': count, 'artifacts': [info(source), info(apk)]}
(delivery / 'SHA256.json').write_text(json.dumps(manifest, indent=2) + '\n')
print(json.dumps(manifest, indent=2))
