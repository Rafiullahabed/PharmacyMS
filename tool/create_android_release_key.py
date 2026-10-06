"""Create a first Android release key locally; never upload or overwrite keys."""

import argparse
import json
import os
from pathlib import Path
import secrets
import shutil
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--keytool', default=shutil.which('keytool'))
    args = parser.parse_args()
    if not args.keytool:
        parser.error('Pass --keytool with the Java JDK keytool executable path.')

    root = Path(__file__).resolve().parents[1]
    private = root / '.signing'
    keystore = private / 'pharmacy-release.jks'
    credentials = private / 'pharmacy-release.credentials.json'
    properties = root / 'android' / 'key.properties'
    if any(path.exists() for path in (keystore, credentials, properties)):
        raise SystemExit('Signing files already exist. Reuse them; no files were overwritten.')

    private.mkdir(mode=0o700, exist_ok=True)
    values = {
        'codemagic_reference': 'pharmacy_release',
        'keystore_file': str(keystore),
        'key_alias': 'pharmacy_release',
        'keystore_password': secrets.token_urlsafe(32),
        'key_password': secrets.token_urlsafe(32),
    }
    # Save passwords privately before invoking keytool so a later I/O failure
    # cannot leave an unrecoverable keystore. Contents are never printed.
    with credentials.open('x', encoding='utf-8') as output:
        output.write(json.dumps(values, indent=2) + '\n')
    credentials.chmod(0o600)
    environment = dict(os.environ)
    environment['PHARMACY_STORE_PASSWORD'] = values['keystore_password']
    environment['PHARMACY_KEY_PASSWORD'] = values['key_password']
    subprocess.run([
        args.keytool, '-genkeypair', '-noprompt', '-storetype', 'JKS',
        '-keystore', str(keystore), '-alias', values['key_alias'],
        '-keyalg', 'RSA', '-keysize', '3072', '-validity', '10000',
        '-dname', 'CN=Pharmacy Companion',
        '-storepass:env', 'PHARMACY_STORE_PASSWORD',
        '-keypass:env', 'PHARMACY_KEY_PASSWORD',
    ], env=environment, check=True, capture_output=True)
    keystore.chmod(0o600)
    with properties.open('x', encoding='utf-8') as output:
        output.write(
            f'storeFile={keystore.as_posix()}\n'
            f'storePassword={values["keystore_password"]}\n'
            f'keyAlias={values["key_alias"]}\n'
            f'keyPassword={values["key_password"]}\n'
        )
    properties.chmod(0o600)
    print(f'Release keystore created: {keystore}')
    print(f'Private Codemagic upload details: {credentials}')
    print('Local signing configured. Back up the keystore and credentials securely.')


if __name__ == '__main__':
    main()
