local M = {}

M.job_id = nil

local state = require("pear.state")

local function log_debug(msg)
    -- Open the log file in append mode
    local f = io.open("/tmp/pear_rpc.log", "a")
    -- If the file was successfully opened
    if f then
        -- Write the message followed by a newline
        f:write(msg .. "\n")
        -- Close the file handle
        f:close()
    end
end

local function handle_rpc_event(parsed)
    local ui = require("pear.ui")
    local state = require("pear.state")
    
    log_debug("RPC Event: " .. vim.json.encode(parsed))

    if parsed.type == "response" then
        -- This is just the RPC acknowledgment that the prompt was queued.
        -- Do nothing here, wait for run_start or message_start to actually indicate progress.
    elseif parsed.type == "run_start" then
        state.set_thinking()
    elseif parsed.type == "message_start" and parsed.message.role == "assistant" then
        state.set_thinking()
    elseif parsed.type == "message_update" and parsed.assistantMessageEvent then
        if parsed.assistantMessageEvent.type == "thinking_start" or parsed.assistantMessageEvent.type == "text_start" then
            state.set_thinking()
        elseif parsed.assistantMessageEvent.type == "text_delta" then
            state.set_writing()
            local text = parsed.assistantMessageEvent.delta
            if text and not text:match("```") then
                ui.append_text(text)
            end
        end
    elseif parsed.type == "tool_execution_start" or parsed.type == "tool_call_start" then
        local name = parsed.toolName or (parsed.tool_call and parsed.tool_call.name) or "unknown"
        state.set_tool_execution(name)
        ui.append_lines({ "", "[Executing Tool: " .. name .. "]" })
        
        -- Handle edit tools by intercepting them and showing suggestions
        if name == "edit" then
            local args = parsed.args or (parsed.tool_call and parsed.tool_call.parameters)
            if args and args.path and args.edits then
                local suggestions = require("pear.suggestions")
                -- Find the buffer for this file path
                local target_buf = vim.fn.bufnr(args.path)
                if target_buf ~= -1 then
                    for i, edit in ipairs(args.edits) do
                        if edit.newText and edit.oldText then
                            local id = (parsed.id or tostring(os.time())) .. "_" .. tostring(i)
                            suggestions.show_suggestion(target_buf, edit.oldText, edit.newText, id)
                            ui.append_lines({ "[Suggestion ID: " .. id .. " pending approval. Type :PearAccept]" })
                        else
                            ui.append_lines({ "[Error: Tool edit missing newText or oldText]" })
                        end
                    end
                else
                    ui.append_lines({ "[Warning: Target file buffer not open for edit: " .. args.path .. "]" })
                end
            end
        end
    elseif parsed.type == "tool_execution_end" or parsed.type == "tool_call_result" then
        state.set_thinking()
        ui.append_lines({ "[Tool Finished]" })
    elseif parsed.type == "turn_end" or parsed.type == "agent_end" or parsed.type == "agent_settled" then
        state.set_idle()
        ui.append_lines({ "", "[Done]" })
    end
end

local stdout_buffer = ""

--- Handle stdout stream from pi RPC
---@param data string[] Lines of JSON string output
local function on_stdout(_, data, _)
    if not data then return end
    
    for i, chunk in ipairs(data) do
        if i == 1 then
            stdout_buffer = stdout_buffer .. chunk
        else
            -- We hit a newline, so process the accumulated buffer
            if stdout_buffer ~= "" then
                local ok, parsed = pcall(vim.json.decode, stdout_buffer)
                if ok and parsed then
                    vim.schedule(function()
                        handle_rpc_event(parsed)
                    end)
                else
                    log_debug("Failed to parse JSON: " .. stdout_buffer)
                end
            end
            -- Start a new buffer with the current chunk (which might be partial)
            stdout_buffer = chunk
        end
    end
end

--- Handle stderr
local function on_stderr(_, data, _)
    -- Open the temporary error log file in append mode
    local f = io.open("/tmp/pear_rpc_err.log", "a")
    -- Process each line from the stderr data stream
    for _, line in ipairs(data) do
        -- Ignore empty lines
        if line and line ~= "" then
            -- Write the error line to the log file if it was successfully opened
            if f then f:write(line .. "\n") end
            -- Schedule the error message to be displayed in Neovim's UI safely
            vim.schedule(function()
                vim.api.nvim_err_writeln("Pear RPC Error: " .. line)
            end)
        end
    end
    -- Close the log file if it was successfully opened
    if f then f:close() end
end

--- Start the Pi RPC process
function M.start(config)
    -- Check if the RPC job is already running
    if M.job_id then
        print("Pear RPC is already running.")
        return
    end

    -- Prepare the command by combining the executable and its arguments
    local cmd = { config.pi_cmd }
    for _, arg in ipairs(config.pi_args) do
        table.insert(cmd, arg)
    end

    -- Start the job asynchronously
    M.job_id = vim.fn.jobstart(cmd, {
        on_stdout = on_stdout,
        on_stderr = on_stderr,
        on_exit = function(_, code, _)
            M.job_id = nil
            -- Ensure printing happens safely on the main loop
            vim.schedule(function()
                print("Pear RPC process exited with code " .. tostring(code))
            end)
        end,
        stdout_buffered = false,
        stderr_buffered = false,
    })

    -- Check if the job successfully started
    if M.job_id > 0 then
        print("Pear RPC started successfully (Job ID: " .. M.job_id .. ")")
    else
        M.job_id = nil
        vim.api.nvim_err_writeln("Failed to start Pear RPC process.")
    end
end

--- Stop the Pear RPC process
function M.stop()
    if M.job_id then
        vim.fn.jobstop(M.job_id)
        M.job_id = nil
        print("Pear RPC stopped.")
    else
        print("Pear RPC is not running.")
    end
end

--- Send a command to the RPC process
function M.send(msg_table)
    if not M.job_id then
        vim.api.nvim_err_writeln("Cannot send message: Pear RPC is not running.")
        return false
    end

    local json_str = vim.json.encode(msg_table)
    -- JSONL format requires a newline
    vim.fn.chansend(M.job_id, json_str .. "\n")
    return true
end

return M
