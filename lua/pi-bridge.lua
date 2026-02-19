local M = {}

M.config = {
  port = 7391,
  host = "127.0.0.1",
}

function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})

  vim.api.nvim_create_user_command("PiSend", function(args)
    M.send_selection("context", args.args ~= "" and args.args or nil)
  end, { range = true, nargs = "?" })

  vim.api.nvim_create_user_command("PiAsk", function(args)
    M.send_selection("prompt", args.args ~= "" and args.args or nil)
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

  local payload = {
    text = text,
    file = file ~= "" and file or nil,
    filetype = filetype ~= "" and filetype or nil,
  }

  if prompt then
    payload.prompt = prompt
  end

  local body = vim.fn.json_encode(payload)
  local url = string.format("http://%s:%d/%s", M.config.host, M.config.port, endpoint)

  vim.fn.jobstart({
    "curl", "-s", "-X", "POST",
    "-H", "Content-Type: application/json",
    "-d", body,
    url,
  }, {
    on_stdout = function(_, data, _)
      local out = table.concat(data, "")
      if out ~= "" then
        local ok, resp = pcall(vim.fn.json_decode, out)
        if ok and resp and resp.ok then
          vim.schedule(function()
            vim.notify("pi: sent to " .. endpoint, vim.log.levels.INFO)
          end)
        elseif ok and resp and resp.error then
          vim.schedule(function()
            vim.notify("pi: " .. resp.error, vim.log.levels.ERROR)
          end)
        end
      end
    end,
    on_stderr = function(_, data, _)
      local err = table.concat(data, "")
      if err ~= "" and not err:match("^%s*$") then
        vim.schedule(function()
          vim.notify("pi: connection failed", vim.log.levels.ERROR)
        end)
      end
    end,
  })
end

function M.health()
  local url = string.format("http://%s:%d/health", M.config.host, M.config.port)
  vim.fn.jobstart({ "curl", "-s", url }, {
    on_stdout = function(_, data, _)
      local out = table.concat(data, "")
      if out ~= "" then
        vim.schedule(function()
          local ok, resp = pcall(vim.fn.json_decode, out)
          if ok and resp and resp.status == "ok" then
            vim.notify("pi: bridge alive on port " .. resp.port, vim.log.levels.INFO)
          else
            vim.notify("pi: bridge not responding", vim.log.levels.WARN)
          end
        end)
      end
    end,
    on_stderr = function(_, data, _)
      local err = table.concat(data, "")
      if err ~= "" and not err:match("^%s*$") then
        vim.schedule(function()
          vim.notify("pi: bridge unreachable", vim.log.levels.ERROR)
        end)
      end
    end,
  })
end

return M
