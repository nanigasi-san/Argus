require 'minitest/autorun'
require 'tmpdir'
require_relative 'release_support'

class ReleaseSupportTest < Minitest::Test
  Build = Struct.new(:id, :version, :processing_state)
  Item = Struct.new(:app_store_version)
  Version = Struct.new(:id, :version_string, :app_version_state, :release_type, :build) do
    def get_build; build; end
  end
  Submission = Struct.new(:id, :state)

  class FakeApple < ArgusRelease::AppleRelease
    attr_accessor :fake_build, :fake_versions, :fake_submissions, :fake_items
    def app; self; end
    def id; 'app'; end
    def target_build; fake_build; end
    def versions; fake_versions || []; end
    def submissions; fake_submissions || []; end
    def review_items(submission); fake_items.fetch(submission.id, []); end
    def get_ready_review_submission(platform:); nil; end
  end

  def setup
    @directory = Dir.mktmpdir
    @apple = FakeApple.new(root: @directory, version: '0.9.0', build: '1011', sha: 'source',
                           app_id: 'app', bundle_id: 'com.argus', team: 'TEAM', run_id: 'run')
    @apple.fake_items = {}
  end

  def teardown
    FileUtils.remove_entry(@directory)
  end

  def verified
    @apple.receipt.update('ipa_sha256' => 'a' * 64, 'status' => 'uploaded')
    @apple.fake_build = Build.new('build', '1011', 'VALID')
  end

  def test_existing_build_requires_matching_provenance
    @apple.fake_build = Build.new('build', '1011', 'VALID')
    assert_raises(RuntimeError) { @apple.preflight }
    verified
    assert_equal false, @apple.preflight
  end

  def test_receipt_from_another_source_or_run_cannot_be_adopted
    @apple.receipt.update('source_sha' => 'other')
    assert_raises(RuntimeError) do
      FakeApple.new(root: @directory, version: '0.9.0', build: '1011', sha: 'source',
                    app_id: 'app', bundle_id: 'com.argus', team: 'TEAM', run_id: 'run')
    end
  end

  def test_uncertain_upload_never_reuploads
    @apple.receipt.update('ipa_sha256' => 'a' * 64, 'status' => 'uploading')
    assert_raises(RuntimeError) { @apple.preflight }
  end

  def test_other_active_version_is_not_renamed_or_cancelled
    verified
    @apple.fake_versions = [Version.new('old', '0.8.0', 'WAITING_FOR_REVIEW')]
    assert_raises(RuntimeError) { @apple.preflight }
  end

  def test_other_submission_item_cannot_be_resumed
    verified
    @apple.fake_submissions = [Submission.new('submission', 'READY_FOR_REVIEW')]
    @apple.fake_items['submission'] = [Item.new(Version.new('other', '0.8.0'))]
    assert_raises(RuntimeError) { @apple.preflight }
  end

  def test_uploaded_build_skips_pilot
    verified
    calls = 0
    @apple.upload({}, ->(**_) { calls += 1 })
    assert_equal 0, calls
    assert_equal 'processed', @apple.receipt.data['status']
  end

  def test_submitted_exact_build_is_idempotent_and_does_not_call_deliver
    verified
    version = Version.new('version', '0.9.0', 'WAITING_FOR_REVIEW', 'AFTER_APPROVAL', @apple.fake_build)
    @apple.fake_versions = [version]
    @apple.fake_submissions = [Submission.new('submission', 'WAITING_FOR_REVIEW')]
    @apple.fake_items['submission'] = [Item.new(version)]
    calls = 0
    @apple.submit({}, ->(**_) { calls += 1 })
    assert_equal 0, calls
    assert_equal 'submitted', @apple.receipt.data['status']
    assert_equal 'submission', @apple.receipt.data['submission_id']
  end

  def test_submitted_version_with_other_build_fails
    verified
    @apple.fake_versions = [Version.new('version', '0.9.0', 'WAITING_FOR_REVIEW', 'AFTER_APPROVAL', Build.new('other', '1012', 'VALID'))]
    assert_raises(RuntimeError) { @apple.preflight }
  end
end
