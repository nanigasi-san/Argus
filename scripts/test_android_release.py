import hashlib
import json
import os
from pathlib import Path
import tempfile
import subprocess
import unittest
import zipfile
from unittest.mock import patch
import android_release as release


class FakePlay:
    def __init__(self, bundles=None, releases=None, fail_commit=False, in_review=False):
        self.bundles = bundles or []
        self.track = {'track': 'production', 'releases': releases or []}
        self.calls = []
        self.valid_edit = False
        self.fail_commit = fail_commit
        self.in_review = in_review
        self.review_cancelled = False

    def request(self, path, method='GET', data=None, binary=None):
        self.calls.append((path, method))
        if path == 'edits':
            self.valid_edit = True
            return {'id': 'edit'}
        if path == 'edits/edit':
            if not self.valid_edit:
                raise release.PlayError(404)
            return {'id': 'edit'}
        if path.endswith('/bundles'):
            return {'bundles': self.bundles}
        if path.endswith('/tracks'):
            return {'tracks': [self.track]}
        if 'uploadType' in path:
            bundle = {'versionCode': 1011, 'sha256': hashlib.sha256(binary).hexdigest()}
            self.bundles.append(bundle)
            return bundle
        if path.endswith('/tracks/production'):
            if method == 'PUT':
                self.track = data
            return self.track
        if ':validate' in path:
            return {}
        if ':commit' in path:
            if self.in_review:
                if 'changesInReviewBehavior=ERROR_IF_IN_REVIEW' in path:
                    raise release.PlayError(400)
                if 'changesInReviewBehavior=CANCEL_IN_REVIEW_AND_SUBMIT' in path:
                    self.review_cancelled = True
            self.valid_edit = False
            if self.fail_commit:
                self.fail_commit = False
                raise TimeoutError('Response lost after commit')
            return {'id': 'edit'}
        raise AssertionError(path)


class AndroidReleaseTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.previous = Path.cwd()
        os.chdir(self.temporary.name)
        self.env = patch.dict(os.environ, {'RELEASE_SHA':'sha', 'RELEASE_VERSION':'0.9.0', 'RELEASE_BUILD':'1011', 'GITHUB_RUN_ID':'run'})
        self.env.start()
        release.ROOT.mkdir(parents=True)
        self.aab = release.ROOT / 'app-release.aab'
        self.aab.write_bytes(b'verified AAB')
        self.digest = hashlib.sha256(self.aab.read_bytes()).hexdigest()
        release.save(release.receipt(), aab_sha256=self.digest, status='built')
        notes = Path('docs/app_store/releases/0.9.0/ja-JP.txt')
        notes.parent.mkdir(parents=True)
        notes.write_text('更新内容')

    def tearDown(self):
        self.env.stop()
        os.chdir(self.previous)
        self.temporary.cleanup()

    def test_new_release_checks_hash_then_commits_production(self):
        play = FakePlay()
        release.publish(play)
        self.assertEqual(play.track['releases'][0]['status'], 'completed')
        self.assertEqual(play.track['releases'][0]['versionCodes'], ['1011'])
        self.assertEqual(release.receipt()['status'], 'production_committed')
        self.assertEqual(play.calls[-2:], [('edits/edit:validate','POST'), ('edits/edit:commit?changesNotSentForReview=false&changesInReviewBehavior=CANCEL_IN_REVIEW_AND_SUBMIT','POST')])

    def test_existing_review_is_cancelled_and_latest_release_is_submitted(self):
        play = FakePlay(in_review=True)
        release.publish(play)
        self.assertTrue(play.review_cancelled)
        self.assertFalse(play.valid_edit)
        self.assertEqual(release.receipt()['status'], 'production_committed')
        self.assertEqual(sum('uploadType' in path for path, _ in play.calls), 1)

    def signed_archive(self):
        self.env_for_signing = patch.dict(os.environ, {
            'RUNNER_TEMP': self.temporary.name, 'ANDROID_KEY_ALIAS': 'test-upload',
            'ANDROID_STORE_PASSWORD': 'temporary-test-password'})
        self.env_for_signing.start()
        self.addCleanup(self.env_for_signing.stop)
        key = Path(self.temporary.name) / 'argus-release.jks'
        subprocess.run(['keytool', '-genkeypair', '-alias', 'test-upload', '-keyalg', 'RSA',
                        '-keystore', str(key), '-storepass:env', 'ANDROID_STORE_PASSWORD',
                        '-dname', 'CN=LocalCDVerification', '-validity', '365'],
                       check=True, capture_output=True)
        with zipfile.ZipFile(self.aab, 'w') as archive:
            archive.writestr('base/assets/payload.txt', 'signed content')
        subprocess.run(['jarsigner', '-keystore', str(key), '-storepass:env',
                        'ANDROID_STORE_PASSWORD', str(self.aab), 'test-upload'],
                       check=True, capture_output=True)

    def test_real_self_signed_upload_certificate_is_accepted(self):
        self.signed_archive()
        release.verify()
        self.assertEqual(release.receipt()['aab_sha256'], hashlib.sha256(self.aab.read_bytes()).hexdigest())

    def test_real_unsigned_entry_appended_after_signing_is_rejected(self):
        self.signed_archive()
        with zipfile.ZipFile(self.aab, 'a') as archive:
            archive.writestr('base/assets/unsigned.txt', 'not signed')
        with self.assertRaises(ValueError):
            release.verify()
        self.assertEqual(release.receipt()['aab_sha256'], self.digest)

    def test_real_modified_signed_entry_is_rejected(self):
        self.signed_archive()
        with zipfile.ZipFile(self.aab) as archive:
            entries = {entry.filename: archive.read(entry) for entry in archive.infolist()}
        entries['base/assets/payload.txt'] = b'tampered content'
        with zipfile.ZipFile(self.aab, 'w') as archive:
            for name, content in entries.items():
                archive.writestr(name, content)
        with self.assertRaises(ValueError):
            release.verify()
        self.assertEqual(release.receipt()['aab_sha256'], self.digest)

    def test_commit_response_loss_resumes_without_upload_or_second_commit(self):
        play = FakePlay(fail_commit=True)
        with self.assertRaises(TimeoutError):
            release.publish(play)
        release.publish(play)
        self.assertEqual(sum('uploadType' in p for p, _ in play.calls), 1)
        self.assertEqual(sum(':commit' in p for p, _ in play.calls), 1)
        self.assertEqual(release.receipt()['status'], 'production_committed')

    def test_existing_number_with_different_hash_never_updates_track(self):
        play = FakePlay(bundles=[{'versionCode':1011, 'sha256':'0'*64}])
        with self.assertRaises(ValueError):
            release.publish(play)
        self.assertFalse(any(m == 'PUT' or ':commit' in p for p,m in play.calls))

    def test_other_draft_rollout_or_newer_production_is_preserved(self):
        for status, number in [('draft','1010'),('inProgress','1010'),('completed','1012')]:
            with self.subTest(status=status):
                play = FakePlay(releases=[{'status':status,'versionCodes':[number]}])
                with self.assertRaises(ValueError):
                    release.publish(play)
                self.assertFalse(any(m == 'PUT' or ':commit' in p for p,m in play.calls))

    def test_changed_artifact_is_rejected_before_contacting_play(self):
        self.aab.write_bytes(b'changed')
        play = FakePlay()
        with self.assertRaises(ValueError):
            release.publish(play)
        self.assertEqual(play.calls, [])

    def test_receipt_from_other_source_is_rejected(self):
        data = release.receipt()
        release.save(data, source_sha='other')
        with self.assertRaises(ValueError):
            release.receipt()

    def test_missing_credentials_fail_closed(self):
        with patch.dict(os.environ, {}, clear=True):
            with self.assertRaises(ValueError):
                release.credentials()

    def test_missing_original_aab_does_not_rebuild_on_rerun(self):
        self.aab.unlink()
        with self.assertRaises(ValueError):
            release.restore_check()

    def test_resume_uncommitted_edit_still_commits(self):
        play = FakePlay(bundles=[{'versionCode':1011,'sha256':self.digest}],
                        releases=[{'versionCodes':['1011'],'status':'completed'}])
        play.valid_edit = True
        release.save(release.receipt(), edit_id='edit', status='committing')
        release.publish(play)
        self.assertTrue(any(':commit' in p for p,_ in play.calls))
        self.assertFalse(any('uploadType' in p for p,_ in play.calls))


if __name__ == '__main__':
    unittest.main()
