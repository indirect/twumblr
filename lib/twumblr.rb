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

  TweetInfo = Struct.new(:tweet) do
    def self.from_url(url)
      require 'twitter'
      @twitter ||= Twitter::REST::Client.new(
        :consumer_key => ENV["TWITTER_API_KEY"],
        :consumer_secret => ENV["TWITTER_API_SECRET"]
      )
      tweet_id = url.match(%r|twitter.com/\w*/status/(\d*)|){|m| m[1] }
      new(@twitter.status(tweet_id, tweet_mode: "extended")) if tweet_id
    end

    def url
      "http://twitter.com/#{tweet.user.screen_name}/status/#{tweet.id}"
    end

    def text
      tweet.attrs[:full_text].
        gsub(%r{(?:^| )(?:https?\://\S*|pic\.twitter\.com\S*|t.co\S*)}, '').
        gsub("\n", "\n<br>")
    end

    def source
      %|<a href="#{url}">@#{tweet.user.screen_name}</a>|
    end

    def caption
      [text, source].join(" — ")
    end

    def quote_tweet_body
      quoted = TweetInfo.new(tweet.quoted_tweet)
      qphoto = tweet.quoted_tweet.media.first

      body = "<blockquote><p>\n"
      body << "#{quoted.source}: #{quoted.text}\n"
      body << %|<img src="#{qphoto.media_uri}">\n| if qphoto
      body << "</p></blockquote>\n\n"
      body << caption
    end
  end

  def tumbl_post(info)
    tweet = info.tweet

    if tweet.quoted_tweet?
      tumbl :text, body: info.quote_tweet_body, format: "html"
    elsif tweet.media.any? && tweet.media.first.type == "video"
      res = HTTP.get(tweet.media.first.video_info.variants.find do |v|
        v.content_type == "video/mp4"
      end.url.to_s)
      tumbl :video,
        :caption => info.caption,
        :data => Faraday::UploadIO.new(StringIO.new(res.to_s), res.content_type.mime_type)
    elsif tweet.media.any? # photo
      tumbl :photo,
        :caption => info.caption,
        :data => photo_data_from(tweet.media),
        :link => info.url
    elsif tweet.urls.any? # link
      link = tweet.urls.first.expanded_url
      tumbl :link,
        :url => follow_redirects(link),
        :description => info.caption,
        :title => title_at_url(link)
    else # quote
      tumbl :quote,
        :quote => info.text,
        :source => info.source
    end
  end

  def tumbl(type, data = {})
    puts "#{type}:\n#{data.inspect}"
    return if ENV["DEBUG"]
    tumblr.send(type, ENV["TUMBLR_BLOG_URL"], data)
  end

  def post
    info = TweetInfo.from_url(@text) || TweetInfo.from_url(follow_redirects(@text))
    return tumbl_post(info) if info

    abort "Couldn't find a post! Looked in:\n\n#{@text}"
  end

end
