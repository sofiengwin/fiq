# README

This README would normally document whatever steps are necessary to get the
application up and running.

Things you may want to cover:

* Ruby version

* System dependencies

* Configuration

* Database creation

* Database initialization

* How to run the test suite

* Services (job queues, cache servers, search engines, etc.)

* Deployment instructions

* ...


# Get all players in a team: This will take care of active players
Copy
require 'uri'
require 'net/http'
require 'openssl'

url = URI("https://v3.football.api-sports.io/players/squads?team=33")

http = Net::HTTP.new(url.host, url.port)
http.use_ssl = true
http.verify_mode = OpenSSL::SSL::VERIFY_NONE

request = Net::HTTP::Get.new(url)
request["x-rapidapi-host"] = 'v3.football.api-sports.io'
request["x-rapidapi-key"] = 'XxXxXxXxXxXxXxXxXxXxXxXx'

response = http.request(request)
puts response.read_body


# Career journey
https://www.api-football.com/documentation-v3#tag/Players/operation/get-players-teams


### Get all teams in a country and league

bin/rails g model Team name:string code:string country:references external_id:string
bin/rails g model League name:string external_id:string country:references
bin/rails g model Country name:string code:string
bin/rails g model Player name:string position:string first_name:string last_name:string team:references external_id:string age:integer appearances:integer
bin/rails g model Career player:references team:references start_date:date end_date:date