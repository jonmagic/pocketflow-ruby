require_relative "test_helper"

class ParallelBatchFlowTest < Minitest::Test
  class AsyncParallelNumberProcessor < Pocketflow::ParallelBatchNode
    def initialize(delay = 0.1, max_retries = 1, wait = 0)
      @delay = delay
      super(max_retries: max_retries, wait: wait)
    end

    def prep(shared)
      bid = @params[:batchId]
      (shared[:batches] || [])[bid] || []
    end

    def exec(num)
      sleep @delay
      num * 2
    end

    def post(shared, _prep, exec_res)
      shared[:processed_numbers] ||= {}
      shared[:processed_numbers][@params[:batchId]] = exec_res
      "processed"
    end
  end

  class AsyncAggregatorNode < Pocketflow::Node
    def prep(shared)
      processed = shared[:processed_numbers] || {}
      all = []
      processed.keys.sort.each { |k| all.concat(processed[k]) }
      all
    end

    def exec(nums)
      sleep 0.01
      nums.reduce(0, :+)
    end

    def post(shared, _prep, total)
      shared[:total] = total
      "aggregated"
    end
  end

  class TestParallelBatchFlow < Pocketflow::ParallelBatchFlow
    def prep(shared)
      (shared[:batches] || []).each_index.map { |i| { batchId: i } }
    end
  end

  # Test-specific ErrorProcessor for error_handling test
  class ErrorProcessor < AsyncParallelNumberProcessor
    def exec(item)
      raise "Error processing item #{item}" if item == 2
      item
    end
  end

  def test_parallel_batch_flow_basic
    shared = { batches: [[1, 2, 3], [4, 5, 6], [7, 8, 9]] }
    processor = AsyncParallelNumberProcessor.new(0.01)
    aggregator = AsyncAggregatorNode.new
    processor.on("processed", aggregator)
    flow = TestParallelBatchFlow.new(processor)
    flow.run(shared)

    expected = {
      0 => [2, 4, 6],
      1 => [8, 10, 12],
      2 => [14, 16, 18]
    }
    assert_equal expected, shared[:processed_numbers]
    total_expected = shared[:batches].flatten.map { |n| n * 2 }.reduce(0, :+)
    assert_equal total_expected, shared[:total]
  end

  def test_error_handling
    shared = { batches: [[1, 2, 3], [4, 5, 6]] }
    processor = ErrorProcessor.new(0)
    flow = TestParallelBatchFlow.new(processor)
    assert_raises(RuntimeError) { flow.run(shared) }
  end

  def test_multiple_batch_sizes
    shared = { batches: [[1], [2, 3, 4], [5, 6], [7, 8, 9, 10]] }
    processor = AsyncParallelNumberProcessor.new(0.005)
    aggregator = AsyncAggregatorNode.new
    processor.on("processed", aggregator)
    flow = TestParallelBatchFlow.new(processor)
    flow.run(shared)
    expected = {
      0 => [2],
      1 => [4, 6, 8],
      2 => [10, 12],
      3 => [14, 16, 18, 20]
    }
    assert_equal expected, shared[:processed_numbers]
    total_expected = shared[:batches].flatten.map { |n| n * 2 }.reduce(0, :+)
    assert_equal total_expected, shared[:total]
  end
end
