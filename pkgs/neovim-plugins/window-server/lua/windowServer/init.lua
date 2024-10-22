-- window-server.lua

local windowServer = {}

function windowServer.setup()
    local pid = vim.fn.getpid()
    local socket = "/tmp/nvim_" .. pid .. ".socket"

    -- Function to remove the socket if it exists
    local function remove_socket(socket_path)
        local ok, err = os.remove(socket_path)
        if not ok and not err:match("No such file") then
            print("Failed to remove socket: " .. err)
        end
    end

    -- Start Neovim server on the unique socket address
    local function start_server()
        -- Check if the socket file exists
        local stat = vim.loop.fs_stat(socket)
        if stat then
            -- Socket file exists; remove it
            remove_socket(socket)
        end

        -- Start the server on the socket
        local success, err = pcall(function()
            vim.fn.serverstart(socket)
        end)

        if not success then
            print("Failed to start server on " .. socket .. ": " .. err)
            return
        end
    end

    -- Function to set the terminal window title to include Neovim PID
    local function set_terminal_title()
        -- get current tile.
        local title = vim.fn.fnamemodify(vim.fn.getcwd(), ':t')

        -- set the title append with pid
        local title = title .. " - " .. pid
        -- Send the escape sequence to set the window title
        vim.fn.chansend(vim.v.stderr, "\x1b]0;" .. title .. "\x07")
    end

    -- Set the window title when Neovim starts
    set_terminal_title()

    start_server()

    -- Optionally, update the title on events like directory changes
    vim.api.nvim_create_autocmd({"DirChanged", "VimEnter"}, {
        callback = set_terminal_title,
    })


    -- Clean up the socket on exit
    vim.api.nvim_create_autocmd("VimLeavePre", {
        callback = function()
            remove_socket(socket)
        end,
    })

    -- Set up an autocommand to handle focus changes
    vim.api.nvim_create_autocmd("WinEnter", {
        callback = function()
            vim.fn.system('hyprctl dispatch focuswindow pid:' .. pid)
        end,
    })



    vim.cmd([[
      function! ExecuteLua(code)
        return luaeval('(function() ' .. a:code .. ' end)()')
      endfunction
    ]])


    -- Define a generic function to execute commands and check if state changed
    function _G.execute_and_check(command)
        local initial_state = vim.inspect(vim.fn.getwininfo())
        local status, err = pcall(function()
            vim.api.nvim_command(command)
        end)
        if not status then
            -- Command failed
            return 0
        end
        local new_state = vim.inspect(vim.fn.getwininfo())
        if initial_state ~= new_state then
            -- State changed
            return 1
        else
            -- State didn't change
            return 0
        end
    end

end

return windowServer
