# frozen_string_literal: true

require_relative "test_helper"
require "benchmark"

class ConcurrencyPerformanceTest < Minitest::Test
  class SlowProcessor < Pocketflow::BatchNode
    def prep(shared)
      shared[:numbers] || []
    end

    def exec(item)
      sleep 0.1  # Simulate I/O operation
      item * 2
    end

    def post(shared, _prep, exec_res)
      shared[:results] = exec_res
      nil
    end
  end

  class ParallelSlowProcessor < Pocketflow::ParallelBatchNode
    def prep(shared)
      shared[:numbers] || []
    end

    def exec(item)
      sleep 0.1  # Simulate I/O operation
      item * 2
    end

    def post(shared, _prep, exec_res)
      shared[:results] = exec_res
      nil
    end
  end

  def test_parallel_performance_improvement
    numbers = [1, 2, 3, 4, 5]  # 5 items with 0.1s each = ~0.5s sequential

    # Test sequential processing
    shared_seq = { numbers: numbers }
    sequential_time = Benchmark.realtime do
      SlowProcessor.new.run(shared_seq)
    end

    # Test parallel processing
    shared_par = { numbers: numbers }
    parallel_time = Benchmark.realtime do
      ParallelSlowProcessor.new.run(shared_par)
    end

    # Results should be the same
    assert_equal [2, 4, 6, 8, 10], shared_seq[:results]
    assert_equal [2, 4, 6, 8, 10], shared_par[:results]

    # Parallel should be significantly faster (allowing some overhead)
    # Sequential: ~0.5s, Parallel: ~0.1s (plus thread overhead)
    assert parallel_time < sequential_time * 0.5,
           "Parallel time (#{parallel_time}s) should be much less than sequential time (#{sequential_time}s)"
  end
end
