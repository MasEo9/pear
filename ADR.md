# Architecture Decision Records (ADR)

## 1. Language Choice: Lua vs. Rust
**Status:** Accepted

**Context:**
We need to build `PEAR`, a Neovim plugin that integrates with the `pi` coding agent. We evaluated Rust (compiled, type-safe, performant) vs. Lua (native to Neovim).

**Decision:**
We will use **Lua** as the primary language for this plugin.

**Consequences:**
- **Pros:** Zero-friction installation (no binaries or cargo required for users), direct and native access to `vim.api` (crucial for window management and `extmarks`), and adherence to Neovim ecosystem standards.
- **Cons:** Less robust typing. We will need to enforce good structural discipline when parsing JSON streams from `pi`.

## 2. Pi Integration: RPC Mode
**Status:** Accepted

**Context:**
`pi` can be executed as a one-shot CLI command or as a long-lived RPC server via standard input/output.

**Decision:**
We will use **RPC Mode** (`pi --mode rpc`). 

**Consequences:**
- **Pros:** Eliminates startup overhead for Node.js/models on every request. Provides a structured JSON stream (JSONL) that makes parsing tool calls (like `read`, `bash`, `edit`) and chat streams explicit and reliable.
- **Cons:** Requires the plugin to manage the lifecycle of a background process (`vim.fn.jobstart`) and handle asynchronous callbacks.

## 3. Agentic UI & UX (More than a Copilot clone)
**Status:** Superseded by ADR 4 & 5

**Context:**
Standard AI assistants just autocomplete or append text. We want `PEAR` to act as an agent that can read, explore, and propose modifications.

**Decision:**
- **Approval Queue:** Tool calls (like editing a file) will be intercepted and placed in a visual queue in a sidebar. (Note: Sidebar was later replaced by inline virtual text, see ADR 5).
- **Ghost Text Diffing:** Proposed code changes will be previewed in the active buffer using `extmarks` (virtual lines) interleaved as gray text, requiring user interaction to accept/reject.
- **Tool Visibility:** When `pi` uses a tool (e.g., executing bash to find a file), the UI will display a discrete status indicator, showing the agent's "thought process".

## 4. Acceptance Flow: Inline Commands vs Sidebar UI
**Status:** Accepted

**Context:**
Initially, accepting a code suggestion required the user to switch focus to a sidebar window and press `<CR>` on a specific line. This required context-switching away from the code being edited.

**Decision:**
We moved to an inline acceptance model.
- `suggestions.lua` intercepts `pi`'s `edit` tool, searches the active buffer for the `oldText`, and overlays `newText` directly on top of the matching block as gray virtual text.
- Global commands `:PearAccept` and `:PearReject` were introduced so users can accept/reject changes directly from their main buffer, completely bypassing the need to interact with the sidebar.

**Consequences:**
- Drastically improved UX and speed.
- Requires precise matching logic to locate `oldText` inside the buffer, including fallback logic if indentation doesn't match perfectly.

## 6. Hybrid Workflow: Agent vs. Copilot (The "Pair Programmer" Philosophy)
**Status:** Accepted

**Context:**
We discovered a friction point between task scope and latency. Using a full agent harness (`pi`) for minor, surgical edits (like adding a docstring) incurred an unacceptable 10-20 second "Agent Tax" (reasoning tokens + tool dispatch). However, removing `pi` entirely would destroy the plugin's ability to act as a true pair programmer that can autonomously gather context across the workspace.

**Decision:**
`PEAR` will embrace a dual-mode workflow to support both architectural implementation and surgical refinement:
1.  **Agent Mode (The Architect):** Driven by the `pi` RPC process. Best used for translating pseudocode/comments into implementations where the agent must autonomously read other files (e.g., schemas, utils) to gather context before writing. 
2.  **Copilot Mode (The Surgeon):** *[Pending Implementation]* A fast, direct API client for sub-second, inline transformations (e.g., "format this", "add comments") that only require the immediate visual selection context.

## 7. Ghost Text & Code Review UX
**Status:** Proposed

**Context:**
The current ghost text implementation uses the `Comment` highlight group (gray text) to differentiate suggested code from real code. However, reading un-highlighted gray text makes code review difficult, defeating the purpose of the approval queue.

**Decision:**
We will revamp the suggestion UI:
- We will retain native syntax highlighting for suggested code.
- To differentiate suggestions from real code, we will utilize background colors (e.g., a subtle green/blue diff background, similar to `DiffAdd` or GitHub PRs) and a virtual text gutter sign (`+`).
- This allows the user to review the code with full syntax comprehension while clearly seeing that it is a pending addition.
