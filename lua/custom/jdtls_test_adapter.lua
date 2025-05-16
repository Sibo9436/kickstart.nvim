-- TODO: this needs a huge refactoring
local lib = require 'neotest.lib'
---@type neotest.Adapter
local M = {
  name = 'jdtls',
}

---@return vim.lsp.Client | nil
local function get_jdtls_client()
  local jdtls_client = vim.lsp.get_clients { name = 'jdtls' }
  if not jdtls_client or #jdtls_client == 0 then
    return nil
  end
  return jdtls_client[1]
end

---Find the project root directory given a current directory to work from.
---Should no root be found, the adapter can still be used in a non-project context if a test file matches.
---@async
---@param dir string @Directory to treat as cwd
---@return string | nil @Absolute root dir of test suite
---@diagnostic disable-next-line: unused-local
function M.root(dir)
  local jdtls_client = get_jdtls_client()
  if not jdtls_client then
    return nil
  end
  return jdtls_client.root_dir
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
  local jdtls_client = get_jdtls_client()
  if not jdtls_client then
    return false
  end
  local result, t_err = jdtls_client:request_sync('workspace/executeCommand', {
    command = 'java.project.isTestFile',
    arguments = { vim.uri_from_fname(file_path) },
  })
  if t_err or result == nil or result.err ~= nil then
    return false
  end
  return result.result
end

--- Converts from jdtls/lsp range to neotest range
function convert_range(range)
  return { range.start.line, range.start.character, range['end'].line, range['end'].character }
end

---Given a file path, parse all the tests within it.
---@async
---@param file_path string Absolute file path
---@return neotest.Tree | nil
function M.discover_positions(file_path)
  -- print('called discover positions with ' .. file_path)
  local jdtls_client = get_jdtls_client()
  if not jdtls_client then
    return nil
  end
  -- sta scoperta di request_sync e' assurda
  local test_methods_response = jdtls_client:request_sync(
    'workspace/executeCommand',
    { command = 'vscode.java.test.findTestTypesAndMethods', arguments = { vim.uri_from_fname(file_path) } }
  )
  if not test_methods_response or test_methods_response.err ~= nil or test_methods_response.result == nil then
    vim.notify('Failure while parsing testfile ', vim.log.levels.DEBUG)
    return nil
  end
  local test_methods = test_methods_response.result[1]
  local nodes = {
    {
      type = 'file',
      path = file_path,
      name = test_methods.label,
      range = convert_range(test_methods.range),
      custom_data = nil,
    },
  }
  for _, child in ipairs(test_methods.children) do
    table.insert(nodes, {
      type = 'test',
      path = file_path,
      name = child.label,
      range = convert_range(child.range),
      custom_data = child,
    })
  end
  -- vim.notify(vim.inspect(nodes), vim.log.levels.INFO)
  return lib.positions.parse_tree(nodes, {})
end

---@param args neotest.RunArgs
---@return nil | neotest.RunSpec | neotest.RunSpec[]
--NOTE: for now only support gradle
-- plan is to have different strategies like gradle/maven/junit
function M.build_spec(args)
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
        'test',
        table.unpack(filenames),
      },
      --@field env? table<string, string>
      env = {},
      cwd = vim.fn.getcwd(),
      --@field context? table Arbitrary data to preserve state between running and result collection
      --@field strategy? table|neotest.Strategy Arguments for strategy or override for chosen strategy
      --@field stream? fun(output_stream: fun(): string[]): fun(): table<string, neotest.Result>
    }
  end
  if data.type == 'file' then
    local classname = string.gsub(data.name, '.java', '')
    return {
      command = {
        args.tree:root():data().path .. '/gradlew',
        'test',
        '--tests',
        classname,
      },
      --@field env? table<string, string>
      env = {},
      cwd = vim.fn.getcwd(),
      --@field context? table Arbitrary data to preserve state between running and result collection
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
      'test',
      '--tests',
      fullname,
    },
    --@field env? table<string, string>
    env = {},
    cwd = vim.fn.getcwd(),
    --@field context? table Arbitrary data to preserve state between running and result collection
    --@field strategy? table|neotest.Strategy Arguments for strategy or override for chosen strategy
    --@field stream? fun(output_stream: fun(): string[]): fun(): table<string, neotest.Result>
  }
end

-- NOTE: this would be glorious
-- function M.build_spec(args)
--   if args.strategy == 'dap' then
--     vim.notify('dap strategy not supported yet', vim.log.levels.ERROR)
--   end
--   local tree = args.tree
--   local data = tree:data()
--   if data.type ~= 'test' then
--     return nil
--   end
--   print(vim.inspect(tree:data()))
--   local custom_data = tree:data().custom_data
--   -- convert node into argument for junit command whatever
--   local argument = {
--     projectName = custom_data.projectName,
--     testLevel = custom_data.testLevel,
--     testKind = custom_data.testKind,
--     -- for now very simple
--     testNames = { custom_data.fullName },
--   }
--   --wow..
--   local arg_json = '{'
--     .. '"projectName":"'
--     .. custom_data.projectName
--     .. '",'
--     .. '"testLevel":'
--     .. custom_data.testLevel
--     .. ','
--     .. '"testKind":'
--     .. custom_data.testKind
--     .. ','
--     .. '"testNames":'
--     .. '['
--     .. '"'
--     .. custom_data.jdtHandler
--     .. '"'
--     .. ']'
--     .. '}'
--   print(arg_json)
--   local jdtls_client = get_jdtls_client()
--   if not jdtls_client then
--     return nil
--   end
--   local result = jdtls_client:request_sync('workspace/executeCommand', {
--     command = 'vscode.java.test.junit.argument',
--     arguments = { arg_json },
--   })
--   if not result or not result.result or result.err ~= nil then
--     vim.notify('Failure while building runspec ' .. vim.inspect(result), vim.log.levels.ERROR)
--     return nil
--   end
--   local response = result.result
--   return {
--     --@field command string[]
--     command = {
--       'java',
--       '-cp',
--       table.concat(response.body.classpath, ':'),
--       table.unpack(response.body.vmArguments),
--       response.body.mainClass,
--       table.unpack(response.body.programArguments),
--     },
--     --@field env? table<string, string>
--     env = {},
--     cwd = response.body.workingDirectory,
--     --@field context? table Arbitrary data to preserve state between running and result collection
--     --@field strategy? table|neotest.Strategy Arguments for strategy or override for chosen strategy
--     --@field stream? fun(output_stream: fun(): string[]): fun(): table<string, neotest.Result>
--   }
-- end
--

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

--- Retrieve results of specified tests from gradle output
---@alias testid string
---@param filepath string the gradle output file
---@param test_names table<testid, string>
---@return table<testid, {line: string, status: string, ctx: any}>
-- NOTE: viene fuori che neotest ha una libreria per parsing xml quindi potrebbe essere carino
-- recuperare le info dall'xml di gradle
local function parse_gradle_test_result(filepath, test_names)
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
  local parse_result = parse_gradle_test_result(result.output, test_names)
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
