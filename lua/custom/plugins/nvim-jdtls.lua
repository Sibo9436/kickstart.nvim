local jdtls_config = {
  'mfussenegger/nvim-jdtls',
  config = function()
    local project_name = vim.fn.fnamemodify(vim.fn.getcwd(), ':p:h:t')

    local jdtls_workspace_dir = vim.fn.expand '$HOME/.cache/jdtls/workspace/' .. project_name
    local config = {
      cmd = {
        -- RUNNING JDTLS DIRECTLY
        'jdtls',
        '-Xmx1G',
        '-configuration',
        vim.fn.expand '$HOME/.cache/jdtls/config',
        '-data',
        jdtls_workspace_dir,
        '--jvm-arg=-Djava.import.generatesMetadataFilesAtProjectRoot=false',
        vim.fn.expand '--jvm-arg=-javaagent:$HOME/.local/share/nvim/mason/share/jdtls/lombok.jar',
        '--add-modules',
        'ALL-SYSTEM',
        '--add-exports',
        'jdk.compiler/com.sun.tools.javac.processing=ALL-UNNAMED',
        '--Amapstruct.verbose=true',
      },
      init_options = {
        bundles = {
          vim.fn.expand '$HOME/.local/share/nvim/mason/share/java-debug-adapter/com.microsoft.java.debug.plugin.jar',
          vim.fn.expand '$HOME/.local/share/nvim/mason/share/java-test/com.microsoft.java.test.plugin.jar',
        },
        settings = {
          java = {
            home = '/opt/homebrew/Cellar/openjdk/23.0.2/libexec/openjdk.jdk/Contents/Home',
            inlayHints = { parameterNames = { enabled = 'literals' } },
            maven = { downloadSources = true },
            references = { includeDecompiledSources = true },
            saveActions = { organizeImports = true },
            contentProvider = {
              preferred = 'fernflower',
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
                'org.junit.Assume.*',
                'org.junit.jupiter.api.Assertions.*',
                'org.junit.jupiter.api.Assumptions.*',
                'org.junit.jupiter.api.DynamicContainer.*',
                'org.junit.jupiter.api.DynamicTest.*',
                'org.assertj.core.api.Assertions.*',
                'org.assertj.core.api.Assertions.*',
                'org.mockito.Mockito.*',
              },
            },
            configuration = {
              updateBuildConfiguration = 'interactive',
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
    require('jdtls').start_or_attach(config)
  end,
  dependencies = {
    'mfussenegger/nvim-dap',
  },
}
return {}
