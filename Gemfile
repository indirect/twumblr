ruby File.read("#{__dir__}/.ruby-version").chomp

source "https://rubygems.org"
git_source(:github) {|repo_name| "https://github.com/#{repo_name}" }

gem "dotenv"
gem "faraday"
gem "http"
gem "puma"
gem "sinatra", "~> 2.2"
gem "tumblr_client", github: "indirect/tumblr_client", branch: "master"
gem "twitter", "~> 7.0", github: "sferik/twitter"
gem "redis"
gem "honeybadger", "~> 4.9"

group :development do
  gem "pry"
end
