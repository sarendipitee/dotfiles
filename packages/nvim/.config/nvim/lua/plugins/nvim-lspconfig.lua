return {
  {
    "nvim-lspconfig",
    opts = {
      inlay_hints = { enabled = false },
      servers = {
        ["*"] = {
          keys = {
            {
              "gd",
              "<cmd>lua vim.lsp.buf.definition()<CR>",
              desc = "Goto Definition",
              has = "definition",
              reuse_win = false,
            },
            {
              "gi",
              "<cmd>lua vim.lsp.buf.implementation()<CR>",
              desc = "Goto implementation",
              has = "definition",
              reuse_win = false,
            },
            {
              "gy",
              "<cmd>lua vim.lsp.buf.definition()<CR>",
              desc = "Goto T[y]pe Definition",
              has = "definition",
              reuse_win = false,
            },
          },
        },
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
}
