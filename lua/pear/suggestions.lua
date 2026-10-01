local M = {}

local namespace = vim.api.nvim_create_namespace("pear_suggestions")
M.active_suggestions = {}

local function find_old_text(bufnr, old_text)
    if not old_text or old_text == "" then return nil end
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local old_lines = vim.split(old_text, "\n", { plain = true })
    
    for i = 1, #lines - #old_lines + 1 do
        local match = true
        for j = 1, #old_lines do
            -- Convert 1-based indexing for both lines array and old_lines array correctly
            local line_content = lines[i + j - 1] or ""
            local old_content = old_lines[j] or ""
            if vim.trim(line_content) ~= vim.trim(old_content) then
                match = false
                break
            end
        end
        if match then
            -- i is the 1-based index in the `lines` array. 
            -- Neovim API takes 0-based indices for start_line, and 0-based exclusive for end_line.
            return { start_line = i - 1, end_line = i - 1 + #old_lines }
        end
    end
    
    -- Fallback: if we can't find it, we will just return a nil range so it defaults to the cursor
    require("pear.ui").append_lines({ "[Warning: Could not find exact oldText match in buffer]" })
    return nil
end

--- Apply a suggestion as ghost text in a specific buffer
---@param bufnr number The buffer number
---@param old_text string The original text to replace
---@param new_text string The code suggested by the agent
---@param id string A unique identifier for this edit
function M.show_suggestion(bufnr, old_text, new_text, id)
    local range = find_old_text(bufnr, old_text)
    local line_start = range and range.start_line or vim.api.nvim_win_get_cursor(0)[1] - 1

    local lines = vim.split(new_text, "\n", { plain = true })
    
    local virt_lines = {}
    for _, line in ipairs(lines) do
        table.insert(virt_lines, { { line, "Comment" } })
    end

    local extmark_id = vim.api.nvim_buf_set_extmark(bufnr, namespace, line_start, 0, {
        virt_lines = virt_lines,
        virt_lines_above = true,
    })

    M.active_suggestions[id] = {
        bufnr = bufnr,
        extmark_id = extmark_id,
        old_text = old_text,
        new_text = new_text,
        range = range,
    }
end

--- Accept all pending suggestions
function M.accept_all()
    for id, suggestion in pairs(M.active_suggestions) do
        vim.api.nvim_buf_del_extmark(suggestion.bufnr, namespace, suggestion.extmark_id)
        
        local lines = vim.split(suggestion.new_text, "\n", { plain = true })
        if suggestion.range then
            -- Replace exact block (start_line is 0-indexed inclusive, end_line is 0-indexed exclusive)
            vim.api.nvim_buf_set_lines(suggestion.bufnr, suggestion.range.start_line, suggestion.range.end_line, false, lines)
        else
            -- Fallback insert
            local start = vim.api.nvim_win_get_cursor(0)[1] - 1
            vim.api.nvim_buf_set_lines(suggestion.bufnr, start, start, false, lines)
        end
        print("Pear: Accepted suggestion " .. id)
    end
    M.active_suggestions = {}
end

--- Reject all pending suggestions
function M.reject_all()
    for id, suggestion in pairs(M.active_suggestions) do
        vim.api.nvim_buf_del_extmark(suggestion.bufnr, namespace, suggestion.extmark_id)
    end
    M.active_suggestions = {}
    print("Pear: Rejected all suggestions")
end

--- Accept a suggestion by ID
---@param id string
function M.accept(id)
    local suggestion = M.active_suggestions[id]
    if not suggestion then return end

    -- Remove the ghost text
    vim.api.nvim_buf_del_extmark(suggestion.bufnr, namespace, suggestion.extmark_id)

    -- Insert the actual text into the buffer
    local lines = vim.split(suggestion.new_text, "\n", { plain = true })
    vim.api.nvim_buf_set_lines(suggestion.bufnr, suggestion.line_start, suggestion.line_start, false, lines)

    M.active_suggestions[id] = nil
end

--- Reject a suggestion by ID
---@param id string
function M.reject(id)
    local suggestion = M.active_suggestions[id]
    if not suggestion then return end

    -- Remove the ghost text
    vim.api.nvim_buf_del_extmark(suggestion.bufnr, namespace, suggestion.extmark_id)
    M.active_suggestions[id] = nil
end

return M
