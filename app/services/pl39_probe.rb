require "yaml"
require "fileutils"

# L2: live-only P1 probe — gates backfill on league seasons that have data.
#
# Starting from the present season and stepping back, asks the live-only
# FootballClient for `teams?league=<id>&season=<S>` and records the
# per-season team count. At most `max_requests` (default 10) live HTTP
# requests per run. Every run hits the API (no response cache); reruns are
# full-cost but idempotent (same YML content for the same window/results).
#
# Artifact (single YML per league under config_dir, default config/):
#   allowlist_<id>.yml   league + present_year + window_truncated +
#                        allowlist (retrievable seasons, capped at present
#                        year) + dead (empty/error seasons as
#                        [{season, reason}], never bulk-pulled) + seasons
#                        (per-season tried -> status + team_count, no cache
#                        refs).
#
# Runs accumulate: an existing YML is read first and seasons outside this
# run's window are preserved, so repeated <=10-request runs (or successive
# years) build the full retrievable window over time. Seasons tried by this
# run overwrite their prior entries.
class Pl39Probe < ApplicationService
  LEAGUE_ID = 39
  MAX_LIVE_REQUESTS = 10

  # Legacy JSON artifact names (data/raw/ era). The probe no longer writes
  # these; CoverageGate still reads them until its own live-only ticket
  # migrates it to the YML allowlist. Do not add new readers here.
  PROBE_FILENAME = "probe_39.json"
  ALLOWLIST_FILENAME = "seasons_allowlist_39.json"
  DEAD_FILENAME = "dead_seasons_39.json"

  def self.probe_filename_for(league_id)
    "probe_#{league_id.to_i}.json"
  end

  def self.allowlist_filename_for(league_id)
    "seasons_allowlist_#{league_id.to_i}.json"
  end

  def self.dead_filename_for(league_id)
    "dead_seasons_#{league_id.to_i}.json"
  end

  # Canonical live-only artifact: one YML per league.
  def self.allowlist_yml_filename_for(league_id)
    "allowlist_#{league_id.to_i}.yml"
  end

  def self.allowlist_yml_path_for(league_id, config_dir: Rails.root.join("config"))
    Pathname.new(config_dir.to_s).join(allowlist_yml_filename_for(league_id))
  end

  # Minimal readers over the YML artifact (string-or-symbol tolerant).
  def self.read_allowlist_yml(path)
    data = read_yml(path)
    Array(data["allowlist"] || data[:allowlist]).map { |season| season.to_i }.sort
  end

  def self.read_dead_yml(path)
    data = read_yml(path)
    Array(data["dead"] || data[:dead]).filter_map do |entry|
      next unless entry.is_a?(Hash)

      season = entry["season"] || entry[:season]
      reason = entry["reason"] || entry[:reason]
      next if season.nil?

      { season: season.to_i, reason: reason.to_s }
    end.sort_by { |entry| entry[:season] }
  end

  def self.read_yml(path)
    return {} unless File.exist?(path.to_s)

    YAML.safe_load(File.read(path.to_s)) || {}
  rescue Psych::SyntaxError
    {}
  end

  def initialize(league_id: LEAGUE_ID, present_year: Time.zone.now.year, max_requests: MAX_LIVE_REQUESTS,
    config_dir: Rails.root.join("config"))
    @league_id = league_id.to_i
    @present_year = present_year
    @max_requests = max_requests
    @config_dir = Pathname.new(config_dir.to_s)
  end

  def call
    previous = self.class.read_yml(yml_path)
    probed = probe_window

    seasons = normalize_seasons(previous).merge(probed_seasons(probed))

    allowlist = (
      previous_allowlist(previous) + probed_allowlist(probed)
    ).uniq.select { |season| season <= @present_year }.sort
    # A season re-probed ok leaves the dead list; a re-probed dead season
    # leaves the allowlist.
    probed_ok = probed.select { |season, info| info[:status] == "ok" }.keys
    probed_dead = probed.keys - probed_ok
    dead = (previous_dead(previous).reject { |entry| probed.key?(entry[:season]) } +
      probed_dead.map { |season| { season: season, reason: probed[season][:reason] } })
      .uniq { |entry| entry[:season] }
      .sort_by { |entry| entry[:season] }
    allowlist -= probed_dead
    probed_ok.each { |season| allowlist |= [ season ] }
    allowlist.sort!

    oldest_tried = probed.keys.min
    window_truncated = !oldest_tried.nil? && probed[oldest_tried][:status] == "ok"

    write_yml(allowlist, dead, seasons, window_truncated)

    live_requests = probed.size
    Rails.logger.info(
      "Pl39Probe league=#{@league_id}: seasons_tried=#{probed.size} allowlisted=#{allowlist.size} " \
      "dead=#{dead.size} live_requests=#{live_requests} window_truncated=#{window_truncated}"
    )

    { league_id: @league_id, live_requests: live_requests, allowlist: allowlist, dead: dead, window_truncated: window_truncated }
  end

  private

  def yml_path
    self.class.allowlist_yml_path_for(@league_id, config_dir: @config_dir)
  end

  # One live request per season in the window (live-only: no cache check, so
  # live_requests always equals the window size, capped at @max_requests).
  def probe_window
    probed = {}
    @present_year.downto(@present_year - @max_requests + 1) do |season|
      begin
        teams = FootballClient.call(end_point: "teams?league=#{@league_id}&season=#{season}")
      rescue StandardError => e
        probed[season] = { status: "dead", team_count: 0, reason: "api error: #{e.message}" }
        next
      end

      if teams.is_a?(Array) && teams.size.positive?
        probed[season] = { status: "ok", team_count: teams.size }
      else
        reason = teams.is_a?(Array) ? "empty teams response" : "unexpected payload shape"
        probed[season] = { status: "dead", team_count: 0, reason: reason }
      end

      break if probed.size >= @max_requests
    end
    probed
  end

  def probed_seasons(probed)
    probed.to_h do |season, info|
      entry = { "status" => info[:status], "team_count" => info[:team_count] }
      entry["reason"] = info[:reason] if info[:reason]
      [ season.to_s, entry ]
    end
  end

  def probed_allowlist(probed)
    probed.select { |_season, info| info[:status] == "ok" }.keys
  end

  def normalize_seasons(previous)
    raw = previous["seasons"] || previous[:seasons] || {}
    return {} unless raw.is_a?(Hash)

    raw.to_h { |season, info| [ season.to_s, info ] }
  end

  def previous_allowlist(previous)
    Array(previous["allowlist"] || previous[:allowlist]).map { |season| season.to_i }
  end

  def previous_dead(previous)
    Array(previous["dead"] || previous[:dead]).filter_map do |entry|
      next unless entry.is_a?(Hash)

      season = entry["season"] || entry[:season]
      reason = entry["reason"] || entry[:reason]
      next if season.nil?

      { season: season.to_i, reason: reason.to_s }
    end
  end

  def write_yml(allowlist, dead, seasons, window_truncated)
    FileUtils.mkdir_p(@config_dir)
    payload = {
      "league" => @league_id,
      "present_year" => @present_year,
      "window_truncated" => window_truncated,
      "allowlist" => allowlist,
      "dead" => dead.map { |entry| { "season" => entry[:season], "reason" => entry[:reason] } },
      "seasons" => seasons
    }
    tmp_path = "#{yml_path}.#{Process.pid}.tmp"
    File.write(tmp_path, YAML.dump(payload))
    File.rename(tmp_path, yml_path.to_s)
  end
end
