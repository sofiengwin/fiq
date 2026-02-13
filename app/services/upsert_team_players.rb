class UpsertTeamPlayers < ApplicationService
  def initialize(team:)
    @team = team
  end

  def call
    response = fetch_players
    return [] if response.blank? || response[0].nil?

    players_data = response[0][:players]
    return [] if players_data.blank?

    players_data.map do |player_params|
      player = Player.find_or_create_by(external_id: player_params[:id]) do |p|
        p.name = player_params[:name]
        p.position = player_params[:position]
        p.age = player_params[:age]
      end

      # Create initial career entry if not exists
      unless player.careers.exists?(football_team: @team)
        player.careers.create(
          football_team: @team,
          duration: Date.current..nil
        )
      end

      player
    end
  end

  private

  def fetch_players
    FootballClient.call(end_point: "players/squads?team=#{@team.external_id}")
  end
end
