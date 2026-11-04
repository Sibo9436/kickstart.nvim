-- debug.lua
--
-- Lazy-loaded DAP setup.
--
-- Following the vim.pack lazy-loading guidance from
-- https://echasnovski.com/blog/2026-03-13-a-guide-to-vim-pack#lazy-loading,
-- the trigger is a single autocommand: FileType java|go installs the plugins
-- and wires up the general DAP infra (setup_once).
--
-- The java configurations are NOT built at attach time. They come from a
-- nvim-dap config provider (:h dap-providers-configs) which only runs when a
-- session is actually started, so jdtls is guaranteed to be loaded by then and
-- the main class list is never stale.

-- Extra runtime args handed to every launch configuration.
local JAVA_LAUNCH_ARGS = '--spring.profiles.active=billow,local'
-- Attach configs assume the JVM was started with
-- `-agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=*:<port>`.
local JAVA_ATTACH_PORT = 5005
-- resolveMainClass is answered instantly by a warm jdtls; the longer timeout is
-- only so a busy (still importing) server gets a fair chance to answer.
local RESOLVE_MAIN_CLASS_TIMEOUT_MS = 5000

--- Wires the java bits into nvim-dap.
---
--- Nothing here talks to jdtls at registration time: the adapter, the config
--- provider and each configuration's `__call` hook all run only once a debug
--- session is started. That is what guarantees jdtls is fully loaded before we
--- ask it for main classes, classpaths or a debug server — no polling, no
--- one-shot latch, and the configurations are recomputed on every `continue()`
--- so they always match the project you are currently in.
local function setup_java(dap)
  local jdtls = require 'custom.jdtls.utils'
  local repl = require 'dap.repl'

  repl.commands = vim.tbl_extend('force', repl.commands, {
    custom_commands = {
      ['.json'] = function(text) repl.execute(string.format('new com.fasterxml.jackson.databind.ObjectMapper().writeValueAsString(%s) ', text)) end,
    },
  })

  --- jdtls of the current buffer, falling back to any jdtls in the session
  --- (the debug UI may already have moved the cursor off the java buffer).
  ---@return JdtlsClient|nil
  local function client_for(bufnr) return jdtls.get_client_opt(bufnr) or jdtls.get_client_opt() end

  dap.adapters.java = function(callback)
    local client = client_for(0)
    if not client then
      vim.notify('No jdtls client attached — cannot start a java debug session', vim.log.levels.ERROR)
      return
    end
    local port = client:start_debug_session() -- notifies on failure
    if not port then return end
    callback { type = 'server', host = '127.0.0.1', port = port }
  end

  --- nvim-dap invokes a configuration's `__call` metamethod right before running
  --- it (:h dap-configuration), so the workspace build and classpath resolution
  --- only happen for the configuration you actually picked.
  ---@param mc {main_class: string, project_name: string}
  local function launch_config(mc)
    return setmetatable({ type = 'java', request = 'launch', name = 'Debug - ' .. mc.project_name }, {
      __call = function(self)
        local client = client_for(0)
        if not client then
          vim.notify('jdtls detached — cannot resolve the classpath', vim.log.levels.ERROR)
          return { type = 'java', request = 'launch', name = self.name, mainClass = dap.ABORT }
        end
        client:build_workspace_sync(mc)
        return {
          type = 'java',
          request = 'launch',
          name = self.name,
          mainClass = mc.main_class,
          projectName = mc.project_name,
          classPaths = client:resolve_java_classpath(mc)[2],
          javaExec = client:resolve_java_executable(mc),
          args = JAVA_LAUNCH_ARGS,
          cwd = client:workspace_dir(),
        }
      end,
    })
  end

  ---@param project_name string
  local function attach_config(project_name)
    return {
      type = 'java',
      request = 'attach',
      name = 'Debug - Attach ' .. project_name,
      hostName = '127.0.0.1',
      port = JAVA_ATTACH_PORT,
      projectName = project_name,
    }
  end

  dap.providers.configs['jdtls'] = function(bufnr)
    if (vim.b[bufnr]['dap-srcft'] or vim.bo[bufnr].filetype) ~= 'java' then return {} end
    local client = client_for(bufnr)
    if not client then
      vim.notify('No jdtls client attached to this buffer', vim.log.levels.WARN)
      return {}
    end

    local configs, projects = {}, {}
    local main_classes = client:resolve_main_classes_opt(RESOLVE_MAIN_CLASS_TIMEOUT_MS)
    if not main_classes then
      vim.notify('jdtls reported no main class — it may still be importing the project', vim.log.levels.WARN)
      main_classes = {}
    end
    for _, mc in ipairs(main_classes) do
      table.insert(configs, launch_config(mc))
      if not projects[mc.project_name] then
        projects[mc.project_name] = true
        table.insert(configs, attach_config(mc.project_name))
      end
    end
    -- Attaching needs no main class, so offer it even where jdtls found none
    -- (libraries, test-only modules, or a project that is still importing).
    if not next(projects) then table.insert(configs, attach_config(vim.fs.basename(client:workspace_dir() or vim.fn.getcwd()))) end
    return configs
  end

  -- Escape hatch: ask the provider what it would offer *right now*, without
  -- starting a session. If jdtls was still importing the first time around,
  -- just run this (or hit <F5>) again — nothing is cached.
  vim.api.nvim_create_user_command('JavaDapConfigs', function()
    local configs = dap.providers.configs['jdtls'](vim.api.nvim_get_current_buf())
    if #configs == 0 then return end -- the provider already said why
    local names = vim.tbl_map(function(config) return '• ' .. config.name end, configs)
    vim.notify(table.concat(names, '\n'), vim.log.levels.INFO)
  end, { desc = 'List the java debug configurations jdtls currently offers' })
end

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

  -- javadbg/javatest are here only so mason installs the jars; they are jdtls
  -- OSGi bundles (loaded via init_options.bundles in custom.jdtls_config), not
  -- standalone adapters, so they get no handler — dap.adapters.java below asks
  -- jdtls itself to start the debug server.
  require('mason-nvim-dap').setup {
    automatic_installation = true,
    handlers = {
      function(config) require('mason-nvim-dap').default_setup(config) end,
      javadbg = function() end,
      javatest = function() end,
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
  local breakpoint_icons = vim.g.have_nerd_font and { Breakpoint = '', BreakpointCondition = '', BreakpointRejected = '', LogPoint = '', Stopped = '' }
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

  setup_java(dap)
end

vim.api.nvim_create_autocmd('FileType', {
  group = vim.api.nvim_create_augroup('kickstart-dap-bootstrap', { clear = true }),
  pattern = { 'java', 'go' },
  once = true,
  callback = setup_once,
})

