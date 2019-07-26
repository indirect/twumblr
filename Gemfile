ruby File.read("#{__dir__}/.ruby-version").chomp

source "https://rubygems.org"
git_source(:github) {|repo_name| "https://github.com/#{repo_name}" }

gem "bugsnag"
gem "dotenv"
gem "faraday"
gem "http"
gem "puma"
gem "sinatra", "~> 2.0"
gem "tumblr_client", github: "indirect/tumblr_client"
gem "twitter", "~> 6.2"
gem "redis"

group :development do
  gem "pry"
end
