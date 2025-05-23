--- Utility module for jdtls integrations
local M = {}

---@class JdtlsClient  Wrapper class around jdtls lsp client
---@field _client vim.lsp.Client wrapped client
local JdtlsClient = {}

---neovim aware assert I guess
---@generic T
---@param v T
---@param message any
---@return T
local function assert(v, message)
  if not v then
    vim.notify(tostring(message), vim.log.levels.ERROR)
    error(message, 1)
  end
  return v
end

---@param client vim.lsp.Client
---@return JdtlsClient
function JdtlsClient:new(client)
  local instance = { _client = client }
  setmetatable(instance, self)
  self.__index = self
  return instance
end

---@param bufnr? integer
---@return JdtlsClient
function M.get_client(bufnr)
  local clients = nil
  if bufnr then
    clients = vim.lsp.get_clients {
      bufnr = bufnr,
      name = 'jdtls',
    }
  else
    clients = vim.lsp.get_clients {
      name = 'jdtls',
    }
  end
  assert(clients, 'No jdtls client found')
  assert(#clients > 0, 'No jdtls client found')
  return JdtlsClient:new(clients[1])
end

--- Resolves current main class and project name
---@return {main_class: string, project_name: string}
function JdtlsClient:resolve_main_class()
  local res = self._client:request_sync('workspace/executeCommand', { command = 'vscode.java.resolveMainClass', arguments = {} })
  assert(res, 'Jdtls did not respond')
  assert(res.result, res.err)
  assert(res.result[1], 'No main class found')
  return {
    main_class = res.result[1].mainClass,
    project_name = res.result[1].projectName,
  }
end

--- Resolve java classpath
---@param project? {main_class: string, project_name:string}
---@return string[][] # Array of modulepaths and classpaths
function JdtlsClient:resolve_java_classpath(project)
  local mc = project or self:resolve_main_class()
  assert(mc, 'No main class found')
  local res = self._client:request_sync('workspace/executeCommand', {
    command = 'vscode.java.resolveClasspath',
    arguments = { mc.main_class, mc.project_name },
  })
  assert(res, 'No classpath found')
  assert(res.result, res.err)
  return res.result
end

--- Sync rebuild
function JdtlsClient:build_workspace_sync()
  local mc = self:resolve_main_class()
  self._client:request_sync('workspace/executeCommand', {
    title = 'Build Workspace',
    command = 'vscode.java.buildWorkspace',
    arguments = { ('{"mainClass":"%s", "projectName":"%s"}'):format(mc.main_class, mc.project_name) },
  })
end
--- Fire and forget workspace rebuild
function JdtlsClient:build_workspace()
  local mc = self:resolve_main_class()
  self._client:exec_cmd {
    title = 'Build Workspace',
    command = 'vscode.java.buildWorkspace',
    arguments = { ('{"mainClass":"%s", "projectName":"%s"}'):format(mc.main_class, mc.project_name) },
  }
end

--- Checks wether specified file is a java test
---@param file_path string
---@return boolean
function JdtlsClient:is_test_file(file_path)
  local result, t_err = self._client:request_sync('workspace/executeCommand', {
    command = 'java.project.isTestFile',
    arguments = { vim.uri_from_fname(file_path) },
  })
  assert(not t_err, 'Request timed out')
  assert(result, 'No response given')
  assert(result.err == nil, result.err)
  return result.result
end

---@alias pos {line:integer, character:integer}
---@class JavaTestItem
---@field id string
---@field label string
---@field fullName string
---@field children JavaTestItem[]
---@field testLevel integer
---@field testKind integer
---@field projectName string
---@field uri string
---@field range  { start: pos, end:pos }
---@field jdtHandler string

--- Finds test methods in described path
---@param file_path string file in which to look for
---@return JavaTestItem[]
function JdtlsClient:find_test_methods(file_path)
  local response = self._client:request_sync('workspace/executeCommand', {
    command = 'vscode.java.test.findTestTypesAndMethods',
    arguments = { vim.uri_from_fname(file_path) },
  })
  assert(response, 'Jdtls did not respond')
  assert(response.err == nil, response.err)
  return response.result
end

--- Resolve java executable to use for project
---@param mc? {main_class:string, project_name:string}
---@return string
function JdtlsClient:resolve_java_executable(mc)
  local mclass = mc or self:resolve_main_class()
  local res = self._client:request_sync('workspace/executeCommand', {
    command = 'vscode.java.resolveJavaExecutable',
    arguments = { mclass.main_class, mclass.project_name },
  })
  assert(res, 'Jdtls did not respond')
  assert(res.err == nil, res.err)
  return res.result
end

return M
