# frozen_string_literal: true

# Public: Pocketflow – A tiny, synchronous workflow library for Ruby 2.5+.
#
# The library mirrors sibling implementations in TypeScript, Python, Go and
# Java while embracing plain‑old Ruby objects and language idioms. "Parallel"
# variants use Thread-based concurrency for I/O-bound tasks like LLM API calls
# and shell commands, providing true parallelism for these operations.
#
# Examples
#
#   require_relative "pocketflow"
#
#   class HelloNode < Pocketflow::Node
#     def exec(*)
#       puts "hello, world"
#     end
#   end
#
#   Pocketflow::Flow.new(HelloNode.new).run({})
#
# Returns nothing.
module Pocketflow
  VERSION = "1.0.0"

  # Public: Default action name used when a node's +post+ does not specify one.
  DEFAULT_ACTION = "default"

  # Public: BaseNode is the minimal building block of a Pocketflow graph.
  #
  # A node's lifecycle is **prep → exec → post**. Override those hooks to
  # perform work. Successor nodes are linked via {#next} or {#on}.
  class BaseNode
    # Public: Arbitrary parameters for the node.
    attr_accessor :params

    # Internal: Action → successor node mapping.
    attr_reader :successors

    # Public: Create a node.
    #
    # Returns the new BaseNode.
    def initialize
      @params     = {}
      @successors = {}
    end

    # Public: Replace the parameter hash.
    #
    # params - The Hash of parameters (may be nil).
    #
    # Returns the node itself.
    def set_params(params)
      @params = params || {}
      self
    end

    # Public: Connect this node to another node for a given action.
    #
    # node   - The BaseNode successor.
    # action - The String action name (default: DEFAULT_ACTION).
    #
    # Returns the given node.
    def next(node, action = DEFAULT_ACTION)
      on(action, node)
      node
    end

    alias >> next

    # Public: Define (or overwrite) a successor for an action.
    #
    # action - The String action name.
    # node   - The BaseNode successor.
    #
    # Returns the node itself.
    def on(action, node)
      warn "Overwriting successor for action '#{action}'" if @successors.key?(action)
      @successors[action] = node
      self
    end

    # Public: Prepare for execution. Override in subclasses.
    #
    # shared - The shared context passed through the entire flow.
    #
    # Returns an arbitrary prep object.
    def prep(shared)
      nil
    end

    # Public: Perform the primary work. Override in subclasses.
    #
    # prep_res - The value returned by +prep+.
    #
    # Returns an arbitrary execution result.
    def exec(prep_res)
      nil
    end

    # Public: Process results and decide the next action. Override in subclasses.
    #
    # shared    - The shared context.
    # prep_res  - The object returned by +prep+.
    # exec_res  - The object returned by +exec+.
    #
    # Returns the String action name or +nil+ / DEFAULT_ACTION.
    def post(shared, prep_res, exec_res)
      nil
    end

    # Internal: Wrapper around the node lifecycle.
    #
    # shared - The shared context.
    #
    # Returns the action String (or nil).
    def run_internal(shared)
      prep_res = prep(shared)
      exec_res = exec_internal(prep_res)
      post(shared, prep_res, exec_res)
    end

    # Internal: Wrapper around +exec+. Subclasses override to inject retry
    # logic.
    #
    # prep_res - The object returned by +prep+.
    #
    # Returns whatever +exec+ returns.
    def exec_internal(prep_res)
      exec(prep_res)
    end

    # Public: Execute this node as a standalone unit.
    #
    # shared - The shared context.
    #
    # Returns the action String (or nil).
    def run(shared)
      warn "Node won't run successors. Use Flow." unless @successors.empty?
      run_internal(shared)
    end

    # Internal: Retrieve the successor for an action.
    #
    # action - The String action name (default: DEFAULT_ACTION).
    #
    # Returns the BaseNode successor or nil.
    def get_next_node(action = DEFAULT_ACTION)
      action = DEFAULT_ACTION if action.nil? || action.empty?
      @successors[action]
    end

    # Internal: Shallow‑clone the node so that params/successors are isolated.
    #
    # Returns the cloned BaseNode.
    def clone
      # Use Object#clone to preserve singleton methods; shallow-copy params and successors
      cloned = super
      cloned.params = @params.dup
      cloned.instance_variable_set(:@successors, @successors.dup)
      cloned
    end
  end

  # Public: Node adds retry/wait behaviour around BaseNode#exec.
  class Node < BaseNode
    attr_reader :max_retries, :wait, :current_retry

    # Public: Build a Node.
    #
    # max_retries - The Integer attempts per execution (minimum 1).
    # wait        - The Numeric seconds between retries.
    #
    # Returns the new Node.
    def initialize(max_retries: 1, wait: 0)
      super()
      @max_retries  = [max_retries, 1].max
      @wait         = [wait, 0].max
      @current_retry = 0
    end

    # Public: Called after all retries fail. Override to customise behaviour.
    #
    # prep_res - The object returned by +prep+.
    # error    - The Exception raised by the last attempt.
    #
    # Returns an execution result or raises.
    def exec_fallback(prep_res, error)
      raise error
    end

    # Internal: Retry wrapper around +exec+.
    def exec_internal(prep_res)
      @current_retry = 0
      while @current_retry < @max_retries
        begin
          return exec(prep_res)
        rescue StandardError => e
          if @current_retry == @max_retries - 1
            return exec_fallback(prep_res, e)
          end
          sleep @wait if @wait.positive?
        ensure
          @current_retry += 1
        end
      end
    end
  end

  # Public: BatchNode executes Node#exec_internal once per item.
  class BatchNode < Node
    # Internal: Sequentially process an Array of items.
    def exec_internal(items)
      return [] unless items.is_a?(Array)
      items.map { |item| super(item) }
    end
  end

  # Public: ParallelBatchNode processes items concurrently using threads.
  class ParallelBatchNode < Node
    # Internal: Process Array items concurrently using threads.
    def exec_internal(items)
      return [] unless items.is_a?(Array)
      return [] if items.empty?

      # Create threads for each item
      threads = items.map do |item|
        Thread.new do
          # Create a fresh node instance but copy essential state
          node_copy = clone_for_thread
          node_copy.send(:exec_with_retry, item)
        end
      end

      # Wait for all threads and collect results in original order
      threads.map(&:value)
    end

    private

    # Internal: Clone this node for use in a thread, preserving state
    def clone_for_thread
      # Use Object#clone to preserve singleton methods and instance variables
      cloned = Object.instance_method(:clone).bind(self).call
      cloned.instance_variable_set(:@params, @params.dup) if @params
      cloned
    end

    # Internal: Execute with retry logic for individual items in threads.
    def exec_with_retry(item)
      current_retry = 0
      while current_retry < @max_retries
        begin
          return exec(item)
        rescue StandardError => e
          if current_retry == @max_retries - 1
            return exec_fallback(item, e)
          end
          sleep @wait if @wait.positive?
        ensure
          current_retry += 1
        end
      end
    end
  end

  # Public: Flow orchestrates the execution of a linked chain of nodes.
  class Flow < BaseNode
    attr_reader :start

    # Public: Build a Flow.
    #
    # start - The BaseNode that begins the graph.
    #
    # Returns the new Flow.
    def initialize(start)
      super()
      @start = start
    end

    # Internal: Execute the graph beginning at +@start+.
    #
    # shared - The shared context.
    # params - A Hash of parameters to merge into each node (optional).
    #
    # Returns nothing.
    def orchestrate_internal(shared, params = nil)
      current          = @start.clone
      effective_params = params || @params

      while current
        current.set_params(effective_params)
        action  = current.run_internal(shared)
        current = current.get_next_node(action)&.clone
      end
    end

    # Internal: Flow's lifecycle wrapper.
    def run_internal(shared)
      prep_res = prep(shared)
      orchestrate_internal(shared)
      post(shared, prep_res, nil)
    end

    # Public: Flows cannot be executed via +exec+.
    def exec(*)
      raise "Flow can't exec directly."
    end
  end

  # Public: BatchFlow runs its flow once for every parameter‑set yielded by +prep+.
  class BatchFlow < Flow
    # Internal: Run the batch flow.
    def run_internal(shared)
      batch_params = prep(shared) || []
      batch_params.each do |bp|
        orchestrate_internal(shared, @params.merge(bp.to_h))
      end
      post(shared, batch_params, nil)
    end

    # Public: Override to supply an Array of Hash‑like parameter sets.
    def prep(shared)
      []
    end
  end

  # Public: ParallelBatchFlow runs batch flows concurrently using threads.
  class ParallelBatchFlow < BatchFlow
    # Internal: Run batch flows concurrently using threads.
    def run_internal(shared)
      batch_params = prep(shared) || []
      return post(shared, batch_params, nil) if batch_params.empty?

      # Create threads for each batch parameter set
      threads = batch_params.map do |bp|
        Thread.new do
          # Each thread gets its own isolated shared context copy for thread safety
          thread_shared = deep_dup_shared(shared)

          # For parallel execution, we only want to run the start node (first node in chain)
          # The successor nodes (like aggregator) should run after all threads complete
          current = @start.clone
          current.set_params(@params.merge(bp.to_h))
          current.run_internal(thread_shared)

          thread_shared
        end
      end

      # Wait for all threads and merge results back into main shared context
      thread_results = threads.map(&:value)
      merge_thread_results(shared, thread_results)

      # Now run the successor nodes (like aggregator) with the merged results
      if @start.successors.any?
        action = "processed"  # Default action from processor nodes
        current = @start.get_next_node(action)&.clone
        while current
          current.set_params(@params)
          action = current.run_internal(shared)
          current = current.get_next_node(action)&.clone
        end
      end

      post(shared, batch_params, nil)
    end

    private

    # Internal: Deep duplicate the shared context to avoid thread conflicts.
    def deep_dup_shared(shared)
      shared.dup.transform_values do |value|
        case value
        when Hash
          value.dup
        when Array
          value.dup
        else
          value
        end
      end
    end

    # Internal: Merge results from thread-local shared contexts back to main context.
    def merge_thread_results(main_shared, thread_results)
      # Merge each thread result back to main shared context
      thread_results.each do |thread_shared|
        thread_shared.each do |key, value|
          # Skip input data to avoid overwriting/concatenating
          next if key.to_s.end_with?("_input")
          next if key == :batches  # Skip the original input batches array

          # Handle different merge strategies based on value types
          if main_shared.key?(key) && main_shared[key].is_a?(Hash) && value.is_a?(Hash)
            # Merge nested hashes (e.g., processed_numbers with batch IDs)
            main_shared[key].merge!(value)
          elsif main_shared.key?(key) && main_shared[key].is_a?(Array) && value.is_a?(Array)
            # Concatenate arrays
            main_shared[key].concat(value)
          else
            # Direct assignment for other types
            main_shared[key] = value
          end
        end
      end
    end
  end
end
