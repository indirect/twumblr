if File.exist? File.expand_path("../../.env", __FILE__)
  puts "requiring env"
  require 'dotenv'
  Dotenv.load
end
