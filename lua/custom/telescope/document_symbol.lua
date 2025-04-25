local conf = require('telescope.config').values
local finders = require 'telescope.finders'
local make_entry = require 'telescope.make_entry'
local pickers = require 'telescope.pickers'
local utils = require 'telescope.utils'

local lsp = {}
-- stolen from telescope.builtin
local symbols_sorter = function(symbols)
  if vim.tbl_isempty(symbols) then
    return symbols
  end

  local current_buf = vim.api.nvim_get_current_buf()

  -- sort adequately for workspace symbols
  local filename_to_bufnr = {}
  for _, symbol in ipairs(symbols) do
    if filename_to_bufnr[symbol.filename] == nil then
      filename_to_bufnr[symbol.filename] = vim.uri_to_bufnr(vim.uri_from_fname(symbol.filename))
    end
    symbol.bufnr = filename_to_bufnr[symbol.filename]
  end

  table.sort(symbols, function(a, b)
    if a.bufnr == b.bufnr then
      return a.lnum < b.lnum
    end
    if a.bufnr == current_buf then
      return true
    end
    if b.bufnr == current_buf then
      return false
    end
    return a.bufnr < b.bufnr
  end)

  return symbols
end

function lsp.document_symbols(opts)
  opts = opts or {}
  opts.path_display = { 'hidden' }
  local bufnr = opts.bufnr or vim.fn.bufnr()
  local params = {
    textDocument = {
      uri = vim.uri_from_bufnr(bufnr),
    },
  }
  vim.lsp.buf_request_all(bufnr, 'textDocument/documentSymbol', params, function(results, ctx)
    if ctx.bufnr ~= bufnr then
      return
    end
    local client_locations = {}
    for _, v in ipairs(results) do
      --assert(v.result, v.err)
      if v.result then
        client_locations = vim.list_extend(client_locations, v.result)
      end
    end
    if vim.fn.has 'nvim-0.11' == 1 then
      local client = assert(vim.lsp.get_client_by_id(ctx.client_id))
      client_locations = vim.lsp.util.symbols_to_items(client_locations or {}, bufnr, client.offset_encoding) or {}
    else
      client_locations = vim.lsp.util.symbols_to_items(client_locations or {}, bufnr) or {}
    end
    --client_locations = utils.filter_symbols(client_locations, opts, symbols_sorter)
    pickers
      .new(opts, {
        prompt_title = 'LSP Document Symbols',
        finder = finders.new_table {
          results = client_locations,
          entry_maker = opts.entry_maker or make_entry.gen_from_lsp_symbols(opts),
        },
        previewer = conf.qflist_previewer(opts),
        sorter = conf.prefilter_sorter {
          tag = 'symbol_type',
          sorter = conf.generic_sorter(opts),
        },
        push_cursor_on_edit = true,
        push_tagstack_on_edit = true,
      })
      :find()
  end)
end

function lsp.lsp_dynamic_workspace_symbol(opts)
  opts = opts or {}
  opts.path_display = { 'hidden' }
  local bufnr = opts.bufnr or vim.fn.bufnr()
  local params = {
    query = '',
  }
  vim.lsp.buf_request_all(bufnr, 'workspace/symbol', params, function(results, ctx)
    if ctx.bufnr ~= bufnr then
      return
    end
    local client_locations = {}
    for _, v in ipairs(results) do
      assert(v.result, v.err)
      client_locations = vim.list_extend(client_locations, v.result)
    end
    if vim.fn.has 'nvim-0.11' == 1 then
      local client = assert(vim.lsp.get_client_by_id(ctx.client_id))
      client_locations = vim.lsp.util.symbols_to_items(client_locations or {}, bufnr, client.offset_encoding) or {}
    else
      client_locations = vim.lsp.util.symbols_to_items(client_locations or {}, bufnr) or {}
    end
    client_locations = utils.filter_symbols(client_locations, opts, symbols_sorter)
    pickers
      .new(opts, {
        prompt_title = 'LSP Workspace Symbols',
        finder = finders.new_table {
          results = client_locations,
          entry_maker = opts.entry_maker or make_entry.gen_from_lsp_symbols(opts),
        },
        previewer = conf.qflist_previewer(opts),
        sorter = conf.prefilter_sorter {
          tag = 'symbol_type',
          sorter = conf.generic_sorter(opts),
        },
        push_cursor_on_edit = true,
        push_tagstack_on_edit = true,
      })
      :find()
  end)
end

return lsp
