require 'sinatra/base'
require 'honeybadger'
require 'twumblr'

class Web < Sinatra::Base
  set :port, ENV['PORT']
  set :server, 'puma'

  POSTS = {}

  configure :development do
    require 'pry'
  end

  post "/post" do
    return 404 unless params["token"] == ENV['TOKEN']
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
    return 404 unless params[:token] == ENV['TOKEN']
    return 404 unless params[:url] || params.dig(:photo, :filename)

    name = params[:url] || params.dig(:photo, :filename)
    posted_url = posted?(name)
    return posted_url if posted_url

    photo = Twumblr.upload_for(params[:url]) if params[:url]
    photo ||= photo_upload_for(params[:photo])

    post = Twumblr.client.photo(ENV["TUMBLR_BLOG_URL"], {data: [photo]})
    post_url(post).tap { |post_url| mark_posted(name, post_url) }
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
    hash = sha(html)
    one_week_ago = Time.now - (60 * 60 * 24 * 7)
    POSTS.key?(hash) && POSTS[hash] > one_week_ago
  end

  def mark_posted(html)
    POSTS[sha(html)] = Time.now
  end

  def sha(html)
    Digest::SHA256.hexdigest(html)
  end

  def post_url(post)
    puts "got post: #{post.inspect}"
    return unless post && post.has_key?("id")
    "https://" + File.join(ENV['TUMBLR_BLOG_URL'], "post", post["id"].to_s)
  end

  def photo_upload_for(photo)
    file = params.dig(:photo, :tempfile)
    type = params.dig(:photo, :type)
    filename = params.dig(:photo, :filename)
    Faraday::UploadIO.new(file, type, filename)
  end

end

Web.run! if $0 == __FILE__
