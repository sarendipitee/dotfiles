-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

-- cmd-1 2 3 change tabs
vim.keymap.set({ "n", "i" }, "<D-1>", ":tabn 1<CR>", { silent = true })
vim.keymap.set({ "n", "i" }, "<D-2>", ":tabn 2<CR>", { silent = true })
vim.keymap.set({ "n", "i" }, "<D-3>", ":tabn 3<CR>", { silent = true })
vim.keymap.set({ "n", "i" }, "<D-4>", ":tabn 4<CR>", { silent = true })
vim.keymap.set({ "n", "i" }, "<D-5>", ":tabn 5<CR>", { silent = true })
vim.keymap.set({ "n", "i" }, "<D-6>", ":tabn 6<CR>", { silent = true })
vim.keymap.set({ "n", "i" }, "<D-7>", ":tabn 7<CR>", { silent = true })
vim.keymap.set({ "n", "i" }, "<D-8>", ":tabn 8<CR>", { silent = true })
vim.keymap.set({ "n", "i" }, "<D-9>", ":tabn 9<CR>", { silent = true })

-- "Go back" to last file/buffer after jumping to a new one
vim.keymap.set({ "n" }, "gb", ":<c-^><CR>", { silent = true })

-- Exit terminal mode with Esc
vim.api.nvim_set_keymap("t", "<ESC>", [[<C-\><C-n>]], { noremap = true })
vim.api.nvim_set_keymap("t", "<C-d>", [[<C-\><C-d>]], { noremap = true })

-- Allow clipboard copy paste in neovim
vim.api.nvim_set_keymap("", "<D-v>", "+p<CR>", { noremap = true, silent = true })
vim.keymap.set({ "i", "t", "v", "!" }, "<D-v>", "<C-R>+", { noremap = true, silent = true })

-- vstar without jumping
vim.keymap.set({ "n" }, "*", [[:keepjumps normal! mi*`i<CR>]], { noremap = true })

-- cmd-. to open code action (like VSCode default)
vim.keymap.set({ "n" }, "<d-.>", vim.lsp.buf.code_action, { remap = false })
