return {
  {
    "nvim-neotest/neotest",
    lazy = false,
    dependencies = {
      "nvim-neotest/nvim-nio",
      "nvim-lua/plenary.nvim",
      "antoinemadec/FixCursorHold.nvim",
      "nvim-treesitter/nvim-treesitter",
      "folke/snacks.nvim",
      "marilari88/neotest-vitest",
    },
    keys = {
      {
        "<leader>tn",
        function() end,
        desc = "Test nearest",
      },
      {
        "<leader>tf",
        function()
          require("neotest").run.run(vim.fn.expand("%"))
        end,
        desc = "Test file",
      },
      {
        "<leader>tr",
        function()
          require("neotest").run.run_last()
        end,
        desc = "Rerun last test",
      },
      {
        "<leader>twn",
        function()
          require("neotest").run.run({ vitestCommand = "vitest --watch" })
        end,
        desc = "Test nearest (watch)",
      },
      {
        "<leader>twf",
        function()
          require("neotest").run.run({ vim.fn.expand("%"), vitestCommand = "vitest --watch" })
        end,
        desc = "Test file (watch)",
      },
    },
    config = function()
      require("neotest").setup({
        adapters = {
          require("neotest-vitest")({
            -- Filter directories when searching for test files. Useful in large projects (see Filter directories notes).
            filter_dir = function(name, rel_path, root)
              return name ~= "node_modules"
            end,
          }),
        },
      })
      Snacks.toggle
        .new({
          id = "neotest-output-panel",
          name = "output panel",
          get = function()
            return require("neotest").output_panel.is_open()
          end,
          set = function(state)
            if state then
              require("neotest").output_panel.open()
            else
              require("neotest").output_panel.close()
            end
          end,
        })
        :map("<leader>to")
      Snacks.toggle
        .new({
          id = "neotest-test-summary",
          name = "test summary panel",
          get = function()
            return require("neotest").summary.is_open()
          end,
          set = function(state)
            if state then
              require("neotest").summary.open()
            else
              require("neotest").summary.close()
            end
          end,
        })
        :map("<leader>ts")
    end,
  },
}
