namespace :data do
  desc "Live-only bounded backfill: one allowlisted PL 39 season via players?team&season union (cap 500, YML-gated, never past present)"
  task :backfill_pl39, [ :season, :max_requests ] => :environment do |_t, args|
    if args[:season].nil?
      puts "backfill_39: status=refused season= live_requests=0 reason=missing season (pass data:backfill_pl39[season])"
      exit(1)
    end

    result = Pl39Backfill.call(
      season: args[:season].to_i,
      max_requests: (args[:max_requests] || Pl39Backfill::DEFAULT_MAX_REQUESTS).to_i
    )

    line = "backfill_39: status=#{result[:status]} season=#{result[:season]} " \
      "live_requests=#{result[:live_requests]} " \
      "teams=#{result[:teams]} players=#{result[:players]} careers=#{result[:careers]} " \
      "capped=#{result[:capped]}"
    line += " reason=#{result[:refusal_reason]}" if result[:refusal_reason]
    puts line

    exit(result[:status] == :refused ? 1 : 0)
  end
end
