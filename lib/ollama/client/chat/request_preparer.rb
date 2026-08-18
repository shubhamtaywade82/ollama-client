# frozen_string_literal: true

require_relative "../../multimodal_input"
require_relative "../../prompt_adapters"

module Ollama
  class Client
    module Chat
      # Prepares Chat Request objects from client configuration and inputs
      class RequestPreparer
        def initialize(config:, provider:)
          @config = config
          @provider = provider
        end

        # rubocop:disable Metrics/MethodLength
        def build_request(params, client_instance)
          target_model = params.model || @config.model
          active_profile = client_instance.send(:resolve_profile, target_model, params.profile)
          adapter = PromptAdapters.for(active_profile) if active_profile

          messages = if params.inputs
                       apply_inputs(params.messages, params.inputs, active_profile)
                     else
                       params.messages
                     end

          adapted_messages = if adapter
                               adapter.adapt_messages(messages, think: !params.think.nil?, tools: params.tools)
                             else
                               messages
                             end

          effective_think = resolve_think_flag(params.think, adapter)
          stream_enabled = params.stream.nil? ? hooks_present?(params.hooks) : params.stream

          Request.new(
            endpoint: :chat,
            model: target_model,
            messages: adapted_messages,
            tools: params.tools,
            format: params.format,
            think: effective_think,
            keep_alive: params.keep_alive,
            options: client_instance.send(:build_options_with_profile, params.options, active_profile),
            stream: stream_enabled,
            metadata: {
              base_url: @config.base_url,
              timeout: @config.timeout,
              hooks: params.hooks,
              uri: @provider.chat_endpoint
            },
            raw_options: {
              logprobs: params.logprobs,
              top_logprobs: params.top_logprobs
            }
          )
        end
        # rubocop:enable Metrics/MethodLength

        private

        def hooks_present?(hooks)
          [hooks[:on_token], hooks[:on_thought], hooks[:on_error],
           hooks[:on_complete], hooks[:on_tool_call]].any?
        end

        def apply_inputs(messages, inputs, active_profile)
          input_obj = MultimodalInput.build(inputs, profile: active_profile || ModelProfile.for("generic"))
          messages + [input_obj.to_message]
        end

        def resolve_think_flag(think, adapter)
          return nil if think.nil?
          return nil if adapter&.inject_think_flag? == false && adapter.is_a?(PromptAdapters::Gemma4)

          think
        end
      end
    end
  end
end
