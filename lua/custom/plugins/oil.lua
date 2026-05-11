vim.pack.add {
  'https://github.com/stevearc/oil.nvim',
  'https://github.com/nvim-tree/nvim-web-devicons',
  'https://github.com/benomahony/oil-git.nvim',
  'https://github.com/JezerM/oil-lsp-diagnostics.nvim',
}

require('oil').setup {
  delete_to_trash = true,
}

require('oil-git').setup {}
require('oil-lsp-diagnostics').setup {}
