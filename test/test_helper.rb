# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "pocketflow"

require "minitest/autorun"

# Shared constants used across tests
SharedStorage = Hash unless defined?(SharedStorage)
BatchParams = Hash unless defined?(BatchParams)

# Shared helper methods used across tests
def call_llm(question_or_prompt)
  if question_or_prompt.include?("PocketFlow")
    "PocketFlow is a TypeScript library for building reliable AI pipelines with a focus on composition and reusability."
  elsif question_or_prompt.start_with?("Summarize")
    "Summary for: #{question_or_prompt[0, 20]}..."
  else
    "I don't know the answer to that question."
  end
end unless defined?(call_llm)
