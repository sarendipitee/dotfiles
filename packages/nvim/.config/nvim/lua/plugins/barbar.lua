return {
  "romgrk/barbar.nvim",
  enabled = false,
  version = "^1.0.0", -- optional: only update when a new 1.x version is released
  dependencies = {
    "lewis6991/gitsigns.nvim", -- OPTIONAL: for git status
    "nvim-tree/nvim-web-devicons", -- OPTIONAL: for file icons
  },
  init = function()
    vim.g.barbar_auto_setup = false

    vim.keymap.set({ "n", "i" }, "<D-1>", "<Cmd>BufferGoto 1<CR>")
    vim.keymap.set({ "n", "i" }, "<D-2>", "<Cmd>BufferGoto 2<CR>")
    vim.keymap.set({ "n", "i" }, "<D-3>", "<Cmd>BufferGoto 3<CR>")
    vim.keymap.set({ "n", "i" }, "<D-4>", "<Cmd>BufferGoto 4<CR>")
    vim.keymap.set({ "n", "i" }, "<D-5>", "<Cmd>BufferGoto 5<CR>")
    vim.keymap.set({ "n", "i" }, "<D-6>", "<Cmd>BufferGoto 6<CR>")
    vim.keymap.set({ "n", "i" }, "<D-7>", "<Cmd>BufferGoto 7<CR>")
    vim.keymap.set({ "n", "i" }, "<D-8>", "<Cmd>BufferGoto 8<CR>")
    vim.keymap.set({ "n", "i" }, "<D-9>", "<Cmd>BufferGoto 9<CR>")
  end,
  opts = {
    -- lazy.nvim will automatically call setup for you. put your options here, anything missing will use the default:
    animation = true,
    -- insert_at_start = true,
    -- …etc.
  },
}
