ActiveAdmin.register Career do
  permit_params :player_id, :football_team_id, :duration

  index do
    selectable_column
    id_column
    column :player
    column :football_team
    column :duration do |career|
      "#{career.duration.begin} - #{career.duration.end || 'Present'}"
    end
    actions
  end

  show do
    attributes_table do
      row :player
      row :football_team
      row :duration do |career|
        "#{career.duration.begin} - #{career.duration.end || 'Present'}"
      end
    end
  end

  filter :player
  filter :football_team
end
