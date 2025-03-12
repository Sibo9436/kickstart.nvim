vim.api.nvim_buf_create_user_command(0, 'Redocly', function()
  local au = vim.api.nvim_create_augroup('redocly', { clear = true })
  vim.api.nvim_create_autocmd('BufWritePost', {
    group = au,
    buffer = 0,
    callback = function(_)
      vim.system({ '../../gradlew', 'buildOpenApiDocs' }, { stdout = false, stderr = false }, function(_)
        print 'telling firefox to reload'
        vim.system({
          'osascript',
          '-e',
          'tell application "Firefox" to activate',
          '-e',
          'tell application "System Events" to keystroke "r" using command down',
        }, {
          stdout = false,
          stderr = false,
        }, function(_) end)
      end)
    end,
  })
end, {})
