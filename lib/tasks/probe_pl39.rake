namespace :data do
  desc "P1 probe PL 39: earliest retrievable season via teams endpoint (<=10 live requests); writes allowlist + dead list under data/raw/"
  task probe_pl39: :environment do
    result = Pl39Probe.call
    puts "probe_39: allowlisted=#{result[:allowlist].size} (#{result[:allowlist].join(",")}) " \
      "dead=#{result[:dead].size} live_requests=#{result[:live_requests]} " \
      "window_truncated=#{result[:window_truncated]}"
    puts "artifacts: data/raw/#{Pl39Probe::PROBE_FILENAME} " \
      "data/raw/#{Pl39Probe::ALLOWLIST_FILENAME} data/raw/#{Pl39Probe::DEAD_FILENAME}"
  end
end
