# frozen_string_literal: true

# This example demonstrates a resilient Background Job (e.g. Sidekiq)
# that uses ollama-client to plan steps via structured generation.

require "ollama_client"

class AiPlanningJob
  # @return [Ollama::Client] A strictly-configured client safe for jobs
  def self.ollama_client
    @ollama_client ||= Ollama::Client.new(
      config: Ollama::Config.new.tap do |c|
        c.model = "llama3.2"    # Use a small, fast model
        c.timeout = 45          # Background jobs can afford longer timeouts
        c.retries = 3           # Let the built-in exponential backoff work
        c.strict_json = true    # Enforce JSON repair
      end
    )
  end

  def perform(user_request_id)
    # Background: User requested a system to schedule marketing emails.

    schema = {
      "type" => "object",
      "required" => ["category", "urgency", "decision"],
      "properties" => {
        "category" => { "type" => "string", "enum" => ["marketing", "support", "billing", "unknown"] },
        "urgency" => { "type" => "string", "enum" => ["low", "high"] },
        "decision" => { "type" => "string" }
      }
    }

    prompt = <<~PROMPT
      Analyze the following user request and categorize it.

      REQUEST ID: #{user_request_id}
      CONTENT: Pls send marketing blast tomorrow at 9AM.
    PROMPT

    begin
      # In this step:
      # - If the model is missing, `ollama-client` will pause and pull it directly.
      # - If `llama3.2` returns invalid JSON, the client will immediately hit it again appending a repair instruction.
      # - If the Ollama server is offline, it fails instantly so Sidekiq can handle the exception queue without waiting 45s.
      plan = self.class.ollama_client.generate(prompt: prompt, schema: schema)

      puts "Categorized as: #{plan['category']} with urgency #{plan['urgency']}"

      # Now your ruby logic continues based on the deterministic structured output
      # case plan['category'] ... end
    rescue Ollama::RetryExhaustedError => e
      # Even with repairs, the model failed 3 times. Move to Dead Letter Queue or notify humans.
      puts "Failed to parse Request #{user_request_id} after retries: #{e.message}"
    rescue Ollama::Error => e
      # Network unreachable, fast failure.
      puts "Ollama Service Unreachable: #{e.message}"
    end
  end
end

AiPlanningJob.new.perform(123) if __FILE__ == $PROGRAM_NAME
