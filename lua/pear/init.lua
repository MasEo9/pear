local rpc = require("pear.rpc")

local M = {}

-- Plugin configuration with defaults
M.config = {
    pi_cmd = "pi",
    pi_args = { "--mode", "rpc", "--name", "pear_session" },
    model = nil, -- Optional: explicitly set the model (e.g., "gemini-flash", "claude-3-5-sonnet")
    default_keymaps = true, -- Automatically bind <leader>pa, <leader>pr, etc.
}

function M.setup(opts)
    M.config = vim.tbl_deep_extend("force", M.config, opts or {})

    -- If a model is specified in the user config, append it to the RPC args
    if M.config.model then
        table.insert(M.config.pi_args, "--model")
        table.insert(M.config.pi_args, M.config.model)
    end

    -- Create user commands
    vim.api.nvim_create_user_command("PearStart", function()
        rpc.start(M.config)
    end, { desc = "Start the Pear (pi) RPC background process" })

    vim.api.nvim_create_user_command("PearStop", function()
        rpc.stop()
    end, { desc = "Stop the Pear (pi) RPC process" })

    vim.api.nvim_create_user_command("PearAccept", function()
        require("pear.suggestions").accept_all()
    end, { desc = "Accept all pending Pear suggestions in buffer" })

    vim.api.nvim_create_user_command("PearReject", function()
        require("pear.suggestions").reject_all()
    end, { desc = "Reject all pending Pear suggestions in buffer" })

    vim.api.nvim_create_user_command("PearSidebar", function()
        require("pear.ui").toggle()
    end, { desc = "Toggle the Pear agent logs sidebar" })

    vim.api.nvim_create_user_command("PearRefine", function(cmd_opts)
        local utils = require("pear.utils")
        local ui = require("pear.ui")
        local api = require("pear.api")
        
        local line1 = cmd_opts.line1
        local line2 = cmd_opts.line2
        local lines = utils.get_lines(line1, line2)
        local selected_text = table.concat(lines, "\n")
        
        -- Fallback: if not in visual mode, don't trigger an empty prompt
        if not selected_text or selected_text == "" then
            print("Pear: Please visually select code first.")
            return
        end

        ui.prompt_user(function(input)
            if not input or vim.trim(input) == "" then return end
            
            ui.set_context(vim.api.nvim_get_current_buf(), line1 - 1)
            ui.start_loading("Pear is refining...")
            vim.cmd("redraw")
            
            api.refine(input, selected_text, M.config.model, function(result)
                ui.stop_loading()
                if result then
                    require("pear.suggestions").show_suggestion(
                        vim.api.nvim_get_current_buf(), 
                        selected_text, 
                        result, 
                        "refine_" .. tostring(os.time())
                    )
                else
                    print("Pear: Refine request failed.")
                end
            end)
        end)
    end, { range = true, desc = "Fast inline edit using direct API" })

    vim.api.nvim_create_user_command("PearSubmit", function(cmd_opts)
        local utils = require("pear.utils")
        local ui = require("pear.ui")
        
        -- The user command is called with a range, so we get line1 and line2
        local line1 = cmd_opts.line1
        local line2 = cmd_opts.line2
        local lines = utils.get_lines(line1, line2)
        local file_path = utils.get_current_file()
        local selected_text = table.concat(lines, "\n")
        
        ui.prompt_user(function(input)
            if not input or vim.trim(input) == "" then
                print("Pear: No instruction provided, aborting.")
                return
            end

            -- Ensure RPC is running
            if not rpc.job_id then
                print("Pear: Starting RPC process...")
                rpc.start(M.config)
            end

            -- Construct the prompt payload for Pi (RPC mode)
            local payload = {
                id = "req-" .. tostring(os.time()),
                type = "prompt",
                message = string.format(
                    "You are an expert coding assistant integrated into Neovim.\n\n" ..
                    "I have selected the following code in %s (lines %d to %d):\n" ..
                    "```lua\n%s\n```\n\n" ..
                    "Instruction: %s\n\n" ..
                    "RULES:\n" ..
                    "1. If modifying code or adding comments, you MUST use the `edit` tool on `%s`.\n" ..
                    "2. Ensure `oldText` matches the file EXACTLY (including whitespace/indentation).\n" ..
                    "3. DO NOT output the code block in the chat. Be extremely brief in your text response (1 sentence max).",
                    file_path, line1, line2, selected_text, input, file_path
                ),
            }

            -- Send it off
            local ui = require("pear.ui")
            ui.set_context(vim.api.nvim_get_current_buf(), line1 - 1)
            
            -- Initialize the UI state machine if it hasn't been already
            if not ui.initialized then
                ui.init()
                ui.initialized = true
            end
            
            local state = require("pear.state")
            state.set_initializing()
            
            -- Flush the buffer so the UI has time to draw the virtual text before the background job kicks in
            vim.cmd("redraw")
            
            -- Defer the actual RPC send by 10ms to ensure the Neovim event loop has completely 
            -- cleared the floating window and rendered the extmark
            vim.defer_fn(function()
                local success = rpc.send(payload)
                if success then
                    print("Pear: Submitted to agent!")
                else
                    state.set_error()
                    print("Pear: Failed to submit to agent.")
                end
            end, 10)
        end)
    end, { range = true, desc = "Submit selected code to Pear" })

    -- Default Keybindings
    if M.config.default_keymaps ~= false then
        -- Normal mode mappings
        vim.keymap.set('n', '<leader>pa', '<Cmd>PearAccept<CR>', { desc = "Pear Accept Suggestion" })
        vim.keymap.set('n', '<leader>pr', '<Cmd>PearReject<CR>', { desc = "Pear Reject Suggestion" })

        -- Visual mode mappings
        -- Note: using <Cmd> here avoids the command-line colon entering visually-selected range automatically
        -- but for visual commands that operate on ranges, we actually *want* the range, so we use ':'
        vim.keymap.set('v', '<leader>ps', ':PearSubmit<CR>', { desc = "Pear Submit (Agent Mode)" })
        vim.keymap.set('v', '<leader>pf', ':PearRefine<CR>', { desc = "Pear Refine (Fast Mode)" })
    end
end

return M
