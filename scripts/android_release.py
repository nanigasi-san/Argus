#!/usr/bin/env python3
"""Publish one verified AAB to production; recover by remote SHA-256, never by number alone."""
import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request

ROOT = Path('build/android-release')
PACKAGE = 'com.argus.orienteering'
REQUIRED = ('ANDROID_KEYSTORE_BASE64', 'ANDROID_KEY_ALIAS', 'ANDROID_KEY_PASSWORD',
            'ANDROID_STORE_PASSWORD', 'PLAY_SERVICE_ACCOUNT_JSON')


def credentials():
    missing = [name for name in REQUIRED if not os.environ.get(name)]
    if missing:
        raise ValueError('Missing Android release secrets: ' + ', '.join(missing))


def expected():
    return {'source_sha': os.environ['RELEASE_SHA'], 'version': os.environ['RELEASE_VERSION'],
            'build_number': os.environ['RELEASE_BUILD'], 'run_id': os.environ['GITHUB_RUN_ID'],
            'package': PACKAGE, 'track': 'production', 'release_status': 'completed'}


def receipt():
    path = ROOT / 'receipt.json'
    data = json.loads(path.read_text()) if path.exists() else expected()
    if any(data.get(k) != v for k, v in expected().items()):
        raise ValueError('Android receipt does not match this release')
    return data


def save(data, **values):
    data.update(values)
    ROOT.mkdir(parents=True, exist_ok=True)
    path = ROOT / 'receipt.json'
    temporary = path.with_suffix('.tmp')
    temporary.write_text(json.dumps(data, indent=2) + '\n')
    temporary.replace(path)


def install():
    names = REQUIRED[:4]
    if any(not os.environ.get(name) for name in names):
        raise ValueError('Release signing credentials are required')
    key = Path(os.environ['RUNNER_TEMP']) / 'argus-release.jks'
    key.write_bytes(base64.b64decode(os.environ[names[0]], validate=True))
    key.chmod(0o600)
    # Java .properties needs escaping for passwords containing backslashes or spaces.
    def escape(value):
        return ''.join('\\u%04x' % ord(c) if c in '\\:=#! \n\r\t' or ord(c) > 126 else c for c in value)
    props = {'storeFile': str(key), 'storePassword': os.environ['ANDROID_STORE_PASSWORD'],
             'keyAlias': os.environ['ANDROID_KEY_ALIAS'], 'keyPassword': os.environ['ANDROID_KEY_PASSWORD']}
    path = Path('android/key.properties')
    if path.exists():
        raise ValueError('Refusing to overwrite existing signing properties')
    path.write_text(''.join(f'{k}={escape(v)}\n' for k,v in props.items()))
    path.chmod(0o600)


def verify():
    aab = ROOT / 'app-release.aab'
    # Trust the configured upload certificate explicitly so normal self-signed
    # Android keys pass strict verification without ignoring warning exit codes.
    # Unsigned entries, invalid signatures and unrelated signing aliases fail.
    key = Path(os.environ['RUNNER_TEMP']) / 'argus-release.jks'
    result = subprocess.run(['jarsigner', '-J-Duser.language=en', '-verify', '-strict',
                             '-keystore', str(key), '-storepass:env', 'ANDROID_STORE_PASSWORD',
                             str(aab), os.environ['ANDROID_KEY_ALIAS']], capture_output=True, text=True)
    if result.returncode or 'jar verified.' not in result.stdout:
        raise ValueError('AAB JAR signature is invalid or absent')
    env = dict(os.environ, LC_ALL='C')
    def fingerprint(args):
        output = subprocess.check_output(['keytool', '-J-Duser.language=en', *args], env=env, stderr=subprocess.DEVNULL, text=True)
        import re
        matches = re.findall(r'SHA256: ([0-9A-F:]+)', output)
        if len(matches) != 1:
            raise ValueError('Cannot identify one AAB signing certificate')
        return matches[0]
    actual = fingerprint(['-printcert', '-jarfile', str(aab)])
    wanted = fingerprint(['-list', '-v', '-keystore', str(key),
                          '-alias', os.environ['ANDROID_KEY_ALIAS'], '-storepass:env', 'ANDROID_STORE_PASSWORD'])
    if actual != wanted:
        raise ValueError('AAB is not signed by the configured upload key')
    save(receipt(), aab_sha256=hashlib.sha256(aab.read_bytes()).hexdigest(), status='built')


def restore_check():
    data = receipt()
    aab = ROOT / 'app-release.aab'
    reusable = bool(data.get('aab_sha256'))
    if reusable and (not aab.is_file() or hashlib.sha256(aab.read_bytes()).hexdigest() != data['aab_sha256']):
        raise ValueError('Original verified AAB is missing or changed; do not rebuild under the same number')
    save(data)
    with open(os.environ['GITHUB_OUTPUT'], 'a') as output:
        output.write(f'build_required={str(not reusable).lower()}\n')


class PlayError(RuntimeError):
    def __init__(self, status):
        self.status = status
        super().__init__(f'Play request failed: HTTP {status}; inspect Play Console before retrying')


class Play:
    def __init__(self):
        self.account = json.loads(os.environ['PLAY_SERVICE_ACCOUNT_JSON'])
        self.token = None
        self.expires = 0

    def authorize(self):
        if time.time() < self.expires:
            return
        def b64(value):
            return base64.urlsafe_b64encode(value).rstrip(b'=')
        now = int(time.time())
        claims = {'iss': self.account['client_email'], 'scope': 'https://www.googleapis.com/auth/androidpublisher',
                  'aud': 'https://oauth2.googleapis.com/token', 'iat': now, 'exp': now + 3600}
        unsigned = b64(b'{"alg":"RS256","typ":"JWT"}') + b'.' + b64(json.dumps(claims).encode())
        with tempfile.NamedTemporaryFile() as key:
            key.write(self.account['private_key'].encode()); key.flush()
            signature = subprocess.run(['openssl', 'dgst', '-sha256', '-sign', key.name], input=unsigned, capture_output=True, check=True).stdout
        assertion = unsigned + b'.' + b64(signature)
        body = urllib.parse.urlencode({'grant_type': 'urn:ietf:params:oauth:grant-type:jwt-bearer', 'assertion': assertion.decode()}).encode()
        request = urllib.request.Request('https://oauth2.googleapis.com/token', data=body)
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                data = json.load(response)
        except urllib.error.HTTPError as error:
            raise RuntimeError(f'Google token request failed: HTTP {error.code}') from None
        self.token, self.expires = data['access_token'], now + int(data['expires_in']) - 120

    def request(self, path, method='GET', data=None, binary=None):
        self.authorize()
        prefix = 'https://androidpublisher.googleapis.com/'
        url = prefix + ('upload/' if binary is not None else '') + f'androidpublisher/v3/applications/{PACKAGE}/' + path
        body = binary if binary is not None else json.dumps(data).encode() if data is not None else None
        headers = {'Authorization': 'Bearer ' + self.token, 'Content-Type': 'application/octet-stream' if binary is not None else 'application/json'}
        try:
            with urllib.request.urlopen(urllib.request.Request(url, data=body, headers=headers, method=method), timeout=300) as response:
                return json.load(response)
        except urllib.error.HTTPError as error:
            # Never echo API response bodies, tokens, or private signing material.
            raise PlayError(error.code) from None


def matching_bundle(bundles, number, digest):
    matches = [bundle for bundle in bundles if str(bundle['versionCode']) == number]
    if not matches:
        return False
    if len(matches) != 1 or matches[0].get('sha256', '').lower() != digest.lower():
        raise ValueError('Existing Play versionCode belongs to a different AAB')
    return True


def publish(play=None):
    data = receipt()
    aab = ROOT / 'app-release.aab'
    digest = hashlib.sha256(aab.read_bytes()).hexdigest()
    if digest != data.get('aab_sha256'):
        raise ValueError('Verified AAB changed')
    play = play or Play()
    # Resume an uncommitted edit when still valid, otherwise inspect a fresh committed snapshot.
    edit = data.get('edit_id')
    fresh = not edit
    if edit:
        try:
            play.request(f'edits/{edit}')
        except PlayError as error:
            if error.status not in (404, 410):
                raise
            edit, fresh = None, True
    if not edit:
        edit = play.request('edits', 'POST', {})['id']
    save(data, edit_id=edit, status='editing')
    bundles = play.request(f'edits/{edit}/bundles').get('bundles', [])
    exists = matching_bundle(bundles, data['build_number'], digest)
    tracks = play.request(f'edits/{edit}/tracks').get('tracks', [])
    production = next((track for track in tracks if track['track'] == 'production'), {'releases': []})
    own = [release for release in production.get('releases', []) if release.get('versionCodes') == [data['build_number']]]
    if fresh and exists and len(own) == 1 and own[0]['status'] == 'completed':
        save(data, status='production_committed', publication='Check Play Console review / managed publishing status')
        return
    # Do not overwrite another draft / staged rollout, or roll a track back to an older build.
    for release in production.get('releases', []):
        if release['status'] != 'completed' and release not in own:
            raise ValueError('Another production draft or rollout exists; resolve it in Play Console')
        if any(int(code) >= int(data['build_number']) for code in release.get('versionCodes', [])) and release not in own:
            raise ValueError('Refusing to replace same/newer production release')
    if not exists:
        if any(int(bundle['versionCode']) >= int(data['build_number']) for bundle in bundles):
            raise ValueError('Build number is not above previously uploaded bundles')
        save(data, status='uploading')
        uploaded = play.request(f'edits/{edit}/bundles?uploadType=media', 'POST', binary=aab.read_bytes())
        if not matching_bundle([uploaded], data['build_number'], digest):
            raise ValueError('Uploaded bundle number differs from release number')
    notes = Path(f'docs/app_store/releases/{data["version"]}/ja-JP.txt').read_text().strip()
    if not notes or len(notes) > 500:
        raise ValueError('Google Play release notes must be 1..500 characters')
    desired = {'track': 'production', 'releases': [{'name': f'Argus {data["version"]} ({data["build_number"]})',
               'versionCodes': [data['build_number']], 'status': 'completed',
               'releaseNotes': [{'language': 'ja-JP', 'text': notes}], 'inAppUpdatePriority': 2}]}
    play.request(f'edits/{edit}/tracks/production', 'PUT', desired)
    # Read back the edit before committing any public release request.
    actual = play.request(f'edits/{edit}/tracks/production')
    if actual.get('track') != 'production' or len(actual.get('releases', [])) != 1 or any(actual['releases'][0].get(k) != v for k, v in desired['releases'][0].items()):
        raise ValueError('Play release differs from the requested production release')
    play.request(f'edits/{edit}:validate', 'POST', {})
    save(data, status='committing')
    # Latest-wins release policy: cancel changes already in review and submit this
    # fully validated production edit instead.
    play.request(f'edits/{edit}:commit?changesNotSentForReview=false&changesInReviewBehavior=CANCEL_IN_REVIEW_AND_SUBMIT', 'POST', {})
    save(data, status='production_committed', publication='Check Play Console review / managed publishing status')
    print('Production release committed; Google review and managed publishing may delay availability')


def cleanup():
    Path('android/key.properties').unlink(missing_ok=True)
    (Path(os.environ['RUNNER_TEMP']) / 'argus-release.jks').unlink(missing_ok=True)


def summary():
    with open(os.environ['GITHUB_STEP_SUMMARY'], 'a') as output:
        output.write('## Android production release\n\n```json\n' + json.dumps(receipt(), indent=2) + '\n```\n')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('action', choices=('credentials', 'install', 'verify', 'restore_check', 'publish', 'cleanup', 'summary'))
    globals()[parser.parse_args().action]()
