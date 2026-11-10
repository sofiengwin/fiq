class CreateLeagueSeasons < ActiveRecord::Migration[8.1]
  def change
    # DB-backed league scope memo: one row per (league, season) recording the
    # latest live probe/backfill contact. Replaces the committed
    # config/allowlist_<id>.yml artifacts; those YML readers remain only as a
    # deprecated fallback when no memo rows exist for a league.
    create_table :league_seasons do |t|
      t.integer :league_id, null: false
      t.integer :season, null: false
      t.string :status, null: false
      t.string :reason
      t.integer :team_count, null: false, default: 0
      t.datetime :checked_at
      t.timestamps
    end
    add_index :league_seasons, %i[league_id season], unique: true
  end
end
