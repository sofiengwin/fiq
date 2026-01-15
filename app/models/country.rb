class Country < ApplicationRecord
  START = {
    "England" => {
      "English Premier League" => {
        league_id: 33,
        season: 2023
      }
    },
    "Spain" => {
      "La Liga" => {
        league_id: 34,
        season: 2023
      }
    },
    "France" => {
      "Ligue 1" => {
        league_id: 35,
        season: 2023
      }
    },
    "Germany" => {
      "Bundesliga" => {
        league_id: 36,
        season: 2023
      }
    },
    "Italy" => {
      "Serie A" => {
        league_id: 37,
        season: 2023
      }
    }
  }
end
