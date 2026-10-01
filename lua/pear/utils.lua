local M = {}

--- Get lines for a given range in the current buffer
---@param line1 number 1-indexed start line
---@param line2 number 1-indexed end line
---@return string[] lines
function M.get_lines(line1, line2)
    -- nvim_buf_get_lines is 0-indexed, end-exclusive
    return vim.api.nvim_buf_get_lines(0, line1 - 1, line2, false)
end

--- Get current buffer file path
---@return string
function M.get_current_file()
    return vim.fn.expand("%:p")
end

return M
