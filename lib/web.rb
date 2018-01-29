require 'sinatra/base'
require 'bugsnag'
require 'redis'
require 'twumblr'

class Web < Sinatra::Base
  set :port, ENV['PORT']
  set :server, 'puma'
  set :redis, Redis.new

  use Bugsnag::Rack

  configure :development do
    require 'pry'
  end

  error do
    Bugsnag.notify(env['sinatra.error'])
    return 403
  end

  post "/post" do
    return 404 unless params["token"] == ENV['TOKEN']
    return 200 if posted?(email_body)
    post = Twumblr.new(email_body).post
    mark_posted(email_body)
    return post_url(post)
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

  def mark_posted(html)
    one_week = 60 * 60 * 24 * 7
    settings.redis.set(sha(html), "posted", ex: one_week)
  end

  def sha(html)
    Digest::SHA256.hexdigest(html)
  end

  def post_url(post)
    return unless post && post.has_key?("id")
    File.join(ENV['TUMBLR_BLOG_URL'], "post", post["id"].to_s)
  end

end

Web.run! if $0 == __FILE__
