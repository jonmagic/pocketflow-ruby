require_relative "test_helper"

SharedStorage = Hash

class CoreAbstractionExamplesTest < Minitest::Test
  class SummarizeFile < Pocketflow::Node
    def prep(shared)
      shared[:data]
    end

    def exec(prep_res)
      return "Empty file content" if prep_res.nil? || prep_res.empty?
      # Trim any trailing spaces and add single space before ellipsis
      trimmed = prep_res[0, 10].to_s.rstrip
      "Summary: #{trimmed} ..."
    end

    def exec_fallback(*_)
      "There was an error processing your request."
    end

    def post(shared, _prep, exec_res)
      shared[:summary] = exec_res
      nil
    end
  end

  class ReviewExpense < Pocketflow::Node
    def prep(shared)
      (shared[:expenses] || []).find { |e| e[:status].nil? }
    end

    def post(shared, prep_res, _exec)
      return "finished" unless prep_res
      expense = prep_res
      if expense[:amount] <= 100
        expense[:status] = "approved"
        "approved"
      elsif expense[:amount] > 500
        expense[:status] = "rejected"
        "rejected"
      else
        expense[:status] = "needs_revision"
        "needs_revision"
      end
    end
  end

  class ReviseExpense < Pocketflow::Node
    def prep(shared)
      (shared[:expenses] || []).find { |e| e[:status] == "needs_revision" }
    end

    def post(shared, prep_res, _exec)
      return "finished" unless prep_res
      expense = prep_res
      expense[:amount] = 75
      expense.delete(:status)
      "default"
    end
  end

  class ProcessPayment < Pocketflow::Node
    def prep(shared)
      (shared[:expenses] || []).find { |e| e[:status] == "approved" }
    end

    def post(_shared, prep_res, _exec)
      return "finished" unless prep_res
      prep_res[:status] = "paid"
      "default"
    end
  end

  class FinishProcess < Pocketflow::Node
    def post(*_)
      "finished"
    end
  end

  class MapSummaries < Pocketflow::BatchNode
    def prep(shared)
      content = shared[:data] || ""
      chunks = []
      i = 0
      while i < content.length
        chunks << content[i, 10]
        i += 10
      end
      chunks
    end

    def exec(chunk)
      "Chunk summary: #{chunk[0, 3]}..."
    end

    def post(shared, _prep, exec_res)
      shared[:summary] = exec_res.join("\n")
      nil
    end
  end

  class LoadFile < Pocketflow::Node
    def prep(_shared)
      "Content of #{@params[:filename]}"
    end

    def post(shared, prep_res, _exec)
      shared[:data] = prep_res
      nil
    end
  end

  class SummarizeAllFiles < Pocketflow::BatchFlow
    def prep(shared)
      (shared[:files] || []).map { |f| { filename: f } }
    end
  end

  class TextSummarizer < Pocketflow::ParallelBatchNode
    def prep(shared)
      (shared[:data] || "").split("\n")
    end

    def exec(text)
      "Summary of: #{text[0, 5]}..."
    end

    def post(shared, _prep, exec_res)
      shared[:results] = exec_res
      nil
    end
  end

  class ValidatePayment < Pocketflow::Node
    def post(shared, *_)
      shared[:payments] ||= []
      shared[:payments] << { id: "payment1", status: "validated" }
      "default"
    end
  end

  class ProcessPaymentFlow < Pocketflow::Node
    def post(shared, *_)
      (shared[:payments] || []).each { |p| p[:status] = "processed" if p[:status] == "validated" }
      "default"
    end
  end

  class PaymentConfirmation < Pocketflow::Node
    def post(shared, *_)
      (shared[:payments] || []).each { |p| p[:status] = "confirmed" if p[:status] == "processed" }
      "default"
    end
  end

  class CheckStock < Pocketflow::Node
    def post(shared, *_)
      shared[:inventory] ||= []
      shared[:inventory] << { id: "inventory1", status: "checked" }
      "default"
    end
  end

  class ReserveItems < Pocketflow::Node
    def post(shared, *_)
      (shared[:inventory] || []).each { |i| i[:status] = "reserved" if i[:status] == "checked" }
      "default"
    end
  end

  class UpdateInventory < Pocketflow::Node
    def post(shared, *_)
      (shared[:inventory] || []).each { |i| i[:status] = "updated" if i[:status] == "reserved" }
      "default"
    end
  end

  class CreateLabel < Pocketflow::Node
    def post(shared, *_)
      shared[:shipping] ||= []
      shared[:shipping] << { id: "shipping1", status: "labeled" }
      "default"
    end
  end

  class AssignCarrier < Pocketflow::Node
    def post(shared, *_)
      (shared[:shipping] || []).each { |s| s[:status] = "assigned" if s[:status] == "labeled" }
      "default"
    end
  end

  class SchedulePickup < Pocketflow::Node
    def post(shared, *_)
      (shared[:shipping] || []).each { |s| s[:status] = "scheduled" if s[:status] == "assigned" }
      shared[:order_complete] = true
      "default"
    end
  end

  def test_summarize_file_content
    shared = { data: "This is a test document that needs to be summarized." }
    SummarizeFile.new.run(shared)
    assert_equal "Summary: This is a ...", shared[:summary]
  end

  def test_summarize_empty_content
    shared = { data: "" }
    SummarizeFile.new.run(shared)
    assert_equal "Empty file content", shared[:summary]
  end

  def test_expense_approve_small
    shared = { expenses: [{ id: "exp1", amount: 50 }] }
    review = ReviewExpense.new
    payment = ProcessPayment.new
    finish = FinishProcess.new
    review.on("approved", payment)
    payment.next(finish)
    Pocketflow::Flow.new(review).run(shared)
    assert_equal "paid", shared[:expenses][0][:status]
  end

  def test_expense_reject_large
    shared = { expenses: [{ id: "exp2", amount: 1000 }] }
    review = ReviewExpense.new
    finish = FinishProcess.new
    review.on("rejected", finish)
    Pocketflow::Flow.new(review).run(shared)
    assert_equal "rejected", shared[:expenses][0][:status]
  end

  def test_expense_revision_then_approval
    shared = { expenses: [{ id: "exp3", amount: 200 }] }
    review = ReviewExpense.new
    revise = ReviseExpense.new
    payment = ProcessPayment.new
    finish = FinishProcess.new
    review.on("approved", payment)
    review.on("needs_revision", revise)
    review.on("rejected", finish)
    revise.next(review)
    payment.next(finish)
    Pocketflow::Flow.new(review).run(shared)
    exp = shared[:expenses][0]
    assert_equal "paid", exp[:status]
    assert_equal 75, exp[:amount]
  end

  def test_map_summaries_chunks
    shared = { data: "This is a very long document that needs to be processed in chunks." }
    MapSummaries.new.run(shared)
    assert_includes shared[:summary], "Chunk summary: Thi"
    assert_operator shared[:summary].split("\n").size, :>, 1
  end

  def test_summarize_all_files
    shared = { files: ["file1.txt", "file2.txt", "file3.txt"] }
    load = LoadFile.new
    summarize = SummarizeFile.new
    load.next(summarize)
    summarize_all = SummarizeAllFiles.new(Pocketflow::Flow.new(load))
    summarize_all.run(shared)
    assert_equal "Summary: Content of ...", shared[:summary]
  end

  def test_text_summarizer_parallel
    shared = { data: "Text 1\nText 2\nText 3\nText 4" }
    TextSummarizer.new.run(shared)
    assert_equal 4, shared[:results].size
    assert_equal "Summary of: Text ...", shared[:results][0]
    assert_equal "Summary of: Text ...", shared[:results][1]
  end

  def test_order_processing_pipeline
    shared = {}
    vp = ValidatePayment.new
    pp = ProcessPaymentFlow.new
    pc = PaymentConfirmation.new
    vp.next(pp).next(pc)
    payment_flow = Pocketflow::Flow.new(vp)
    cs = CheckStock.new
    ri = ReserveItems.new
    ui = UpdateInventory.new
    cs.next(ri).next(ui)
    inventory_flow = Pocketflow::Flow.new(cs)
    cl = CreateLabel.new
    ac = AssignCarrier.new
    sp = SchedulePickup.new
    cl.next(ac).next(sp)
    shipping_flow = Pocketflow::Flow.new(cl)
    payment_flow.next(inventory_flow).next(shipping_flow)
    order_pipeline = Pocketflow::Flow.new(payment_flow)
    order_pipeline.run(shared)
    assert_equal "confirmed", shared[:payments][0][:status]
    assert_equal "updated", shared[:inventory][0][:status]
    assert_equal "scheduled", shared[:shipping][0][:status]
    assert_equal true, shared[:order_complete]
  end
end
