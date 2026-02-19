local M = {}

M.config = {}

local uv = vim.uv or vim.loop

local function socket_path(cwd)
  local hash = vim.fn.sha256(cwd):sub(1, 16)
  return "/tmp/pi-bridge-" .. hash .. ".sock"
end

local function send(sock_path, payload, callback)
  local encoded = vim.fn.json_encode(payload) .. "\n"
  local pipe = uv.new_pipe(false)
  pipe:connect(sock_path, function(err)
    if err then
      pipe:close()
      vim.schedule(function() callback(nil, err) end)
      return
    end

    pipe:write(encoded)

    local chunks = {}
    pipe:read_start(function(read_err, data)
      if read_err then
        pipe:read_stop()
        pipe:close()
        vim.schedule(function() callback(nil, read_err) end)
        return
      end

      if data then
        table.insert(chunks, data)
      else
        pipe:read_stop()
        pipe:close()
        local raw = table.concat(chunks, ""):match("^(.-)\n")
        vim.schedule(function() callback(raw, nil) end)
      end
    end)
  end)
end

function M.floating_input(on_confirm)
  local width = math.floor(vim.o.columns * 0.6)
  local height = 8
  local row = math.floor((vim.o.lines - height) / 2) - 1
  local col = math.floor((vim.o.columns - width) / 2)

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_option_value("buftype", "nofile", { buf = buf })
  vim.api.nvim_set_option_value("filetype", "markdown", { buf = buf })

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    row = row,
    col = col,
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
    title = " ask pi (enter send, shift-enter newline) ",
    title_pos = "center",
  })

  vim.api.nvim_set_option_value("wrap", true, { win = win })
  vim.api.nvim_set_option_value("linebreak", true, { win = win })
  vim.cmd("startinsert")

  local closed = false
  local function close()
    if closed then return end
    closed = true
    vim.cmd("stopinsert")
    if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
    if vim.api.nvim_buf_is_valid(buf) then vim.api.nvim_buf_delete(buf, { force = true }) end
  end

  local function submit()
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local text = vim.fn.trim(table.concat(lines, "\n"))
    close()
    if text ~= "" then
      vim.schedule(function() on_confirm(text) end)
    end
  end

  vim.keymap.set("i", "<CR>", submit, { buffer = buf })
  vim.keymap.set("n", "<CR>", submit, { buffer = buf })
  vim.keymap.set("i", "<S-CR>", "<CR>", { buffer = buf, remap = false })
  vim.keymap.set({ "n", "i" }, "<Esc>", close, { buffer = buf })
end

function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})

  vim.api.nvim_create_user_command("PiSend", function()
    M.send_selection("context")
  end, { range = true })

  vim.api.nvim_create_user_command("PiAsk", function(args)
    if args.args ~= "" then
      M.send_selection("prompt", args.args)
      return
    end
    local text = M.get_visual_selection()
    if not text or text == "" then
      vim.notify("pi: no selection", vim.log.levels.WARN)
      return
    end
    M.floating_input(function(input)
      if not input or input == "" then return end
      M.send_selection("prompt", input)
    end)
  end, { range = true, nargs = "?" })

  vim.api.nvim_create_user_command("PiHealth", function()
    M.health()
  end, {})
end

function M.get_visual_selection()
  local _, srow, scol, _ = unpack(vim.fn.getpos("'<"))
  local _, erow, ecol, _ = unpack(vim.fn.getpos("'>"))

  if srow > erow or (srow == erow and scol > ecol) then
    srow, erow = erow, srow
    scol, ecol = ecol, scol
  end

  local lines = vim.api.nvim_buf_get_lines(0, srow - 1, erow, false)
  if #lines == 0 then
    return nil
  end

  if #lines == 1 then
    lines[1] = string.sub(lines[1], scol, ecol)
  else
    lines[1] = string.sub(lines[1], scol)
    lines[#lines] = string.sub(lines[#lines], 1, ecol)
  end

  return table.concat(lines, "\n")
end

function M.send_selection(endpoint, prompt)
  local text = M.get_visual_selection()
  if not text or text == "" then
    vim.notify("pi: no selection", vim.log.levels.WARN)
    return
  end

  local file = vim.fn.expand("%:p")
  local filetype = vim.bo.filetype
  local cwd = vim.fn.getcwd()
  local sock = socket_path(cwd)

  local payload = {
    type = endpoint,
    text = text,
    file = file ~= "" and file or nil,
    filetype = filetype ~= "" and filetype or nil,
  }

  if prompt then
    payload.prompt = prompt
  end

  send(sock, payload, function(resp, err)
    if err then
      vim.notify("pi: bridge not running for " .. cwd, vim.log.levels.ERROR)
      return
    end
    if resp then
      local ok, decoded = pcall(vim.fn.json_decode, resp)
      if ok and decoded and decoded.ok then
        vim.notify("pi: sent to " .. endpoint, vim.log.levels.INFO)
      elseif ok and decoded and decoded.error then
        vim.notify("pi: " .. decoded.error, vim.log.levels.ERROR)
      end
    end
  end)
end

function M.health()
  local cwd = vim.fn.getcwd()
  local sock = socket_path(cwd)

  if vim.fn.getftype(sock) ~= "socket" then
    vim.notify("pi: no bridge at " .. sock, vim.log.levels.WARN)
    return
  end

  send(sock, { type = "health" }, function(resp, err)
    if err then
      vim.notify("pi: bridge unreachable", vim.log.levels.ERROR)
      return
    end
    if resp then
      local ok, decoded = pcall(vim.fn.json_decode, resp)
      if ok and decoded and decoded.status == "ok" then
        vim.notify("pi: bridge alive for " .. decoded.cwd, vim.log.levels.INFO)
      else
        vim.notify("pi: bridge not responding", vim.log.levels.WARN)
      end
    end
  end)
end

return M
