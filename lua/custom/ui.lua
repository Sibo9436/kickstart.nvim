-- Custom UI elements that I apparently I had to do for myself
-- Dependis on plenary.nvim (for now???)
local M = {}

local highlights = {
  SiboUINormal = { default = true, link = 'Normal' },
  SiboUIPopup = { default = true, link = 'PopupColor1' },
  SiboUICurrent = { default = true, link = 'Visual' },
  SiboUISelection = { default = true, link = 'Type' },
  SiboUIGutter = { default = true, link = 'Identifier' },
  -- hide cursor for selection windows, doesn't seem to work rn :)
  SiboUICursorHidden = { default = true, blend = 100 },
}

for k, v in pairs(highlights) do
  -- NOTE: do I want to keep this globally available?
  vim.api.nvim_set_hl(0, k, v)
end

-- Prompts the user for a selection and calls the provided cb function
-- with the data
---@generic T: any
---@param opts {
---prompt: string,
---index_map: (fun(v:T):string),
---custom_virt: fun(v:T):string[][] }
---@param values T[]
---@param cb fun(sel: T[]|nil)
M.select = function(opts, values, cb)
  if not values or #values == 0 then
    return
  end
  local prompt = opts.prompt or 'Select zero or more:'
  local index_map = opts.index_map or function(v)
    return tostring(v)
  end
  local buf = vim.api.nvim_create_buf(false, true)
  local strings = vim.tbl_map(index_map, values)
  local virts = opts.custom_virt ~= nil and vim.tbl_map(opts.custom_virt, values) or nil
  local sel = vim.tbl_map(function(_)
    return false
  end, values)
  vim.api.nvim_buf_set_lines(buf, 0, -1, true, strings)
  local ns = vim.api.nvim_create_namespace ''

  local marks = {}
  vim.api.nvim_set_option_value('buftype', 'nofile', { buf = buf })
  vim.api.nvim_set_option_value('bufhidden', 'wipe', { buf = buf })
  vim.api.nvim_set_option_value('modifiable', false, { buf = buf })
  local height = #strings + 4
  local width = math.floor(vim.o.columns * 0.35)
  for idx, line in ipairs(strings) do
    -- marks for decoration
    -- TODO: I guess I should
    vim.api.nvim_buf_set_extmark(buf, vim.api.nvim_create_namespace 'customuigutter', idx - 1, 0, {
      virt_text = { { ' ', 'SiboUIGutter' }, { tostring(idx) .. ': ', 'SiboUIGutter' } },
      virt_text_pos = 'inline',
    })
    local sw = vim.fn.strdisplaywidth(line) + 6
    if virts then
      vim.api.nvim_buf_set_extmark(buf, vim.api.nvim_create_namespace 'customuivirt', idx - 1, -1, {
        virt_text = virts[idx],
        hl_mode = 'combine',
        virt_text_pos = 'eol_right_align',
      })
    end
    if width < sw then
      width = sw
    end
  end
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)
  local win = vim.api.nvim_open_win(buf, true, {
    -- Padded for prettiness
    -- title = { { '▏' .. prompt .. '▕', 'FloatBorder' } },
    title = { { prompt, 'FloatBorder' } },
    title_pos = 'center',
    border = 'single',
    relative = 'editor',
    anchor = 'NW',
    style = 'minimal',
    row = row,
    col = col,
    width = width,
    height = height,
    -- FOR now I guess
    noautocmd = true,
  })
  local toggle_sel = function(up)
    local line = vim.fn.line '.'
    sel[line] = not sel[line]
    local c = vim.api.nvim_win_get_cursor(0)
    if up then
      c[1] = line == 1 and #strings or line - 1
    else
      c[1] = line % #strings + 1
    end
    vim.api.nvim_win_set_cursor(0, c)
    vim.api.nvim_buf_clear_namespace(buf, vim.api.nvim_create_namespace 'customuigutter', line - 1, line)
    vim.api.nvim_buf_set_extmark(buf, vim.api.nvim_create_namespace 'customuigutter', line - 1, 0, {
      virt_text = { { sel[line] and '+' or ' ', 'SiboUIGutter' }, { tostring(line) .. ': ', 'SiboUIGutter' } },
      virt_text_pos = 'inline',
    })
    if sel[line] then
      marks[line] = vim.api.nvim_buf_set_extmark(buf, ns, line - 1, 0, {
        hl_group = 'SiboUISelection',
        hl_eol = true,
        end_line = line,
        end_col = 0,
      })
    else
      vim.api.nvim_buf_del_extmark(buf, ns, marks[line])
    end
  end
  local toggle_sel_move_up = function()
    toggle_sel(true)
  end
  -- oddioo...???
  -- non molto elegante ma impedisce di chiamare il cb due volte...
  local cb_called = false
  local end_sel = function()
    local v = {}
    for idx, s in ipairs(sel) do
      if s then
        table.insert(v, values[idx])
      end
    end
    cb(v)
    cb_called = true
    vim.api.nvim_win_close(win, true)
  end
  vim.api.nvim_create_autocmd('WinLeave', {
    buffer = buf,
    callback = function()
      -- NOTE: non sono sicuro se chiamare il cb o meno in caso di uscita senza selezione
      -- pero la logica e' che se poi certo di sincronizzare l'api e non chiamo il cb
      -- blocco una coroutine per sempre
      if not cb_called then
        cb(nil)
      end
      if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_close(win, true)
      end
    end,
  })
  -- Window styling
  vim.api.nvim_set_option_value('cursorline', true, { win = win })
  -- TODO: check if setting up a window local highlight override could be better
  vim.api.nvim_set_option_value('winhl', 'Normal:SiboUINormal,EndOfBuffer:SiboUINormal,CursorLine:SiboUICurrent', { win = win })
  -- Buffer keymaps
  vim.api.nvim_buf_set_keymap(buf, 'n', '<Tab>', '', { callback = toggle_sel })
  vim.api.nvim_buf_set_keymap(buf, 'n', '<S-Tab>', '', { callback = toggle_sel_move_up })
  vim.api.nvim_buf_set_keymap(buf, 'n', '<Space>', '', { callback = toggle_sel })
  vim.api.nvim_buf_set_keymap(buf, 'n', '<CR>', '', { callback = end_sel })
  vim.api.nvim_buf_set_keymap(buf, 'n', '<Esc>', '', {
    callback = function()
      if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_close(win, true)
      end
    end,
  })
  vim.api.nvim_buf_set_keymap(buf, 'n', 'q', '<Esc>', {})
end

return M
