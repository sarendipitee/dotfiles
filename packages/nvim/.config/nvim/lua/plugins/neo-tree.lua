return {
  "nvim-neo-tree/neo-tree.nvim",
  -- enabled = false,
  dependencies = {
    --"nvim-lua/plenary.nvim",
    --"nvim-tree/nvim-web-devicons",
    --"MunifTanjim/nui.nvim",
    --"3rd/image.nvim",
  },
  opts = {
    source_selector = {
      winbar = false,
      statusline = false,
      show_scrolled_off_parent_node = true,
      separator = nil,
    },
    filesystem = {
      follow_current_file = { enabled = false },
      filtered_items = {
        hide_dotfiles = false,
      },
      never_show = {
        ".DS_Store",
      },
      window = {
        mappings = {
          ["u"] = "navigate_up",
          ["C"] = "set_root",
        },
      },
    },
    window = {
      mappings = {
        ["o"] = "open",
        ["a"] = { "add", config = { show_path = "relative" } },
        ["m"] = { "move", config = { show_path = "absolute" } },
        ["-"] = "expand_all_nodes",
        ["+"] = "close_all_subnodes",
      },
    },
    event_handlers = {
      {
        event = "after_render",
        handler = function(state)
          -- Set the current source_selector state as a global variable that Bufferline can use
          if state.current_position == "left" or state.current_position == "right" then
            vim.api.nvim_win_call(state.winid, function()
              local str = require("neo-tree.ui.selector").get()
              if str then
                _G.__cached_neo_tree_selector = str
              end
            end)
          end
        end,
      },
    },
  },
  keys = {
    {
      "<D-E>",
      function()
        require("neo-tree.command").execute({ focus = true, dir = vim.uv.cwd(), reveal = true })
      end,
      desc = "Open/Focus NeoTree (Root Dir)",
    },
  },
}
