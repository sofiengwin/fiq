class UpsertTeamPlayers < ApplicationService
  def initialize(team:)
    @team = team
  end

  def call
    players = fetch_players[0][:players]
    players.map do |player_params|
      play = Player.find_or_create_by(external_id: player_params[:id]) do |player|
        player.name = player_params[:name]
        player.position = player_params[:position]
      end

      play.careers << current_career
      play
    end
  end

  private

  def current_career
    Career.build(team: @team)
  end

  def fetch_players
    FootballClient.call(end_point: "players/squads?team=#{@team.external_id}")
  end
end
