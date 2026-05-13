-- Lazy-register jdtls: its config walks Mason and spring share dirs, so we
-- defer the work until the first Java buffer is loaded. Module-level guard
-- keeps repeat buffer loads cheap.
if vim.g._jdtls_registered then return end
vim.g._jdtls_registered = true
vim.lsp.config('jdtls', require('custom.jdtls_config').config())
vim.lsp.enable 'jdtls'
