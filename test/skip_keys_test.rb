require_relative "test_helper"

class SkipKeysTest < Minitest::Test
  def test_default_skip_keys_behavior
    # Node that processes batch data and adds various keys to shared context
    processor = Class.new(Pocketflow::Node) do
      def prep(shared)
        # Get the batch data for this batch ID
        batch_id = @params[:batch_id]
        shared[:input_data][batch_id] if shared[:input_data]
      end

      def exec(batch_item)
        "processed_#{batch_item}"
      end

      def post(shared, prep_res, exec_res)
        batch_id = @params[:batch_id]

        # Store results (should be merged)
        shared[:results] ||= {}
        shared[:results][batch_id] = exec_res

        # Add input-like keys (should be skipped by default patterns)
        shared[:some_input] = "should_be_skipped"
        shared[:user_input] = "also_skipped"

        # Add output data (should be kept)
        shared[:output_data] = "should_be_kept"

        "processed"
      end
    end

    # Custom ParallelBatchFlow that creates batch parameters
    flow_class = Class.new(Pocketflow::ParallelBatchFlow) do
      def prep(shared)
        # Create batch parameters for each input item
        shared[:input_data].each_index.map { |i| { batch_id: i } }
      end
    end

    flow = flow_class.new(processor.new)

    # Initialize shared context with input data
    shared = {
      input_data: ["item1", "item2"],
      batches: ["original_batches"],  # Should be preserved by default skip
      existing_data: "preserved"
    }

    flow.run(shared)

    # Check that results were merged correctly
    expected_results = { 0 => "processed_item1", 1 => "processed_item2" }
    assert_equal expected_results, shared[:results]

    # Check that output data was merged
    assert_equal "should_be_kept", shared[:output_data]

    # Check that default skip patterns worked
    assert_equal ["original_batches"], shared[:batches]  # Original batches preserved
    assert_equal "preserved", shared[:existing_data]     # Original data preserved

    # Keys ending with _input should be skipped
    refute shared.key?(:some_input)
    refute shared.key?(:user_input)
  end

  def test_custom_skip_keys
    processor = Class.new(Pocketflow::Node) do
      def prep(shared)
        @params[:data]
      end

      def exec(data)
        "processed_#{data}"
      end

      def post(shared, prep_res, exec_res)
        shared[:results] ||= []
        shared[:results] << exec_res

        # These should be skipped due to custom skip_keys
        shared[:config_data] = "should_be_skipped"
        shared[:raw_data] = "should_be_skipped"

        # This should be kept
        shared[:processed_data] = "should_be_kept"

        "processed"
      end
    end

    flow_class = Class.new(Pocketflow::ParallelBatchFlow) do
      def prep(shared)
        [{ data: "item1" }, { data: "item2" }]
      end
    end

    # Setup with custom skip keys
    flow = flow_class.new(
      processor.new,
      skip_keys: ["config_data", "raw_data"]
    )

    shared = { initial_data: "preserved" }
    flow.run(shared)

    # Custom skip keys should be honored
    refute shared.key?(:config_data)
    refute shared.key?(:raw_data)

    # Non-skipped data should be present
    assert shared[:results].length == 2
    assert shared[:results].all? { |r| r.start_with?("processed_") }
    assert_equal "should_be_kept", shared[:processed_data]
    assert_equal "preserved", shared[:initial_data]
  end

  def test_empty_skip_keys_merges_everything
    processor = Class.new(Pocketflow::Node) do
      def prep(shared)
        @params[:data]
      end

      def exec(data)
        "result_#{data}"
      end

      def post(shared, prep_res, exec_res)
        # These would normally be skipped but shouldn't be with empty skip_keys
        # Since we only have one thread, these should be the final values
        shared[:some_input] = "merged"
        shared[:user_input] = "also_merged"
        shared[:batches] = ["new_batches"]
        shared[:result] = exec_res

        "processed"
      end
    end

    flow_class = Class.new(Pocketflow::ParallelBatchFlow) do
      def prep(shared)
        [{ data: "item1" }]
      end
    end

    # No skip keys - everything should be merged
    flow = flow_class.new(processor.new, skip_keys: [])

    shared = {
      batches: ["original"],
      existing_data: "original"
    }

    flow.run(shared)

    # With empty skip_keys, input-like keys should be merged
    # Since we have only one batch/thread, the values should be present
    assert_equal "merged", shared[:some_input]
    assert_equal "also_merged", shared[:user_input]
    assert_equal ["new_batches"], shared[:batches]  # Original was overwritten
    assert_equal "original", shared[:existing_data] # This wasn't touched by threads
    assert_equal "result_item1", shared[:result]
  end
end
