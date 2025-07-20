# frozen_string_literal: true

require_relative "test_helper"

class QaPatternTest < Minitest::Test
  class GetQuestionNode < Pocketflow::Node
    def initialize(question)
      @question = question
      super()
    end
    def exec(_)
      @question
    end
    def post(shared, _prep, question)
      shared[:question] = question
      "default"
    end
  end

  class AnswerNode < Pocketflow::Node
    def prep(shared)
      shared[:question] || ""
    end
    def exec(question)
      # Inline QA logic to avoid conflicts with global call_llm definitions
      if question.include?("PocketFlow")
        "PocketFlow is a TypeScript library for building reliable AI pipelines with a focus on composition and reusability."
      else
        "I don't know the answer to that question."
      end
    end
    def post(shared, _prep, answer)
      shared[:answer] = answer
      nil
    end
  end

  def create_qa_flow(question)
    q = GetQuestionNode.new(question)
    a = AnswerNode.new
    q.next(a)
    Pocketflow::Flow.new(q)
  end

  def test_basic_qa_flow
    shared = {}
    flow = create_qa_flow("What is PocketFlow?")
    flow.run(shared)
    assert_equal "What is PocketFlow?", shared[:question]
    assert_equal "PocketFlow is a TypeScript library for building reliable AI pipelines with a focus on composition and reusability.", shared[:answer]
  end

  def test_unknown_question
    shared = {}
    flow = create_qa_flow("What is the meaning of life?")
    flow.run(shared)
    assert_equal "What is the meaning of life?", shared[:question]
    assert_equal "I don't know the answer to that question.", shared[:answer]
  end

  def test_empty_question
    shared = {}
    flow = create_qa_flow("")
    flow.run(shared)
    assert_equal "", shared[:question]
    assert_equal "I don't know the answer to that question.", shared[:answer]
  end
end
