namespace :data do
  desc "League-generic live-only bounded backfill: one in-scope season via players?team&season union (cap 500, memo-gated, convention range only)"
  task :backfill_league, [ :league_id, :season, :max_requests ] => :environment do |_t, args|
    if args[:league_id].nil? || args[:season].nil?
      puts "backfill: status=refused league=#{args[:league_id]} season=#{args[:season]} live_requests=0 " \
        "reason=missing league/season (pass data:backfill_league[league_id,season])"
      exit(1)
    end

    league_id = args[:league_id].to_i
    result = Pl39Backfill.call(
      league_id: league_id,
      season: args[:season].to_i,
      max_requests: (args[:max_requests] || Pl39Backfill::DEFAULT_MAX_REQUESTS).to_i
    )

    line = "backfill_#{league_id}: status=#{result[:status]} season=#{result[:season]} " \
      "live_requests=#{result[:live_requests]} " \
      "teams=#{result[:teams]} players=#{result[:players]} careers=#{result[:careers]} " \
      "capped=#{result[:capped]}"
    line += " reason=#{result[:refusal_reason]}" if result[:refusal_reason]
    puts line

    exit(result[:status] == :refused ? 1 : 0)
  end
end
