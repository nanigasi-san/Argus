require 'minitest/autorun'
require 'tmpdir'
require 'digest'
require_relative 'release_support'

class ReleaseSupportTest < Minitest::Test
  Build = Struct.new(:id, :version, :processing_state)
  Item = Struct.new(:app_store_version)
  Detail = Struct.new(:contact_first_name, :contact_last_name, :contact_phone, :contact_email,
                      :demo_account_required, :demo_account_name, :demo_account_password, :notes)
  Version = Struct.new(:id, :version_string, :app_version_state, :release_type, :build, :detail) do
    attr_accessor :whats_new, :phased, :test_build
    def get_build; build; end
    def select_build(build_id:)
      raise 'wrong test build' unless test_build.id == build_id
      self.build = test_build
    end
    def fetch_app_store_version_phased_release; phased; end
    def get_app_store_version_localizations; [Struct.new(:locale, :whats_new).new('ja', whats_new)]; end
    def fetch_app_store_review_detail; detail; end
  end
  Submission = Struct.new(:id, :state, :apple) do
    attr_accessor :submit_count
    def add_app_store_version_to_review_items(app_store_version_id:)
      raise 'wrong version' unless apple.target_version.id == app_store_version_id
      apple.fake_items[id] = [Item.new(apple.target_version)]
      apple.target_version.app_version_state = 'READY_FOR_REVIEW'
    end
    def submit_for_review
      self.submit_count = (submit_count || 0) + 1
      self.state = 'WAITING_FOR_REVIEW'
      apple.target_version.app_version_state = 'WAITING_FOR_REVIEW'
    end
  end

  class FakeApple < ArgusRelease::AppleRelease
    attr_accessor :fake_build, :fake_versions, :fake_submissions, :fake_items
    def app; self; end
    def id; 'app'; end
    def target_build; fake_build; end
    def versions; fake_versions || []; end
    def submissions; fake_submissions || []; end
    def review_items(submission); fake_items.fetch(submission.id, []); end
    def get_ready_review_submission(platform:); submissions.find { |s| s.state == 'READY_FOR_REVIEW' }; end
    def create_review_submission(platform:)
      submission = Submission.new('submission', 'READY_FOR_REVIEW', self)
      self.fake_submissions = [submission]
      submission
    end
    def get_edit_app_store_version(platform:); target_version; end
    def optional_relation_present?(version, method); method == :get_app_store_version_phased_release && !!version.phased; end
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

  def test_retry_with_empty_review_detail_inherits_previous_contact_and_login
    previous = Version.new('old', '0.8.0', 'READY_FOR_DISTRIBUTION', nil, nil,
                           Detail.new('First', 'Last', 'Phone', 'Email', true, 'User', 'Password'))
    target = Version.new('new', '0.9.0', 'PREPARE_FOR_SUBMISSION')
    @apple.fake_versions = [previous, target]
    information = @apple.existing_review_information(target)
    assert_equal 'Email', information[:email_address]
    assert_equal 'User', information[:demo_user]
    assert_equal 'Password', information[:demo_password]
  end

  def test_incomplete_target_review_contact_is_not_overwritten
    previous = Version.new('old', '0.8.0', nil, nil, nil,
                           Detail.new('First', 'Last', 'Phone', 'Email', false))
    target = Version.new('new', '0.9.0', nil, nil, nil,
                         Detail.new('First', 'Last', nil, 'Email', false))
    @apple.fake_versions = [previous, target]
    assert_raises(RuntimeError) { @apple.existing_review_information(target) }
  end

  def test_new_upload_uses_only_verified_ipa_and_waits_for_exact_build
    ipa = File.join(@directory, 'build/ios/ipa/ARGUS.ipa')
    FileUtils.mkdir_p(File.dirname(ipa))
    File.write(ipa, 'verified IPA')
    @apple.receipt.update('ipa_sha256' => Digest::SHA256.file(ipa).hexdigest, 'status' => 'built')
    @apple.upload({ key_id: 'key' }, lambda do |**options|
      assert_equal ipa, options[:ipa]
      assert_equal true, options[:skip_submission]
      assert_equal true, options[:skip_waiting_for_build_processing]
      assert_equal 'uploading', @apple.receipt.data['status']
      @apple.fake_build = Build.new('build', '1011', 'VALID')
    end)
    assert_equal 'processed', @apple.receipt.data['status']
    assert_equal 'build', @apple.receipt.data['build_id']
  end

  def test_new_submission_sets_exact_build_notes_and_automatic_release
    verified
    notes = File.join(@directory, 'docs/app_store/releases/0.9.0')
    FileUtils.mkdir_p(notes)
    File.write(File.join(notes, 'ja-JP.txt'), '更新内容')
    File.write(File.join(notes, 'review_notes.md'), '審査メモ')
    previous = Version.new('old', '0.8.0', 'READY_FOR_DISTRIBUTION', nil, nil,
                           Detail.new('First', 'Last', 'Phone', 'Email', false))
    @apple.fake_versions = [previous]
    calls = 0
    @apple.submit({}, lambda do |**options|
      calls += 1
      assert_equal '0.9.0', options[:app_version]
      assert_equal '1011', options[:build_number]
      assert_equal({ 'ja' => '更新内容' }, options[:release_notes])
      assert_equal "ARGUS 0.9.0 (1011)\n\n審査メモ", options[:app_review_information][:notes]
      assert_equal false, options[:submit_for_review]
      assert_equal true, options[:automatic_release]
      assert_equal false, options[:phased_release]
      assert_equal false, options[:reset_ratings]
      version = Version.new('new', '0.9.0', 'PREPARE_FOR_SUBMISSION', 'AFTER_APPROVAL', nil,
                            Detail.new('First', 'Last', 'Phone', 'Email', false, nil, nil, options[:app_review_information][:notes]))
      version.test_build = @apple.fake_build
      version.whats_new = '更新内容'
      @apple.fake_versions << version
    end)
    assert_equal 1, calls
    assert_equal 'submitted', @apple.receipt.data['status']
  end
  def test_external_build_after_archive_is_not_adopted
    @apple.receipt.update('ipa_sha256' => 'a' * 64, 'status' => 'built')
    @apple.fake_build = Build.new('external', '1011', 'VALID')
    assert_raises(RuntimeError) { @apple.upload({}, ->(**_) { flunk('must not upload') }) }
    assert_nil @apple.receipt.data['build_id']
  end

  def test_uncertain_upload_does_not_adopt_external_matching_number
    @apple.receipt.update('ipa_sha256' => 'a' * 64, 'status' => 'uploading')
    @apple.fake_build = Build.new('external', '1011', 'VALID')
    assert_raises(RuntimeError) { @apple.preflight }
  end

  def test_resume_checks_publication_and_metadata_before_submit
    verified
    @apple.receipt.update('build_id' => 'build')
    path = File.join(@directory, 'docs/app_store/releases/0.9.0')
    FileUtils.mkdir_p(path)
    File.write(File.join(path, 'ja-JP.txt'), '更新内容')
    File.write(File.join(path, 'review_notes.md'), '審査メモ')
    detail = Detail.new('First', 'Last', 'Phone', 'Email', false, nil, nil, "ARGUS 0.9.0 (1011)\n\n審査メモ")
    version = Version.new('new', '0.9.0', 'READY_FOR_REVIEW', 'MANUAL', @apple.fake_build, detail)
    version.whats_new = '更新内容'
    @apple.fake_versions = [version]
    draft = Submission.new('draft', 'READY_FOR_REVIEW', @apple)
    @apple.fake_submissions = [draft]
    @apple.fake_items['draft'] = [Item.new(version)]
    assert_raises(RuntimeError) { @apple.submit({}, ->(**_) { flunk('must not deliver') }) }
    assert_nil draft.submit_count
    version.release_type = 'AFTER_APPROVAL'
    version.whats_new = 'Unexpected change'
    assert_raises(RuntimeError) { @apple.submit({}, ->(**_) { flunk('must not deliver') }) }
    assert_nil draft.submit_count
    version.whats_new = '更新内容'
    version.phased = true
    assert_raises(RuntimeError) { @apple.submit({}, ->(**_) { flunk('must not deliver') }) }
    assert_nil draft.submit_count
    version.phased = nil
    @apple.submit({}, ->(**_) { flunk('must not deliver') })
    assert_equal 1, draft.submit_count
    assert_equal 'submitted', @apple.receipt.data['status']
  end
end
