require 'faraday'

class Twumblr

  def initialize(text)
    @text = text
  end

  def follow_redirects(url)
    require 'http'
    res = HTTP.head(url)
    res = HTTP.head(res.headers['Location']) while res.headers['Location']
    res.uri.to_s
  end

  def title_at_url(url)
    require 'http'
    res = HTTP.get(url)
    res.to_s.scan(%r|<title>(.*)</title>|).flatten.first
  end

  def twitter
    require 'twitter'
    @twitter ||= Twitter::REST::Client.new(
      :consumer_key => ENV["TWITTER_API_KEY"],
      :consumer_secret => ENV["TWITTER_API_SECRET"]
    )
  end

  def tweet_at_url(url)
    tweet_id = url.match(%r|twitter.com/\w*/status/(\d*)|){|m| m[1] }
    twitter.status(tweet_id, tweet_mode: "extended")
  end

  def tumblr
    require 'tumblr_client'
    @tumblr ||= Tumblr::Client.new(
      :consumer_key => ENV["TUMBLR_CONSUMER_KEY"],
      :consumer_secret => ENV["TUMBLR_CONSUMER_SECRET_KEY"],
      :oauth_token => ENV["TUMBLR_OAUTH_TOKEN"],
      :oauth_token_secret => ENV["TUMBLR_OAUTH_TOKEN_SECRET"]
    )
  end

  def photo_data_from(media)
    media.map do |m|
      res = Faraday.get(m.media_url)
      io = StringIO.new(res.body)
      type = res.headers["content-type"]
      filename = m.media_uri.path.split("/").last
      Faraday::UploadIO.new(io, type, filename)
    end
  end

  def tumbl_tweet(tweet)
    tweet_url = "http://twitter.com/#{tweet.user.screen_name}/status/#{tweet.id}"
    tweet_text = tweet.attrs[:full_text]
    tweet_text.gsub!(%r{(?:^| )(?:https?\://\S*|pic\.twitter\.com\S*|t.co\S*)}, '')
    tweet_text.gsub!("\n", "<br>")
    attribution = %|<a href="#{tweet_url}">@#{tweet.user.screen_name}</a>|

    if tweet.media.any? && tweet.media.first.type == "video"
      res = HTTP.get(tweet.media.first.video_info.variants.first.url.to_s)
      tumbl :video,
        :caption => "#{tweet_text} - #{attribution}",
        :data => Faraday::UploadIO.new(StringIO.new(res.to_s), res.content_type.mime_type)
    elsif tweet.media.any? # photo
      tumbl :photo,
        :caption => "#{tweet_text} — #{attribution}",
        :data => photo_data_from(tweet.media),
        :link => tweet_url
    elsif tweet.urls.any? # link
      link = tweet.urls.first.expanded_url
      tumbl :link,
        :url => follow_redirects(link),
        :description => "#{tweet_text} — #{attribution}",
        :title => title_at_url(link)
    else # quote
      tumbl :quote,
        :quote => tweet_text,
        :source => attribution
    end
  end

  def tumbl(type, data = {})
    puts "#{type}:\n#{data.inspect}"
    return if ENV["DEBUG"]
    tumblr.send(type, ENV["TUMBLR_BLOG_URL"], data)
  end

  def post
    tweet = tweet_at_url(@text)
    tweet ||= tweet_at_url(follow_redirects(@text))
    abort "Couldn't find a tweet URL!" unless tweet
    tumbl_tweet(tweet)
  end
end

