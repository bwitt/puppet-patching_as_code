# frozen_string_literal: true

require 'spec_helper_acceptance'

describe 'patching_as_code' do
  # A weekday that is never today, so nothing gets patched or rebooted
  let(:not_today) { (Time.now.utc + (2 * 86_400)).strftime('%A') }

  context 'with patch_group never' do
    it_behaves_like 'an idempotent resource' do
      let(:manifest) do
        <<~PUPPET
          class { 'patching_as_code':
            patch_group => 'never',
            fact_upload => false,
          }
        PUPPET
      end
    end

    describe file('/etc/puppetlabs/puppet/patching_unsafe_processes') do
      it { is_expected.to be_file }
    end

    describe file('/opt/puppetlabs/facter/facts.d/patching_configuration.json') do
      it { is_expected.to be_file }

      its(:content_as_json) do
        is_expected.to include(
          'patching_as_code_config' => include(
            'enable_patching' => true,
            'patch_fact' => 'os_patching',
            'patch_group' => ['never'],
            'patch_schedule' => { 'never' => 'N/A' },
          ),
        )
      end
    end

    describe file('/usr/local/bin/os_patching_fact_generation.sh') do
      it { is_expected.to be_executable }
    end

    describe file('/var/cache/os_patching/patch_window') do
      its(:content) { is_expected.to match(%r{never}) }
    end
  end

  context 'with a patch schedule that is not today' do
    it_behaves_like 'an idempotent resource' do
      let(:manifest) do
        <<~PUPPET
          class { 'patching_as_code':
            patch_group         => 'custom',
            patch_schedule      => {
              'custom' => {
                'day_of_week'   => '#{not_today}',
                'count_of_week' => [1, 2, 3, 4, 5],
                'hours'         => '00:00 - 23:59',
                'max_runs'      => 1,
                'reboot'        => 'never',
              },
            },
            blocklist           => ['foo'],
            unsafe_process_list => ['bar', 'baz'],
            fact_upload         => false,
          }
        PUPPET
      end
    end

    describe file('/etc/puppetlabs/puppet/patching_unsafe_processes') do
      its(:content) { is_expected.to eq("bar\nbaz") }
    end

    describe file('/opt/puppetlabs/facter/facts.d/patching_configuration.json') do
      its(:content_as_json) do
        is_expected.to include(
          'patching_as_code_config' => include(
            'blocklist' => ['foo'],
            'patch_group' => ['custom'],
            'patch_schedule' => include('custom' => include('day_of_week' => not_today)),
            'unsafe_process_list' => %w[bar baz],
          ),
        )
      end
    end

    describe file('/var/cache/os_patching/patch_window') do
      its(:content) { is_expected.to match(%r{custom}) }
    end

    describe file('/opt/puppetlabs/patching_as_code/last_run') do
      it { is_expected.not_to exist }
    end
  end

  context 'with functions' do
    it_behaves_like 'an idempotent resource' do
      let(:manifest) do
        <<~PUPPET
          file { '/tmp/is_patchday_any':
            content => String(patching_as_code::is_patchday('Any', [1, 2, 3, 4, 5], 'test')),
          }
          file { '/tmp/is_patchday_not_today':
            content => String(patching_as_code::is_patchday('#{not_today}', [1, 2, 3, 4, 5], 'test')),
          }
          file { '/tmp/dedupe_arch':
            content => String(patching_as_code::dedupe_arch(['foo.x86_64', 'foo.i686', 'bar.noarch'])),
          }
        PUPPET
      end
    end

    describe file('/tmp/is_patchday_any') do
      its(:content) { is_expected.to eq('true') }
    end

    describe file('/tmp/is_patchday_not_today') do
      its(:content) { is_expected.to eq('false') }
    end

    describe file('/tmp/dedupe_arch') do
      its(:content) { is_expected.to eq("['foo', 'bar.noarch']") }
    end

    it 'writes the last run info' do
      apply_manifest("file { '/tmp/last_run': content => Deferred('patching_as_code::last_run', [['foo'], ['bar']]) }", catch_failures: true)
    end

    describe file('/tmp/last_run') do
      its(:content_as_json) { is_expected.to include('patches_installed' => ['foo'], 'choco_patches_installed' => ['bar']) }
    end
  end
end
