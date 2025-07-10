return {
  {
    "nvim-lspconfig",
    opts = {
      inlay_hints = { enabled = false },
      servers = {
        cssls = {},
        cssmodules_ls = {},
        vtsls = {
          keys = {
            {
              "<leader>cm",
              LazyVim.lsp.action["source.addMissingImports.ts"],
              desc = "Add missing imports",
            },
          },
        },
      },
    },
  },
  {
    "neovim/nvim-lspconfig",
    opts = function()
      -- "reuse_win = true" is annoying as hell
      local keys = require("lazyvim.plugins.lsp.keymaps").get()
      keys[#keys + 1] = {
        "gd",
        function()
          require("telescope.builtin").lsp_definitions({ reuse_win = false })
        end,
        desc = "Goto Definition",
        has = "definition",
      }

      keys[#keys + 1] = {
        "gI",
        function()
          require("telescope.builtin").lsp_implementations({ reuse_win = false })
        end,
        desc = "Goto Implementation",
      }
      keys[#keys + 1] = {
        "gy",
        function()
          require("telescope.builtin").lsp_type_definitions({ reuse_win = false })
        end,
        desc = "Goto T[y]pe Definition",
      }
    end,
  },
}
