ActiveAdmin.register FootballTeam do
  permit_params :name, :code, :external_id, :country_id, competition_ids: []

  # Custom action to fetch team players
  member_action :fetch_players, method: :post do
    FetchTeamPlayersJob.perform_later(resource.id)
    redirect_to admin_football_team_path(resource), notice: "Player fetch job queued for #{resource.name}"
  end

  action_item :fetch_players, only: :show do
    link_to "Fetch Players", fetch_players_admin_football_team_path(resource), method: :post
  end

  index do
    selectable_column
    id_column
    column :name
    column :code
    column :country
    column :external_id
    column :national
    column :players_count do |team|
      team.players.count
    end
    actions
  end

  show do
    attributes_table do
      row :name
      row :code
      row :country
      row :external_id
      row :national
      row :competitions do |team|
        team.competitions.map(&:name).join(", ")
      end
    end

    panel "Players (#{resource.players.count})" do
      table_for resource.players.limit(50) do
        column :name do |player|
          link_to player.name, admin_player_path(player)
        end
        column :position
      end
    end
  end

  filter :name
  filter :code
  filter :country
  filter :competitions
end
