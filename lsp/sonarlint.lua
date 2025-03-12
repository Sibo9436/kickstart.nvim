-- TODO: Maybe add it to lspconfig.config
local project_name = vim.fn.fnamemodify(vim.fn.getcwd(), ':p:h:t')
local capabilities = vim.lsp.protocol.make_client_capabilities()
-- TODO: move outside, I've already been bamboozled once
capabilities = vim.tbl_deep_extend('force', capabilities, require('blink.cmp').get_lsp_capabilities())
---@type vim.lsp.Config
local sonarlint = {
  cmd = {
    '/Users/andrea.sibona/Library/Java/JavaVirtualMachines/corretto-21.0.8/Contents/Home/bin/java',
    '-jar',
    vim.fn.expand '$MASON/packages/sonarlint-language-server/extension/server/sonarlint-ls.jar',
    -- Ensure that sonarlint-language-server uses stdio channel
    '-stdio',
    '-analyzers',
    -- paths to the analyzers you need, using those for python and java in this example
    vim.fn.expand '$MASON/share/sonarlint-analyzers/sonarpython.jar',
    vim.fn.expand '$MASON/share/sonarlint-analyzers/sonarcfamily.jar',
    vim.fn.expand '$MASON/share/sonarlint-analyzers/sonarjava.jar',
  },
  capabilities = capabilities,
  init_options = {
    showVerboseLogs = false,
    productKey = 'nvim',
    telemetryStorage = '/tmp/sonarlint_usage',
    productName = 'SonarLint VSCode',
    workspaceName = project_name,
    firstSecretDetected = false,
    -- platform=
    -- architecture= process.arch,
    enableNotebooks = true,
    rules = {},
    focusOnNewCode = true,
    automaticAnalysis = true,
  },
  filetypes = {
    'cs',
    'dockerfile',
    'python',
    'cpp',
    'java',
  },
}
return sonarlint
