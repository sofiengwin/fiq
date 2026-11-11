namespace :data do
  desc "Live-only P1 probe PL 39: earliest retrievable season via teams endpoint (<=10 live requests); writes league_seasons memos"
  task probe_pl39: :environment do
    result = LeagueProbe.call
    puts "probe_39: allowlisted=#{result[:allowlist].size} (#{result[:allowlist].join(",")}) " \
      "dead=#{result[:dead].size} live_requests=#{result[:live_requests]} " \
      "window_truncated=#{result[:window_truncated]}"
    puts "scope: league_seasons memos for league 39"
  end
end
