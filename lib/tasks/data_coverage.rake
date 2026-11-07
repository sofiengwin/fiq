namespace :data do
  desc "Per-season coverage gate: zero teams without players, zero players without careers (dead listed, not missing); exits 0 on pass, 1 on fail"
  task :coverage, [ :league_id, :season ] => :environment do |_t, args|
    league_id = (args[:league_id] || 39).to_i
    season = (args[:season] || Time.zone.now.year).to_i

    report = CoverageGate.call(league_id: league_id, season: season)
    report.lines.each { |line| puts line }

    exit(report.pass? ? 0 : 1)
  end
end
