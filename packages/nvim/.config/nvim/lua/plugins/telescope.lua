return {
  --[[ {
    "LukasPietzschmann/telescope-tabs",
    dependencies = { "nvim-telescope/telescope.nvim" },
    config = function()
      require("telescope").load_extension("telescope-tabs")
      require("telescope-tabs").setup({
        -- Your custom config :^)
      })
    end,
  }, ]]
  "nvim-telescope/telescope.nvim",
  keys = {
    { "<leader><space>", LazyVim.pick("files", { root = false }), desc = "Find Files (cwd)" },
    { "<leader>/", LazyVim.pick("live_grep", { root = false }), desc = "Live Grep (cwd)" },
    {
      "<D-O>",
      function()
        require("telescope.builtin").lsp_document_symbols({
          symbols = LazyVim.config.get_kind_filter(),
        })
      end,
      desc = "Goto Symbol",
    },
  },
  opts = {
    defaults = {
      mappings = {
        i = {
          ["<C-t>"] = "select_tab",
          ["<C-k>"] = "move_selection_previous",
          ["<C-j>"] = "move_selection_next",
        },
        n = {
          ["<C-t>"] = "select_tab",
          ["<C-s>"] = "select_horizontal",
          ["<C-v>"] = "select_vertical",
        },
      },
    },
  },
}
