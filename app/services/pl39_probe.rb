require "json"
require "fileutils"

# T3: P1 probe — gates backfill on PL seasons that actually have data.
#
# Starting from the present season and stepping back, asks the cached
# FootballClient for `teams?league=39&season=<S>` and records the per-season
# team count. At most `max_requests` (default 10) live HTTP requests per run;
# reruns are cache-first (~0 live requests) and rewrite identical artifacts.
#
# Artifacts (under output_dir, default data/raw/):
#   probe_39.json             per-season tried -> team count + cache file ref
#   seasons_allowlist_39.json retrievable seasons only, capped at present year
#   dead_seasons_39.json      empty/error seasons ({season, reason}), never bulk-pulled
class Pl39Probe < ApplicationService
  LEAGUE_ID = 39
  MAX_LIVE_REQUESTS = 10

  PROBE_FILENAME = "probe_39.json"
  ALLOWLIST_FILENAME = "seasons_allowlist_39.json"
  DEAD_FILENAME = "dead_seasons_39.json"

  def initialize(present_year: Time.zone.now.year, max_requests: MAX_LIVE_REQUESTS, output_dir: Rails.root.join("data/raw"))
    @present_year = present_year
    @max_requests = max_requests
    @output_dir = Pathname.new(output_dir.to_s)
  end

  def call
    seasons = {}
    live_requests = 0

    @present_year.downto(@present_year - @max_requests + 1) do |season|
      endpoint = "teams?league=#{LEAGUE_ID}&season=#{season}"
      cached = File.exist?(FootballClient.cache_path_for(endpoint))

      begin
        teams = FootballClient.call(end_point: endpoint)
      rescue StandardError => e
        # Error payloads are never cached (T2), so a retry always costs a request.
        live_requests += 1 unless cached
        seasons[season] = { status: "dead", team_count: 0, reason: "api error: #{e.message}" }
        next
      end

      live_requests += 1 unless cached

      cache_file = File.basename(FootballClient.cache_path_for(endpoint).to_s)
      if teams.is_a?(Array) && teams.size.positive?
        seasons[season] = { status: "ok", team_count: teams.size, cache_file: cache_file }
      else
        reason = teams.is_a?(Array) ? "empty teams response" : "unexpected payload shape"
        seasons[season] = { status: "dead", team_count: 0, reason: reason, cache_file: cache_file }
      end

      break if live_requests >= @max_requests
    end

    allowlist = seasons.select { |season, info| info[:status] == "ok" && season <= @present_year }.keys.sort
    dead = seasons.filter_map do |season, info|
      { season: season, reason: info[:reason] } if info[:status] == "dead"
    end.sort_by { |entry| entry[:season] }

    oldest_tried = seasons.keys.min
    window_truncated = !oldest_tried.nil? && seasons[oldest_tried][:status] == "ok"

    write_artifacts(seasons, allowlist, dead, window_truncated)

    Rails.logger.info(
      "Pl39Probe: seasons_tried=#{seasons.size} allowlisted=#{allowlist.size} " \
      "dead=#{dead.size} live_requests=#{live_requests} window_truncated=#{window_truncated}"
    )

    { live_requests: live_requests, allowlist: allowlist, dead: dead, window_truncated: window_truncated }
  end

  private

  def write_artifacts(seasons, allowlist, dead, window_truncated)
    FileUtils.mkdir_p(@output_dir)
    # NB: live_requests is per-run metadata (logged + returned, not persisted)
    # so that reruns rewrite byte-identical artifacts.
    probe = {
      league: LEAGUE_ID,
      present_year: @present_year,
      max_requests: @max_requests,
      window_truncated: window_truncated,
      seasons: seasons
    }
    atomic_write(PROBE_FILENAME, JSON.pretty_generate(probe))
    atomic_write(ALLOWLIST_FILENAME, JSON.pretty_generate(allowlist))
    atomic_write(DEAD_FILENAME, JSON.pretty_generate(dead))
  end

  def atomic_write(filename, content)
    path = @output_dir.join(filename)
    tmp_path = "#{path}.#{Process.pid}.tmp"
    File.write(tmp_path, content)
    File.rename(tmp_path, path.to_s)
  end
end
