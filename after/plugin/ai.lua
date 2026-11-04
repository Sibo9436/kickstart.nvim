-- :ClaudeAsk — ask Claude a question; the answer renders in a markdown float.
-- A visual range (if any) is sent as stdin context; the buffer is never modified.

-- Returns a `stop` function. Uses fidget.nvim if available; otherwise falls
-- back to a cmdline echo.
local function start_thinking(prompt)
  local ok, progress = pcall(require, 'fidget.progress')
  if ok then
    local short = #prompt > 50 and (prompt:sub(1, 47) .. '…') or prompt
    local handle = progress.handle.create {
      title = 'Claude',
      message = short,
      lsp_client = { name = 'claude' },
    }
    return function() handle:finish() end
  end
  vim.api.nvim_echo({ { 'Claude is thinking…', 'Comment' } }, false, {})
  return function() vim.api.nvim_echo({ { '' } }, false, {}) end
end

vim.api.nvim_create_user_command('ClaudeAsk', function(args)
  local bufnr = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local stdinput = args.range ~= 0 and vim.api.nvim_buf_get_lines(0, args.line1 - 1, args.line2, false)
  vim.ui.input({ prompt = 'Ask Claude: ' }, function(value)
    if not value or value == '' then return end
    local stop_thinking = start_thinking(value)
    vim.system({
      'claude',
      '--model',
      'opus',
      '--append-system-prompt',
      [[You are assisting inside neovim, answering questions about the user's project or current file.
Be concise. Use markdown. Include quickfix-style file:line links when referring to code.
If the user selected lines before asking, they are provided on stdin as context.]],
      '--append-system-prompt',
      'current file: ' .. vim.uri_from_bufnr(bufnr),
      '--append-system-prompt',
      'file type: ' .. vim.bo[bufnr].filetype,
      '--append-system-prompt',
      string.format('cursor position: line %d, column %d', cursor[1], cursor[2] + 1),
      '-p',
      value,
    }, { stdin = stdinput }, function(out)
      vim.schedule(stop_thinking)
      if out.code ~= 0 then
        vim.schedule(function() vim.notify('Claude call failed' .. (out.stderr or ''), vim.log.levels.ERROR) end)
        return
      end
      local lines = vim.split(out.stdout, '\n')
      vim.schedule(function()
        local scratch = vim.api.nvim_create_buf(false, true)
        vim.bo[scratch].filetype = 'markdown'
        vim.api.nvim_buf_set_lines(scratch, 0, #lines, false, lines)
        vim.bo[scratch].modifiable = false
        vim.bo[scratch].readonly = true
        vim.diagnostic.enable(false, { bufnr = scratch })
        local max_w = math.floor(vim.o.columns * 0.7)
        local max_h = math.floor(vim.o.lines * 0.6)
        local w = 30
        for _, l in ipairs(lines) do
          w = math.max(w, vim.fn.strdisplaywidth(l) + 2)
        end
        vim.api.nvim_open_win(scratch, true, {
          title = { { 'Claude', 'FloatBorder' } },
          title_pos = 'center',
          border = 'single',
          relative = 'cursor',
          row = 0,
          col = 0,
          anchor = 'NW',
          style = 'minimal',
          width = math.min(w, max_w),
          height = math.max(1, math.min(#lines, max_h)),
          noautocmd = true,
        })
        vim.keymap.set('n', 'q', '<cmd>close<cr>', { buffer = scratch, nowait = true, silent = true })
      end)
    end)
  end)
end, { range = true })
