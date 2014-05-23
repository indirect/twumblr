require 'sinatra/base'
require 'twumblr'

class Web < Sinatra::Base
  set :port, ENV['PORT']
  set :server, 'puma'

  configure :development do
    require 'pry'
  end

  post "/post" do
    return 404 unless params["token"] == "EjqIR3T8FWOiGUy9ujFkbfq"
    return 200 if posted?(params["html"])
    post = Twumblr.new(params["html"]).post
    mark_posted(params["html"])
    return post_url(post)
  end

  def posted?(html)
    redis.get(sha(html))
  end

  def mark_posted(html)
    one_week = 60 * 60 * 24 * 7
    redis.set(sha(html), "posted", ex: one_week)
  end

  def sha(html)
    Digest::SHA256.hexdigest(html)
  end

  def post_url(post)
    File.join(ENV['TUMBLR_BLOG_URL'], "post", post["id"])
  end

  def redis
    require 'redis'
    @redis ||= Redis.new
  end
end

Web.run! if $0 == __FILE__
