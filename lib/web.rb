require 'sinatra/base'
require 'honeybadger'
require 'redis'
require 'twumblr'

class Web < Sinatra::Base
  set :port, ENV['PORT']
  set :server, 'puma'
  set :redis, Redis.new

  configure :development do
    require 'pry'
  end

  configure :test do
    require "mock_redis"
    set :raise_errors, true
    set :show_exceptions, false
    set :redis, MockRedis.new
  end

  post "/post" do
    return 404 unless params["token"] == ENV['TOKEN']
    return 422 if email_body.nil? || email_body.empty?

    post_url = posted?(email_body)
    return post_url if post_url

    post = Twumblr.new(email_body).post
    post_url = post_url(post)
    mark_posted(email_body, post_url)

    if post["state"] == "transcoding"
      param = URI.encode_www_form(s: post["display_text"])
      return url("/message?#{param}")
    end

    # Return the URL in the body so Shortcuts can open it
    post_url
  end

  post "/photo" do
    return 404 unless params["token"] == ENV['TOKEN']

    photo_id = params.dig(:photo, :filename) || params[:url]
    return 404 unless photo_id

    post_url = posted?(photo_id)
    return post_url if post_url

    data = params.dig(:photo, :tempfile) || Twumblr.upload_for(params[:url])
    post = Twumblr.client.photo(ENV["TUMBLR_BLOG_URL"], {data: data})

    post_url(post).tap do |url|
      mark_posted(params.dig(:photo, :filename), url)
    end
  end

  get "/message" do
    params[:s]
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
    puts "got post: #{post.inspect}"
    return unless post && post.has_key?("id")
    "https://" + File.join(ENV['TUMBLR_BLOG_URL'], "post", post["id"].to_s)
  end

end

Web.run! if $0 == __FILE__
