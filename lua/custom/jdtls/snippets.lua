local utils = require 'custom.jdtls.utils'
local M = {}

local function builder_methods()
  local client = utils.get_client(0)
  ---@type lsp.CompletionParams
  local params = vim.lsp.util.make_position_params(0, client._client.offset_encoding)
  params.context = { triggerKind = 2, triggerCharacter = '.' }
  vim.lsp.get_client_by_id(1):request_sync('textDocument/completion', params)
end

return M
