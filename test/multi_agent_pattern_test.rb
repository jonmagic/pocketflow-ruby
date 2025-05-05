require_relative "test_helper"

SharedStorage = Hash

def mock_llm(prompt)
  return "This is a hint: Something cold on a stick" if prompt.include?("Generate hint")
  return "popsicle" if prompt.include?("Guess")
  "Response to: #{prompt[0, 20]}..."
end

class MultiAgentPatternTest < Minitest::Test
  class ListenerAgent < Pocketflow::Node
    def prep(shared)
      return nil if shared[:messages].empty?
      shared[:messages].shift
    end

    def exec(message)
      return nil unless message
      "Processed: #{message}"
    end

    def post(shared, _prep_res, exec_res)
      shared[:processed_messages] << exec_res if exec_res
      shared[:messages].empty? ? "finished" : "continue"
    end
  end

  def run_flow_until_finished(flow, shared)
    loop do
      action = flow.run(shared)
      break if action == "finished"
    end
  end

  def test_basic_agent_message_queue
    agent = ListenerAgent.new
    agent.on("continue", agent)
    flow = Pocketflow::Flow.new(agent)
    shared = {
      messages: [
        "System status: all systems operational",
        "Memory usage: normal",
        "Network connectivity: stable",
        "Processing load: optimal"
      ],
      processed_messages: []
    }
    flow.run(shared)
    assert_equal 0, shared[:messages].size
    assert_equal 4, shared[:processed_messages].size
    assert_equal "Processed: System status: all systems operational", shared[:processed_messages][0]
  end

  # Taboo game agents
  class Hinter < Pocketflow::Node
    def prep(shared)
      return nil if shared[:game_over]
      return nil if shared[:hinter_queue].empty?
      message = shared[:hinter_queue].shift
      { target: shared[:target_word], forbidden: shared[:forbidden_words], past_guesses: shared[:past_guesses], message: message }
    end

    def exec(input)
      return nil unless input
      mock_llm("Generate hint for word \"#{input[:target]}\" without using forbidden words: #{input[:forbidden].join(', ')}")
    end

    def post(shared, _prep, hint)
      return "finished" if shared[:game_over]
      # End flow when no hint is generated
      return "finished" unless hint
      shared[:guesser_queue] << hint
      shared[:current_round] += 1
      # Continue providing hints
      "continue_hinter"
    end
  end

  class Guesser < Pocketflow::Node
    def prep(shared)
      return nil if shared[:game_over]
      return nil if shared[:guesser_queue].empty?
      shared[:guesser_queue].shift
    end

    def exec(hint)
      return nil unless hint
      mock_llm("Guess the word based on the hint: #{hint}")
    end

    def post(shared, _prep, guess)
      return "finished" if shared[:game_over]
      # End flow when no guess to process
      return "finished" unless guess
      shared[:past_guesses] << guess
      if guess.downcase == shared[:target_word].downcase
        shared[:is_correct_guess] = true
        shared[:game_over] = true
        return "finished"
      end
      if shared[:current_round] >= shared[:max_rounds]
        shared[:game_over] = true
        return "finished"
      end
      # Request next hint
      shared[:hinter_queue] << "next_hint"
      "continue_guesser"
    end
  end

  def test_taboo_game_multi_agent_interaction
    hinter = Hinter.new
    guesser = Guesser.new
    hinter.on("continue_hinter", hinter)
    guesser.on("continue_guesser", guesser)
    shared = {
      target_word: "popsicle",
      forbidden_words: %w[ice cream frozen stick summer],
      past_guesses: [],
      hinter_queue: ["start_game"],
      guesser_queue: [],
      game_over: false,
      max_rounds: 3,
      current_round: 0,
      is_correct_guess: false
    }
    hinter_flow = Pocketflow::Flow.new(hinter)
    guesser_flow = Pocketflow::Flow.new(guesser)
    until shared[:game_over]
      hinter_flow.run(shared)
      guesser_flow.run(shared)
    end
    assert shared[:game_over]
    assert shared[:past_guesses].size.positive?
    assert shared[:is_correct_guess]
  end

  class ConfigurableAgent < Pocketflow::Node
    def initialize(delay = 0)
      @delay = delay
      super()
    end

    def prep(shared)
      return nil if shared[:messages].empty?
      shared[:messages].shift
    end

    def exec(message)
      return nil unless message
      sleep(@delay / 1000.0) if @delay.positive?
      "Processed with #{@delay}ms delay: #{message}"
    end

    def post(shared, _prep, exec_res)
      shared[:processed_messages] << exec_res if exec_res
      shared[:messages].empty? ? "finished" : "continue"
    end
  end

  def test_configurable_agent_behavior
    # fast agent
    fast_agent = ConfigurableAgent.new(0)
    fast_agent.on("continue", fast_agent)
    flow_fast = Pocketflow::Flow.new(fast_agent)
    fast_shared = { messages: ["Message 1", "Message 2", "Message 3"], processed_messages: [] }
    flow_fast.run(fast_shared)

    # slow agent
    slow_agent = ConfigurableAgent.new(10)
    slow_agent.on("continue", slow_agent)
    flow_slow = Pocketflow::Flow.new(slow_agent)
    slow_shared = { messages: ["Message 1", "Message 2", "Message 3"], processed_messages: [] }
    flow_slow.run(slow_shared)

    assert_equal 3, fast_shared[:processed_messages].size
    assert_equal 3, slow_shared[:processed_messages].size
    assert_includes fast_shared[:processed_messages][0], "Processed with 0ms delay"
    assert_includes slow_shared[:processed_messages][0], "Processed with 10ms delay"
  end
end
