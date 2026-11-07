namespace :data do
  desc "Live-only P1 probe PL 39: earliest retrievable season via teams endpoint (<=10 live requests); writes config/allowlist_39.yml"
  task probe_pl39: :environment do
    result = Pl39Probe.call
    puts "probe_39: allowlisted=#{result[:allowlist].size} (#{result[:allowlist].join(",")}) " \
      "dead=#{result[:dead].size} live_requests=#{result[:live_requests]} " \
      "window_truncated=#{result[:window_truncated]}"
    puts "artifact: config/#{Pl39Probe.allowlist_yml_filename_for(39)}"
  end
end
