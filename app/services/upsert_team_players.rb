class UpsertTeamPlayers < ApplicationService
  def initialize(team:)
    @team = team
  end

  # L8: auto-discovery squad path — every live call spends one auto-budget
  # request (separate from the batch 500 / nightly 200 caps). Over budget
  # the squad stays pending with zero HTTP; first-seen players created here
  # get their career fetch enqueued by FetchTeamPlayersJob.
  def call
    response = fetch_players
    return [] if response.blank? || response[0].nil?

    players_data = response[0][:players]
    return [] if players_data.blank?

    players_data.map do |player_params|
      player_profile = fetch_player_profile(player_params[:id])
      next if player_profile.blank? || player_profile[0].nil?
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
  rescue AutoDiscovery::OverBudget => e
    AutoDiscovery.note("pending-budget", kind: "squad", team_id: @team.id, reason: e.message)
    []
  end

  private

  # L8: checkout before every auto HTTP call; raises before any HTTP when
  # the daily auto budget is spent.
  def auto_fetch(endpoint)
    AutoDiscovery.checkout!
    FootballClient.call(end_point: endpoint)
  end

  def fetch_players
    auto_fetch("players/squads?team=#{@team.external_id}")
  end

  def fetch_player_profile(player_id)
    auto_fetch("players/profiles?player=#{player_id}")
  end
end
