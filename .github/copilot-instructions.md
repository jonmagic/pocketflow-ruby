# PocketFlow Ruby - AI Coding Agent Instructions

## Architecture Overview

PocketFlow Ruby is a synchronous workflow orchestration library for Ruby 2.7+ ported from TypeScript, designed around a simple node-graph execution model. The entire library is contained in a single file: `lib/pocketflow.rb`.

### Core Components

- **BaseNode**: The fundamental execution unit with `prep → exec → post` lifecycle
- **Node**: Extends BaseNode with retry/wait behavior around `exec`
- **BatchNode/ParallelBatchNode**: Process arrays sequentially/concurrently using threads
- **Flow**: Orchestrates node execution following action-based transitions
- **BatchFlow/ParallelBatchFlow**: Execute flows once per parameter set, sequentially/concurrently

### Key Patterns

**Node Lifecycle**: Every node follows `prep(shared) → exec(prep_result) → post(shared, prep_result, exec_result)`
- `prep`: Extract/prepare data from shared context
- `exec`: Perform the core work (only method that should fail/retry)
- `post`: Process results and return next action name (or nil/"default")

**Action-Based Routing**: Nodes connect via `.next(node, action)` or `.on(action, node)`
```ruby
review_node.on("approved", payment_node)
           .on("rejected", finish_node)
           .on("needs_revision", revise_node)
```

**Shared Context**: All nodes share a single hash that flows through the entire execution

## Development Workflow

**Testing**: Run `bundle exec rake` (runs minitest suite)
**Console**: Use `bin/console` for interactive development
**Gem Build**: Standard bundler gem structure (`bundle exec rake build`)

## Project Conventions

**Error Handling**: Only `exec` methods should raise exceptions. Use `exec_fallback` for custom retry behavior.

**State Management**: Store all workflow state in the shared hash, not in node instance variables (nodes are cloned during execution).

**Action Names**: Use descriptive strings like "approved", "needs_revision", "finished" rather than generic names.

**Node Composition**: Build complex workflows by composing simple, single-purpose nodes rather than monolithic ones.

**Concurrency**: Use `ParallelBatchNode` and `ParallelBatchFlow` for I/O-bound tasks like LLM API calls and shell commands where Ruby's GVL is released for true parallelism.

**Thread Safety**: Parallel nodes automatically handle thread safety by cloning node instances and safely merging shared context results.

## Common Patterns from Tests

**QA Pattern**: Question → Answer flow with shared context passing
**RAG Pattern**: Chunk → Embed → Store → Query → Retrieve → Generate pipeline
**MapReduce**: BatchNode for mapping, followed by reduction node (use ParallelBatchNode for concurrent mapping)
**Multi-Agent**: Self-referencing nodes with queue-based message passing
**Conditional Branching**: Use `post` return values to route between different node paths
**Concurrent I/O**: ParallelBatchNode/ParallelBatchFlow for API calls, shell commands, file operations

## Testing Patterns

Tests are in `test/` using Minitest. Each pattern has dedicated test files:
- `core_abstraction_examples_test.rb`: Basic node lifecycle examples
- `*_pattern_test.rb`: Specific workflow patterns (QA, RAG, etc.)
- `flow_*_test.rb`: Flow orchestration and composition

Test nodes often mock external services (LLM calls, file operations) with simple string operations for deterministic testing.

## Key Files

- `lib/pocketflow.rb`: Complete library implementation
- `test/core_abstraction_examples_test.rb`: Best examples of node patterns
- `README.md`: Comprehensive examples and API documentation
