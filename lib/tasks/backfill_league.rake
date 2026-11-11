namespace :data do
  desc "Enqueue a live-only bounded backfill: one in-scope season via players?team&season union (cap 500, memo-gated, convention range only)"
  task :backfill_league, [ :league_id, :season, :max_requests ] => :environment do |_t, args|
    if args[:league_id].nil? || args[:season].nil?
      puts "backfill: status=refused league=#{args[:league_id]} season=#{args[:season]} live_requests=0 " \
        "reason=missing league/season (pass data:backfill_league[league_id,season])"
      exit(1)
    end

    league_id = args[:league_id].to_i
    season = args[:season].to_i
    max_requests = (args[:max_requests] || LeagueBackfill::DEFAULT_MAX_REQUESTS).to_i

    # Always enqueue (never inline): keeps web/CLI fast. For an inline dev
    # run, call LeagueBackfill.call(league_id:, season:, max_requests:)
    # from a rails console instead.
    job = BackfillLeagueJob.perform_later(league_id, season, max_requests: max_requests)
    puts "backfill_#{league_id}: status=enqueued job_id=#{job.job_id} job_class=#{job.class.name} " \
      "league_id=#{league_id} season=#{season} max_requests=#{max_requests}"
  end
end
