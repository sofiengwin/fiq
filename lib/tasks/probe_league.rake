namespace :data do
  desc "League-generic probe: earliest retrievable season via teams endpoint (<=10 live requests); writes per-league allowlist + dead list under data/raw/"
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
    puts "artifacts: data/raw/#{Pl39Probe.probe_filename_for(league_id)} " \
      "data/raw/#{Pl39Probe.allowlist_filename_for(league_id)} data/raw/#{Pl39Probe.dead_filename_for(league_id)}"
  end
end
