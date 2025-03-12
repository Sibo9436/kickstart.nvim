-- debug.lua
--
-- Shows how to use the DAP plugin to debug your code.
--
-- Primarily focused on configuring the debugger for Go, but can
-- be extended to other languages as well. That's why it's called
-- kickstart.nvim and not kitchen-sink.nvim ;)

vim.pack.add {
  'https://github.com/mfussenegger/nvim-dap',
  'https://github.com/rcarriga/nvim-dap-ui',
  'https://github.com/nvim-neotest/nvim-nio',
  'https://github.com/mason-org/mason.nvim',
  'https://github.com/jay-babu/mason-nvim-dap.nvim',
  'https://github.com/leoluz/nvim-dap-go',
}

vim.keymap.set('n', '<F5>', function() require('dap').continue() end, { desc = 'Debug: Start/Continue' })
vim.keymap.set('n', '<F1>', function() require('dap').step_into() end, { desc = 'Debug: Step Into' })
vim.keymap.set('n', '<F2>', function() require('dap').step_over() end, { desc = 'Debug: Step Over' })
vim.keymap.set('n', '<F3>', function() require('dap').step_out() end, { desc = 'Debug: Step Out' })
vim.keymap.set('n', '<leader>b', function() require('dap').toggle_breakpoint() end, { desc = 'Debug: Toggle Breakpoint' })
vim.keymap.set('n', '<leader>B', function() require('dap').set_breakpoint(vim.fn.input 'Breakpoint condition: ') end, { desc = 'Debug: Set Breakpoint' })
vim.keymap.set('n', '<F7>', function() require('dapui').toggle() end, { desc = 'Debug: See last session result.' })

local dap = require 'dap'
local dapui = require 'dapui'

require('mason-nvim-dap').setup {
  automatic_installation = true,
  handlers = {
    function(config)
      require('mason-nvim-dap').default_setup(config)
    end,
    javadbg = function(config)
      config.adapters = {
        type = 'executable',
        command = 'java',
        args = {
          '-jar',
          vim.fn.expand '$HOME/.local/share/nvim/mason/share/java-debug-adapter/com.microsoft.java.debug.plugin.jar',
        },
      }
      require('mason-nvim-dap').default_setup(config)
    end,
  },
  ensure_installed = {
    'delve',
    'javadbg',
    'javatest',
  },
}

local jdtls = require 'custom.jdtls.utils'
local j_client = jdtls.get_client_opt()
if j_client then
  local repl = require 'dap.repl'
  repl.commands = vim.tbl_extend('force', repl.commands, {
    custom_commands = {
      ['.json'] = function(text)
        repl.execute(string.format('new com.fasterxml.jackson.databind.ObjectMapper().writeValueAsString(%s) ', text))
      end,
    },
  })
end
local main_classes = j_client and j_client:resolve_main_classes() or {}
local launch_local_config = {}
print('Found', #main_classes, 'main classes')
for _, mc in ipairs(main_classes) do
  local v = setmetatable({
    type = 'java',
    request = 'launch',
    name = 'Debug - ' .. mc.project_name,
  }, {
    __call = function()
      local jdtls_client = jdtls.get_client()
      jdtls_client:build_workspace_sync()
      local ws = jdtls_client._client.workspace_folders and jdtls_client._client.workspace_folders[1].name or nil
      return {
        type = 'java',
        request = 'launch',
        name = 'Debug - ' .. mc.project_name,
        mainClass = mc.main_class,
        projectName = mc.project_name,
        classPaths = jdtls_client:resolve_java_classpath(mc)[2],
        args = '--spring.profiles.active=billow,local',
        javaExec = jdtls_client:resolve_java_executable(mc),
        cwd = ws,
      }
    end,
  })
  table.insert(launch_local_config, v)
  table.insert(launch_local_config, {
    type = 'java',
    request = 'attach',
    name = 'Debug - Attach ' .. mc.project_name,
    hostName = '127.0.0.1',
    port = 5005,
    projectName = mc.project_name,
  })
end
dap.configurations.java = {}
print('Loading dap config', #dap.configurations.java)
for _, conf in ipairs(launch_local_config) do
  table.insert(dap.configurations.java, conf)
end
print('Loading dap config', #dap.configurations.java)

dap.adapters.java = function(callback)
  local res = jdtls.get_client()._client:request_sync('workspace/executeCommand', { command = 'vscode.java.startDebugSession' })
  if res == nil or res.err ~= nil then
    return
  end
  local port = res.result
  callback { type = 'server', host = '127.0.0.1', port = port }
end

---@diagnostic disable-next-line: missing-fields
dapui.setup {
  icons = { expanded = '▾', collapsed = '▸', current_frame = '*' },
  ---@diagnostic disable-next-line: missing-fields
  controls = {
    icons = {
      pause = '⏸',
      play = '▶',
      step_into = '⏎',
      step_over = '⏭',
      step_out = '⏮',
      step_back = 'b',
      run_last = '▶▶',
      terminate = '⏹',
      disconnect = '⏏',
    },
  },
}

vim.api.nvim_set_hl(0, 'DapBreak', { link = 'Error' })
vim.api.nvim_set_hl(0, 'DapStop', { link = 'WarningMsg' })
local breakpoint_icons = vim.g.have_nerd_font
    and { Breakpoint = '', BreakpointCondition = '', BreakpointRejected = '', LogPoint = '', Stopped = '' }
  or { Breakpoint = '●', BreakpointCondition = '⊜', BreakpointRejected = '⊘', LogPoint = '◆', Stopped = '⭔' }
for type, icon in pairs(breakpoint_icons) do
  local tp = 'Dap' .. type
  local hl = (type == 'Stopped') and 'DapStop' or 'DapBreak'
  vim.fn.sign_define(tp, { text = icon, texthl = hl, numhl = hl })
end

dap.listeners.after.event_initialized['dapui_config'] = dapui.open
dap.listeners.before.event_terminated['dapui_config'] = dapui.close
dap.listeners.before.event_exited['dapui_config'] = dapui.close

require('dap-go').setup {
  delve = {
    detached = vim.fn.has 'win32' == 0,
  },
}
