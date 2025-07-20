# frozen_string_literal: true

require_relative "test_helper"

class FlowBasicTest < Minitest::Test
  class NumberNode < Pocketflow::Node
    def initialize(number, max_retries = 1, wait = 0)
      @number = number
      super(max_retries: max_retries, wait: wait)
    end

    def prep(shared)
      shared[:current] = @number
      nil
    end
  end

  class AddNode < Pocketflow::Node
    def initialize(number, max_retries = 1, wait = 0)
      @number = number
      super(max_retries: max_retries, wait: wait)
    end

    def prep(shared)
      shared[:current] += @number if shared.key?(:current)
      nil
    end
  end

  class MultiplyNode < Pocketflow::Node
    def initialize(number, max_retries = 1, wait = 0)
      @number = number
      super(max_retries: max_retries, wait: wait)
    end

    def prep(shared)
      shared[:current] *= @number if shared.key?(:current)
      nil
    end
  end

  class CheckPositiveNode < Pocketflow::Node
    def post(shared, _prep_res, _exec_res)
      shared.key?(:current) && shared[:current] >= 0 ? "positive" : "negative"
    end
  end

  class NoOpNode < Pocketflow::Node
    def prep(_shared)
      nil
    end
  end

  class FlakyNode < Pocketflow::Node
    def initialize(fail_until_attempt, max_retries = 3, wait = 0.01)
      @fail_until_attempt = fail_until_attempt
      @attempt_count = 0
      super(max_retries: max_retries, wait: wait)
    end

    def exec(_)
      @attempt_count += 1
      raise "Attempt #{@attempt_count} failed" if @attempt_count < @fail_until_attempt
      "Success on attempt #{@attempt_count}"
    end

    def post(shared, _prep_res, exec_res)
      shared[:exec_result] = exec_res
      "default"
    end
  end

  class ExecNode < Pocketflow::Node
    def initialize(operation, max_retries = 1, wait = 0)
      @operation = operation
      super(max_retries: max_retries, wait: wait)
    end

    def prep(shared)
      shared[:current] || 0
    end

    def exec(current_value)
      case @operation
      when "square" then current_value * current_value
      when "double" then current_value * 2
      when "negate" then -current_value
      else current_value
      end
    end

    def post(shared, _prep_res, exec_res)
      shared[:current] = exec_res
      "default"
    end
  end

  def test_single_number
    shared = {}
    start = NumberNode.new(5)
    pipeline = Pocketflow::Flow.new(start)
    pipeline.run(shared)
    assert_equal 5, shared[:current]
  end

  def test_sequence_with_chaining
    shared = {}
    n1 = NumberNode.new(5)
    n2 = AddNode.new(3)
    n3 = MultiplyNode.new(2)
    n1.next(n2).next(n3)
    pipeline = Pocketflow::Flow.new(n1)
    pipeline.run(shared)
    assert_equal 16, shared[:current]
  end

  def test_branching_positive
    shared = {}
    start = NumberNode.new(5)
    check = CheckPositiveNode.new
    add_pos = AddNode.new(10)
    add_neg = AddNode.new(-20)
    start.next(check).on("positive", add_pos).on("negative", add_neg)
    pipeline = Pocketflow::Flow.new(start)
    pipeline.run(shared)
    assert_equal 15, shared[:current]
  end

  def test_negative_branch
    shared = {}
    start = NumberNode.new(-5)
    check = CheckPositiveNode.new
    add_pos = AddNode.new(10)
    add_neg = AddNode.new(-20)
    start.next(check).on("positive", add_pos).on("negative", add_neg)
    pipeline = Pocketflow::Flow.new(start)
    pipeline.run(shared)
    assert_equal(-25, shared[:current])
  end

  def test_cycle_until_negative
    shared = {}
    n1 = NumberNode.new(10)
    check = CheckPositiveNode.new
    subtract3 = AddNode.new(-3)
    no_op = NoOpNode.new
    n1.next(check).on("positive", subtract3).on("negative", no_op)
    subtract3.next(check)
    pipeline = Pocketflow::Flow.new(n1)
    pipeline.run(shared)
    assert_equal(-2, shared[:current])
  end

  def test_retry_functionality
    shared = {}
    flaky_node = FlakyNode.new(2, 3, 0.01)
    pipeline = Pocketflow::Flow.new(flaky_node)
    pipeline.run(shared)
    assert_equal "Success on attempt 2", shared[:exec_result]
  end

  def test_retry_with_fallback
    shared = {}
    flaky_node = FlakyNode.new(5, 2, 0.01)
    def flaky_node.exec_fallback(_prep, _err)
      "Fallback executed due to failure"
    end
    pipeline = Pocketflow::Flow.new(flaky_node)
    pipeline.run(shared)
    assert_equal "Fallback executed due to failure", shared[:exec_result]
  end

  def test_exec_method_processing
    shared = { current: 5 }
    square = ExecNode.new("square")
    doub   = ExecNode.new("double")
    neg    = ExecNode.new("negate")
    square.next(doub).next(neg)
    pipeline = Pocketflow::Flow.new(square)
    pipeline.run(shared)
    assert_equal(-50, shared[:current])
  end
end
