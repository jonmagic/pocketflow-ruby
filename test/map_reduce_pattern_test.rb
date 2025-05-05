require_relative "test_helper"

SharedStorage = Hash

def call_llm(prompt)
  "Summary for: #{prompt[0, 20]}..."
end

class MapReducePatternTest < Minitest::Test
  class SummarizeAllFiles < Pocketflow::BatchNode
    def prep(shared)
      (shared[:files] || {}).to_a
    end

    def exec(file_pair)
      filename, content = file_pair
      [filename, call_llm("Summarize the following file:\n#{content}")]
    end

    def post(shared, _prep, exec_res)
      shared[:file_summaries] = exec_res.to_h
      "summarized"
    end
  end

  class CombineSummaries < Pocketflow::Node
    def prep(shared)
      shared[:file_summaries] || {}
    end

    def exec(file_summaries)
      text = file_summaries.map { |fname, summ| "#{fname} summary:\n#{summ}\n" }.join("\n---\n")
      call_llm("Combine these file summaries into one final summary:\n#{text}")
    end

    def post(shared, _prep, exec_res)
      shared[:all_files_summary] = exec_res
      "combined"
    end
  end

  class MapChunks < Pocketflow::ParallelBatchNode
    def prep(shared)
      text = shared[:text_to_process] || ""
      chunks = []
      i = 0
      while i < text.length
        chunks << text[i, 10]
        i += 10
      end
      shared[:text_chunks] = chunks
      chunks
    end

    def exec(chunk)
      chunk.upcase
    end

    def post(shared, _prep, exec_res)
      shared[:processed_chunks] = exec_res
      "mapped"
    end
  end

  class ReduceResults < Pocketflow::Node
    def prep(shared)
      shared[:processed_chunks] || []
    end

    def exec(chunks)
      chunks.join(" + ")
    end

    def post(shared, _prep, exec_res)
      shared[:final_result] = exec_res
      "reduced"
    end
  end

  # Test-specific ConfigurableMapChunks for varying chunk sizes in MapReduce pattern
  class ConfigurableMapChunks < Pocketflow::ParallelBatchNode
    def initialize(size)
      @size = size
      super()
    end

    def prep(shared)
      text = shared[:text_to_process] || ""
      chunks = []
      i = 0
      while i < text.length
        chunks << text[i, @size]
        i += @size
      end
      shared[:text_chunks] = chunks
      chunks
    end

    def exec(chunk)
      chunk.upcase
    end

    def post(shared, _prep, exec_res)
      shared[:processed_chunks] = exec_res
      "mapped"
    end
  end

  def test_document_summarization_mapreduce
    batch = SummarizeAllFiles.new
    combine = CombineSummaries.new
    batch.on("summarized", combine)
    flow = Pocketflow::Flow.new(batch)
    shared = {
      files: {
        "file1.txt" => "Alice was beginning to get very tired of sitting by her sister...",
        "file2.txt" => "Some other interesting text ...",
        "file3.txt" => "Yet another file with some content to summarize..."
      }
    }
    flow.run(shared)
    assert shared[:file_summaries]
    assert_equal 3, shared[:file_summaries].keys.size
    assert shared[:all_files_summary].is_a?(String)
  end

  def test_parallel_text_processing_mapreduce
    map = MapChunks.new
    reduce = ReduceResults.new
    map.on("mapped", reduce)
    flow = Pocketflow::Flow.new(map)
    shared = {
      text_to_process: "This is a longer text that will be processed in parallel using the MapReduce pattern."
    }
    flow.run(shared)
    assert shared[:text_chunks]
    assert shared[:processed_chunks]
    assert_equal shared[:text_chunks].size, shared[:processed_chunks].size
    assert shared[:final_result].is_a?(String)
    assert shared[:processed_chunks].all? { |c| c == c.upcase }
  end

  def test_varying_chunk_size_in_mapreduce
    # Use ConfigurableMapChunks defined at class level
    text = "This is a test text for demonstrating chunk size effects."

    map_small = ConfigurableMapChunks.new(5)
    reduce_small = ReduceResults.new
    map_small.on("mapped", reduce_small)
    flow_small = Pocketflow::Flow.new(map_small)
    shared_small = { text_to_process: text }
    flow_small.run(shared_small)

    map_large = ConfigurableMapChunks.new(20)
    reduce_large = ReduceResults.new
    map_large.on("mapped", reduce_large)
    flow_large = Pocketflow::Flow.new(map_large)
    shared_large = { text_to_process: text }
    flow_large.run(shared_large)

    assert shared_small[:text_chunks].size > shared_large[:text_chunks].size
    assert_equal shared_small[:final_result].gsub(/ \+ /, ""), shared_large[:final_result].gsub(/ \+ /, "")
  end
end
