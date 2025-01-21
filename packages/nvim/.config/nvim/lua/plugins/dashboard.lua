return {
  "snacks.nvim",
  opts = {
    dashboard = {
      sections = {
        { section = "header" },
        { section = "keys", gap = 1, padding = 2 },
        { section = "projects", title = "Projects", gap = 4, padding = { 2, 2 } },
        { section = "startup" },
      },
      preset = {

        header = [[
██████╗░  ███████╗  ██╗░░░░░  ██╗  ███████╗  ██╗░░░██╗  ███████╗
██╔══██╗  ██╔════╝  ██║░░░░░  ██║  ██╔════╝  ██║░░░██║  ██╔════╝
██████╦╝  █████╗░░  ██║░░░░░  ██║  █████╗░░  ╚██╗░██╔╝  █████╗░░
██╔══██╗  ██╔══╝░░  ██║░░░░░  ██║  ██╔══╝░░  ░╚████╔╝░  ██╔══╝░░
██████╦╝  ███████╗  ███████╗  ██║  ███████╗  ░░╚██╔╝░░  ███████╗
╚═════╝░  ╚══════╝  ╚══════╝  ╚═╝  ╚══════╝  ░░░╚═╝░░░  ╚══════╝]],
      },
    },
  },
  --[[ {
    "snacks.nvim",
    opts = function(_, opts)
      -- return opts
      -- print(dump(opts))
      --
      -- table.insert(opts.sections, { section = "projects" })
    end,
  }, ]]
}
-- { action = 'lua require("persistence").select()',              desc = " Restore Session", icon = " ", key = "s" },
