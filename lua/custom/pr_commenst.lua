local M = {}
-- TODO: consider migrating to loclist maybe...?

---@class pr_comment
---@field resolution {}
---@field inline { path: string, to: integer }
---@field content { raw: string}
---@field deleted boolean
---@field id integer
---@field created_on string
---

--- Adds qf entries to current buffer diagnostics (if missing fetches from current qflist)
---@param qfitems vim.quickfix.entry[]?
---@param bufnr integer?
local function add_to_buffer_diagnostics(qfitems, bufnr)
  qfitems = qfitems or vim.fn.getqflist()
  bufnr = bufnr or 0
  local to_insert = {}
  for _, item in ipairs(qfitems) do
    -- NOTE: a bit crude but whatevs
    -- print(vim.fn.bufname(bufnr), item.filename)
    -- NOTE: apparently setqflist does some magic, cause I cannot get the fname back
    -- buf I have a bufnr even for unopened files, and it works :o
    if vim.fn.bufnr(item.bufnr) == bufnr or item.user_data ~= nil and vim.fn.bufname(bufnr) == item.user_data.filename then
      table.insert(to_insert, item)
    end
  end
  local d = vim.diagnostic.fromqflist(to_insert)
  -- vim.notify('Adding ' .. #d .. ' diagnostics to buffer ' .. vim.fn.bufnr(), vim.log.levels.DEBUG)
  vim.diagnostic.set(M.namespace_id, bufnr, d, {})
end

local token = vim.fn.expand '$BB_TOKEN_API'

local function call_bb_api(url, callback)
  -- print 'calling'
  vim.system({
    'curl',
    '-s',
    url,
    '--user',
    'andrea.sibona@check24.de:' .. token,
    '--header',
    'Accept: application/json',
  }, { text = true }, callback)
end

local function on_curl_complete(context)
  context = context or {}
  return function(job_result)
    if job_result.code ~= 0 then
      vim.schedule(function()
        vim.notify('HTTP request failed - could not find prs: ' .. job_result.stderr, vim.log.levels.ERROR)
      end)
      return
    end
    local json_string = job_result.stdout

    -- Use pcall (protected call) for safe decoding, as it can error on invalid JSON
    ---@type boolean,{next:string, values: pr_comment[]}
    local ok, data = pcall(vim.json.decode, json_string)

    if not ok or data == nil then
      vim.schedule(function()
        vim.notify('Failed to parse PR JSON: ' .. tostring(data), vim.log.levels.ERROR)
      end)
      return
    end

    -- print(vim.inspect(data))
    ---@type pr_comment[]
    local values = vim.tbl_extend('force', context, data.values)
    -- table.sort(values, function(a, b)
    --   return a.created_on > b.created_on
    -- end)

    if data.next ~= nil then
      call_bb_api(data.next, on_curl_complete(values))
      return
    else
      -- print(vim.inspect(values))
      ---@type vim.quickfix.entry[]
      local comments = {}
      local fnames = {}
      for _, value in ipairs(values) do
        local errtype
        if value.resolution ~= nil then
          errtype = 'N'
        else
          errtype = 'I'
        end
        local comment = {
          filename = value.inline.path,
          lnum = value.inline.to,
          text = value.content.raw,
          type = errtype,
          user_data = { filename = value.inline.path },
        }
        if not value.deleted then
          table.insert(comments, comment)
          fnames[comment.filename] = true
        end
      end
      -- replace whole qflist -> I think it mbuf?akes the most sense
      vim.schedule(function()
        vim.notify('Found ' .. #comments .. ' comments', vim.log.levels.INFO)
        if #comments == 0 then
          return
        end
        vim.fn.setqflist(comments, 'r')
        add_to_buffer_diagnostics()
        vim.api.nvim_create_autocmd({ 'BufEnter' }, {
          group = vim.api.nvim_create_augroup('pr_quickfix', { clear = true }),
          pattern = vim.tbl_keys(fnames),
          callback = function(event)
            add_to_buffer_diagnostics(nil, event.buf)
          end,
        })
      end)
    end
  end
end

--- This function will have to introduce "adapters" for different api
--- or however I'll be deciding to handle this
---@param url any
function M.find_bitbucket_pr_comments(url)
  call_bb_api(url, on_curl_complete {})
end

--- NOTE: probably expose
--- This function should be used if you have a smart way to retrieve a single pr based on your current workspace
--- adapters adapters adapters
--- by default this one checks my cwd and finds the latest pr matching jira id and repo slug
local function resolve_pr_url(cb)
  -- I really hate having all these callbacks
  local issue_nr = vim.fn.fnamemodify(vim.fn.getcwd(), ':p:h:t')
  local repo_slug = vim.fn.fnamemodify(vim.fn.getcwd(), ':~:h:t')
  call_bb_api(
    'https://api.bitbucket.org/2.0/workspaces/check24/pullrequests/andreasibona?state=OPEN&fields=values.title,values.links.comments,values.source.repository.name,values.source.branch.name,next',
    function(job_result)
      if job_result.code ~= 0 then
        vim.schedule(function()
          vim.notify('HTTP request failed - could not find prs: ' .. job_result.stderr, vim.log.levels.ERROR)
        end)
        return
      end
      local json_string = job_result.stdout

      -- Use pcall (protected call) for safe decoding, as it can error on invalid JSON
      local ok, data = pcall(vim.json.decode, json_string)

      if not ok then
        vim.schedule(function()
          vim.notify('Failed to parse PR JSON: ' .. tostring(data), vim.log.levels.ERROR)
        end)
        return
      end
      for _, entry in ipairs(data.values) do
        if entry.source.repository.name == repo_slug then
          -- print(vim.inspect(entry))
          if string.find(entry.source.branch.name, issue_nr, 1, true) ~= nil or string.find(entry.title, issue_nr, 1, true) ~= nil then
            -- print('resolved', vim.inspect(entry))
            cb(entry.links.comments.href)
            return
          end
        end
      end
    end
  )
end

local function autocomplete(argLead, cmdLine, cursorPos)
  return { 'check', 'find ' }
end

--- Setup your preferred method or retrieving blabla
---@param opts any?
function M.setup(opts)
  opts = opts or {}
  resolve_pr_url = opts.resolve_pr_url or resolve_pr_url
  M.namespace_id = vim.api.nvim_create_namespace 'pr_comments'
  vim.api.nvim_create_user_command('BB', function(args)
    if args.fargs[1] == 'check' then
      resolve_pr_url(M.find_bitbucket_pr_comments)
    elseif args.fargs[1] == 'find' then
      vim.ui.input({
        prompt = 'Enter pr url: ',
        default = nil,
      }, function(res)
        if res == nil then
          vim.notify('Command requires a pr url (only)', vim.log.levels.ERROR)
          return
        end

        local url = res
        -- argument will be like:
        -- https://bitbucket.org/check24/fin-ga-c24-easyinvest/pull-requests/79

        local repo_slug, pr_number = url:match '^https?://[^/]+/([^/]+/[^/]+)/pull%-requests/(%d+)'

        -- print('Repository slug: ' .. (repo_slug or 'nil'))
        -- print('PR number: ' .. (pr_number or 'nil'))
        local api_url = 'https://api.bitbucket.org/2.0/repositories/' .. repo_slug .. '/pullrequests/' .. pr_number .. '/comments'
        M.find_bitbucket_pr_comments(api_url)
      end)
    end
  end, {
    nargs = 1,
    complete = autocomplete,
  })
end
return M
