local M = {}
-- TODO: consider migrating to loclist maybe...?

---@class pr_comment
---@field resolution {}
---@field inline { path: string, to: integer }
---@field content { raw: string}
---@field deleted boolean
---@field id integer
---@field created_on string

---@class PrCommentsConfig
---@field workspace string Bitbucket workspace slug
---@field user string Bitbucket user slug used in the "my PRs" lookup
---@field auth_user string Username (email) used for HTTP basic auth
---@field token_env string Name of the env var holding the API token
---@field resolve_pr_url? fun(cb: fun(url:string))
local defaults = {
  workspace = vim.env.BB_WORKSPACE or 'check24',
  user = vim.env.BB_USER or 'andreasibona',
  auth_user = vim.env.BB_AUTH_USER or 'andrea.sibona@check24.de',
  token_env = 'BB_TOKEN_API',
}

---@type PrCommentsConfig
local config = vim.deepcopy(defaults)

--- Adds qf entries to current buffer diagnostics (if missing fetches from current qflist)
---@param qfitems vim.quickfix.entry[]?
---@param bufnr integer?
local function add_to_buffer_diagnostics(qfitems, bufnr)
  qfitems = qfitems or vim.fn.getqflist()
  bufnr = bufnr or 0
  local to_insert = {}
  for _, item in ipairs(qfitems) do
    -- NOTE: a bit crude but whatevs
    -- NOTE: apparently setqflist does some magic, so item.filename comes back
    -- empty even when we set it; we keep the original under user_data.
    if vim.fn.bufnr(item.bufnr) == bufnr or (item.user_data ~= nil and vim.fn.bufname(bufnr) == item.user_data.filename) then
      table.insert(to_insert, item)
    end
  end
  local d = vim.diagnostic.fromqflist(to_insert)
  vim.diagnostic.set(M.namespace_id, bufnr, d, {})
end

--- Asynchronously call the Bitbucket API. Token comes from
--- `config.token_env`; we pass it via curl's `-K -` (config from stdin) so it
--- never appears in argv (avoids leaking through `ps`).
---@param url string
---@param callback fun(out: vim.SystemCompleted)
local function call_bb_api(url, callback)
  local token = vim.env[config.token_env]
  if not token or token == '' then
    vim.schedule(function() vim.notify(('$%s is not set — cannot call Bitbucket API'):format(config.token_env), vim.log.levels.ERROR) end)
    return
  end
  -- curl reads additional config from stdin. We escape quotes defensively even
  -- though the values should never contain them.
  local curl_config = ('user = "%s:%s"\n'):format(config.auth_user:gsub('"', '\\"'), token:gsub('"', '\\"'))
  vim.system({
    'curl',
    '-s',
    url,
    '-K',
    '-',
    '--header',
    'Accept: application/json',
  }, { text = true, stdin = curl_config }, callback)
end

--- Iteratively page through a Bitbucket comments listing, accumulating results.
---@param start_url string
---@param on_done fun(values: pr_comment[])
local function fetch_all_pages(start_url, on_done)
  local accumulated = {}
  local visit
  visit = function(url)
    call_bb_api(url, function(job_result)
      if job_result.code ~= 0 then
        vim.schedule(function() vim.notify('HTTP request failed: ' .. (job_result.stderr or ''), vim.log.levels.ERROR) end)
        return
      end
      local json_string = job_result.stdout
      ---@type boolean, { next: string?, type: string?, values: pr_comment[] }
      local ok, data = pcall(vim.json.decode, json_string)
      if not ok or data == nil then
        vim.schedule(function() vim.notify('Failed to parse PR JSON: ' .. tostring(json_string), vim.log.levels.ERROR) end)
        return
      end
      if data.type == 'error' then
        vim.schedule(function() vim.notify('Bitbucket API error: ' .. vim.inspect(data), vim.log.levels.ERROR) end)
        return
      end
      if data.values then
        for _, v in ipairs(data.values) do
          table.insert(accumulated, v)
        end
      end
      if data.next then
        -- Schedule the next request instead of recursing in-place so deep
        -- pagination doesn't stack libuv callbacks.
        vim.schedule(function() visit(data.next) end)
      else
        vim.schedule(function() on_done(accumulated) end)
      end
    end)
  end
  visit(start_url)
end

local function publish_comments(values)
  ---@type vim.quickfix.entry[]
  local comments = {}
  local fnames = {}
  for _, value in ipairs(values) do
    if not value.deleted and value.inline then
      local errtype = value.resolution ~= nil and 'N' or 'I'
      local comment = {
        filename = value.inline.path,
        lnum = value.inline.to,
        text = value.content.raw,
        type = errtype,
        user_data = { filename = value.inline.path },
      }
      table.insert(comments, comment)
      fnames[comment.filename] = true
    end
  end
  vim.notify('Found ' .. #comments .. ' comments', vim.log.levels.INFO)
  if #comments == 0 then return end
  vim.fn.setqflist(comments, 'r')
  add_to_buffer_diagnostics()
  vim.api.nvim_create_autocmd({ 'BufEnter' }, {
    group = vim.api.nvim_create_augroup('pr_quickfix', { clear = true }),
    pattern = vim.tbl_keys(fnames),
    callback = function(event) add_to_buffer_diagnostics(nil, event.buf) end,
  })
end

--- This function will have to introduce "adapters" for different api
--- or however I'll be deciding to handle this
---@param url string
function M.find_bitbucket_pr_comments(url) fetch_all_pages(url, publish_comments) end

--- Default PR-URL resolver: checks the cwd's directory name as the JIRA id and
--- its parent dir as the repo slug, then finds the matching open PR on the
--- configured workspace+user.
---@param cb fun(comments_url: string)
local function default_resolve_pr_url(cb)
  local issue_nr = vim.fn.fnamemodify(vim.fn.getcwd(), ':p:h:t')
  local repo_slug = vim.fn.fnamemodify(vim.fn.getcwd(), ':~:h:t')
  local url = ('https://api.bitbucket.org/2.0/workspaces/%s/pullrequests/%s'):format(config.workspace, config.user)
    .. '?state=OPEN&fields=values.title,values.links.comments,values.source.repository.name,values.source.branch.name,next'
  call_bb_api(url, function(job_result)
    if job_result.code ~= 0 then
      vim.schedule(function() vim.notify('HTTP request failed - could not find prs: ' .. (job_result.stderr or ''), vim.log.levels.ERROR) end)
      return
    end
    local ok, data = pcall(vim.json.decode, job_result.stdout)
    if not ok then
      vim.schedule(function() vim.notify('Failed to parse PR JSON: ' .. tostring(data), vim.log.levels.ERROR) end)
      return
    end
    for _, entry in ipairs(data.values or {}) do
      if entry.source.repository.name == repo_slug then
        if string.find(entry.source.branch.name, issue_nr, 1, true) ~= nil or string.find(entry.title, issue_nr, 1, true) ~= nil then
          vim.schedule(function() cb(entry.links.comments.href) end)
          return
        end
      end
    end
  end)
end

local function autocomplete(_, _, _) return { 'check', 'find' } end

--- Setup your preferred method for retrieving PR comments.
---@param opts PrCommentsConfig|nil
function M.setup(opts)
  opts = opts or {}
  config = vim.tbl_extend('force', defaults, opts)
  local resolver = config.resolve_pr_url or default_resolve_pr_url
  M.namespace_id = vim.api.nvim_create_namespace 'pr_comments'
  vim.api.nvim_create_user_command('BB', function(args)
    if args.fargs[1] == 'check' then
      resolver(M.find_bitbucket_pr_comments)
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
        if not repo_slug or not pr_number then
          vim.notify('Could not parse PR URL: ' .. tostring(url), vim.log.levels.ERROR)
          return
        end
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
