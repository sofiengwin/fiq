class CreateCompetitionsFootballTeams < ActiveRecord::Migration[8.1]
  def change
    create_join_table :competitions, :football_teams do |t|
      t.index [ :competition_id, :football_team_id ], name: "idx_comp_team"
      t.index [ :football_team_id, :competition_id ], name: "idx_team_comp"
    end
  end
end
