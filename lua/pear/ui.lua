local M = {}

M.buf = nil
M.win = nil
M.spinner_timer = nil
M.spinner_frames = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
M.spinner_idx = 1
M.is_loading = false

local spinner_ns = vim.api.nvim_create_namespace("pear_spinner")
M.target_bufnr = nil
M.target_row = nil
M.spinner_extmark = nil

--- Set the context for where the inline spinner should appear
function M.set_context(bufnr, row)
    M.target_bufnr = bufnr
    M.target_row = row
end

--- Ensure the log buffer exists without opening a window
function M.ensure_buffer()
    if not M.buf or not vim.api.nvim_buf_is_valid(M.buf) then
        M.buf = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_name(M.buf, "Pear_Logs")
        vim.bo[M.buf].filetype = "markdown"
        vim.bo[M.buf].buftype = "nofile"
        vim.bo[M.buf].swapfile = false
    end
end

--- Stop the loading spinner
function M.stop_loading()
    M.is_loading = false
    if M.spinner_timer then
        M.spinner_timer:stop()
        if not M.spinner_timer:is_closing() then
            M.spinner_timer:close()
        end
        M.spinner_timer = nil
    end
    
    -- Remove the inline spinner extmark
    if M.spinner_extmark and M.target_bufnr and vim.api.nvim_buf_is_valid(M.target_bufnr) then
        vim.api.nvim_buf_del_extmark(M.target_bufnr, spinner_ns, M.spinner_extmark)
        M.spinner_extmark = nil
    end
end

--- Open a small floating window near the cursor to get the user's instruction
function M.prompt_user(callback)
    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].buftype = "nofile"
    vim.bo[buf].bufhidden = "wipe"
    
    local width = 60
    local height = 1
    
    -- Save the current visual selection marks so we can re-highlight them
    -- '< is start of last visual selection, '> is end
    local v_start = vim.fn.getpos("'<")
    local v_end = vim.fn.getpos("'>")
    
    -- Create a temporary highlight namespace for the visual selection
    local hl_ns = vim.api.nvim_create_namespace("pear_visual_hl")
    local current_buf = vim.api.nvim_get_current_buf()
    
    -- Apply the visual highlight if we have valid marks
    if v_start[2] > 0 and v_end[2] > 0 then
        -- Highlight line by line (Neovim extmarks handle line ranges best)
        for i = v_start[2] - 1, v_end[2] - 1 do
            vim.api.nvim_buf_set_extmark(current_buf, hl_ns, i, 0, {
                line_hl_group = "Visual",
            })
        end
    end

    local win = vim.api.nvim_open_win(buf, true, {
        relative = 'cursor',
        row = 1,
        col = 0,
        width = width,
        height = height,
        style = 'minimal',
        border = 'rounded',
        title = ' Pear Instruction ',
        title_pos = 'center',
    })

    -- Schedule starting insert mode so it triggers after the window opens
    vim.schedule(function()
        vim.cmd("startinsert")
    end)

    local function cleanup()
        vim.cmd("stopinsert")
        if vim.api.nvim_win_is_valid(win) then
            vim.api.nvim_win_close(win, true)
        end
        -- Clear the temporary visual highlight
        if vim.api.nvim_buf_is_valid(current_buf) then
            vim.api.nvim_buf_clear_namespace(current_buf, hl_ns, 0, -1)
        end
    end

    local function submit()
        local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
        local text = lines[1] or ""
        cleanup()
        callback(text)
    end

    local function cancel()
        cleanup()
        callback(nil)
    end

    -- Map Enter to submit in both insert and normal mode
    vim.keymap.set({'i', 'n'}, '<CR>', submit, { buffer = buf, noremap = true, silent = true })
    -- Map Escape to cancel
    vim.keymap.set('n', '<Esc>', cancel, { buffer = buf, noremap = true, silent = true })
    vim.keymap.set('n', 'q', cancel, { buffer = buf, noremap = true, silent = true })
end

--- Start a loading spinner inline above the selected text
function M.start_loading()
    if M.is_loading then return end
    M.is_loading = true
    
    if not M.target_bufnr or not vim.api.nvim_buf_is_valid(M.target_bufnr) then return end

    M.spinner_timer = vim.loop.new_timer()
    M.spinner_timer:start(0, 100, vim.schedule_wrap(function()
        if not M.is_loading or not vim.api.nvim_buf_is_valid(M.target_bufnr) then
            M.stop_loading()
            return
        end
        
        M.spinner_idx = (M.spinner_idx % #M.spinner_frames) + 1
        local frame = M.spinner_frames[M.spinner_idx]
        
        if M.spinner_extmark then
            vim.api.nvim_buf_del_extmark(M.target_bufnr, spinner_ns, M.spinner_extmark)
        end
        
        M.spinner_extmark = vim.api.nvim_buf_set_extmark(M.target_bufnr, spinner_ns, M.target_row, 0, {
            virt_lines = { { { frame .. " Pear agent thinking...", "WarningMsg" } } },
            virt_lines_above = true,
        })
    end))
end

--- Set up keymaps for the sidebar buffer
local function setup_buffer_keymaps(bufnr)
    -- Map <CR> (Enter) to accept a suggestion
    -- Call the Neovim API to set a buffer-local keymap
    -- Parameters:
    --   bufnr: The buffer ID where this keymap applies
    --   "n": Normal mode
    --   "<CR>": The key to press (Enter)
    --   "": The right-hand side is empty because we use a Lua callback instead
    vim.api.nvim_buf_set_keymap(bufnr, "n", "<CR>", "", {
        -- The Lua function to execute when the key is pressed
        callback = function()
            -- Get the contents of the line where the cursor is currently positioned
            local line = vim.api.nvim_get_current_line()
            -- Extract the suggestion ID if the line contains a pending suggestion
            -- Use Lua pattern matching to find a specific string format and capture the ID
            local id = line:match("%[Suggestion ID: (.-) pending approval%]")
            -- Check if a valid ID was found on the current line
            if id then
                -- Accept the suggestion
                -- Require the 'pear.suggestions' module, lazy-loading it
                local suggestions = require("pear.suggestions")
                -- Call the accept function on the suggestions module with the extracted ID
                suggestions.accept(id)
                -- Update the line text to reflect that it was accepted
                -- Get the current row of the cursor in the current window (0). Subtract 1 because API is 0-indexed
                local row = vim.api.nvim_win_get_cursor(0)[1] - 1
                -- Replace the current line in the buffer with a new string indicating the suggestion was accepted
                -- Parameters: bufnr, start row, end row (exclusive), strict indexing, list of replacement lines
                vim.api.nvim_buf_set_lines(bufnr, row, row + 1, false, { "[Suggestion ID: " .. id .. " Accepted]" })
            else
                -- If no ID was found, notify the user that no suggestion exists on this line
                print("Pear: No suggestion found on this line.")
            end
        end,
        -- Ensure the keymap doesn't trigger other mappings recursively
        noremap = true,
        -- Prevent the command from echoing on the command line
        silent = true,
        -- Provide a description for the keymap, visible in tools like telescope or which-key
        desc = "Accept Pear Suggestion",
    })
    
    -- Map "x" to reject a suggestion
    -- Call the Neovim API to set a buffer-local keymap
    -- Parameters:
    --   bufnr: The buffer ID where this keymap applies
    --   "n": Normal mode
    --   "x": The key to press (x)
    --   "": The right-hand side is empty because we use a Lua callback instead
    vim.api.nvim_buf_set_keymap(bufnr, "n", "x", "", {
        -- The Lua function to execute when the key is pressed
        callback = function()
            -- Get the contents of the line where the cursor is currently positioned
            local line = vim.api.nvim_get_current_line()
            -- Extract the suggestion ID if the line contains a pending suggestion
            -- Use Lua pattern matching to find a specific string format and capture the ID
            local id = line:match("%[Suggestion ID: (.-) pending approval%]")
            -- Check if a valid ID was found on the current line
            if id then
                -- Reject the suggestion
                -- Require the 'pear.suggestions' module, lazy-loading it
                local suggestions = require("pear.suggestions")
                -- Call the reject function on the suggestions module with the extracted ID
                suggestions.reject(id)
                -- Update the line text to reflect that it was rejected
                -- Get the current row of the cursor in the current window (0). Subtract 1 because API is 0-indexed
                local row = vim.api.nvim_win_get_cursor(0)[1] - 1
                -- Replace the current line in the buffer with a new string indicating the suggestion was rejected
                -- Parameters: bufnr, start row, end row (exclusive), strict indexing, list of replacement lines
                vim.api.nvim_buf_set_lines(bufnr, row, row + 1, false, { "[Suggestion ID: " .. id .. " Rejected]" })
            else
                -- If no ID was found, notify the user that no suggestion exists on this line
                print("Pear: No suggestion found on this line.")
            end
        end,
        -- Ensure the keymap doesn't trigger other mappings recursively
        noremap = true,
        -- Prevent the command from echoing on the command line
        silent = true,
        -- Provide a description for the keymap, visible in tools like telescope or which-key
        desc = "Reject Pear Suggestion",
    })
end

--- Create or open the UI sidebar window
function M.open()
    -- If window already exists and is valid, just focus or return
    if M.win and vim.api.nvim_win_is_valid(M.win) then
        return
    end

    M.ensure_buffer()
    setup_buffer_keymaps(M.buf)

    -- Open a vertical split on the right
    vim.cmd("botright vsplit")
    -- Store window handle
    M.win = vim.api.nvim_get_current_win()
    
    -- Set window buffer
    vim.api.nvim_win_set_buf(M.win, M.buf)
    
    -- Adjust window width
    vim.api.nvim_win_set_width(M.win, 40)

    -- Window local options
    -- Enable line wrapping
    vim.wo[M.win].wrap = true
    -- Disable absolute line numbers
    vim.wo[M.win].number = false
    -- Disable relative line numbers
    vim.wo[M.win].relativenumber = false
    -- Show sign column
    vim.wo[M.win].signcolumn = "yes"
end

--- Scroll the sidebar to the bottom
function M.scroll_to_bottom()
    if M.win and vim.api.nvim_win_is_valid(M.win) then
        local new_count = vim.api.nvim_buf_line_count(M.buf)
        vim.api.nvim_win_set_cursor(M.win, {new_count, 0})
    end
end

--- Append text lines to the sidebar
---@param lines string[]
function M.append_lines(lines)
    M.ensure_buffer()
    if not M.buf or not vim.api.nvim_buf_is_valid(M.buf) then
        return
    end
    
    local line_count = vim.api.nvim_buf_line_count(M.buf)
    
    -- If the buffer is empty (just 1 empty line), replace it
    if line_count == 1 then
        local first_line = vim.api.nvim_buf_get_lines(M.buf, 0, 1, false)[1]
        if first_line == "" then
            vim.api.nvim_buf_set_lines(M.buf, 0, -1, false, lines)
            M.scroll_to_bottom()
            return
        end
    end

    vim.api.nvim_buf_set_lines(M.buf, line_count, line_count, false, lines)
    M.scroll_to_bottom()
end

--- Append a raw string chunk to the buffer, handling inline concatenation
---@param text string
function M.append_text(text)
    M.ensure_buffer()
    if not M.buf or not vim.api.nvim_buf_is_valid(M.buf) then
        return
    end

    local lines = vim.split(text, "\n", { plain = true })
    local line_count = vim.api.nvim_buf_line_count(M.buf)
    local last_line = vim.api.nvim_buf_get_lines(M.buf, line_count - 1, line_count, false)[1] or ""

    -- Concatenate first segment to the existing last line
    lines[1] = last_line .. lines[1]

    -- Replace the last line and append any new lines from the chunk
    vim.api.nvim_buf_set_lines(M.buf, line_count - 1, line_count, false, lines)
    M.scroll_to_bottom()
end

--- Close the sidebar
function M.close()
    if M.win and vim.api.nvim_win_is_valid(M.win) then
        vim.api.nvim_win_close(M.win, true)
        M.win = nil
    end
end

--- Toggle the sidebar
function M.toggle()
    if M.win and vim.api.nvim_win_is_valid(M.win) then
        M.close()
    else
        M.open()
    end
end

return M
