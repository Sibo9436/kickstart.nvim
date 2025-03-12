-- Linting

vim.pack.add { 'https://github.com/mfussenegger/nvim-lint' }

local lint = require 'lint'
require('lint.linters.checkstyle').config_file = vim.fn.getcwd() .. '/codestyle/checkstyle/checkstyle.xml'
local checkstyle_args = require('lint.linters.checkstyle').args
table.insert(checkstyle_args, '--exclude-regexp')
table.insert(checkstyle_args, '/build/generated/')
require('lint.linters.checkstyle').args = checkstyle_args
require('lint.linters.pmd').rulesets = vim.fn.getcwd() .. '/codestyle/pmd/ruleset.xml'

lint.linters_by_ft = {
  markdown = { 'markdownlint' },
  typescriptreact = { 'eslint_d' },
  typescript = { 'eslint_d' },
  java = { 'checkstyle', 'pmd' },
}

local lint_augroup = vim.api.nvim_create_augroup('lint', { clear = true })
vim.api.nvim_create_autocmd({ 'BufEnter', 'BufWritePost', 'InsertLeave' }, {
  group = lint_augroup,
  callback = function()
    if vim.bo.modifiable then lint.try_lint() end
  end,
})
