# frozen_string_literal: true

require_relative "test_helper"

class ParallelBatchNodeTest < Minitest::Test
  class AsyncParallelNumberProcessor < Pocketflow::ParallelBatchNode
    def initialize(delay = 0.1, max_retries = 1, wait = 0)
      @delay = delay
      super(max_retries: max_retries, wait: wait)
    end

    def prep(shared)
      shared[:input_numbers] || []
    end

    def exec(num)
      sleep @delay
      num * 2
    end

    def post(shared, _prep, exec_res)
      shared[:processed_numbers] = exec_res
      "processed"
    end
  end

  class ErrorProcessor < Pocketflow::ParallelBatchNode
    def prep(shared)
      shared[:input_numbers] || []
    end

    def exec(item)
      raise "Error processing item #{item}" if item == 2
      item
    end
  end

  class OrderTrackingProcessor < Pocketflow::ParallelBatchNode
    def initialize
      @order = []
      super()
    end

    def prep(shared)
      @order.clear
      shared[:execution_order] = @order
      shared[:input_numbers] || []
    end

    def exec(item)
      delay = item.even? ? 0.1 : 0.05
      sleep delay
      @order << item
      item
    end

    def post(shared, *_)
      shared[:execution_order] = @order
      nil
    end
  end

  # Test-specific node to process results after initial batch processing
  class ProcessResultsNode < Pocketflow::ParallelBatchNode
    def prep(shared)
      shared[:processed_numbers] || []
    end
    def exec(num)
      num + 1
    end
    def post(shared, _prep, exec_res)
      shared[:final_results] = exec_res
      "completed"
    end
  end

  def test_parallel_processing_results
    shared = { input_numbers: (0..4).to_a }
    AsyncParallelNumberProcessor.new(0.01).run(shared)
    assert_equal [0, 2, 4, 6, 8], shared[:processed_numbers]
  end

  def test_empty_input
    shared = { input_numbers: [] }
    AsyncParallelNumberProcessor.new.run(shared)
    assert_equal [], shared[:processed_numbers]
  end

  def test_single_item
    shared = { input_numbers: [42] }
    AsyncParallelNumberProcessor.new.run(shared)
    assert_equal [84], shared[:processed_numbers]
  end

  def test_large_batch
    input_size = 100
    shared = { input_numbers: (0...input_size).to_a }
    AsyncParallelNumberProcessor.new(0.001).run(shared)
    expected = (0...input_size).map { |i| i * 2 }
    assert_equal expected, shared[:processed_numbers]
  end

  def test_error_handling
    shared = { input_numbers: [1, 2, 3] }
    assert_raises(RuntimeError) { ErrorProcessor.new.run(shared) }
  end

  def test_execution_order
    shared = { input_numbers: (0..3).to_a }
    OrderTrackingProcessor.new.run(shared)
    assert_equal [0, 1, 2, 3], shared[:execution_order]
  end

  def test_integration_with_flow
    shared = { input_numbers: (0..4).to_a }
    processor = AsyncParallelNumberProcessor.new
    results_proc = ProcessResultsNode.new
    processor.on("processed", results_proc)
    Pocketflow::Flow.new(processor).run(shared)
    assert_equal [1, 3, 5, 7, 9], shared[:final_results]
  end
end
