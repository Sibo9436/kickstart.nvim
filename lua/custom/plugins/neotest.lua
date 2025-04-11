--- Converts a callback-based function to a coroutine function.
---
--- credits to https://gregorias.github.io/posts/using-coroutines-in-neovim-lua/
---
---@param f function The function to convert.
---                  The callback needs to be its first argument.
---@return function A fire-and-forget coroutine function.
---                 Accepts the same arguments as f without the callback.
---                 Returns what f has passed to the callback.
local cb_to_co = function(f)
  local f_co = function(...)
    local this = coroutine.running()
    assert(this ~= nil, 'The result of cb_to_co must be called within a coroutine.')

    local f_status = 'running'
    local f_ret = nil
    -- f needs to have the callback as its first argument, because varargs
    -- passing doesn’t work otherwise.
    f(function(ret)
      f_status = 'done'
      f_ret = ret
      if coroutine.status(this) == 'suspended' then
        -- If we are suspended, then f_co has yielded control after calling f.
        -- Use the caller of this callback to resume computation until the next yield.
        coroutine.resume(this)
      end
    end, ...)
    if f_status == 'running' then
      -- If we are here, then `f` must not have called the callback yet, so it
      -- will do so asynchronously.
      -- Yield control and wait for the callback to resume it.
      coroutine.yield()
    end
    return f_ret
  end

  return f_co
end

return {
  'nvim-neotest/neotest',
  dependencies = {
    'nvim-neotest/nvim-nio',
    'nvim-lua/plenary.nvim',
    'antoinemadec/FixCursorHold.nvim',
    'nvim-treesitter/nvim-treesitter',
    'nvim-neotest/neotest-jest',
  },
  config = function()
    local neotest = require 'neotest'
    neotest.setup {
      discovery = {
        enabled = false,
      },
      adapters = {
        require 'neotest-jest' {
          jest_test_discovery = true,
          jestCommand = 'npm test --',
          jestConfigFile = string.find(vim.api.nvim_buf_get_name(0), '/react/')
              and string.match(vim.api.nvim_buf_get_name(0), '(.-/[^/]+/react)') .. '/jest.config.json'
            or 'custom.jest.config.ts',
          env = { CI = true },
          cwd = function(file)
            -- TODO: add here further possible wacky locations I guess
            -- or maybe a cool way to find a package.json?
            local ok, plenary_scandir = pcall(require, 'plenary.scandir')
            if ok then
              local pjson = plenary_scandir.scan_dir(vim.fn.getcwd(0), {
                depth = 4,
                search_pattern = 'package.json',
                respect_gitignore = true,
              })
              local found = ''
              if #pjson > 1 then
                local pick_co = cb_to_co(function(on_choice, items, opts)
                  vim.ui.select(items, opts, on_choice)
                end)
                local pick = pick_co(pjson, {
                  prompt = 'Select tabs or spaces:',
                  format_item = function(item)
                    return item
                  end,
                })
                print('pick', pick)
                return string.match(pick, '(.-/[^/]+/)package.json')
              elseif #pjson == 1 then
                found = string.match(pjson[1], '(.-/[^/]+/)package.json')
                return found
              end
            end
            if string.find(file, '/react/') then
              return string.match(file, '(.-/[^/]+/react)')
            end
            return vim.fn.getcwd()
          end,
        },
      },
    }
  end,
}
