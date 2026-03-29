ActiveAdmin.register Player do
  permit_params :name, :external_id, :first_name, :last_name

  # Custom action to fetch career data
  member_action :fetch_career, method: :post do
    resource.fetch_data
    redirect_to admin_player_path(resource), notice: "Career fetch job queued for #{resource.name}"
  end

  action_item :fetch_career, only: :show do
    button_to "Fetch Career", fetch_career_admin_player_path(resource), method: :post
  end

  index do
    selectable_column
    id_column
    column :name
    column :first_name
    column :last_name
    column :external_id
    actions
  end

  show do
    attributes_table do
      row :name
      row :position
      row :external_id
      row :age
      row :appearances
      row :journey do |player|
        player.journey.html_safe
      end
    end

    panel "Careers" do
      table_for resource.careers.includes(:football_team).order("duration DESC") do
        column :football_team
        column :duration do |career|
          "#{career.duration.begin} - #{career.duration.end || 'Present'}"
        end
      end
    end
  end

  filter :name
  filter :position
  filter :external_id
end
