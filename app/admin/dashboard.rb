# frozen_string_literal: true

ActiveAdmin.register_page "Dashboard" do
  menu priority: 1, label: proc { I18n.t("active_admin.dashboard") }

  content title: proc { I18n.t("active_admin.dashboard") } do
    columns do
      column do
        panel "Statistics" do
          ul do
            li "Countries: #{Country.count}"
            li "Teams: #{FootballTeam.count}"
            li "Players: #{Player.count}"
            li "Competitions: #{Competition.count}"
            li "Careers: #{Career.count}"
          end
        end
      end

      column do
        panel "Recent Players" do
          table_for Player.order(created_at: :desc).limit(10) do
            column :name do |player|
              link_to player.name, admin_player_path(player)
            end
            column :position
            column :created_at
          end
        end
      end
    end

    columns do
      column do
        panel "Start Data Ingestion" do
          para "Click to start fetching data for all configured leagues:"
          text_node link_to "Start Full Sync", admin_dashboard_start_sync_path, method: :post, class: "button"
        end
      end
    end
  end

  page_action :start_sync, method: :post do
    LeagueTeamsJob.start_ingestion
    redirect_to admin_dashboard_path, notice: "Data ingestion jobs have been queued!"
  end
end
