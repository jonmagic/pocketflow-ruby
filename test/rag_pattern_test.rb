# frozen_string_literal: true

require_relative "test_helper"

# ---------- Mock helpers ----------

def get_embedding(text)
  text[0, 5].chars.map(&:ord)
end

def create_index(embeds)
  { embeddings: embeds }
end

def search_index(index, query, top_k: 1)
  sims = index[:embeddings].each_with_index.map do |vec, i|
    sim = vec.each_with_index.reduce(0) { |s, (val, idx)| s + val * (query[idx] || 0) }
    [i, sim]
  end
  sims.sort_by! { |_, s| -s }
  selected = sims.first(top_k)
  [[selected.map(&:first)], [selected.map(&:last)]]
end

def rag_call_llm(prompt)
  "Answer based on: #{prompt[0, 30]}..."
end

# ---------- Nodes ----------

class ChunkDocs < Pocketflow::BatchNode
  def prep(shared)
    shared[:files] || []
  end

  def exec(path)
    text = "This is mock content for #{path}. It contains some sample text for testing the RAG pattern."
    chunks = []
    i = 0
    while i < text.length
      chunks << text[i, 20]
      i += 20
    end
    chunks
  end

  def post(shared, _prep, lists)
    shared[:all_chunks] = lists.flatten
    nil
  end
end

class EmbedDocs < Pocketflow::BatchNode
  def prep(shared)
    shared[:all_chunks] || []
  end

  def exec(chunk)
    get_embedding(chunk)
  end

  def post(shared, _prep, embeds)
    shared[:all_embeds] = embeds
    nil
  end
end

class StoreIndex < Pocketflow::Node
  def prep(shared)
    shared[:all_embeds] || []
  end

  def exec(embeds)
    create_index(embeds)
  end

  def post(shared, _prep, idx)
    shared[:index] = idx
    nil
  end
end

class EmbedQuery < Pocketflow::Node
  def prep(shared)
    shared[:question] || ""
  end

  def exec(q)
    get_embedding(q)
  end

  def post(shared, _prep, q_emb)
    shared[:q_emb] = q_emb
    nil
  end
end

class RetrieveDocs < Pocketflow::Node
  def prep(shared)
    [shared[:q_emb] || [], shared[:index] || {}, shared[:all_chunks] || []]
  end

  def exec(arr)
    q_emb, idx, chunks = arr
    indices, _ = search_index(idx, q_emb, top_k: 1)
    chunks[indices[0][0]]
  end

  def post(shared, _prep, chunk)
    shared[:retrieved_chunk] = chunk
    nil
  end
end

class GenerateAnswer < Pocketflow::Node
  def prep(shared)
    [shared[:question] || "", shared[:retrieved_chunk] || ""]
  end

  def exec(arr)
    q, chunk = arr
    prompt = "Question: #{q}\nContext: #{chunk}\nAnswer:"
    rag_call_llm(prompt)
  end

  def post(shared, _prep, answer)
    shared[:answer] = answer
    nil
  end
end

# ---------- Test Suite ----------

class RagPatternTest < Minitest::Test
  def offline_flow
    c = ChunkDocs.new
    e = EmbedDocs.new
    s = StoreIndex.new
    c.next(e).next(s)
    Pocketflow::Flow.new(c)
  end

  def online_flow
    eq = EmbedQuery.new
    r = RetrieveDocs.new
    g = GenerateAnswer.new
    eq.next(r).next(g)
    Pocketflow::Flow.new(eq)
  end

  def test_offline_indexing_flow
    flow = offline_flow
    shared = { files: %w[doc1.txt doc2.txt] }
    flow.run(shared)
    assert shared[:all_chunks]&.any?
    assert shared[:all_embeds]&.size == shared[:all_chunks].size
    assert shared[:index]
  end

  def test_online_query_answer_flow
    # prepare offline
    shared = { files: %w[doc1.txt doc2.txt] }
    offline_flow.run(shared)
    shared[:question] = "What is the content about?"
    online_flow.run(shared)
    assert shared[:q_emb]
    assert shared[:retrieved_chunk]
    assert_kind_of String, shared[:answer]
  end

  def test_complete_rag_pipeline
    # combine
    c = ChunkDocs.new
    e = EmbedDocs.new
    s = StoreIndex.new
    eq = EmbedQuery.new
    r = RetrieveDocs.new
    g = GenerateAnswer.new
    c.next(e).next(s).next(eq).next(r).next(g)
    flow = Pocketflow::Flow.new(c)
    shared = { files: %w[doc1.txt doc2.txt], question: "What is the content about?" }
    flow.run(shared)
    [:all_chunks, :all_embeds, :index, :q_emb, :retrieved_chunk, :answer].each { |k| assert shared[k] }
    assert_kind_of String, shared[:answer]
  end
end
