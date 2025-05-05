require_relative "test_helper"

SharedStorage = Hash
BatchParams = Hash

class AsyncDataProcessNode < Pocketflow::Node
  def prep(shared)
    key  = @params[:key]
    data = shared.dig(:input_data, key) || 0
    shared[:results] ||= {}
    shared[:results][key] = data
    data
  end

  def exec(prep_res) = prep_res

  def post(shared, _prep_res, exec_res)
    key = @params[:key]
    shared[:results] ||= {}
    shared[:results][key] = exec_res * 2
    "processed"
  end
end

class AsyncErrorNode < Pocketflow::Node
  def post(_shared, _prep_res, _exec_res)
    key = @params[:key]
    raise "Async error processing key: #{key}" if key == :errorKey
    "processed"
  end
end

class BatchFlowTest < Minitest::Test
  # Test-specific BatchFlow subclasses and Nodes, defined at class-level to satisfy Ruby syntax
  class SimpleTestBatchFlow < Pocketflow::BatchFlow
    def prep(shared)
      (shared[:input_data] || {}).keys.map { |k| { key: k } }
    end
  end

  class EmptyTestBatchFlow < Pocketflow::BatchFlow
    def prep(shared)
      shared[:results] ||= {}
      (shared[:input_data] || {}).keys.map { |k| { key: k } }
    end

    def post(shared, _prep_res, _exec_res)
      shared[:results] ||= {}
      nil
    end
  end

  class ErrorTestBatchFlow < Pocketflow::BatchFlow
    def prep(shared)
      (shared[:input_data] || {}).keys.map { |k| { key: k } }
    end
  end

  class AsyncInnerNode < Pocketflow::Node
    def post(shared, _prep_res, _exec_res)
      key = @params[:key]
      shared[:intermediate_results] ||= {}
      input_val = shared.dig(:input_data, key) || 0
      shared[:intermediate_results][key] = input_val + 1
      "next"
    end
  end

  class AsyncOuterNode < Pocketflow::Node
    def post(shared, _prep_res, _exec_res)
      key = @params[:key]
      shared[:results] ||= {}
      inter = shared.dig(:intermediate_results, key) || 0
      shared[:results][key] = inter * 2
      "done"
    end
  end

  class NestedBatchFlow < Pocketflow::BatchFlow
    def prep(shared)
      (shared[:input_data] || {}).keys.map { |k| { key: k } }
    end
  end

  class CustomParamNode < Pocketflow::Node
    def post(shared, _prep_res, _exec_res)
      key        = @params[:key]
      multiplier = @params[:multiplier] || 1
      shared[:results] ||= {}
      input_val = shared.dig(:input_data, key) || 0
      shared[:results][key] = input_val * multiplier
      "done"
    end
  end

  class CustomParamBatchFlow < Pocketflow::BatchFlow
    def prep(shared)
      (shared[:input_data] || {}).keys.each_with_index.map do |k, i|
        { key: k, multiplier: i + 1 }
      end
    end
  end

  def test_basic_async_batch_processing
    shared = { input_data: { a: 1, b: 2, c: 3 } }
    flow   = SimpleTestBatchFlow.new(AsyncDataProcessNode.new)

    flow.run(shared)

    assert_equal({ a: 2, b: 4, c: 6 }, shared[:results])
  end

  def test_empty_async_batch
    shared = { input_data: {} }
    flow   = EmptyTestBatchFlow.new(AsyncDataProcessNode.new)

    flow.run(shared)

    assert_equal({}, shared[:results])
  end

  def test_async_error_handling
    shared = { input_data: { normalKey: 1, errorKey: 2, anotherKey: 3 } }
    flow   = ErrorTestBatchFlow.new(AsyncErrorNode.new)

    err = assert_raises RuntimeError do
      flow.run(shared)
    end
    assert_match "Async error processing key: errorKey", err.message
  end

  def test_nested_async_flow
    inner_node = AsyncInnerNode.new
    outer_node = AsyncOuterNode.new
    inner_node.on("next", outer_node)

    shared = { input_data: { x: 1, y: 2 } }
    flow   = NestedBatchFlow.new(inner_node)

    flow.run(shared)

    assert_equal({ x: 4, y: 6 }, shared[:results])
  end

  def test_custom_async_parameters
    shared = { input_data: { a: 1, b: 2, c: 3 } }
    flow   = CustomParamBatchFlow.new(CustomParamNode.new)

    flow.run(shared)

    assert_equal({ a: 1, b: 4, c: 9 }, shared[:results])
  end
end
