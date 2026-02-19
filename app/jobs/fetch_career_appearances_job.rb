class FetchCareerAppearancesJob < ApplicationJob
  queue_as :default

  def perform(player_id)
    player = Player.find(player_id)
    career_teams_data = fetch_player_teams(player)

    return if career_teams_data.blank?

    player.careers.find_each do |career|
      team_external_id = career.football_team.external_id.to_i
      team_data = career_teams_data.find { |ct| ct.dig(:team, :id) == team_external_id }

      next unless team_data

      seasons = team_data[:seasons] || []
      appearances = fetch_appearances_for_seasons(player, seasons, team_external_id)

      career.update!(appearances: appearances) if appearances.positive?
    end
  end

  private

  def fetch_player_teams(player)
    FootballClient.call(end_point: "players/teams?player=#{player.external_id}")
  end

  # Fetches total appearances for a player at a specific team across multiple seasons
  # Uses the /players?id={id}&season={year} endpoint
  def fetch_appearances_for_seasons(player, seasons, team_external_id)
    total = 0

    seasons.each do |season|
      stats = FootballClient.call(end_point: "players?id=#{player.external_id}&season=#{season}")
      next if stats.blank? || stats[0].nil?

      # Find statistics for the specific team
      team_stats = stats[0][:statistics]&.find { |s| s.dig(:team, :id) == team_external_id }
      next unless team_stats

      # Note: API uses "appearences" (typo in their API)
      appearances = team_stats.dig(:games, :appearences) || team_stats.dig(:games, :appearances) || 0
      total += appearances
    end

    total
  end
end
