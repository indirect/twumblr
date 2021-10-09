require 'sinatra/base'
require 'honeybadger'
require 'redis'
require 'twumblr'

ENV["REDIS_URL"] ||= ENV["FLY_REDIS_CACHE_URL"] if ENV.key?("FLY_REDIS_CACHE_URL")

class Web < Sinatra::Base
  set :port, ENV['PORT']
  set :server, 'puma'
  set :redis, Redis.new

  configure :development do
    require 'pry'
  end

  error do
    Bugsnag.notify(env['sinatra.error'])
    return 403
  end

  post "/post" do
    return 404 unless params["token"] == ENV['TOKEN']
    url = posted?(email_body)
    return url if url

    post = Twumblr.new(email_body).post
    url = post_url(post)
    mark_posted(email_body, url)
    return url
  end

  def email_body
    if params.has_key?("html") && !params["html"].empty?
      params["html"]
    else
      params["plain"]
    end
  end

  def posted?(html)
    return false if ENV.has_key?("DEBUG")
    settings.redis.get(sha(html))
  end

  def mark_posted(html, url)
    one_week = 60 * 60 * 24 * 7
    settings.redis.set(sha(html), url, ex: one_week)
  end

  def sha(html)
    Digest::SHA256.hexdigest(html)
  end

  def post_url(post)
    return unless post && post.has_key?("id")
    "https://" + File.join(ENV['TUMBLR_BLOG_URL'], "post", post["id"].to_s)
  end

end

Web.run! if $0 == __FILE__
