require "faraday"
require "upmark"

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
    require "tumblr_client"
    @tumblr ||= Tumblr::Client.new(
      :consumer_key => ENV["TUMBLR_CONSUMER_KEY"],
      :consumer_secret => ENV["TUMBLR_CONSUMER_SECRET_KEY"],
      :oauth_token => ENV["TUMBLR_OAUTH_TOKEN"],
      :oauth_token_secret => ENV["TUMBLR_OAUTH_TOKEN_SECRET"]
    )
  end

  def photo_data_from(urls)
    urls.map do |u|
      res = Faraday.get(u)
      io = StringIO.new(res.body)
      type = res.headers["content-type"]
      filename = u.split("/").last
      Faraday::UploadIO.new(io, type, filename)
    end
  end

  SkeetInfo = Struct.new(:skeet) do
    def self.from_url(url)
      return unless url.match(%r{bsky\.app|skeeet\.xyz})

      require "http"
      uri = URI.parse(url)
      post_uri = "https://skeeet.xyz#{uri.path}"
      post = HTTP.get(post_uri).to_s
      require "ox"
      skeet = Ox.load(post, mode: :generic, effort: :tolerant, smart: true)
      new(skeet)
    end

    def text
      body = skeet.locate("*/section[@id=body]/?[@class=body-text]").first
      text = body.nodes.map{|n| n.is_a?(String) ? n : Ox.dump(n) }.join

      "#{quote_text}#{text}"
    end

    def quote_text
      body = skeet.locate("*/section[@class=quoted-post]/?[@class=body-text]").first
      return unless body

      quote = "<blockquote><p>\n"
      quote << body.nodes.map{|n| n.is_a?(String) ? n : Ox.dump(n) }.join
      quote << "</p></blockquote>\n\n"
    end

    def source
      %|<a href="#{url}">#{attribution}</a>|
    end

    def url
      skeet.locate("*/a[@title]/@href").first
    end

    def attribution
      name = skeet.locate("*/?[@class=display-name]/h1").first&.text
      handle = skeet.locate("*/?[@class=display-name]/h2").first&.text
      "#{name} (#{handle})"
    end

    def photos
      skeet.locate("*/section[@id=images]/img").map(&:src)
    end

    def type
      if photos.any?
        :photo
      else
        :quote
      end
    end

    def data
      case type
      when :photo
        {caption: "#{text} — #{source}", data: photo_data_from(photos), link: url}
      when :quote
        {quote: text, source: source, format: "markdown"}
      else
        raise "unimplemented type #{type}!"
      end
    end

    def to_tumblr(tumblr)
      puts "#{type}:\n#{data.inspect}"
      return if ENV["DEBUG"]
      tumblr.send(type, ENV["TUMBLR_BLOG_URL"], data)
    end
  end

  ChostInfo = Struct.new(:chost) do
    def self.from_url(url)
      return unless url.match(%r|cohost.org|)

      require 'http'
      state = HTTP.get(url).to_s.match(%r|trpc-dehydrated-state">(.+?)</script|){|m| m[1] }
      trpc = JSON.parse(state)
      chost = trpc["queries"].find{|q| q.dig("queryKey", 0, 1) == "singlePost" }.dig("state", "data", "post")
      p chost if ENV["DEBUG"]
      return unless chost

      if chost["transparentShareOfPostId"]
        new(chost["shareTree"].find{|h| h["postId"] == chost["transparentShareOfPostId"] })
      else
        new(chost)
      end
    end

    def url
      chost["singlePostPageUrl"]
    end

    def text
      ["### #{chost["headline"]}", *chost["blocks"].flat_map{|b| b.dig("markdown", "content") }].join("\n\n")
    end

    def source
      %|<a href="#{url}">@#{chost.dig("postingProject", "handle")}</a>|
    end

    def caption
      [text, source].join(" — ")
    end

    def type
      :quote
    end

    def data
      case type
      when :quote
        {quote: text, source: source, format: "markdown"}
      else
        raise "unimplemented type #{type}!"
      end
    end

    def to_tumblr(tumblr)
      puts "#{type}:\n#{data.inspect}"
      return if ENV["DEBUG"]
      tumblr.send(type, ENV["TUMBLR_BLOG_URL"], data)
    end
  end

  TweetInfo = Struct.new(:tweet) do
    def self.from_url(url)
      tweet_id = url.match(%r{(twitter|twittpr|x).com/\w*/status/(\d*)}){|m| m[2] }
      return nil unless tweet_id

      require "http"
      info_url = "https://api.vxtwitter.com/i/status/#{tweet_id}"
      new(HTTP.get(info_url).parse)
    end

    def quoted_tweet
      @qt ||= TweetInfo.from_url(tweet["qrtURL"]) if tweet["qrtURL"]
    end

    def url
      tweet["tweetURL"]
    end

    def quoted_text
      return unless quoted_tweet

      "<blockquote><p>\n" \
      "#{quoted_tweet.source}: #{quoted_tweet.text}\n" \
      "</p></blockquote>\n\n"
    end

    def text
      "#{quoted_text}#{tweet["text"].gsub("\n", "\n<br>")}"
    end

    def attribution
      "#{tweet["user_name"]} (@#{tweet["user_screen_name"]})"
    end

    def source
      %|<a href="#{url}">#{attribution}</a>|
    end

    def caption
      [text, source].join(" — ")
    end

    def photos
      tweet["media_extended"].
        select{|h| h["type"] == "image" }.
        map{|h| h["url"] }
    end

    def videos
      tweet["media_extended"].
        select{|h| h["type"] == "video" }.
        map{|h| h["url"] }
    end

    def type
      if videos.any?
        :video
      elsif photos.any?
        :photo
      else
        :quote
      end
    end

    def data
      case type
      when :video
        {caption: "#{text} — #{source}", data: photo_data_from(videos), link: url}
      when :photo
        {caption: "#{text} — #{source}", data: photo_data_from(photos), link: url}
      when :quote
        {quote: text, source: source, format: "markdown"}
      else
        raise "unimplemented type #{type}!"
      end
    end

    def to_tumblr(tumblr)
      puts "#{type}:\n#{data.inspect}"
      return if ENV["DEBUG"]
      tumblr.send(type, ENV["TUMBLR_BLOG_URL"], data)
    end
  end

  PostInfo = Struct.new(:post) do
    def self.from_url(url)
      base, id = url.match(%r{(https?://.*?)/@.*/(\d+)}){|m| [m[1], m[2]] }
      return nil unless base && id

      require 'http'
      post_uri = "#{base}/api/v1/statuses/#{id}"
      post = HTTP.get(post_uri).parse
      p post if ENV["DEBUG"]
      new(post)
    end

    def url
      post["url"]
    end

    def text
      post["content"]
    end

    def source
      %|<a href="#{url}">@#{post.dig("account", "username")}</a>|
    end

    def caption
      [text, source].join(" — ")
    end

    def type
      if post.dig("media_attachments", 0, "type") == "video"
        :video
      elsif post.dig("media_attachments", 0, "type") == "image"
        :photo
      else
        :quote
      end
    end

    def data
      case type
      when :photo
        {
          :caption => caption,
          :data => photo_data,
          :link => url
        }
      when :quote
        {quote: text, source: source, format: "markdown"}
      else
        raise "unimplemented type #{type}!"
      end
    end

    def photo_data
      post.fetch("media_attachments", []).map do |m|
        create_faraday_upload(m["url"])
      end
    end

    def create_faraday_upload(url)
      res = Faraday.get(url)
      io = StringIO.new(res.body)
      type = res.headers["content-type"]
      filename = url.split("/").last
      Faraday::UploadIO.new(io, type, filename)
    end

    def to_tumblr(tumblr)
      puts "#{type}:\n#{data.inspect}"
      return if ENV["DEBUG"]
      tumblr.send(type, ENV["TUMBLR_BLOG_URL"], data)
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
    skeet = SkeetInfo.from_url(@text)
    return skeet.to_tumblr(tumblr) if skeet

    chost = ChostInfo.from_url(@text)
    return chost.to_tumblr(tumblr) if chost

    tweet = TweetInfo.from_url(@text) || TweetInfo.from_url(follow_redirects(@text))
    return tweet.to_tumblr(tumblr) if tweet

    post = PostInfo.from_url(@text)
    return post.to_tumblr(tumblr) if post

    abort "Couldn't find a post! Looked in:\n\n#{@text}"
  end

end
