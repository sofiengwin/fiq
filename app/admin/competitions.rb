ActiveAdmin.register Competition do
  permit_params :name, :external_id, :country_id

  # Custom action to start league sync
  member_action :sync_teams, method: :post do
    LeagueTeamsJob.perform_later(resource.external_id.to_i, Time.zone.now.year, resource.name)
    redirect_to admin_competition_path(resource), notice: "Team sync job queued for #{resource.name}"
  end

  action_item :sync_teams, only: :show do
    link_to "Sync Teams", sync_teams_admin_competition_path(resource), method: :post
  end

  index do
    selectable_column
    id_column
    column :name
    column :country
    column :external_id
    column :teams_count do |comp|
      comp.football_teams.count
    end
    column :teams_count do |comp|
      comp.football_teams.count
    end
    column :players_count do |comp|
      comp.players.count
    end
    actions
  end

  show do
    attributes_table do
      row :name
      row :country
      row :external_id
    end

    panel "Teams (#{resource.football_teams.count})" do
      table_for resource.football_teams.limit(50) do
        column :name do |team|
          link_to team.name, admin_football_team_path(team)
        end
        column :code
      end
    end
  end

  filter :name
  filter :country
end
