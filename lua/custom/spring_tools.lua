-- Configuration for spring-tools language server
local M = {}

local function find_jdtls(bufnr)
  local buf = bufnr or 0
  local clients = vim.lsp.get_clients { bufnr = buf, name = 'jdtls' }
  if #clients == 0 then
    return nil
  else
    return clients[1]
  end
end

function M.config()
  -- TODO: Maybe add it to lspconfig.config
  local capabilities = vim.lsp.protocol.make_client_capabilities()
  -- TODO: move outside, I've already been bamboozled once
  capabilities = vim.tbl_deep_extend('force', capabilities, require('blink.cmp').get_lsp_capabilities())
  capabilities = vim.tbl_deep_extend('keep', capabilities, {
    workspace = {
      executeCommand = { dynamicRegistration = true },
      didChangeWorkspaceFolders = { dynamicRegistration = true },
    },
  })
  -- Add custom springboot_ls manually since it's not in mason
  vim.lsp.config['springboot_ls'] = {
    cmd = {
      'java',
      '-Dlsp.completions.indentation.enable=true',
      '-Dlanguageserver.boot.enableJandexIndex=false',
      -- '-Dlogging.level.org.springframework.ide.vscode=debug',
      '-Xmx1024m',
      '-XX:TieredStopAtLevel=1',
      '-jar',
      vim.fn.expand '~/.local/share/lsp/spring-boot-language-server.jar',
    },
    filetypes = { 'properties', 'yaml', 'java' },
    root_markers = { 'build.gradle', 'pom.xml', '.git/' },
    settings = {},
    capabilities = capabilities,
  }
  -- vim.lsp.enable 'springboot_ls'
  -- vim.lsp.set_log_level 'debug'
end

-- create handler to map a sts request to a jdtls command
local function makeStsHandler(jdlts_command, title)
  return function(err, result, ctx)
    vim.notify('called ' .. jdlts_command, vim.log.levels.INFO)
    local clients = vim.lsp.get_clients { name = 'jdtls' }
    if #clients == 0 then
      vim.notify('No jdtls client running, sts/javadoc failed', vim.log.levels.ERROR)
      return vim.lsp.rpc.rpc_response_error(vim.lsp.protocol.ErrorCodes.InternalError)
    end
    local jdtls = clients[1]
    local co = coroutine.running()
    jdtls:exec_cmd(
      {
        title = title,
        command = jdlts_command,
        arguments = result.arguments,
      },
      ctx,
      function(err, res, _)
        coroutine.resume(co, err, res)
      end
    )
    local error, response = coroutine.yield()
    if error then
      vim.notify('error: ' .. vim.inspect(error), vim.log.levels.ERROR)
      return error
    end
    return response
  end
end

--I'm sure half of this could be on general lsp config and not on attach
function M.on_attach(event)
  local client = vim.lsp.get_client_by_id(event.data.client_id)
  if not client or (client.name ~= 'springboot_ls' and client.name ~= 'jdtls') then
    return
  end
  -- TODO:: Passing a {handlers} parameter to |vim.lsp.start()|. This sets the default
  --  |lsp-handler| for a specific server. (Note: only for server-to-client
  --  requests/notifications, not client-to-server.)
  client.handlers['sts/addClasspathListener'] = function(err, result, ctx)
    vim.notify(client.name .. ' sts/addClasspathListener', vim.log.levels.INFO, {})
    local clients = vim.lsp.get_clients {
      --bufnr = ctx.bufnr,
      name = 'jdtls',
    }
    if #clients == 0 then
      vim.notify('No active jdtls client found, sts needs one running', vim.log.levels.ERROR, {})
      return vim.lsp.rpc.rpc_response_error(vim.lsp.protocol.ErrorCodes.InternalError)
    else
      local jdtls_client = clients[1]
      jdtls_client:request('workspace/executeCommand', {
        command = 'sts.java.addClasspathListener',
        arguments = { result.callbackCommandId },
      }, function(err, result, ctx)
        vim.notify('addClasspathListener result: ' .. vim.inspect(result), vim.log.levels.INFO)
      end, ctx.bufnr)
    end

    return { success = true }
  end
  client.handlers['sts/removeClasspathListener'] = function(err, result, ctx)
    --vim.notify('Received sts/removeClasspathListener Command', vim.log.levels.INFO, {})
    local clients = vim.lsp.get_clients { bufnr = ctx.bufnr, name = 'jdtls' }
    if #clients == 0 then
      vim.notify('No active jdtls client found, sts needs one running', vim.log.levels.ERROR, {})
      return vim.lsp.rpc.rpc_response_error(vim.lsp.protocol.ErrorCodes.InternalError)
    else
      local jdtls_client = clients[1]
      jdtls_client:request('workspace/executeCommand', {
        command = 'sts.java.removeClasspathListener',
        arguments = { result.callbackCommandId },
      }, function(err, result, ctx) end, ctx.bufnr)
    end
    return { success = true }
  end
  -- Tries to match command to known commands and if it misses sends it to the other client
  -- NOTE: can I make it better in the future??
  client.handlers['workspace/executeClientCommand'] = function(err, result, ctx)
    vim.notify(client.name .. ' client asks for a client command ' .. vim.inspect(result.command), vim.log.levels.DEBUG, {})
    -- get all clients for this buffer
    --TODO: move this to commands I guess (or add a new client_commands?)
    if result.command == 'vscode-spring-boot.ls.start' then
      vim.lsp.enable 'springboot_ls'
      local spls_id = vim.lsp.start(vim.lsp.config['springboot_ls'], {
        bufnr = event.buf,
        reuse_client = vim.lsp.config['springboot_ls'].reuse_client,
        _root_markers = vim.lsp.config['springboot_ls'].root_markers,
      })
      if not spls_id then
        return vim.lsp.rpc.rpc_response_error(vim.lsp.protocol.ErrorCodes.InternalError)
      else
        local spls = vim.lsp.get_client_by_id(spls_id)
        if spls == nil then
          return vim.lsp.rpc.rpc_response_error(vim.lsp.protocol.ErrorCodes.InternalError)
        end
        -- force start classpath listening
        spls:request('workspace/executeCommand', {
          title = 'EnableClasspathListening',
          command = 'sts.vscode-spring-boot.enableClasspathListening',
          arguments = { 'true' },
        }, function(err, _, _)
          if err ~= nil then
            vim.notify('could not enable classpath listening: ' .. err.message, vim.log.levels.ERROR)
          end
        end, ctx.bufnr)
        return { result = { success = true } }
      end
    end
    local client_command_fn = (client.commands and client.commands[result.command]) or (vim.lsp.commands and vim.lsp.commands[result.command])
    if client_command_fn then
      local ok, client_command_result = pcall(client_command_fn, result, ctx)
      if ok then
        return client_command_result
      else
        return vim.lsp.rpc.rpc_response_error(vim.lsp.protocol.ErrorCodes.InternalError, client_command_result)
      end
    end
    local clients = vim.lsp.get_clients { bufnr = ctx.bufnr }
    if #clients < 2 then
      vim.notify('no other clients to send the command', vim.log.levels.ERROR)
      return vim.lsp.rpc.rpc_response_error(vim.lsp.protocol.ErrorCodes.InternalError)
    end
    local co = coroutine.running()
    for _, ac_client in ipairs(clients) do
      -- only register this back and forth for jdtls and springboot_ls
      -- again, maybe in lsp.config in the future?? Or is it only for lsp.start
      if client.id ~= ac_client.id and (ac_client.name == 'springboot_ls' or ac_client.name == 'jdtls') then
        -- seems I cannot use exec_cmd because of not very dynamic registration of execute commands
        --ac_client:exec_cmd(result, ctx, function(err, result, ctx)
        ac_client:request('workspace/executeCommand', result, function(err, result, ctx)
          coroutine.resume(co, err, result)
        end, ctx.bufnr)
        break
      end
    end

    -- blocks the current coroutine to wait for the exec_cmd result
    local error, response = coroutine.yield()
    if error then
      vim.notify('error: ' .. vim.inspect(error), vim.log.levels.ERROR)
      return error
    end
    vim.notify('[' .. client.name .. '/' .. result.command .. '] -> ' .. vim.inspect(response), vim.log.levels.INFO)
    return response
  end

  -- weird handlers required in https://github.com/spring-projects/spring-tools/wiki/Developer-Manual-Java-Messages
  client.handlers['sts/javaType'] = makeStsHandler('sts.java.type', 'sts.java.type')
  client.handlers['sts/javadocHoverLink'] = makeStsHandler('sts.java.javadocHoverLink', 'sts.java.javadocHoverLink')
  client.handlers['sts/javaLocation'] = makeStsHandler('sts.java.location', 'sts.java.location')
  client.handlers['sts/javadoc'] = makeStsHandler('sts.java.javadoc', 'sts.java.javadoc')
  client.handlers['sts/javaSearchTypes'] = makeStsHandler('sts.java.search.types', 'sts.java.search.types')
  client.handlers['sts/javaSearchPackages'] = makeStsHandler('sts.java.search.packages', 'sts.java.search.packages')
  client.handlers['sts/javaSubTypes'] = makeStsHandler('sts.java.hierarchy.subtypes', 'sts.java.hierarchy.subtypes')
  client.handlers['sts/javaSuperTypes'] = makeStsHandler('sts.java.hierarchy.supertypes', 'sts.java.hierarchy.supertypes')
  client.handlers['sts/javaCodeComplete'] = makeStsHandler('sts.java.code.completions', 'sts.java.code.completions')
  client.handlers['sts/project/gav'] = makeStsHandler('sts.project.gav', 'sts.project.gav')

  -- custom spring commands!
  vim.api.nvim_buf_create_user_command(0, 'SpringUgradeSpringBoot', function(args)
    local version = args.fargs[1]
    local jdtls = find_jdtls()
    if not jdtls then
      return
    end
    client:exec_cmd({ command = 'sts/upgrade/spring-boot', arguments = { vim.uri_from_fname(jdtls.root_dir), version, true } }, {}, function(err, res, ctx)
      if err then
        vim.notify('Could not upgrade spring boot to version: ' .. version .. ' ' .. err.message, vim.log.levels.ERROR, {})
      else
        vim.notify('Successfully upgraded spring boot to ' .. version, vim.log.levels.INFO, {})
      end
    end)
  end, { nargs = 1 })
end

return M
