require_relative "test_helper"

SharedStorage = Hash

class AsyncArrayChunkNode < Pocketflow::BatchNode
  def initialize(chunk_size = 10, max_retries = 1, wait = 0)
    super(max_retries: max_retries, wait: wait)
    @chunk_size = chunk_size
  end

  def prep(shared)
    array = shared[:input_array] || []
    chunks = []
    start = 0
    while start < array.length
      chunks << array.slice(start, @chunk_size)
      start += @chunk_size
    end
    chunks
  end

  def exec(chunk)
    chunk.reduce(0) { |sum, v| sum + v }
  end

  def post(shared, _prep_res, exec_res)
    shared[:chunk_results] = exec_res
    "processed"
  end
end

class AsyncSumReduceNode < Pocketflow::Node
  def prep(shared)
    shared[:chunk_results] || []
  end

  def exec(chunk_results)
    chunk_results.reduce(0) { |sum, v| sum + v }
  end

  def post(shared, _prep_res, exec_res)
    shared[:total] = exec_res
    "reduced"
  end
end

class ErrorBatchNode < Pocketflow::BatchNode
  def prep(shared)
    shared[:input_array] || []
  end

  def exec(item)
    raise "Error processing item 2" if item == 2
    item
  end
end

class BatchNodeTest < Minitest::Test
  # Test-specific BatchNode subclasses
  class RetryTestNode < Pocketflow::BatchNode
    def initialize(attempts_ref)
      @attempts_ref = attempts_ref
      super(max_retries: 3, wait: 0)
    end

    def prep(_shared)
      [1]
    end

    def exec(_item)
      @attempts_ref[:count] += 1
      raise "Failure on attempt #{@attempts_ref[:count]}" if @attempts_ref[:count] < 3
      "Success on attempt #{@attempts_ref[:count]}"
    end

    def post(shared, _prep_res, exec_res)
      shared[:result] = exec_res.first
      nil
    end
  end

  class ParallelProcessingNode < Pocketflow::ParallelBatchNode
    def initialize(completed)
      @completed = completed
      super(max_retries: 1, wait: 0)
    end

    def prep(_shared)
      [1, 2, 3, 4, 5]
    end

    def exec(item)
      @completed << item
      item
    end

    def post(shared, _prep_res, exec_res)
      shared[:parallel_results] = exec_res
      shared[:completion_order] = @completed.dup
      nil
    end
  end

  def test_array_chunking
    shared = { input_array: (0..24).to_a }
    chunk_node = AsyncArrayChunkNode.new(10)
    chunk_node.run(shared)
    assert_equal [45, 145, 110], shared[:chunk_results]
  end

  def test_async_map_reduce_sum
    array = (0..99).to_a
    expected_sum = array.reduce(:+)
    shared = { input_array: array }

    chunk_node = AsyncArrayChunkNode.new(10)
    reduce_node = AsyncSumReduceNode.new
    chunk_node.on("processed", reduce_node)

    pipeline = Pocketflow::Flow.new(chunk_node)
    pipeline.run(shared)

    assert_equal expected_sum, shared[:total]
  end

  def test_uneven_chunks
    array = (0..24).to_a
    expected_sum = array.reduce(:+)
    shared = { input_array: array }

    chunk_node = AsyncArrayChunkNode.new(10)
    reduce_node = AsyncSumReduceNode.new
    chunk_node.on("processed", reduce_node)

    pipeline = Pocketflow::Flow.new(chunk_node)
    pipeline.run(shared)

    assert_equal expected_sum, shared[:total]
  end

  def test_custom_chunk_size
    array = (0..99).to_a
    expected_sum = array.reduce(:+)
    shared = { input_array: array }

    chunk_node = AsyncArrayChunkNode.new(15)
    reduce_node = AsyncSumReduceNode.new
    chunk_node.on("processed", reduce_node)
    pipeline = Pocketflow::Flow.new(chunk_node)
    pipeline.run(shared)

    assert_equal expected_sum, shared[:total]
  end

  def test_single_element_chunks
    array = (0..4).to_a
    expected_sum = array.reduce(:+)
    shared = { input_array: array }

    chunk_node = AsyncArrayChunkNode.new(1)
    reduce_node = AsyncSumReduceNode.new
    chunk_node.on("processed", reduce_node)
    pipeline = Pocketflow::Flow.new(chunk_node)
    pipeline.run(shared)

    assert_equal expected_sum, shared[:total]
  end

  def test_empty_array
    shared = { input_array: [] }
    chunk_node = AsyncArrayChunkNode.new(10)
    reduce_node = AsyncSumReduceNode.new
    chunk_node.on("processed", reduce_node)
    pipeline = Pocketflow::Flow.new(chunk_node)
    pipeline.run(shared)

    assert_equal 0, shared[:total]
  end

  def test_error_handling
    shared = { input_array: [1, 2, 3] }
    error_node = ErrorBatchNode.new
    err = assert_raises RuntimeError do
      error_node.run(shared)
    end
    assert_match "Error processing item 2", err.message
  end

  def test_retry_mechanism
    attempts_ref = { count: 0 }
    shared = {}
    retry_node = RetryTestNode.new(attempts_ref)
    retry_node.run(shared)
    assert_equal 3, attempts_ref[:count]
    assert_equal "Success on attempt 3", shared[:result]
  end

  def test_parallel_batch_processing
    completed = []
    shared = {}
    parallel_node = ParallelProcessingNode.new(completed)
    parallel_node.run(shared)
    assert_equal [1, 2, 3, 4, 5], shared[:parallel_results].sort
    assert_equal [1, 2, 3, 4, 5], shared[:completion_order]
  end
end
