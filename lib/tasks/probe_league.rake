namespace :data do
  desc "Live-only league-generic probe: earliest retrievable season via teams endpoint (<=10 live requests); writes league_seasons memos"
  task :probe_league, [ :league_id ] => :environment do |_t, args|
    if args[:league_id].nil?
      puts "probe: status=refused reason=missing league_id (pass data:probe_league[league_id])"
      exit(1)
    end

    league_id = args[:league_id].to_i
    result = Pl39Probe.call(league_id: league_id)

    puts "probe_#{league_id}: allowlisted=#{result[:allowlist].size} (#{result[:allowlist].join(",")}) " \
      "dead=#{result[:dead].size} live_requests=#{result[:live_requests]} " \
      "window_truncated=#{result[:window_truncated]}"
    puts "scope: league_seasons memos for league #{league_id}"
  end
end
