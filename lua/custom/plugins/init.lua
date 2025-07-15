-- You can add your own plugins here or in other files in this directory!
--  I promise not to create any merge conflicts in this directory :)
--
-- See the kickstart.nvim README for more information
return {
  {
    'stevearc/oil.nvim',
    ---@module 'oil'
    ---@type oil.SetupOpts
    opts = {
      delete_to_trash = true,
    },
    -- Optional dependencies
    dependencies = {
      -- { 'echasnovski/mini.icons', opts = {} }

      { 'nvim-tree/nvim-web-devicons', enabled = vim.g.have_nerd_font },
      { 'benomahony/oil-git.nvim' },
      { 'JezerM/oil-lsp-diagnostics.nvim', opts = {} },
    },
    -- dependencies = { "nvim-tree/nvim-web-devicons" }, -- use if you prefer nvim-web-devicons
    -- Lazy loading is not recommended because it is very tricky to make it work correctly in all situations.
    lazy = false,
  },
}
