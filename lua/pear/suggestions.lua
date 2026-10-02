local M = {}

M.active_suggestions = {}

local function find_old_text(bufnr, old_text)
    if not old_text or old_text == "" then return nil end
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local old_lines = vim.split(old_text, "\n", { plain = true })
    
    for i = 1, #lines - #old_lines + 1 do
        local match = true
        for j = 1, #old_lines do
            local line_content = lines[i + j - 1] or ""
            local old_content = old_lines[j] or ""
            if vim.trim(line_content) ~= vim.trim(old_content) then
                match = false
                break
            end
        end
        if match then
            return { start_line = i - 1, end_line = i - 1 + #old_lines }
        end
    end
    return nil
end

--- Generate a unified diff-like view for the float
local function generate_diff_lines(old_text, new_text)
    local old_lines = vim.split(old_text, "\n", { plain = true })
    local new_lines = vim.split(new_text, "\n", { plain = true })
    
    local display_lines = {}
    local hl_commands = {}
    
    -- Very basic diffing heuristic: find common prefix and suffix lines
    local prefix_count = 0
    while prefix_count < #old_lines and prefix_count < #new_lines and old_lines[prefix_count + 1] == new_lines[prefix_count + 1] do
        prefix_count = prefix_count + 1
    end
    
    local suffix_count = 0
    while suffix_count < (#old_lines - prefix_count) and suffix_count < (#new_lines - prefix_count) 
          and old_lines[#old_lines - suffix_count] == new_lines[#new_lines - suffix_count] do
        suffix_count = suffix_count + 1
    end

    -- 1. Unchanged Prefix
    for i = 1, prefix_count do
        table.insert(display_lines, "  " .. old_lines[i])
    end
    
    -- 2. Deleted middle (Red)
    for i = prefix_count + 1, #old_lines - suffix_count do
        table.insert(display_lines, "- " .. old_lines[i])
        table.insert(hl_commands, { group = "DiffDelete", line = #display_lines - 1 })
    end
    
    -- 3. Added middle (Green)
    for i = prefix_count + 1, #new_lines - suffix_count do
        table.insert(display_lines, "+ " .. new_lines[i])
        table.insert(hl_commands, { group = "DiffAdd", line = #display_lines - 1 })
    end
    
    -- 4. Unchanged Suffix
    for i = #old_lines - suffix_count + 1, #old_lines do
        table.insert(display_lines, "  " .. old_lines[i])
    end

    return display_lines, hl_commands
end

--- Render the suggestion inside a floating window for review
---@param bufnr number The buffer number
---@param old_text string The original text to replace
---@param new_text string The code suggested by the agent
---@param id string A unique identifier for this edit
function M.show_suggestion(bufnr, old_text, new_text, id)
    local range = find_old_text(bufnr, old_text)
    local line_start = range and range.start_line or vim.api.nvim_win_get_cursor(0)[1] - 1

    -- Create a scratch buffer to hold the unified diff
    local diff_buf = vim.api.nvim_create_buf(false, true)
    vim.bo[diff_buf].buftype = "nofile"
    vim.bo[diff_buf].bufhidden = "wipe"
    -- Attempt to set the same filetype as the original buffer for syntax highlighting
    vim.bo[diff_buf].filetype = vim.bo[bufnr].filetype

    local display_lines, hl_commands = generate_diff_lines(old_text, new_text)

    -- Set the lines in the buffer
    vim.api.nvim_buf_set_lines(diff_buf, 0, -1, false, display_lines)

    -- Apply the highlight groups
    local ns_id = vim.api.nvim_create_namespace("pear_diff")
    for _, hl in ipairs(hl_commands) do
        vim.api.nvim_buf_set_extmark(diff_buf, ns_id, hl.line, 0, {
            line_hl_group = hl.group,
        })
    end

    -- Calculate floating window dimensions
    local win_width = math.floor(vim.o.columns * 0.7)
    local win_height = math.min(#display_lines + 2, math.floor(vim.o.lines * 0.6))
    
    local win_opts = {
        relative = 'editor',
        width = win_width,
        height = win_height,
        row = math.floor((vim.o.lines - win_height) / 2),
        col = math.floor((vim.o.columns - win_width) / 2),
        style = 'minimal',
        border = 'rounded',
        title = ' Pear Code Review (y = accept, n = reject) ',
        title_pos = 'center',
    }

    local diff_win = vim.api.nvim_open_win(diff_buf, true, win_opts)

    -- Save suggestion state
    M.active_suggestions[id] = {
        bufnr = bufnr,
        old_text = old_text,
        new_text = new_text,
        range = range,
        diff_win = diff_win,
        diff_buf = diff_buf,
    }

    -- Set up keymaps for the floating window
    local function accept()
        M.accept(id)
    end
    
    local function reject()
        M.reject(id)
    end

    vim.keymap.set('n', 'y', accept, { buffer = diff_buf, noremap = true, silent = true })
    vim.keymap.set('n', '<CR>', accept, { buffer = diff_buf, noremap = true, silent = true })
    vim.keymap.set('n', 'n', reject, { buffer = diff_buf, noremap = true, silent = true })
    vim.keymap.set('n', 'q', reject, { buffer = diff_buf, noremap = true, silent = true })
    vim.keymap.set('n', '<Esc>', reject, { buffer = diff_buf, noremap = true, silent = true })
end

--- Accept a suggestion by ID
---@param id string
function M.accept(id)
    local suggestion = M.active_suggestions[id]
    if not suggestion then return end

    local lines = vim.split(suggestion.new_text, "\n", { plain = true })
    if suggestion.range then
        -- Replace exact block
        vim.api.nvim_buf_set_lines(suggestion.bufnr, suggestion.range.start_line, suggestion.range.end_line, false, lines)
    else
        -- Fallback insert at cursor
        local start = vim.api.nvim_win_get_cursor(0)[1] - 1
        vim.api.nvim_buf_set_lines(suggestion.bufnr, start, start, false, lines)
    end

    -- Close the window
    if vim.api.nvim_win_is_valid(suggestion.diff_win) then
        vim.api.nvim_win_close(suggestion.diff_win, true)
    end

    print("Pear: Accepted change.")
    M.active_suggestions[id] = nil
end

--- Reject a suggestion by ID
---@param id string
function M.reject(id)
    local suggestion = M.active_suggestions[id]
    if not suggestion then return end

    -- Close the window
    if vim.api.nvim_win_is_valid(suggestion.diff_win) then
        vim.api.nvim_win_close(suggestion.diff_win, true)
    end

    print("Pear: Rejected change.")
    M.active_suggestions[id] = nil
end

-- Fallbacks for the global commands if they hit it outside the window
function M.accept_all()
    for id, _ in pairs(M.active_suggestions) do
        M.accept(id)
    end
end

function M.reject_all()
    for id, _ in pairs(M.active_suggestions) do
        M.reject(id)
    end
end

return M