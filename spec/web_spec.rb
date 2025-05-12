require "spec_helper"
require "rack/test"
require "web"

describe Web, :vcr do
  include Rack::Test::Methods

  let(:app) { Web.new }

  describe "/post" do
    it "delegates to Twumblr" do
      post "/post", plain: "https://transfem.social/notes/a7mgctvw8cub4i6v"
      expect(last_response.body).to eq("")
      expect(last_response.status).to eq(200)
    end
  end
end
