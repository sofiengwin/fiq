namespace :data do
  desc "L6 nightly stale-only refresh (live-only): dry-run by default (pass false to run live); capped at 200 live requests, league-first"
  task :nightly_refresh, [ :dry_run, :max_requests, :league_id ] => :environment do |_t, args|
    dry_run = args[:dry_run].nil? ? true : args[:dry_run].to_s.strip.downcase != "false"
    max_requests = (args[:max_requests] || Pl39NightlyRefresh::DEFAULT_MAX_REQUESTS).to_i
    league_id = (args[:league_id] || Pl39NightlyRefresh::LEAGUE_ID).to_i

    result = Pl39NightlyRefresh.call(dry_run: dry_run, max_requests: max_requests, league_id: league_id)

    puts "nightly_refresh: status=#{result[:status]} dry_run=#{result[:dry_run]} league=#{league_id} " \
      "teams=#{result[:teams]} players=#{result[:players]} careers=#{result[:careers]} " \
      "total=#{result[:total]} live_requests=#{result[:live_requests]} " \
      "capped=#{result[:capped]} skipped=#{result[:skipped]} failed=#{result[:failed]}"
  end
end
