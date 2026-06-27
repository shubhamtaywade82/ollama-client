require "bundler/setup"
require "webmock"
WebMock.disable_net_connect!
WebMock.stub_request(:post, "http://localhost:11434/api/generate")
  .to_return(status: 200, body: { response: '{"action":"search","input":{},"extra":"nope"}' }.to_json)
require_relative "lib/ollama/config"
require_relative "lib/ollama/client"
client = Ollama::Client.new(config: Ollama::Config.new(base_url: "http://localhost:11434", strict_json: true).tap { |c| c.retries = 0 })
begin
  p client.generate(
    prompt: "Find next step",
    tools: [{ name: "search", description: "Search the web" }],
    schema: {"type"=>"object", "required"=>%w[action], "properties"=>{"action"=>{"type"=>"string"}, "input"=>{"type"=>"object"}}, "additionalProperties"=>false},
    strict: true
  )
rescue => e
  p [e.class, [e.message]]
end
