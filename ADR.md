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

## 5. UI Feedback: Inline Spinners & Floating Prompts
**Status:** Accepted

**Context:**
The original design forced a sidebar open every time a prompt was submitted, which was intrusive. Furthermore, users lacked clear visual feedback on what code was selected during prompt entry.

**Decision:**
- **Floating Input:** Replaced `vim.ui.input` with a custom floating window positioned at the cursor (`ui.prompt_user`).
- **Visual Retention:** While the float is open, the visual selection is manually re-highlighted using an `extmark` namespace so the user remembers what code they are modifying.
- **Inline Loading:** Removed the auto-opening sidebar. Replaced it with an asynchronous animated spinner (`⠋ Pear agent thinking...`) rendered as virtual text immediately above the selected code block.
- **Hidden Logs:** The sidebar is now strictly a hidden log buffer, accessible only via `:PearSidebar` when a user wishes to debug or read verbose LLM chat output.

**Consequences:**
- The plugin feels highly integrated, premium, and non-intrusive.
- The user's focus never leaves their active code buffer during the entire prompt-to-edit lifecycle.
