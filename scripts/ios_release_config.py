#!/usr/bin/env python3
"""Resolve a trusted release tag and require successful checks for its exact commit."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import time

CHECKS = ('Flutter Tests', 'Android Build', 'iOS Build', 'Android E2E', 'iOS E2E')


def command(*args):
    return subprocess.check_output(args, text=True).strip()


def resolve(tag, run_number, offset, platform="ios"):
    if not re.fullmatch(r'v[0-9]+\.[0-9]+\.[0-9]+', tag):
        raise ValueError('Release tag must be vX.Y.Z')
    if not re.fullmatch(r'[0-9]+', str(offset)) or int(run_number) < 1:
        raise ValueError('Set the platform build-number offset and a positive run number')
    number = int(run_number) + int(offset)
    # CFBundleVersion: first component is at most four digits.
    if not 1 <= number <= (9999 if platform == 'ios' else 2100000000):
        raise ValueError('Build number exceeds platform limit')
    return tag[1:], str(number)


def check_status(checks, sha):
    """Use the newest GitHub Actions check of each required name; never accept stale success."""
    missing = []
    for name in CHECKS:
        candidates = [c for c in checks if c['name'] == name and c.get('head_sha') == sha
                      and c.get('app', {}).get('slug') == 'github-actions']
        latest = max(candidates, key=lambda c: c['id'], default=None)
        if latest is None or latest['status'] != 'completed':
            missing.append(name)
        elif latest['conclusion'] != 'success':
            raise ValueError(f'Required check failed: {name} ({latest["conclusion"]})')
    return missing


def gh_json(endpoint):
    return json.loads(command('gh', 'api', endpoint))


def gate(timeout, platform="ios"):
    if os.environ.get("GITHUB_EVENT_NAME") != "push" or os.environ.get("GITHUB_REF_TYPE") != "tag":
        raise ValueError("Only tag pushes may release")
    tag = os.environ['GITHUB_REF_NAME']
    version, build = resolve(tag, os.environ['GITHUB_RUN_NUMBER'],
                             os.environ.get('IOS_RELEASE_BUILD_NUMBER_OFFSET' if platform == 'ios' else 'RELEASE_VERSION_CODE_OFFSET', ''), platform)
    sha = command('git', 'rev-parse', f'refs/tags/{tag}^{{commit}}')
    if sha != command('git', 'rev-parse', 'HEAD'):
        raise ValueError('Checkout does not match tag commit')
    subprocess.run(['git', 'merge-base', '--is-ancestor', sha, 'origin/main'], check=True)
    # Main ancestry includes the reviewed release definition at that commit.
    # Environment/tag access controls must also protect who can push release tags.
    repo = os.environ['GITHUB_REPOSITORY']
    deadline = time.monotonic() + timeout
    while True:
        checks = []
        page = 1
        while True:
            data = gh_json(f'repos/{repo}/commits/{sha}/check-runs?per_page=100&page={page}')
            checks.extend(data['check_runs'])
            if len(data['check_runs']) < 100:
                break
            page += 1
        missing = check_status(checks, sha)
        if not missing and verify_main_workflows(repo, sha):
            break
        if time.monotonic() >= deadline:
            raise ValueError('Required main checks missing/pending: ' + ', '.join(missing or WORKFLOWS))
        print('Waiting for main CI: ' + ', '.join(missing or WORKFLOWS), flush=True)
        time.sleep(30)
    # Require reviewed release notes instead of guessing changes during a tag run.
    release_dir = Path('docs/app_store/releases') / version
    for filename in ('ja-JP.txt', 'review_notes.md'):
        path = release_dir / filename
        if not path.is_file() or not path.read_text().strip():
            raise ValueError(f'Prepare {path} before tagging')
        limit = 500 if platform == 'android' and filename == 'ja-JP.txt' else 3900
        if len(path.read_text().strip()) > limit:
            raise ValueError(f'{path} exceeds {limit} characters')
    with open(os.environ['GITHUB_OUTPUT'], 'a') as out:
        out.write(f'version={version}\nbuild={build}\nsha={sha}\n')
    print(f'Release {tag}, build {build}, source {sha}')


WORKFLOWS = {
    'Flutter Tests': '.github/workflows/flutter_tests.yml',
    'Android Build': '.github/workflows/android_build.yml',
    'iOS Build': '.github/workflows/ios_build.yml',
    'Android E2E': '.github/workflows/android_e2e.yml',
    'iOS E2E': '.github/workflows/ios_e2e.yml',
}


def verify_main_workflows(repo, sha):
    # A same-name check from an arbitrary workflow is not proof of main CI.
    for name, path in WORKFLOWS.items():
        data = gh_json(f'repos/{repo}/actions/workflows/{Path(path).name}/runs?head_sha={sha}&event=push&branch=main&per_page=100')
        runs = [run for run in data['workflow_runs'] if run['head_sha'] == sha
                and run['head_branch'] == 'main' and run['event'] == 'push'
                and run['path'] == path]
        latest = max(runs, key=lambda run: (run['run_number'], run.get('run_attempt', 1)), default=None)
        if not latest or latest['status'] != 'completed' or latest['conclusion'] != 'success':
            return False
    return True


def restore_receipt(platform="ios"):
    """Only restore receipts from earlier attempts of this exact Actions run."""
    repo, run = os.environ['GITHUB_REPOSITORY'], os.environ['GITHUB_RUN_ID']
    attempt = int(os.environ['GITHUB_RUN_ATTEMPT'])
    destination = Path(f'build/{platform}-release')
    destination.mkdir(parents=True, exist_ok=True)
    artifacts = json.loads(command('gh', 'api', '--paginate', '--slurp',
                                  f'repos/{repo}/actions/runs/{run}/artifacts?per_page=100'))
    choices = []
    for page in artifacts:
        for item in page['artifacts']:
            match = re.fullmatch(rf'{platform}-release-(preupload|result)-(\d+)', item['name'])
            if match and int(match[2]) < attempt and not item['expired']:
                choices.append((int(match[2]), match[1] == 'result', item['name']))
    if choices:
        name = max(choices)[2]
        subprocess.run(['gh', 'run', 'download', run, '--repo', repo,
                        '--name', name, '--dir', str(destination)], check=True)
        print(f'Restored receipt from {name}')
    elif attempt > 1:
        if platform == 'android':
            raise ValueError('Previous Android receipt/AAB unavailable; inspect Play before recovery')
        print('No previous receipt: Apple build must not be adopted without provenance')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('action', choices=('gate', 'restore'))
    parser.add_argument('--platform', choices=('ios', 'android'), default='ios')
    parser.add_argument('--timeout', type=int, default=2400)
    args = parser.parse_args()
    if args.action == 'gate':
        gate(args.timeout, args.platform)
    else:
        restore_receipt(args.platform)
