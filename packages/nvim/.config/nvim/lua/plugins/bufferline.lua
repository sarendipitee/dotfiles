-- bufferline
_G.__cached_neo_tree_selector = nil
_G.__get_selector = function()
  return _G.__cached_neo_tree_selector
end

return {
  "akinsho/bufferline.nvim",
  version = "*",
  dependencies = "nvim-tree/nvim-web-devicons",
  config = function()
    local bufferline = require("bufferline")
    bufferline.setup({
      options = {
        style_preset = bufferline.style_preset.no_italic,
        mode = "tabs",
        separator_style = "slope",
        max_name_length = 32,
        tab_size = 32,
        show_duplicate_prefix = false,
        enforce_regular_tabs = false,
        always_show_bufferline = false,
        offsets = {
          {
            filetype = "neo-tree",
            --[[ text = " ",
            highlight = "bg",
            text_align = "center", ]]
            raw = " %{%v:lua.__get_selector()%} ",
            highlight = { sep = { link = "WinSeparator" } },
            separator = "┃",
          },
        },
        custom_filter = function(buf_number, buf_numbers)
          if vim.bo[buf_number].filetype ~= "neo-tree" then
            return true
          end
          return false
        end,
      },
    })
  end,
  keys = {
    { "<leader>bp", "<Cmd>BufferLineTogglePin<CR>", desc = "Toggle pin" },
    { "<leader>bP", "<Cmd>BufferLineGroupClose ungrouped<CR>", desc = "Delete non-pinned buffers" },
    { "<leader>bo", "<Cmd>BufferLineCloseOthers<CR>", desc = "Delete other buffers" },
    { "<leader>br", "<Cmd>BufferLineCloseRight<CR>", desc = "Delete buffers to the right" },
    { "<leader>bl", "<Cmd>BufferLineCloseLeft<CR>", desc = "Delete buffers to the left" },
    { "[b", "<cmd>bprevious<cr>", desc = "Prev buffer" },
    { "]b", "<cmd>bnext<cr>", desc = "Next buffer" },
    { "<leader>bd", "<cmd>Bdelete<cr>", desc = "Delete current buffer" },
  },
}
