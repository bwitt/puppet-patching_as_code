# frozen_string_literal: true

# os_patching provides the patching facts but is not a metadata dependency
RSpec.configure do |c|
  c.before :suite do
    hosts.each do |host|
      # its stdlib < 10 requirement makes the PMT pick an ancient release
      on(host, 'puppet module install albatrossflavour-os_patching --ignore-dependencies')
      # os_patching manages cron jobs
      apply_manifest_on(host, "package { $facts['os']['family'] ? { 'RedHat' => 'cronie', default => 'cron' }: ensure => installed }", catch_failures: true)
    end
  end
end
