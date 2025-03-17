return {
  "snacks.nvim",
  opts = {
    dashboard = {
      sections = {
        { section = "header" },
        { section = "keys", padding = { 2, 1 } },
        { section = "projects", title = "Projects", padding = { 0, 1 } },
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
