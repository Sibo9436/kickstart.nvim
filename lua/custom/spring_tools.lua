-- Configuration for spring-tools language server
local M = {}

function M.config()
  -- TODO: Maybe add it to lspconfig.config
  local capabilities = vim.lsp.protocol.make_client_capabilities()
  capabilities = vim.tbl_deep_extend('force', capabilities, require('blink.cmp').get_lsp_capabilities())
  capabilities = vim.tbl_deep_extend('keep', capabilities, { workspace = { executeCommand = { dynamicRegistration = true } } })
  -- Add custom springboot_ls manually since it's not in mason
  vim.lsp.config['springboot_ls'] = {
    cmd = {
      'java',
      '-Dlsp.completions.indentation.enable=true',
      '-Xmx1024m',
      '-XX:TieredStopAtLevel=1',
      '-jar',
      vim.fn.expand '~/.local/share/lsp/spring-boot-language-server.jar',
    },
    filetypes = { 'properties', 'yaml', 'java' }, -- optionally add 'java' if you want it in Java files too
    root_markers = { 'gradle.build', 'pom.xml', '.git/' },
    settings = {},
    capabilities = capabilities,
  }
  --vim.lsp.set_log_level 'debug'
end

function M.on_attach(event)
  local client = vim.lsp.get_client_by_id(event.data.client_id)
  if not client or (client.name ~= 'springboot_ls' and client.name ~= 'jdtls') then
    return
  end
  -- TODO:: Passing a {handlers} parameter to |vim.lsp.start()|. This sets the default
  --  |lsp-handler| for a specific server. (Note: only for server-to-client
  --  requests/notifications, not client-to-server.)
  client.handlers['sts/addClasspathListener'] = function(err, result, ctx)
    --vim.notify('Received sts/addClasspathListener Command' .. vim.inspect(result), vim.log.levels.INFO, {})
    local clients = vim.lsp.get_clients { bufnr = ctx.bufnr, name = 'jdtls' }
    if #clients == 0 then
      vim.notify('No active jdtls client found, sts needs one running', vim.log.levels.ERROR, {})
      return {
        err = vim.lsp.rpc.rpc_response_error(vim.lsp.protocol.ErrorCodes.InternalError),
      }
    else
      local jdtls_client = clients[1]
      jdtls_client:request('workspace/executeCommand', {
        command = 'sts.java.addClasspathListener',
        arguments = { result.callbackCommandId },
      }, function(err, result, ctx)
        vim.notify('sent executeCommand, received' .. vim.inspect(result), vim.log.levels.INFO, {})
      end, ctx.bufnr)
      -- jdtls_client:exec_cmd({
      --   title = 'addClasspathListener',
      --   command = 'sts.java.addClasspathListener',
      --   arguments = { result.callbackCommandId },
      -- }, ctx, nil)
    end

    return {
      result = { success = true },
    }
  end
  client.handlers['sts/removeClasspathListener'] = function(err, result, ctx)
    vim.notify('Received sts/removeClasspathListener Command', vim.log.levels.INFO, {})
    local clients = vim.lsp.get_clients { bufnr = ctx.bufnr, name = 'jdtls' }
    if #clients == 0 then
      vim.notify('No active jdtls client found, sts needs one running', vim.log.levels.ERROR, {})
      return {
        err = vim.lsp.rpc.rpc_response_error(vim.lsp.protocol.ErrorCodes.InternalError),
      }
    else
      local jdtls_client = clients[1]
      jdtls_client:request('workspace/executeCommand', {
        command = 'sts.java.removeClasspathListener',
        arguments = { result.callbackCommandId },
      }, function(err, result, ctx)
        vim.notify('sent executeCommand, received' .. vim.inspect(result), vim.log.levels.INFO, {})
      end, ctx.bufnr)
      -- jdtls_client:exec_cmd({
      --   title = 'removeClasspathListener',
      --   command = 'sts.java.removeClasspathListener',
      --   arguments = { result.callbackCommandId },
      -- }, ctx, nil)
    end
    return { result = { success = true } }
  end
  client.handlers['workspace/executeClientCommand'] = function(err, result, ctx)
    vim.notify('Client asks for a client Command' .. vim.inspect(result.command), vim.log.levels.DEBUG, {})
    -- get all clients for this buffer
    local clients = vim.lsp.get_clients { bufnr = ctx.bufnr }
    local co = coroutine.running()
    for _, ac_client in ipairs(clients) do
      -- only register this back and forth for jdtls and springboot_ls
      -- again, maybe in lsp.config in the future?? Or is it only for lsp.start
      if client.id ~= ac_client.id and (ac_client.name == 'springboot_ls' or ac_client.name == 'jdtls') then
        print('handling client ' .. ac_client.name .. ' for ' .. result.command)
        ac_client:exec_cmd(result, ctx, function(err, result, ctx)
          if err ~= nil then
            print('ohno' .. vim.inspect(err))
            coroutine.resume(co, {
              err = err,
            })
          else
            print('ohye' .. vim.inspect(result))
            coroutine.resume(co { result = result })
          end
        end)
        break
      end
    end

    -- blocks the current coroutine to wait for the exec_cmd result
    local ret = coroutine.yield()
    print(vim.inspect(co) .. 'resumes' .. vim.inspect(ret))
    return ret
  end
end

return M
