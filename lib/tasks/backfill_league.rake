namespace :data do
  desc "Enqueue a live-only bounded backfill via players?team&season union (cap 500, memo-gated, convention range only): one season when given, else all in-range non-fresh-dead seasons"
  task :backfill_league, [ :league_id, :season, :max_requests ] => :environment do |_t, args|
    if args[:league_id].nil?
      puts "backfill: status=refused league=#{args[:league_id]} season=#{args[:season]} live_requests=0 " \
        "reason=missing league (pass data:backfill_league[league_id] or data:backfill_league[league_id,season])"
      exit(1)
    end

    league_id = args[:league_id].to_i
    max_requests = (args[:max_requests] || LeagueBackfill::DEFAULT_MAX_REQUESTS).to_i

    unless args[:season].nil?
      season = args[:season].to_i
      # Always enqueue (never inline): keeps web/CLI fast. For an inline dev
      # run, call LeagueBackfill.call(league_id:, season:, max_requests:)
      # from a rails console instead.
      job = BackfillLeagueJob.perform_later(league_id, season, max_requests: max_requests)
      puts "backfill_#{league_id}: status=enqueued job_id=#{job.job_id} job_class=#{job.class.name} " \
        "league_id=#{league_id} season=#{season} max_requests=#{max_requests}"
      next
    end

    # No season: fan out one job per convention-range season, skipping
    # fresh-dead memos (DB check only, zero HTTP at enqueue).
    present_year = Time.zone.now.year
    seasons = (LeagueSeason::FIRST_SEASON..present_year).to_a
    skipped = seasons.select do |season|
      row = LeagueSeason.memo_for(league_id, season)
      row&.dead? && row.fresh?
    end
    enqueued_seasons = seasons - skipped
    enqueued_seasons.each do |season|
      BackfillLeagueJob.perform_later(league_id, season, max_requests: max_requests)
    end
    puts "backfill_#{league_id}: status=enqueued_all league_id=#{league_id} enqueued=#{enqueued_seasons.size} " \
      "skipped=#{skipped.size} enqueued_seasons=#{enqueued_seasons.join(",")} " \
      "skipped_seasons=#{skipped.join(",")} max_requests=#{max_requests}"
  end
end
