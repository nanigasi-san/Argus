#!/usr/bin/env python3
"""Temporary CI signing setup and verification of the final distributed IPA."""
import argparse
import base64
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import secrets
import shutil
import subprocess
import tempfile
import zipfile

REQUIRED = ('IOS_TEAM_ID', 'ASC_KEY_ID', 'ASC_ISSUER_ID', 'ASC_PRIVATE_KEY_BASE64',
            'IOS_DISTRIBUTION_P12_BASE64', 'IOS_DISTRIBUTION_P12_PASSWORD',
            'IOS_APPSTORE_PROFILE_BASE64')


def run(*args):
    # Never print command arguments: security import receives a private password.
    result = subprocess.run(args, capture_output=True, check=False)
    if result.returncode:
        raise RuntimeError(f'{args[0]} failed (exit {result.returncode}); signing setup could not complete')
    return result.stdout


def validate_profile(profile, team, bundle, cert_hashes=None):
    expiry = profile['ExpirationDate'].replace(tzinfo=timezone.utc)
    ent = profile['Entitlements']
    if expiry <= datetime.now(timezone.utc):
        raise ValueError('App Store profile has expired')
    if profile['TeamIdentifier'] != [team] or ent.get('application-identifier') != f'{team}.{bundle}':
        raise ValueError('Profile Team/Bundle ID mismatch')
    if (ent.get('get-task-allow') is not False or not ent.get('beta-reports-active')
            or 'ProvisionedDevices' in profile or profile.get('ProvisionsAllDevices')):
        raise ValueError('An App Store distribution profile is required')
    if not ent.get('com.apple.developer.usernotifications.time-sensitive'):
        raise ValueError('Profile does not allow Time Sensitive Notifications')
    allowed = {hashlib.sha1(cert).hexdigest().upper() for cert in profile['DeveloperCertificates']}
    if cert_hashes is not None and not allowed.intersection(cert_hashes):
        raise ValueError('Profile does not match a valid imported distribution identity')


def credentials(names=REQUIRED):
    missing = [name for name in names if not os.environ.get(name)]
    if missing:
        raise ValueError('Register required ios-release credentials: ' + ', '.join(missing))


def signing_dir():
    if os.environ.get('GITHUB_ACTIONS') != 'true' or os.environ.get('RUNNER_OS') != 'macOS':
        raise ValueError('Keychain setup/cleanup is restricted to a macOS Actions runner')
    return Path(os.environ['RUNNER_TEMP']) / 'argus-ios-signing'


def install():
    credentials(('IOS_TEAM_ID', 'IOS_DISTRIBUTION_P12_BASE64', 'IOS_DISTRIBUTION_P12_PASSWORD', 'IOS_APPSTORE_PROFILE_BASE64'))
    directory = signing_dir()
    directory.mkdir(mode=0o700, parents=True, exist_ok=True)
    cert = directory / 'distribution.p12'
    profile_path = directory / 'appstore.mobileprovision'
    for name, path in (('IOS_DISTRIBUTION_P12_BASE64', cert), ('IOS_APPSTORE_PROFILE_BASE64', profile_path)):
        path.write_bytes(base64.b64decode(os.environ[name], validate=True))
        path.chmod(0o600)
    profile = plistlib.loads(run('security', 'cms', '-D', '-i', str(profile_path)))
    team, bundle = os.environ['IOS_TEAM_ID'], os.environ['IOS_BUNDLE_ID']
    validate_profile(profile, team, bundle)
    keychain = directory / 'release.keychain-db'
    password = secrets.token_urlsafe(32)
    original = run('security', 'list-keychains', '-d', 'user').decode()
    (directory / 'original-keychains.json').write_text(json.dumps(re.findall(r'"([^"]+)"', original)))
    run('security', 'create-keychain', '-p', password, str(keychain))
    run('security', 'set-keychain-settings', '-lut', '21600', str(keychain))
    run('security', 'unlock-keychain', '-p', password, str(keychain))
    run('security', 'import', str(cert), '-P', os.environ['IOS_DISTRIBUTION_P12_PASSWORD'],
        '-A', '-t', 'cert', '-f', 'pkcs12', '-k', str(keychain))
    run('security', 'set-key-partition-list', '-S', 'apple-tool:,apple:,codesign:',
        '-s', '-k', password, str(keychain))
    original_paths = json.loads((directory / 'original-keychains.json').read_text())
    run('security', 'list-keychains', '-d', 'user', '-s', str(keychain), *original_paths)
    identities = run('security', 'find-identity', '-v', '-p', 'codesigning', str(keychain)).decode()
    cert_hashes = set(re.findall(r'([A-F0-9]{40}) "Apple Distribution:', identities))
    validate_profile(profile, team, bundle, cert_hashes)
    uuid = profile['UUID']
    if not re.fullmatch(r'[A-Fa-f0-9-]{36}', uuid):
        raise ValueError('Invalid profile UUID')
    target = Path.home() / 'Library/MobileDevice/Provisioning Profiles' / f'{uuid}.mobileprovision'
    target.parent.mkdir(parents=True, exist_ok=True)
    if target.exists():
        raise ValueError('Refusing to overwrite an existing provisioning profile')
    shutil.copyfile(profile_path, target)
    (directory / 'installed-profile.txt').write_text(str(target))
    options = {'method': 'app-store-connect', 'destination': 'export',
               'teamID': team, 'signingStyle': 'manual', 'signingCertificate': 'Apple Distribution',
               'provisioningProfiles': {bundle: uuid}, 'manageAppVersionAndBuildNumber': False,
               'testFlightInternalTestingOnly': False, 'stripSwiftSymbols': True, 'uploadSymbols': True}
    options_path = directory / 'ExportOptions.plist'
    options_path.write_bytes(plistlib.dumps(options))
    with open(os.environ['GITHUB_ENV'], 'a') as env:
        env.write(f'IOS_PROFILE_UUID={uuid}\nIOS_EXPORT_OPTIONS={options_path}\n')
    print(f'Installed App Store profile, expires {profile["ExpirationDate"].date()}')


def validate_ipa_info(info, entitlements, version, build, team, bundle):
    if (info.get('CFBundleIdentifier'), info.get('CFBundleShortVersionString'), str(info.get('CFBundleVersion'))) != (bundle, version, build):
        raise ValueError('Final IPA Bundle ID/version/build mismatch')
    if info.get('MinimumOSVersion') != '15.0' or not {'audio', 'location'}.issubset(info.get('UIBackgroundModes', [])):
        raise ValueError('Final IPA minimum iOS/Background Modes mismatch')
    if info.get('ITSAppUsesNonExemptEncryption') is not False:
        raise ValueError('Final IPA export compliance declaration is missing')
    if (entitlements.get('application-identifier') != f'{team}.{bundle}'
            or entitlements.get('com.apple.developer.team-identifier') != team
            or entitlements.get('get-task-allow') is not False
            or not entitlements.get('com.apple.developer.usernotifications.time-sensitive')):
        raise ValueError('Final IPA distribution entitlements mismatch')


def verify(ipa):
    with tempfile.TemporaryDirectory() as directory:
        with zipfile.ZipFile(ipa) as archive:
            # Archive was generated in this job; nevertheless reject traversal paths.
            for name in archive.namelist():
                if name.startswith('/') or '..' in Path(name).parts:
                    raise ValueError('Invalid IPA member path')
            archive.extractall(directory)
        apps = list(Path(directory).glob('Payload/*.app'))
        if len(apps) != 1:
            raise ValueError('Expected one application in IPA')
        app = apps[0]
        run('codesign', '--verify', '--deep', '--strict', str(app))
        ent = plistlib.loads(run('codesign', '-d', '--entitlements', ':-', str(app)))
        info = plistlib.loads((app / 'Info.plist').read_bytes())
        validate_ipa_info(info, ent, os.environ['RELEASE_VERSION'], os.environ['RELEASE_BUILD'],
                          os.environ['IOS_TEAM_ID'], os.environ['IOS_BUNDLE_ID'])
        profile = plistlib.loads(run('security', 'cms', '-D', '-i', str(app / 'embedded.mobileprovision')))
        validate_profile(profile, os.environ['IOS_TEAM_ID'], os.environ['IOS_BUNDLE_ID'])
    receipt_path = Path('build/ios-release/receipt.json')
    receipt = json.loads(receipt_path.read_text())
    receipt.update(ipa_sha256=hashlib.sha256(Path(ipa).read_bytes()).hexdigest(), status='built')
    receipt_path.write_text(json.dumps(receipt, indent=2) + '\n')
    print('IPA signature, version/build, entitlements and Background Modes verified')


def cleanup():
    directory = signing_dir()
    errors = []

    def attempt(*args):
        try:
            run(*args)
        except RuntimeError as error:
            errors.append(str(error))

    keychains = directory / 'original-keychains.json'
    if keychains.exists():
        attempt('security', 'list-keychains', '-d', 'user', '-s', *json.loads(keychains.read_text()))
    keychain = directory / 'release.keychain-db'
    if keychain.exists():
        attempt('security', 'delete-keychain', str(keychain))
    profile_record = directory / 'installed-profile.txt'
    if profile_record.exists():
        Path(profile_record.read_text()).unlink(missing_ok=True)
    shutil.rmtree(directory, ignore_errors=True)
    if errors:
        raise RuntimeError('Signing cleanup failed: ' + '; '.join(errors))


def summary():
    receipt = json.loads(Path('build/ios-release/receipt.json').read_text())
    with open(os.environ['GITHUB_STEP_SUMMARY'], 'a') as output:
        output.write('## iOS release\n\n```json\n' + json.dumps(receipt, indent=2) + '\n```\n')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('action', choices=('credentials', 'install', 'verify', 'cleanup', 'summary'))
    parser.add_argument('--ipa')
    args = parser.parse_args()
    if args.action == 'verify':
        verify(args.ipa)
    else:
        globals()[args.action]()
