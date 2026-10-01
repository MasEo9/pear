local rpc = require("pear.rpc")

local M = {}

-- Plugin configuration with defaults
M.config = {
    pi_cmd = "pi",
    pi_args = { "--mode", "rpc", "--name", "pear_session" },
}

function M.setup(opts)
    M.config = vim.tbl_deep_extend("force", M.config, opts or {})

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
            ui.set_context(vim.api.nvim_get_current_buf(), line1 - 1)
            
            local success = rpc.send(payload)
            if success then
                print("Pear: Submitted to agent!")
            end
        end)
    end, { range = true, desc = "Submit selected code to Pear" })
end

return M
