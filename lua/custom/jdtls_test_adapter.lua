-- TODO: this needs a huge refactoring
local lib = require 'neotest.lib'
local util = require 'custom.jdtls.utils'
---@type neotest.Adapter
local M = {
  name = 'jdtls',
}

---Find the project root directory given a current directory to work from.
---Should no root be found, the adapter can still be used in a non-project context if a test file matches.
---@async
---@param dir string @Directory to treat as cwd
---@return string | nil @Absolute root dir of test suite
---@diagnostic disable-next-line: unused-local
function M.root(dir)
  return util.get_client()._client.root_dir
end

---Filter directories when searching for test files
---@async
---@param name string Name of directory
---@param rel_path string Path to directory, relative to root
---@param root string Root directory of project
---@return boolean
function M.filter_dir(name, rel_path, root)
  -- NOTE: very simple for now
  return string.find(rel_path, '/test/') ~= nil
end

---@async
---@param file_path string
---@return boolean
function M.is_test_file(file_path)
  -- cerco di ridurre il numero di chiamate al lsp
  if string.find(file_path, '.java') == nil then
    return false
  end
  return util.get_client():is_test_file(file_path)
end

--- Converts from jdtls/lsp range to neotest range
---@param range table
---@return Range4
local function convert_range(range)
  return { range.start.line, range.start.character, range['end'].line, range['end'].character }
end

-- beautiful name
--- @param test_item JavaTestItem
--- @param file_path string
--- @return neotest.Tree[]
local function convert_child(test_item, file_path)
  local nodes = {}
  if test_item.children == nil or #test_item.children == 0 then
    table.insert(nodes, {
      type = 'test',
      path = file_path,
      name = test_item.label,
      range = convert_range(test_item.range),
      custom_data = test_item,
    })
  else
    table.insert(nodes, {
      type = 'namespace',
      path = file_path,
      name = test_item.label,
      range = convert_range(test_item.range),
      custom_data = test_item,
    })
    for _, child in ipairs(test_item.children) do
      local ns = convert_child(child, file_path)
      for _, n in ipairs(ns) do
        table.insert(nodes, n)
      end
    end
  end
  return nodes
end

---Given a file path, parse all the tests within it.
---@async
---@param file_path string Absolute file path
---@return neotest.Tree | nil
function M.discover_positions(file_path)
  -- print('called discover positions with ' .. file_path)
  -- NOTE: should always only be 1 I think
  local test_files = util.get_client():find_test_methods(file_path)
  local nodes = {}
  for _, test_file in ipairs(test_files) do
    table.insert(nodes, {
      type = 'file',
      path = file_path,
      name = test_file.label,
      range = convert_range(test_file.range),
      custom_data = test_file,
    })
    for _, child in ipairs(test_file.children) do
      local test_nodes = convert_child(child, file_path)
      for _, node in ipairs(test_nodes) do
        table.insert(nodes, node)
      end
    end
  end
  -- vim.notify(vim.inspect(nodes), vim.log.levels.INFO)
  return lib.positions.parse_tree(nodes, { nested_tests = true, require_namespaces = false })
end

local function resolve_gradle_project_name(projectName)
  if #util.get_client():get_all_projects() > 1 then
    return projectName
  else
    return ''
  end
end

---@param args neotest.RunArgs
---@return nil | neotest.RunSpec | neotest.RunSpec[]
local function build_spec(args)
  local tree = args.tree
  local data = tree:data()
  if data.type == 'dir' then
    local filenames = {}
    for _, node in tree:iter_nodes() do
      if node:data().type == 'file' then
        local filename = string.gsub(node:data().name, '.java', '')
        table.insert(filenames, '--tests')
        table.insert(filenames, filename)
      end
    end
    return {
      command = {
        args.tree:root():data().path .. '/gradlew',
        data.custom_data and data.custom_data.projectName and resolve_gradle_project_name(data.custom_data.projectName) .. ':test' or 'test',
        table.unpack(filenames),
      },
      --@field env? table<string, string>
      env = {},
      cwd = vim.fn.getcwd(),
      --@field context? table Arbitrary data to preserve state between running and result collection
      context = { name = 'gradle' },
      --@field strategy? table|neotest.Strategy Arguments for strategy or override for chosen strategy
      --@field stream? fun(output_stream: fun(): string[]): fun(): table<string, neotest.Result>
    }
  end
  if data.type == 'file' then
    local classname = string.gsub(data.name, '.java', '')
    return {
      command = {
        args.tree:root():data().path .. '/gradlew',
        data.custom_data and data.custom_data.projectName and resolve_gradle_project_name(data.custom_data.projectName) .. ':test' or 'test',
        '--tests',
        classname,
      },
      --@field env? table<string, string>
      env = {},
      cwd = vim.fn.getcwd(),
      --@field context? table Arbitrary data to preserve state between running and result collection
      context = { name = 'gradle' },
      --@field strategy? table|neotest.Strategy Arguments for strategy or override for chosen strategy
      --@field stream? fun(output_stream: fun(): string[]): fun(): table<string, neotest.Result>
    }
  end
  if data.type == 'namespace' then
    local classname = data.custom_data.fullName
    return {
      command = {
        args.tree:root():data().path .. '/gradlew',
        data.custom_data and data.custom_data.projectName and resolve_gradle_project_name(data.custom_data.projectName) .. ':test' or 'test',
        '--tests',
        classname,
      },
      --@field env? table<string, string>
      env = {},
      cwd = vim.fn.getcwd(),
      --@field context? table Arbitrary data to preserve state between running and result collection
      context = { name = 'gradle' },
      --@field strategy? table|neotest.Strategy Arguments for strategy or override for chosen strategy
      --@field stream? fun(output_stream: fun(): string[]): fun(): table<string, neotest.Result>
    }
  end
  if data.type ~= 'test' then
    -- print(vim.inspect(data))
    return nil
  end
  local custom_data = data.custom_data
  local fullname, _ = string.gsub(custom_data.fullName, '#', '.')
  fullname = string.gsub(fullname, '%((.*)%)', '')

  -- print(vim.inspect(data))
  -- print(fullname)

  -- NOTE: for now I'm running one test at a time
  return {
    command = {
      args.tree:root():data().path .. '/gradlew',
      resolve_gradle_project_name(data.custom_data.projectName) .. ':test',
      '--tests',
      fullname,
    },
    --@field env? table<string, string>
    env = {},
    cwd = vim.fn.getcwd(),
    --@field context? table Arbitrary data to preserve state between running and result collection
    context = { name = 'gradle' },
    --@field strategy? table|neotest.Strategy Arguments for strategy or override for chosen strategy
    --@field stream? fun(output_stream: fun(): string[]): fun(): table<string, neotest.Result>
  }
end

---@class MessageBuffer
---@field buffer string[]
---@field is_closed boolean
local MessageBuffer = {}

function MessageBuffer:new(o)
  o = o or {
    buffer = {},
    is_closed = false,
  } -- create object if user does not provide one
  setmetatable(o, self)
  self.__index = self
  return o
end

function MessageBuffer:write(chunk)
  table.insert(self.buffer, chunk)
  -- print('DATA:', chunk)
end
function MessageBuffer:close()
  self.is_closed = true
end
function MessageBuffer:read()
  return self.buffer
end

---@param port integer port number to bind to
---@param message_buffer MessageBuffer
local function open_local_socket(port, message_buffer)
  local server = vim.uv.new_tcp()
  assert(server ~= nil, 'Could not listen on', port)
  server:bind('127.0.0.1', port)
  server:listen(128, function(err)
    assert(not err, err)
    local client = vim.uv.new_tcp()
    assert(client ~= nil)
    server:accept(client)
    client:read_start(function(err, chunk)
      assert(not err, err)
      if chunk then
        message_buffer:write(chunk)
      else
        message_buffer:close()
        client:shutdown()
        client:close()
        server:close()
      end
    end)
  end)
end

---@param args neotest.RunArgs
---@return nil | neotest.RunSpec | neotest.RunSpec[]
-- NOTE: this would be glorious
local function build_spec_dap_junit(args)
  if args.strategy ~= 'dap' then
    vim.notify('launching through java-debug only supported via dap', vim.log.levels.ERROR)
  end
  local tree = args.tree
  local data = tree:data()
  if data.type ~= 'test' then
    vim.notify('debugging ' .. data.type .. ' is still not supported', vim.log.levels.ERROR)
    return nil
  end
  -- print(vim.inspect(tree:data()))
  local custom_data = tree:data().custom_data
  -- convert node into argument for junit command whatever
  local argument = {
    projectName = custom_data.projectName,
    testLevel = custom_data.testLevel,
    testKind = custom_data.testKind,
    -- for now very simple
    testNames = { custom_data.fullName },
  }
  --wow..
  local arg_json = '{'
    .. '"projectName":"'
    .. custom_data.projectName
    .. '",'
    .. '"testLevel":'
    .. custom_data.testLevel
    .. ','
    .. '"testKind":'
    .. custom_data.testKind
    .. ','
    .. '"testNames":'
    .. '['
    .. '"'
    .. custom_data.jdtHandler
    .. '"'
    .. ']'
    .. '}'

  local jdtls_client = util.get_client()
  jdtls_client:build_workspace()
  local result = jdtls_client._client:request_sync('workspace/executeCommand', {
    command = 'vscode.java.test.junit.argument',
    arguments = { arg_json },
  })
  if not result or not result.result or result.err ~= nil then
    vim.notify('Failure while building runspec ' .. vim.inspect(result), vim.log.levels.ERROR)
    return nil
  end
  local response = result.result
  local port = ''
  for idx, val in ipairs(response.body.programArguments) do
    if val == '-port' then
      port = response.body.programArguments[idx + 1]
      break
    end
  end
  -- print('will listen on port', port)
  local spec = {
    --@field command string[]
    strategy = {
      name = ('Launch test: %s'):format(tree:data().name),
      type = 'java',
      request = 'launch',
      projectName = response.body.projectName,
      vmArgs = table.concat(response.body.vmArguments, ' '),
      cwd = response.body.workingDirectory,
      classPaths = response.body.classpath,
      mainClass = response.body.mainClass,
      args = table.concat(response.body.programArguments, ' '),
    },
    --@field env? table<string, string>
    env = {},
    cwd = response.body.workingDirectory,
    --@field context? table Arbitrary data to preserve state between running and result collection
    context = { name = 'java', message_buffer = MessageBuffer:new() },
    --@field strategy? table|neotest.Strategy Arguments for strategy or override for chosen strategy
    --@field stream? fun(output_stream: fun(): string[]): fun(): table<string, neotest.Result>
  }

  open_local_socket(math.floor(tonumber(port) or 0), spec.context.message_buffer)
  -- print(vim.inspect(spec))
  return spec
end

---@param args neotest.RunArgs
---@return nil | neotest.RunSpec | neotest.RunSpec[]
--NOTE: for now only support gradle
-- plan is to have different "strategies" like gradle/maven/junit
function M.build_spec(args)
  if args.strategy == 'dap' then
    return build_spec_dap_junit(args)
  end
  return build_spec(args)
end

--- Get error information for failed tests
local function find_next_emtpy_line(lines)
  local result = {}
  for _, line in ipairs(lines) do
    if line == '' then
      return result
    end
    table.insert(result, line)
  end
  return result
end

-- sarebbe ancora meglio utilizzare il bytecode di gradle ma magari in futuro
--- Retrieve test results from xml
--- expects a settings.gradle
---
---@param test_full_names string[]
local function parse_xml_gradle_results(test_full_names)
  -- check if build directory is standard
  local builddir = 'build'
  if not vim.fn.isdirectory(builddir) then
    -- call
    local output = vim.fn.system('./gradlew', 'properties')
    local s, _, match = output:find 'buildDir: (.*)'
    assert(s, 'No buildDir found for gradle')
    builddir = match
  end
  local test_dir = builddir .. '/test-results/test'
  print(test_dir)
  for id, fullname in pairs(test_full_names) do
    fullname, _ = fullname:gsub('#.*', '')
    print(fullname)
    local content = lib.xml.parse(lib.files.read(test_dir .. '/TEST-' .. fullname .. '.xml'))
    print(vim.inspect(content))
  end
end

--- Retrieve results of specified tests from gradle output
---@alias testid string
---@param filepath string the gradle output file
---@param test_names table<testid, string>
---@return table<testid, {line: string, status: string, ctx: any}>
-- NOTE: viene fuori che neotest ha una libreria per parsing xml quindi potrebbe essere carino
-- recuperare le info dall'xml di gradle
local function parse_gradle_test_result(filepath, test_names, test_full_names)
  -- TODO: Still in wip, now I have to work though
  -- parse_xml_gradle_results(test_full_names)
  --- NOTE: shoud split file reading and parsing imho
  local lines = lib.files.read_lines(filepath)
  local test_lines = {}
  for idx, line in ipairs(lines) do
    for test_id, test_name in pairs(test_names) do
      if string.find(line, test_name, 1, true) then
        -- iirc gradle only logs failures
        local status = 'passed'
        local ctx = {}
        if string.find(line, 'FAILED') ~= nil then
          local error_message = find_next_emtpy_line { table.unpack(lines, idx) }
          status = 'failed'
          ctx.short = table.concat(error_message, '\n')
          ctx.errors = {}
          for _, l in ipairs(error_message) do
            local err = {
              message = l,
              line = string.match(l, '(%d+)'),
            }
            table.insert(ctx.errors, err)
          end
        elseif string.find(line, 'SKIPPED') ~= nil then
          status = 'skipped'
        end
        -- print('found: ', line, status)
        test_lines[test_id] = {
          line = line,
          status = status,
          ctx = ctx, -- we'll add this later
        }
      end
    end
  end
  return test_lines
end

---@async
---@param spec neotest.RunSpec
--I could use the strategy for switching between gradle maven and co
---@param result neotest.StrategyResult
---@param tree neotest.Tree
---@return table<string, neotest.Result>
function M.results(spec, result, tree)
  if spec.context.name == 'java' then
    -- print(vim.inspect(spec.context))
    return {
      [tree:data().id] = {
        status = 'failed',
        short = table.concat(spec.context.message_buffer:read()),
      },
    }
  end
  if spec.context.name ~= 'gradle' then
    return { [tree:data().id] = { status = 'failed' } }
  end
  local r = {}
  -- print(vim.inspect(tree:root()))
  -- vim.notify(vim.inspect(spec), vim.log.levels.INFO)
  -- vim.notify(vim.inspect(result), vim.log.levels.INFO)
  -- vim.notify(vim.inspect(tree:data()), vim.log.levels.INFO)
  local test_names = {}
  local lastfile = ''
  for _, node in tree:iter_nodes() do
    if node:data().type == 'file' then
      lastfile = node:data().name
    elseif node:data().type == 'test' then
      test_names[node:data().id] = lastfile .. ' > ' .. node:data().name
    end
  end
  local test_full_names = {}
  for _, node in tree:iter_nodes() do
    if node:data().type == 'test' then
      test_full_names[node:data().id] = node:data().custom_data.fullName
    end
  end
  -- print(vim.inspect(test_full_names))
  local parse_result = parse_gradle_test_result(result.output, test_names, test_full_names)
  if rawequal(next(parse_result), nil) and result.code ~= 0 then
    r[tree:data().id] = { status = 'failed' }
    return r
  end

  for _, node in tree:iter_nodes() do
    local value = node:data()
    if value.type == 'file' then
      -- r[value.id] = { status = parse_result[value.name].success and 'passed' or 'failed' }
      r[value.id] = { status = 'passed' }
    else
      local status = (parse_result[value.id] and not parse_result[value.id].success) and 'failed' or 'passed'
      local short = nil
      if parse_result[value.id] and parse_result[value.id].ctx then
        short = parse_result[value.id].ctx.short
      end
      local errors = nil
      if parse_result[value.id] and parse_result[value.id].ctx then
        errors = parse_result[value.id].ctx.errors
      end
      r[value.id] = {
        status = status,
        short = short,
        errors = errors,
      }
    end
  end

  -- print(vim.inspect(r))
  return r
end

setmetatable(M, {
  __call = function(_, opts)
    return M
  end,
})
return M
