require_relative "test_helper"

SharedStorage = Hash

class FlowCompositionTest < Minitest::Test
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
  # Test-specific Flow node with retry behavior
  class FaultyNumberNode < Pocketflow::Node
    def initialize(number, max_retries = 2, wait = 0.01)
      @number = number
      @attempts = 0
      super(max_retries: max_retries, wait: wait)
    end

    def prep(_shared)
      @number
    end

    def exec(val)
      @attempts += 1
      raise "Simulated failure on first attempt" if @attempts == 1
      val
    end

    def post(shared, _prep, exec_res)
      shared[:current] = exec_res
      "default"
    end
  end

  def test_flow_as_node
    shared = {}
    n = NumberNode.new(5)
    a = AddNode.new(10)
    m = MultiplyNode.new(2)
    n.next(a)
    a.next(m)
    f1 = Pocketflow::Flow.new(n)
    f2 = Pocketflow::Flow.new(f1)
    f3 = Pocketflow::Flow.new(f2)
    f3.run(shared)
    assert_equal 30, shared[:current]
  end

  def test_nested_flow
    shared = {}
    num = NumberNode.new(5)
    add = AddNode.new(3)
    num.next(add)
    inner = Pocketflow::Flow.new(num)
    mul = MultiplyNode.new(4)
    inner.next(mul)
    middle = Pocketflow::Flow.new(inner)
    wrapper = Pocketflow::Flow.new(middle)
    wrapper.run(shared)
    assert_equal 32, shared[:current]
  end

  def test_flow_chaining_flows
    shared = {}
    num = NumberNode.new(10)
    add = AddNode.new(10)
    num.next(add)
    flow1 = Pocketflow::Flow.new(num)
    mul = MultiplyNode.new(2)
    flow2 = Pocketflow::Flow.new(mul)
    flow1.next(flow2)
    wrapper = Pocketflow::Flow.new(flow1)
    wrapper.run(shared)
    assert_equal 40, shared[:current]
  end

  def test_flow_with_retry_handling
    shared = {}
    faulty = FaultyNumberNode.new(5)
    add = AddNode.new(10)
    mul = MultiplyNode.new(2)
    faulty.next(add)
    add.next(mul)
    flow = Pocketflow::Flow.new(faulty)
    flow.run(shared)
    assert_equal 30, shared[:current]
  end

  def test_nested_flows_with_mixed_retry_configurations
    shared = {}
    num = NumberNode.new(5, 5, 0.01)
    add = AddNode.new(3, 2, 0.01)
    num.next(add)
    inner = Pocketflow::Flow.new(num)
    mul = MultiplyNode.new(4, 3, 0.01)
    inner.next(mul)
    middle = Pocketflow::Flow.new(inner)
    wrapper = Pocketflow::Flow.new(middle)
    wrapper.run(shared)
    assert_equal 32, shared[:current]
  end
end
