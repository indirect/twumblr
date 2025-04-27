require "faraday"
require "http"
require "upmark"
require "uri"

class Info < Struct
  def uploads_for(urls)
    urls.map { |u| Twumblr.upload_for(u) }
  end
end

class Twumblr
  def initialize(text)
    @text = text
  end

  def follow_redirects(url)
    res = HTTP.head(url)
    res = HTTP.head(res.headers['Location']) while res.headers['Location']
    res.uri.to_s
  end

  def tumblr
    self.class.client
  end

  def self.client
    require "tumblr_client"
    @client ||= Tumblr::Client.new(
      :consumer_key => ENV["TUMBLR_CONSUMER_KEY"],
      :consumer_secret => ENV["TUMBLR_CONSUMER_SECRET_KEY"],
      :oauth_token => ENV["TUMBLR_OAUTH_TOKEN"],
      :oauth_token_secret => ENV["TUMBLR_OAUTH_TOKEN_SECRET"]
    )
  end

  def self.upload_for(u)
    res = HTTP.follow.get(u)
    io = StringIO.new(res.body)
    type = res.headers["content-type"]
    filename = u.split("/").last
    Faraday::UploadIO.new(io, type, filename)
  end

  SkeetInfo = Info.new(:skeet) do
    def self.from_url(url)
      return unless url.match(%r{bsky\.app|dbsky\.app})

      # Remove skeet.xyz URL param if present
      url = url.gsub("?url=https://bsky.app/", "")

      uri = URI.parse(url)
      require "http"
      post = HTTP.get("https://dbsky.app#{uri.path}").to_s
      require "ox"
      skeet = Ox.load(post, mode: :generic, effort: :tolerant, smart: true)
      new(skeet)
    end

    def text
      body = skeet.locate("*/section[@id=body]/?[@class=body-text]").last
      text = body.nodes.map{|n| n.is_a?(String) ? n : Ox.dump(n) }.join

      "#{quote_text}#{text}"
    end

    def quote_text
      body = skeet.locate("*/section[@class=quoted-post]/?[@class=body-text]").last
      return unless body

      quote = "<blockquote><p>\n"
      quote << body.nodes.map{|n| n.is_a?(String) ? n : Ox.dump(n) }.join
      quote << "</p></blockquote>\n\n"
    end

    def source
      %|<a href="#{url}">#{attribution}</a>|
    end

    def url
      skeet.locate("*/a[@title]/@href").last
    end

    def attribution
      name = skeet.locate("*/?[@class=display-name]/h1").last&.text
      handle = skeet.locate("*/?[@class=display-name]/h2").last&.text
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
        {caption: "#{text} — #{source}", data: uploads_for(photos), link: url}
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

  ChostInfo = Info.new(:chost) do
    def self.from_url(url)
      return unless url.match(%r|cohost.org|)

      page = HTTP.get(url).to_s.match(%r|(<head>.+</head>)|m){|m| m[1] }
      return unless page

      require "ox"
      elements = Ox.load(page, mode: :generic, effort: :tolerant, smart: true)
      chost = elements.locate("*/meta[@property]").map{|m| [m.property, m.content] }.to_h

      p chost if ENV["DEBUG"]
      new(chost)
    end

    def url
      chost["og:url"]
    end

    def text
      text = chost.fetch("og:title", "")
      text << "\n\n" if chost.key?("og:title")
      text << chost["og:description"]
    end

    def handle
      chost["og:image:alt"]
    end

    def source
      %|<a href="#{url}">@#{handle}</a>|
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

  TweetInfo = Info.new(:tweet) do
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
        {caption: "#{text} — #{source}", data: uploads_for(videos)}
      when :photo
        {caption: "#{text} — #{source}", data: uploads_for(photos), link: url}
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

  PostInfo = Info.new(:post) do
    def self.from_url(url)
      page = HTTP.get(url).to_s.match(%r|(<head.+</head>)|m){|m| m[1] }
      return unless page

      require "ox"
      doc = Ox.load(page, mode: :generic, effort: :tolerant, smart: true)
      post = doc.locate("*/meta").map do |m|
        [m.attributes[:name], m.attributes[:content]]
      end.to_h.compact.merge("url" => url)

      p post if ENV["DEBUG"]
      new(post)
    end

    def url
      post["url"]
    end

    def text
      post["og:description"].gsub(/\n\(\d+ attachments?\)/, "")
    end

    def source
      %|<a href="#{url}">@#{post["og:title"]}</a>|
    end

    def caption
      [text, source].join(" — ")
    end

    def type
      if post["og:image"]
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
          :data => uploads_for(media_urls),
          :link => url
        }
      when :quote
        {quote: text, source: source, format: "markdown"}
      else
        raise "unimplemented type #{type}!"
      end
    end

    def media_urls
      [post["og:image"]]
    end

    def to_tumblr(tumblr)
      puts "#{type}:\n#{data.inspect}"
      return if ENV["DEBUG"]
      tumblr.send(type, ENV["TUMBLR_BLOG_URL"], data)
    end
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
