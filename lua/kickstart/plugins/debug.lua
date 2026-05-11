-- debug.lua
--
-- Lazy-loaded DAP setup.
--
-- Following the vim.pack lazy-loading guidance from
-- https://echasnovski.com/blog/2026-03-13-a-guide-to-vim-pack#lazy-loading,
-- triggers are simple autocommands rather than keymap callbacks:
--   - FileType java|go  -> install plugins + general DAP infra (setup_once)
--   - LspAttach (jdtls) -> wire dap.configurations.java + dap.adapters.java

local did_setup = false
local function setup_once()
  if did_setup then return end
  did_setup = true

  vim.pack.add {
    'https://github.com/mfussenegger/nvim-dap',
    'https://github.com/rcarriga/nvim-dap-ui',
    'https://github.com/nvim-neotest/nvim-nio',
    'https://github.com/jay-babu/mason-nvim-dap.nvim',
    'https://github.com/leoluz/nvim-dap-go',
  }

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
            vim.fn.stdpath 'data' .. '/mason/share/java-debug-adapter/com.microsoft.java.debug.plugin.jar',
          },
        }
        require('mason-nvim-dap').default_setup(config)
      end,
    },
    ensure_installed = { 'delve', 'javadbg', 'javatest' },
  }

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
    delve = { detached = vim.fn.has 'win32' == 0 },
  }

  vim.keymap.set('n', '<F5>', function() dap.continue() end, { desc = 'Debug: Start/Continue' })
  vim.keymap.set('n', '<F1>', function() dap.step_into() end, { desc = 'Debug: Step Into' })
  vim.keymap.set('n', '<F2>', function() dap.step_over() end, { desc = 'Debug: Step Over' })
  vim.keymap.set('n', '<F3>', function() dap.step_out() end, { desc = 'Debug: Step Out' })
  vim.keymap.set('n', '<leader>b', function() dap.toggle_breakpoint() end, { desc = 'Debug: Toggle Breakpoint' })
  vim.keymap.set('n', '<leader>B', function() dap.set_breakpoint(vim.fn.input 'Breakpoint condition: ') end, { desc = 'Debug: Set Breakpoint' })
  vim.keymap.set('n', '<F7>', function() dapui.toggle() end, { desc = 'Debug: See last session result.' })
end

local did_java_setup = false
local function setup_java_once()
  if did_java_setup then return end

  local dap = require 'dap'
  local jdtls = require 'custom.jdtls.utils'
  local j_client = jdtls.get_client_opt()
  if not j_client then return end

  -- jdtls may have attached but not finished indexing the project yet — in that
  -- case resolve_main_classes asserts. Don't latch unless the call succeeds.
  local ok, main_classes = pcall(function() return j_client:resolve_main_classes() end)
  if not ok or not main_classes or #main_classes == 0 then return end

  did_java_setup = true

  local repl = require 'dap.repl'
  repl.commands = vim.tbl_extend('force', repl.commands, {
    custom_commands = {
      ['.json'] = function(text)
        repl.execute(string.format('new com.fasterxml.jackson.databind.ObjectMapper().writeValueAsString(%s) ', text))
      end,
    },
  })

  dap.configurations.java = {}
  for _, mc in ipairs(main_classes) do
    table.insert(
      dap.configurations.java,
      setmetatable({
        type = 'java',
        request = 'launch',
        name = 'Debug - ' .. mc.project_name,
      }, {
        __call = function()
          local c = jdtls.get_client()
          c:build_workspace_sync()
          local ws = c._client.workspace_folders and c._client.workspace_folders[1].name or nil
          return {
            type = 'java',
            request = 'launch',
            name = 'Debug - ' .. mc.project_name,
            mainClass = mc.main_class,
            projectName = mc.project_name,
            classPaths = c:resolve_java_classpath(mc)[2],
            args = '--spring.profiles.active=billow,local',
            javaExec = c:resolve_java_executable(mc),
            cwd = ws,
          }
        end,
      })
    )
    table.insert(dap.configurations.java, {
      type = 'java',
      request = 'attach',
      name = 'Debug - Attach ' .. mc.project_name,
      hostName = '127.0.0.1',
      port = 5005,
      projectName = mc.project_name,
    })
  end

  dap.adapters.java = function(callback)
    local res = jdtls.get_client()._client:request_sync('workspace/executeCommand', { command = 'vscode.java.startDebugSession' })
    if res == nil or res.err ~= nil then return end
    callback { type = 'server', host = '127.0.0.1', port = res.result }
  end
end

vim.api.nvim_create_autocmd('FileType', {
  group = vim.api.nvim_create_augroup('kickstart-dap-bootstrap', { clear = true }),
  pattern = { 'java', 'go' },
  once = true,
  callback = setup_once,
})

vim.api.nvim_create_autocmd('LspAttach', {
  group = vim.api.nvim_create_augroup('kickstart-dap-jdtls', { clear = true }),
  pattern = '*.java', -- only consider LSPs attaching to a java buffer
  callback = function(ev)
    local client = vim.lsp.get_client_by_id(ev.data.client_id)
    if not client or client.name ~= 'jdtls' then return end -- silent no-op; let the autocmd persist for the real jdtls attach
    setup_once()

    -- jdtls may already be done indexing (rare but possible); try eagerly.
    setup_java_once()
    if did_java_setup then return true end

    -- Otherwise wait for jdtls to send `language/status` with ServiceReady.
    local prev = client.handlers['language/status']
    client.handlers['language/status'] = function(err, result, ctx, cfg)
      if result and (result.type == 'ServiceReady' or result.type == 'Started') then
        setup_java_once()
      end
      if prev then return prev(err, result, ctx, cfg) end
    end
    return true -- self-delete the autocmd; the status handler now owns the trigger
  end,
})

