require_relative "test_helper"

SharedStorage = Hash

class FallbackTest < Minitest::Test
  class FallbackNode < Pocketflow::Node
    def initialize(should_fail = true, max_retries = 1, wait = 0)
      @should_fail = should_fail
      @attempt_count = 0
      super(max_retries: max_retries, wait: wait)
    end

    def prep(shared)
      shared[:results] ||= []
      nil
    end

    def exec(*)
      @attempt_count += 1
      raise "Intentional failure" if @should_fail
      "success"
    end

    def exec_fallback(*_)
      "fallback"
    end

    def post(shared, _prep, exec_res)
      shared[:results] << { attempts: @attempt_count, result: exec_res }
      nil
    end
  end

  class AsyncFallbackNode < Pocketflow::Node
    def initialize(should_fail = true, max_retries = 1, wait = 0)
      @should_fail = should_fail
      @attempt_count = 0
      super(max_retries: max_retries, wait: wait)
    end

    def prep(shared)
      shared[:results] ||= []
      nil
    end

    def exec(*)
      @attempt_count += 1
      raise "Intentional async failure" if @should_fail
      "success"
    end

    def exec_fallback(*_)
      "async_fallback"
    end

    def post(shared, _prep, exec_res)
      shared[:results] << { attempts: @attempt_count, result: exec_res }
      nil
    end
  end

  class ResultNode < Pocketflow::Node
    def prep(shared)
      shared[:results] || []
    end

    def exec(prep_res)
      prep_res
    end

    def post(shared, _prep, exec_res)
      shared[:final_result] = exec_res
      nil
    end
  end

  class NoFallbackNode < Pocketflow::Node
    def prep(shared)
      shared[:results] ||= []
      nil
    end

    def exec(*)
      raise "Test error"
    end

    def post(shared, *_)
      shared[:results] << { attempts: 1, result: "should_not_reach" }
      "should_not_reach"
    end
  end

  class EventualSuccessNode < Pocketflow::Node
    def initialize(succeed_after = 2, max_retries = 3, wait = 0.01)
      @succeed_after = succeed_after
      @attempt_count = 0
      super(max_retries: max_retries, wait: wait)
    end

    def prep(shared)
      shared[:results] ||= []
      nil
    end

    def exec(*)
      @attempt_count += 1
      raise "Fail on attempt #{@attempt_count}" if @attempt_count < @succeed_after
      "success_after_#{@attempt_count}_attempts"
    end

    def post(shared, *_prep, exec_res)
      shared[:results] << { attempts: @attempt_count, result: exec_res }
      nil
    end
  end

  class CustomErrorHandlerNode < Pocketflow::Node
    def initialize(error_type = "standard", max_retries = 1, wait = 0)
      @error_type = error_type
      super(max_retries: max_retries, wait: wait)
    end

    def prep(shared)
      shared[:results] ||= []
      nil
    end

    def exec(*)
      raise @error_type
    end

    def exec_fallback(*_, error)
      case error.message
      when "network" then "network_error_handled"
      when "timeout" then "timeout_error_handled"
      else "generic_error_handled"
      end
    end

    def post(shared, *_prep, exec_res)
      shared[:results] << { attempts: 1, result: exec_res }
      nil
    end
  end

  def test_successful_execution
    shared = {}
    node = FallbackNode.new(false)
    node.run(shared)
    assert_equal 1, shared[:results].size
    assert_equal 1, shared[:results][0][:attempts]
    assert_equal "success", shared[:results][0][:result]
  end

  def test_fallback_after_failure
    shared = {}
    node = AsyncFallbackNode.new(true, 2)
    node.run(shared)
    assert_equal 1, shared[:results].size
    assert_equal 2, shared[:results][0][:attempts]
    assert_equal "async_fallback", shared[:results][0][:result]
  end

  def test_fallback_in_flow
    shared = {}
    fnode = FallbackNode.new(true, 1)
    rnode = ResultNode.new
    fnode.next(rnode)
    flow = Pocketflow::Flow.new(fnode)
    flow.run(shared)
    assert_equal 1, shared[:results].size
    assert_equal "fallback", shared[:results][0][:result]
    assert_equal [{ attempts: 1, result: "fallback" }], shared[:final_result]
  end

  def test_no_fallback_implementation
    shared = {}
    node = NoFallbackNode.new
    assert_raises(RuntimeError, "Test error") { node.run(shared) }
  end

  def test_retry_before_fallback
    shared = {}
    node = AsyncFallbackNode.new(true, 3)
    node.run(shared)
    assert_equal 1, shared[:results].size
    assert_equal 3, shared[:results][0][:attempts]
    assert_equal "async_fallback", shared[:results][0][:result]
  end

  def test_eventual_success_after_retries
    shared = {}
    node = EventualSuccessNode.new(2, 3)
    node.run(shared)
    assert_equal 1, shared[:results].size
    assert_equal 2, shared[:results][0][:attempts]
    assert_equal "success_after_2_attempts", shared[:results][0][:result]
  end

  def test_custom_error_handling_based_on_error_type
    shared1 = {}
    CustomErrorHandlerNode.new("network").run(shared1)
    assert_equal "network_error_handled", shared1[:results][0][:result]

    shared2 = {}
    CustomErrorHandlerNode.new("timeout").run(shared2)
    assert_equal "timeout_error_handled", shared2[:results][0][:result]

    shared3 = {}
    CustomErrorHandlerNode.new("other").run(shared3)
    assert_equal "generic_error_handled", shared3[:results][0][:result]
  end

  def test_flow_with_mixed_retry_patterns
    shared = {}
    node1 = FallbackNode.new(true, 1)
    node2 = AsyncFallbackNode.new(false, 2)
    node3 = EventualSuccessNode.new(2, 3)
    result_node = ResultNode.new
    node1.next(node2)
    node2.next(node3)
    node3.next(result_node)
    flow = Pocketflow::Flow.new(node1)
    flow.run(shared)
    assert_equal 3, shared[:results].size
    assert_equal "fallback", shared[:results][0][:result]
    assert_equal "success", shared[:results][1][:result]
    assert_equal "success_after_2_attempts", shared[:results][2][:result]
  end
end
