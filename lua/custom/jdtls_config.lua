-- FIXME: Turns out a client:request_sync exists ... :/
-- so I think some of this code could be semplified/fixed

-- Logic for setting up jdtls
local M = {}
local ui = require 'custom/ui'

-- Load configuration for java language server jdtls
function M.config()
  -- jdtls workspace resolution
  local project_name = vim.fn.fnamemodify(vim.fn.getcwd(), ':p:h:t')
  local project_parent = vim.fn.fnamemodify(vim.fn.getcwd(), ':~:h:t')

  local jdtls_workspace_dir = vim.fn.expand '$HOME/.cache/jdtls/workspace/' .. project_parent .. '/' .. project_name
  local mason_share = vim.fn.expand '$MASON/share'
  local spring_share = vim.fn.expand '$HOME/.local/share/spring/jdtls-extensions/'
  -- local java_test_plugins = vim.fn.glob(mason_share .. '/java-test/*.jar', true, true)
  local test_bundle_names = {
    'org.eclipse.jdt.junit4.runtime_',
    'org.eclipse.jdt.junit5.runtime_',
    'junit-jupiter-api',
    'junit-jupiter-engine',
    'junit-jupiter-migrationsupport',
    'junit-jupiter-params',
    'junit-vintage-engine',
    'org.opentest4j',
    'junit-platform-commons',
    'junit-platform-engine',
    'junit-platform-launcher',
    'junit-platform-runner',
    'junit-platform-suite-api',
    'junit-platform-suite-commons',
    'junit-platform-suite-engine',
    'org.apiguardian.api',
    'org.jacoco.core',
  }
  local java_test_plugins = vim.tbl_map(function(test_bundle_name)
    --only return a string, hopefully we're only matching one file
    vim.fn.glob(mason_share .. '/java-test/' .. test_bundle_name .. '*.jar', true, false)
  end, test_bundle_names)
  local java_debug_bundles = vim.fn.glob(mason_share .. '/java-debug-adapter/*.jar', true, true)
  local spring_tools_bundles = vim.fn.glob(spring_share .. '*.jar', true, true)
  local jdtls_bundles = {}
  table.move(java_debug_bundles, 1, #java_debug_bundles, #jdtls_bundles + 1, jdtls_bundles)
  table.move(java_test_plugins, 1, #java_test_plugins, #jdtls_bundles + 1, jdtls_bundles)
  table.move(spring_tools_bundles, 1, #spring_tools_bundles, #jdtls_bundles + 1, jdtls_bundles)

  --capabilities ..?
  local capabilities = vim.lsp.protocol.make_client_capabilities()
  capabilities = vim.tbl_deep_extend('force', capabilities, require('blink.cmp').get_lsp_capabilities())
  capabilities = vim.tbl_deep_extend('force', capabilities, {
    workspace = {
      symbol = { dynamicRegistration = true },
      didChangeWorkspaceFolders = { dynamicRegistration = true },
    },
  })
  return {
    filetypes = { 'java', 'yaml', 'properties' },
    cmd = {
      'jdtls',
      '-Xmx1G',
      -- '-XX:+UseG1GC',
      '-XX:+UseZGC',
      '-XX:+ZGenerational',
      '-XX:+UseStringDeduplication',
      '-configuration',
      vim.fn.expand '$HOME/.cache/jdtls/config',
      '-data',
      jdtls_workspace_dir,
      '--jvm-arg=-Declipse.application=org.eclipse.jdt.ls.core.id1',
      '--jvm-arg=-Dosgi.bundles.defaultStartLevel=4',
      '--jvm-arg=-Declipse.product=org.eclipse.jdt.ls.core.product',
      '--jvm-arg=-Djava.import.generatesMetadataFilesAtProjectRoot=false',
      '--jvm-arg=-javaagent:' .. vim.fn.stdpath 'data' .. '/mason/share/jdtls/lombok.jar',
      --'--jvm-arg=-javaagent:' .. vim.fn.stdpath 'data' .. '/mason/share/java-test/jacocoagent.jar',
      '--add-opens',
      'java.base/java.util=ALL-UNNAMED',
      '--add-opens',
      'java.base/java.lang=ALL-UNNAMED',
      '--add-modules',
      'ALL-SYSTEM',
      '--add-exports',
      'jdk.compiler/com.sun.tools.javac.processing=ALL-UNNAMED',
      '--Amapstruct.verbose=true',
    },
    capabilities = capabilities,
    init_options = {
      bundles = jdtls_bundles,
      extendedClientCapabilities = {
        advancedExtractRefactoringSupport = false,
        advancedOrganizeImportsSupport = true,
        executeClientCommandSupport = true,
        generateToStringPromptSupport = true,
        generateConstructorsPromptSupport = true,
        generateDelegateMethodsPromptSupport = true,
        overrideMethodsPromptSupport = true,
      },
      settings = {
        java = {
          home = '/opt/homebrew/Cellar/openjdk/23.0.2/libexec/openjdk.jdk/Contents/Home',
          inlayHints = { uparameterNames = { enabled = 'literals' } },
          maven = { downloadSources = true },
          eclipse = { downloadSources = true },
          references = { includeDecompiledSources = true },
          saveActions = { organizeImports = true },
          contentProvider = {
            preferred = 'fernflowerContentProvider',
          },
          signatureHelp = {
            enabled = true,
          },
          referencesCodeLens = {
            enabled = true,
          },
          import = {
            gradle = { enabled = true, annotationProcessing = { enabled = true } },
            maven = { enabled = true },
          },
          implementationsCodeLens = {
            enabled = true,
          },
          jdt = {
            ls = {
              lombokSupport = {
                enabled = true,
              },
            },
          },
          exclusions = {
            '**/node_modules/**',
            '**/.metadata/**',
            '**/archetype-resources/**',
            '**/META-INF/maven/**',
            '/**/test/**',
          },
          codeGeneration = {
            toString = {},
          },
          -- import order options
          completion = {
            importOrder = {
              'static',
              'de.c24',
              'de.check24',
              '',
              'java',
              'javax',
            },
            favoriteStaticMembers = {
              -- 'org.junit.Assume.*',
              -- 'org.junit.jupiter.api.Assertions.*',
              -- 'org.junit.jupiter.api.Assumptions.*',
              -- 'org.junit.jupiter.api.DynamicContainer.*',
              -- 'org.junit.jupiter.api.DynamicTest.*',
              'org.assertj.core.api.Assertions.*',
              'org.assertj.core.api.Assertions.*',
              'org.mockito.Mockito.*',
            },
          },
          configuration = {
            updateBuildConfiguration = 'automatic',
          },
          autobuild = { enabled = false },
          -- C24 formatting options
          -- TODO:  add null-ls or something to integrate checkstyle
          format = {
            enabled = true,
            settings = {
              url = vim.fn.expand 'file://$HOME/c24_javastyle.xml',
              profile = 'c24-javastyle',
            },
          },
        },
      },
    },
  }
end

-- :shrug:
function M.on_attach(event)
  local client = vim.lsp.get_client_by_id(event.data.client_id)
  if client == nil or client.name ~= 'jdtls' then
    return
  end
  client.commands['java.action.generateToStringPrompt'] = function(cmd, ctx)
    local params = ctx.params
    local bufnr = ctx.bufnr

    client:request('java/checkToStringStatus', params, function(err, res, ctx)
      if err ~= nil then
        vim.notify(err.message, vim.log.levels.ERROR)
        return
      end
      if not res then
        return
      end
      -- toString exists already, I could prompt but I don't think it's necessary
      if res.exists then
        vim.notify('ToString already exists', vim.log.levels.ERROR)
        return
      end
      ui.select(
        {
          prompt = 'To String',
          index_map = function(v)
            return v.name
          end,
          custom_virt = function(v)
            return { { v.isField and 'field' or '', 'Comment' } }
          end,
        },
        res.fields,
        function(selected_fields)
          client:request('java/generateToString', { context = params, fields = selected_fields }, function(err, res, ctx)
            if err == nil and res ~= nil then
              vim.lsp.util.apply_workspace_edit(res, 'utf-16')
            end
          end, bufnr)
        end
      )
    end, bufnr)
  end
  -- For now we just register this fakeass command
  vim.api.nvim_buf_create_user_command(event.buf, 'JavaIsTestFile', function()
    client:exec_cmd({
      command = 'java.project.isTestFile',
      arguments = { vim.uri_from_bufnr(event.buf) },
    }, {
      bufnr = event.buf,
    }, function(err, result)
      if err then
        vim.notify('Error while executing JavaIsTestFile: ' .. err.message, vim.log.levels.ERROR, {})
        return
      elseif result ~= nil then
        if result then
          vim.notify '✅ This is a test file.'
        else
          vim.notify '❌ This is NOT a test file.'
        end
      else
        vim.notify '⚠️ No result returned.'
      end
    end)
  end, {})
  -- TODO: bello ma non proprio un prompt per ora
  client.commands['java.action.generateConstructorsPrompt'] = function(cmd, ctx)
    local bufnr = ctx.bufnr
    local params = cmd.arguments[1] --[[@as table]]
    client:request('java/checkConstructorsStatus', params, function(err, res, ctx)
      if err then
        vim.notify(err.message, vim.log.levels.ERROR)
        return
      end
      ui.select(
        {
          prompt = 'Constructors fields',
          index_map = function(v)
            return v.name
          end,
        },
        res.fields,
        function(selected)
          client:request('java/generateConstructors', {
            context = params,
            constructors = res.constructors,
            fields = selected,
          }, function(err, res, ctx)
            if not err and res ~= nil then
              vim.lsp.util.apply_workspace_edit(res, 'utf-16')
            end
          end, bufnr)
        end
      )
    end, bufnr)
  end
  client.commands['java.action.generateDelegateMethodsPrompt'] = function(cmd, ctx)
    local bufnr = ctx.bufnr
    local params = cmd.arguments[1] --[[@as table]]
    client:request('java/checkDelegateMethodsStatus', params, function(err, res, ctx)
      if err then
        vim.notify(err.message, vim.log.levels.ERROR)
        return
      end
      ui.select(
        {
          prompt = 'Select fields to delegate',
          index_map = function(v)
            return v.field.name
          end,
        },
        res.delegateFields,
        function(selected)
          if not selected then
            return
          end
          local delegate_entries = {}
          for _, delegate_field in ipairs(selected) do
            for _, delegate_method in ipairs(delegate_field.delegateMethods) do
              table.insert(delegate_entries, { field = delegate_field.field, delegateMethod = delegate_method })
            end
          end
          ui.select(
            {
              prompt = cmd.title,
              index_map = function(entry)
                return entry.field.name .. '.' .. entry.delegateMethod.name
              end,
              custom_virt = function(entry)
                local res = {}
                local list = entry.delegateMethod.parameters
                for idx, param in ipairs(list) do
                  table.insert(res, { param .. (idx == #list and '' or ','), 'Comment' })
                end
                return res
              end,
            },
            delegate_entries,
            function(selected_entries)
              client:request('java/generateDelegateMethods', {
                context = params,
                delegateEntries = selected_entries,
              }, function(err, res, ctx)
                if not err and res ~= nil then
                  vim.lsp.util.apply_workspace_edit(res, 'utf-16')
                end
              end, bufnr)
            end
          )
        end
      )
    end, bufnr)
  end
  -- NOTE: for some reason this is not a executeCommand but an executeClientCommand :/
  client.commands['_java.reloadBundles.command'] = function(cmd, ctx)
    ---@diagnostic disable-next-line: redundant-return-value
    return {}
  end
  -- NOTE: for some reason this is not a executeCommand but an executeClientCommand :/
  client.commands['java.action.organizeImports.chooseImports'] = function(cmd, ctx)
    local file = cmd.arguments[1] --[[@as string]]
    local import_selections = cmd.arguments[2] --[[@as table[]]
    local co = coroutine.running()
    -- TODO: for now I'm picking one at a time but my goal would be to
    -- have a ui.select_by or similar that groups them and lets me
    -- select only one out of a group
    -- Only thing is that being able to search fast for the imports is really good
    local result = {}
    for _, import_selection in ipairs(import_selections) do
      vim.ui.select(import_selection.candidates, {
        prompt = 'Select import',
        format_item = function(item)
          return item.fullyQualifiedName
        end,
      }, function(choice)
        coroutine.resume(co, choice)
      end)
      local selection_result = coroutine.yield(co)
      table.insert(result, selection_result)
    end
    ---@diagnostic disable-next-line: redundant-return-value
    return result
  end
  client.commands['java.action.applyRefactoringCommand'] = function(cmd, ctx)
    local bufnr = ctx.bufnr
    local params = ctx.params
    local refactoring_command = cmd.arguments[0] --[[@as string]]
    client:request('java/getRefactorEdit', {
      command = cmd.arguments[1],
      context = params,
      options = {
        tabSize = vim.lsp.util.get_effective_tabstop(ctx.bufnr),
        insertSpaces = vim.bo.expandtab,
      },
    }, function(err, res, ctx)
      if not err and res then
        vim.lsp.util.apply_workspace_edit(res, 'utf-16')
      end
    end, bufnr)
  end
  client.commands['java.action.overrideMethodsPrompt'] = function(cmd, ctx)
    local bufnr = ctx.bufnr
    local params = ctx.params
    client:request('java/listOverridableMethods', params, function(err, res, ctx)
      ui.select(
        {
          prompt = 'Add overrides for ' .. res.type,
          index_map = function(o_method)
            local arg_string = ''
            for idx, arg in ipairs(o_method.parameters) do
              arg_string = arg_string .. arg .. (idx ~= #o_method.parameters and ', ' or '')
            end
            return o_method.name .. '(' .. arg_string .. ')'
          end,
          custom_virt = function(o_method)
            return { { o_method.declaringClass, 'Comment' } }
          end,
        },
        res.methods,
        function(selected_methods)
          client:request('java/addOverridableMethods', { context = params, overridableMethods = selected_methods }, function(err, res, ctx)
            if res and not err then
              vim.lsp.util.apply_workspace_edit(res, 'utf-16')
            end
          end, bufnr)
        end
      )
    end, bufnr)
  end
  vim.api.nvim_buf_create_user_command(event.buf, 'JavaJumpToMain', function()
    client:exec_cmd({
      command = 'vscode.java.resolveMainClass',
      arguments = {},
    }, {
      bufnr = event.buf,
    }, function(err, result)
      if err then
        vim.notify('Error while executing JavaJumpToMain: ' .. err.message, vim.log.levels.ERROR, {})
        return
      elseif result ~= nil and #result > 0 then
        -- TODO: handle multiple results ...?
        vim.cmd('edit ' .. vim.fn.fnameescape(result[1].filePath))
      else
        vim.notify '⚠️ No result returned.'
      end
    end)
  end, {})
  -- NOTE: I don't love this here but let's see

  -- TODO: I think this should be removed
  -- check if springboot_lsp is up
  local clients = vim.lsp.get_clients { name = 'springboot_ls' }
  if #clients > 0 then
    return
  end
  -- if no springboot_ls client has been found register it
  vim.lsp.enable 'springboot_ls'
  vim.lsp.start(vim.lsp.config['springboot_ls'], {
    bufnr = event.buf,
    reuse_client = vim.lsp.config['springboot_ls'].reuse_client,
    _root_markers = vim.lsp.config['springboot_ls'].root_markers,
  })
end

return M
