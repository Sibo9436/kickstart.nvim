local eval_file = function()
  local filename = vim.fn.expand '%'
end
local eval_line = function()
  vim.system({
    vim.fn.expand '~/personal/git/crisp/crisp',
    '--raw',
  }, {
    text = true,
    stdin = vim.api.nvim_get_current_line(),
  }, function(s)
    vim.schedule(function()
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(buf, 0, -1, true, s)
      local win = vim.api.nvim_open_win(buf, true, {
        title = { { 'crisp:', 'FloatBorder' } },
        title_pos = 'left',
        border = 'single',
        relative = 'cursor',
        anchor = 'NW',
        style = 'minimal',
        row = row,
        col = col,
        width = width,
        height = height,
        -- FOR now I guess
        noautocmd = true,
      })

      print(vim.inspect(s))
      -- vim.notify(vim.inspect(s), vim.log.levels.INFO)
    end)
  end)
end

local eval_sel = function()
  vim.system({
    vim.fn.expand '~/personal/git/crisp/crisp',
    '--raw',
  }, {
    text = true,
    stdin = table.concat(
      vim.api.nvim_buf_get_text(0, vim.fn.getpos("'<")[2], vim.fn.getpos("'<")[3], vim.fn.getpos("'>")[2], vim.fn.getpos("'>")[3] + 1, {}),
      ' '
    ),
  }, function(s)
    vim.schedule(function()
      print(vim.inspect(s))
      -- vim.notify(vim.inspect(s), vim.log.levels.INFO)
    end)
  end)
end
vim.keymap.set('n', '<leader>el', eval_line, { desc = '[e]val current [l]ine' })
vim.keymap.set('v', '<leader>el', eval_sel, { desc = '[e]val current se[l]ection' })
vim.keymap.set('n', '<leader>ef', eval_file, { desc = '[e]val current [f]ile' })
vim.o.tabstop = 2
vim.o.softtabstop = 2
vim.o.sw = 0
