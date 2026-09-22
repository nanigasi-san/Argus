require 'json'
require 'fileutils'
require 'time'

module ArgusRelease
  ACCEPTED_STATES = %w[WAITING_FOR_REVIEW IN_REVIEW PENDING_APPLE_RELEASE PROCESSING_FOR_DISTRIBUTION READY_FOR_DISTRIBUTION].freeze
  EDITABLE_STATES = %w[PREPARE_FOR_SUBMISSION DEVELOPER_REJECTED REJECTED METADATA_REJECTED INVALID_BINARY READY_FOR_REVIEW].freeze

  class Receipt
    attr_reader :data

    def initialize(path, expected)
      @path = path
      @data = File.exist?(path) ? JSON.parse(File.read(path)) : expected.merge('status' => 'preflight')
      expected.each do |key, value|
        raise "Receipt #{key} does not match this release" unless @data[key] == value
      end
    end

    def verified_upload?
      @data['ipa_sha256'].to_s.match?(/\A[0-9a-f]{64}\z/) &&
        %w[built uploading uploaded processed submitting submitted].include?(@data['status'])
    end

    def update(values)
      @data.merge!(values)
      @data['updated_at'] = Time.now.utc.iso8601
      FileUtils.mkdir_p(File.dirname(@path))
      temporary = "#{@path}.tmp"
      File.write(temporary, JSON.pretty_generate(@data) + "\n")
      File.rename(temporary, @path)
    end
  end

  def self.assert_submission_items!(items, version_id)
    raise 'Existing review submission contains unrelated items; stop and inspect it' unless
      items.length == 1 && items.first.app_store_version&.id == version_id
  end

  def self.mask_for_actions(value)
    return unless ENV['GITHUB_ACTIONS'] == 'true' && !value.to_s.empty?
    escaped = value.to_s.gsub('%', '%25').gsub("\r", '%0D').gsub("\n", '%0A')
    puts "::add-mask::#{escaped}"
  end

  class AppleRelease
    attr_reader :receipt

    def initialize(root:, version:, build:, sha:, app_id:, bundle_id:, team:, run_id:)
      @root, @version, @build, @sha = root, version, build, sha
      @app_id, @bundle_id = app_id, bundle_id
      @receipt = Receipt.new(File.join(root, 'build/ios-release/receipt.json'), {
        'source_sha' => sha, 'version' => version, 'build_number' => build,
        'app_id' => app_id, 'bundle_id' => bundle_id, 'team_id' => team, 'run_id' => run_id,
        'run_url' => "https://github.com/#{ENV.fetch('GITHUB_REPOSITORY', 'nanigasi-san/Argus')}/actions/runs/#{run_id}",
        'automatic_release' => true, 'phased_release' => false, 'reset_ratings' => false
      })
    end

    def app
      @app ||= Spaceship::ConnectAPI::App.find(@bundle_id)
      raise 'App Store Connect App ID/Bundle ID mismatch' unless @app && @app.id == @app_id
      @app
    end

    def target_build
      builds = Spaceship::ConnectAPI::Build.all(app_id: app.id, version: @version,
                                               build_number: @build, platform: 'IOS')
      raise 'Multiple builds match version/build' if builds.length > 1
      builds.first
    end

    def target_version
      versions.find { |version| version.version_string == @version }
    end

    def versions
      app.get_app_store_versions(filter: { platform: 'IOS' }, includes: 'build')
    end

    def submissions
      app.get_review_submissions(filter: { platform: 'IOS' }, includes: 'items')
    end

    def preflight
      app
      build = target_build
      if build
        raise 'Existing Apple build has no matching receipt; refusing to adopt it' unless receipt.verified_upload?
        assert_owned_build!(build)
        receipt.update('build_id' => build.id)
      end
      all_versions = versions
      all_versions.each do |version|
        next if version.version_string == @version
        if !%w[READY_FOR_DISTRIBUTION REPLACED_WITH_NEW_VERSION].include?(version.app_version_state)
          raise "Another App Store version is active: #{version.version_string} (#{version.app_version_state})"
        end
      end
      version = all_versions.find { |candidate| candidate.version_string == @version }
      if version && !EDITABLE_STATES.include?(version.app_version_state) && !ACCEPTED_STATES.include?(version.app_version_state)
        raise "App Store version requires intervention: #{version.app_version_state}"
      end
      if version && ACCEPTED_STATES.include?(version.app_version_state)
        raise 'Submitted version does not use this build' unless build && version.get_build&.id == build.id
      end
      submissions.each do |submission|
        next if submission.state == 'COMPLETE'
        items = review_items(submission)
        if !items.empty?
          ArgusRelease.assert_submission_items!(items, version&.id)
          raise 'Existing submission has no matching receipt' unless receipt.verified_upload?
        elsif submission.state != 'READY_FOR_REVIEW'
          raise "An unrelated review submission is active: #{submission.state}"
        end
      end
      unless build
        # An earlier attempt may have uploaded a build that is not visible yet.
        # Never retry an upload with an uncertain outcome automatically.
        raise 'Previous upload may still be processing; rerun later after inspecting Apple state' if receipt.verified_upload?
        latest = Spaceship::ConnectAPI::Build.all(app_id: app.id, platform: 'IOS')
        numbers = latest.map(&:version)
        raise 'Existing build number is not a supported integer; verify offset manually' unless numbers.all? { |n| n.match?(/\A[0-9]+\z/) }
        raise 'Candidate build number is already used or lower than an uploaded build; update offset' if numbers.any? { |n| n.to_i >= @build.to_i }
      end
      receipt.update('status' => receipt.data['status'])
      !build
    end

    def review_items(submission)
      Spaceship::ConnectAPI::ReviewSubmissionItem.all(review_submission_id: submission.id,
                                                      includes: 'appStoreVersion')
    end

    def wait_for_build(timeout: 2400, interval: 30)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
      loop do
        build = target_build
        if build
          assert_owned_build!(build)
          raise "Apple build processing failed: #{build.processing_state}" if %w[FAILED INVALID].include?(build.processing_state)
          receipt.update('build_id' => build.id, 'processing_state' => build.processing_state)
          if build.processing_state == 'VALID'
            receipt.update('status' => 'processed')
            return build
          end
        end
        raise 'Apple build processing timed out; rerun to reuse the uploaded build' if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
        puts 'Waiting for uploaded Apple build processing...'
        sleep(interval)
      end
    end

    def upload(api_key, pilot)
      build = target_build
      assert_owned_build!(build) if build
      unless build
        raise 'No verified IPA receipt for upload' unless receipt.verified_upload?
        ipa = Dir[File.join(@root, 'build/ios/ipa/*.ipa')]
        raise 'Expected exactly one verified IPA' unless ipa.length == 1
        require 'digest'
        raise 'IPA changed after verification' unless Digest::SHA256.file(ipa.first).hexdigest == receipt.data['ipa_sha256']
        receipt.update('status' => 'uploading')
        pilot.call(api_key: api_key, app_identifier: @bundle_id, apple_id: @app_id,
                   ipa: ipa.first, skip_submission: true, skip_waiting_for_build_processing: true)
        receipt.update('status' => 'uploaded')
      end
      wait_for_build
    end

    def assert_owned_build!(build)
      raise 'Apple build has no upload provenance; manual investigation required' unless receipt.verified_upload?
      known_id = receipt.data['build_id']
      if known_id
        raise 'Receipt build ID mismatch' unless known_id == build.id
      elsif receipt.data['status'] != 'uploaded'
        # Only a successful upload response may establish a previously unknown Apple ID.
        # built / uploading may refer to an external upload or an ambiguous failure.
        raise 'Unknown Apple build appeared without confirmed upload; refusing to adopt it'
      end
    end

    def submit(api_key, deliver)
      version = target_version
      build = target_build
      raise 'Build is not ready for review' unless build && build.processing_state == 'VALID'
      assert_owned_build!(build)
      if version && ACCEPTED_STATES.include?(version.app_version_state)
        verify_submission(version, build)
        return
      end
      ready = app.get_ready_review_submission(platform: 'IOS')
      items = ready ? review_items(ready) : []
      if !items.empty?
        # deliver 2.240.1 stops on a nonempty draft. Only resume our exact version/build.
        ArgusRelease.assert_submission_items!(items, version&.id)
        raise 'Cannot resume unknown review draft' unless receipt.verified_upload? && version.get_build&.id == build.id
        receipt.update('version_id' => version.id, 'submission_id' => ready.id, 'status' => 'submitting')
        raise "Version is not ready to submit: #{version.app_version_state}" unless version.app_version_state == 'READY_FOR_REVIEW'
        verify_submission_content!(version, build)
        ready.submit_for_review
      else
        notes = File.read(File.join(@root, "docs/app_store/releases/#{@version}/ja-JP.txt")).strip
        review_notes = File.read(File.join(@root, "docs/app_store/releases/#{@version}/review_notes.md")).strip
        review_notes = "ARGUS #{@version} (#{@build})\n\n#{review_notes}"
        raise 'Release notes exceed Apple limit' if notes.length > 4000 || review_notes.length > 4000
        # Prevent deliver's ensure_version! from renaming an unrelated editable version.
        editable = app.get_edit_app_store_version(platform: 'IOS')
        raise 'An unrelated editable version exists' if editable && editable.version_string != @version
        review_information = existing_review_information(version)
        review_information[:notes] = review_notes
        receipt.update('status' => 'submitting')
        deliver.call(api_key: api_key, app_identifier: @bundle_id, app_version: @version,
                     build_number: @build, platform: 'ios', force: true,
                     skip_binary_upload: true, skip_screenshots: true, skip_metadata: false,
                     metadata_path: File.join(@root, 'build/ios-release/metadata'),
                     release_notes: { 'ja' => notes }, app_review_information: review_information,
                     submit_for_review: false, automatic_release: true, phased_release: false,
                     reset_ratings: false, run_precheck_before_submit: false)
        version = target_version
        raise 'Target editable version missing after metadata update' unless version && EDITABLE_STATES.include?(version.app_version_state)
        version.select_build(build_id: build.id)
        version = target_version
        verify_submission_content!(version, build)
        active = submissions.reject { |submission| submission.state == 'COMPLETE' }
        raise 'Another submission appeared during upload' if active.any? { |submission| submission.state != 'READY_FOR_REVIEW' || !review_items(submission).empty? }
        ready = app.get_ready_review_submission(platform: 'IOS') || app.create_review_submission(platform: 'IOS')
        receipt.update('version_id' => version.id, 'submission_id' => ready.id, 'status' => 'submitting')
        ready.add_app_store_version_to_review_items(app_store_version_id: version.id)
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 150
        loop do
          version = target_version
          break if version.app_version_state == 'READY_FOR_REVIEW'
          raise 'Version did not become ready for review; rerun after inspection' if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
          sleep(15)
        end
        ArgusRelease.assert_submission_items!(review_items(ready), version.id)
        verify_submission_content!(version, build)
        ready.submit_for_review
      end
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 300
      loop do
        version = target_version
        if version && ACCEPTED_STATES.include?(version.app_version_state)
          verify_submission(version, build)
          return
        end
        raise 'Submission state not confirmed; inspect receipt and rerun' if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
        sleep(15)
      end
    end

    def optional_relation_present?(version, method)
      # Read raw data: fastlane's model parser can raise on the valid data:null response.
      # Do not treat authorization/network/API errors as 'disabled'.
      response = Spaceship::ConnectAPI.public_send(method, app_store_version_id: version.id)
      raise 'Invalid Apple optional-relation response' unless response.body.is_a?(Hash) && response.body.key?('data')
      !response.body['data'].nil?
    end

    def verify_submission_content!(version, build)
      raise 'Unexpected version or state before submission' unless version && version.version_string == @version && EDITABLE_STATES.include?(version.app_version_state)
      raise 'Selected build changed before submission' unless version.get_build&.id == build.id
      raise 'Release type is not automatic' unless version.release_type == 'AFTER_APPROVAL'
      raise 'Phased release must be disabled before submission' if optional_relation_present?(version, :get_app_store_version_phased_release)
      notes = File.read(File.join(@root, "docs/app_store/releases/#{@version}/ja-JP.txt")).strip
      review_notes = "ARGUS #{@version} (#{@build})\n\n" + File.read(File.join(@root, "docs/app_store/releases/#{@version}/review_notes.md")).strip
      japanese = version.get_app_store_version_localizations.find { |localization| localization.locale == 'ja' }
      raise 'Release notes changed before submission' unless japanese&.whats_new == notes
      detail = version.fetch_app_store_review_detail
      raise 'Review notes changed before submission' unless detail && detail.notes == review_notes
      existing_review_information(version) # Also ensure required contacts / demo login remain complete.
    end

    def existing_review_information(version)
      # A failed deliver attempt can leave a new version without review details.
      # Use the latest previous version only when the target has no detail at all.
      detail = version&.fetch_app_store_review_detail
      unless detail
        source = versions.reject { |candidate| candidate.id == version&.id }
                         .max_by { |candidate| Gem::Version.new(candidate.version_string) }
        raise 'No existing review contact information; configure it in App Store Connect' unless source
        detail = source.fetch_app_store_review_detail
      end
      raise 'Existing review detail missing; configure it in App Store Connect' unless detail
      fields = { first_name: :contact_first_name, last_name: :contact_last_name,
                 phone_number: :contact_phone, email_address: :contact_email }
      information = fields.transform_values { |field| detail.public_send(field) }
      raise 'Existing review contact information is incomplete' if information.values.any? { |value| value.to_s.strip.empty? }
      if detail.demo_account_required
        information[:demo_user] = detail.demo_account_name
        information[:demo_password] = detail.demo_account_password
        raise 'Existing required review login is incomplete' if information[:demo_user].to_s.empty? || information[:demo_password].to_s.empty?
      end
      # deliver prints review contact fields in its configuration summary.
      information.values.each { |value| ArgusRelease.mask_for_actions(value) }
      information
    end

    def verify_submission(version, build)
      raise 'Submitted version unexpectedly enables phased release' if optional_relation_present?(version, :get_app_store_version_phased_release)
      raise 'Submitted build ID mismatch' unless version.get_build&.id == build.id
      raise 'Release type is not automatic' unless version.release_type == 'AFTER_APPROVAL'
      submission = submissions.find do |candidate|
        %w[WAITING_FOR_REVIEW IN_REVIEW COMPLETE].include?(candidate.state) &&
          review_items(candidate).any? { |item| item.app_store_version&.id == version.id }
      end
      raise 'Could not confirm matching review submission' unless submission
      ArgusRelease.assert_submission_items!(review_items(submission), version.id)
      receipt.update('version_id' => version.id, 'build_id' => build.id,
                     'submission_id' => submission.id, 'app_store_state' => version.app_version_state,
                     'submission_state' => submission.state, 'status' => 'submitted',
                     'submission_url' => "https://appstoreconnect.apple.com/apps/#{@app_id}/distribution/reviewsubmissions/details/#{submission.id}")
      puts "Confirmed App Store state: #{version.app_version_state}; release follows Apple approval"
    end
  end
end
