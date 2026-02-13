ActiveAdmin.register Country do
  permit_params :name, :code

  index do
    selectable_column
    id_column
    column :name
    column :code
    column :teams_count do |country|
      country.football_teams.count
    end
    actions
  end

  show do
    attributes_table do
      row :name
      row :code
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
  filter :code
end
