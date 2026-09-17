import copy
import json
from datetime import datetime, timedelta
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from ios_release_config import CHECKS, WORKFLOWS, check_status, resolve, verify_main_workflows, gate
from ios_release_signing import cleanup, validate_ipa_info, validate_profile


class ReleaseGateTests(unittest.TestCase):
    def test_exact_tag_and_android_style_number(self):
        self.assertEqual(resolve('v0.9.0', '1', '1010'), ('0.9.0', '1011'))
        for tag in ('v0.9.0-beta', 'v0.9', 'v0.9.0/branch', '0.9.0'):
            with self.assertRaises(ValueError):
                resolve(tag, 1, '1010')
        for offset in ('', '-1', '10000', 'one'):
            with self.assertRaises(ValueError):
                resolve('v0.9.0', 1, offset)

    def checks(self):
        return [dict(id=i + 1, name=name, head_sha='expected', status='completed',
                     conclusion='success', app={'slug': 'github-actions'}) for i, name in enumerate(CHECKS)]

    def test_all_checks_exact_sha_and_provider(self):
        checks = self.checks()
        self.assertEqual(check_status(checks, 'expected'), [])
        checks[0]['head_sha'] = 'other'
        checks[1]['app']['slug'] = 'untrusted'
        self.assertEqual(check_status(checks, 'expected'), list(CHECKS[:2]))

    def test_newer_failure_never_uses_old_success(self):
        checks = self.checks()
        checks.append(dict(checks[0], id=50, conclusion='failure'))
        with self.assertRaisesRegex(ValueError, 'Flutter Tests'):
            check_status(checks, 'expected')
        checks[-1].update(status='in_progress', conclusion=None)
        self.assertEqual(check_status(checks, 'expected'), ['Flutter Tests'])

    def test_main_workflows_reject_same_name_checks_from_other_events_or_paths(self):
        def answer(endpoint):
            name = endpoint.split('/workflows/')[1].split('/')[0]
            return {'workflow_runs': [{'head_sha':'sha', 'head_branch':'main', 'event':'push',
                    'path':'.github/workflows/' + name, 'run_number':1, 'run_attempt':1,
                    'status':'completed', 'conclusion':'success'}]}
        with patch('ios_release_config.gh_json', side_effect=answer):
            self.assertTrue(verify_main_workflows('owner/repo', 'sha'))
        for mutation in ({'event':'pull_request'}, {'head_branch':'feature'}, {'path':'fake.yml'},
                         {'head_sha':'other'}, {'conclusion':'failure'}, {'status':'in_progress'}):
            def bad_answer(endpoint):
                result = answer(endpoint)
                result['workflow_runs'][0].update(mutation)
                return result
            with self.subTest(mutation=mutation), patch('ios_release_config.gh_json', side_effect=bad_answer):
                self.assertFalse(verify_main_workflows('owner/repo', 'sha'))

    def test_manual_dispatch_cannot_enter_either_release_gate(self):
        for platform in ('android', 'ios'):
            with patch.dict('os.environ', {'GITHUB_EVENT_NAME':'workflow_dispatch', 'GITHUB_REF_TYPE':'branch'}):
                with self.assertRaisesRegex(ValueError, 'Only tag pushes'):
                    gate(0, platform)

    def test_android_build_number_must_not_use_missing_offset(self):
        self.assertEqual(resolve('v0.9.0', 6, '1005', 'android'), ('0.9.0', '1011'))
        with self.assertRaises(ValueError):
            resolve('v0.9.0', 6, '', 'android')
        with self.assertRaises(ValueError):
            resolve('v0.9.0', 1, '2100000000', 'android')


class SigningVerificationTests(unittest.TestCase):
    def test_cleanup_removes_secrets_even_when_keychain_restore_fails(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary) / 'signing'
            directory.mkdir()
            (directory / 'original-keychains.json').write_text(json.dumps(['original.keychain-db']))
            (directory / 'release.keychain-db').touch()
            (directory / 'distribution.p12').write_bytes(b'private')
            profile = Path(temporary) / 'installed.mobileprovision'
            profile.touch()
            (directory / 'installed-profile.txt').write_text(str(profile))
            with patch('ios_release_signing.signing_dir', return_value=directory), \
                 patch('ios_release_signing.run', side_effect=[RuntimeError('restore failed'), b'']) as command:
                with self.assertRaisesRegex(RuntimeError, 'restore failed'):
                    cleanup()
            self.assertEqual(command.call_count, 2)
            self.assertFalse(directory.exists())
            self.assertFalse(profile.exists())

    def profile(self):
        return {'ExpirationDate': datetime.now() + timedelta(days=20),
                'TeamIdentifier': ['TEAM'], 'DeveloperCertificates': [b'certificate'],
                'Entitlements': {'application-identifier': 'TEAM.com.argus',
                                 'get-task-allow': False, 'beta-reports-active': True,
                                 'com.apple.developer.usernotifications.time-sensitive': True}}

    def test_profile_rejects_development_expired_and_other_identity(self):
        profile = self.profile()
        validate_profile(profile, 'TEAM', 'com.argus')
        for mutation in ({'ExpirationDate': datetime.now() - timedelta(days=1)},
                         {'ProvisionedDevices': ['device']}, {'TeamIdentifier': ['OTHER']}):
            candidate = copy.deepcopy(profile)
            candidate.update(mutation)
            with self.assertRaises(ValueError):
                validate_profile(candidate, 'TEAM', 'com.argus')
        with self.assertRaises(ValueError):
            validate_profile(profile, 'TEAM', 'com.argus', {'WRONG_CERT'})
        profile['Entitlements']['get-task-allow'] = True
        with self.assertRaises(ValueError):
            validate_profile(profile, 'TEAM', 'com.argus')

    def test_final_ipa_rejects_wrong_build_or_missing_capability(self):
        info = {'CFBundleIdentifier': 'com.argus', 'CFBundleShortVersionString': '0.9.0',
                'CFBundleVersion': '1011', 'MinimumOSVersion': '15.0',
                'UIBackgroundModes': ['audio', 'location'], 'ITSAppUsesNonExemptEncryption': False}
        ent = {'application-identifier': 'TEAM.com.argus', 'com.apple.developer.team-identifier': 'TEAM',
               'get-task-allow': False, 'com.apple.developer.usernotifications.time-sensitive': True}
        validate_ipa_info(info, ent, '0.9.0', '1011', 'TEAM', 'com.argus')
        with self.assertRaises(ValueError):
            validate_ipa_info(info, ent, '0.9.0', '1012', 'TEAM', 'com.argus')
        ent['com.apple.developer.usernotifications.time-sensitive'] = False
        with self.assertRaises(ValueError):
            validate_ipa_info(info, ent, '0.9.0', '1011', 'TEAM', 'com.argus')


if __name__ == '__main__':
    unittest.main()
