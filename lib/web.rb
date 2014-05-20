require 'sinatra/base'
require File.expand_path('../twumblr', __FILE__)

class Web < Sinatra::Base
  set :port, ENV['PORT']
  set :server, 'puma'

  post "/post" do
    return 404 unless params["token"] == "EjqIR3T8FWOiGUy9ujFkbfq"
    Twumblr.new(params["html"]).post
  end
end

Web.run! if $0 == __FILE__
