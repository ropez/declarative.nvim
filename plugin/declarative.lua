if vim.g.load_declarative_nvim then
  return
end
vim.g.load_declarative_nvim = true

local TOML = require 'toml'

-- Contains settings we've changed, so that we can restore
local state = {
  o = {},
  keymap = {},
}

local function has_mapping(tab, mode, seq)
  if tab == nil then
    return false
  end
  for i, v in ipairs(tab) do
    local m = v.mode or 'n'
    if m == mode and v.seq == seq then
      return true
    end
  end
  return false
end

local function read_file(filepath)
  -- FIXME We can't restore keymaps that we overwrite

  local toml_file = io.open(filepath)
  if toml_file == nil then
    return false
  end
  local data = TOML.parse(toml_file:read('*a'))

  print("Reading: " .. filepath)

  if data.colorscheme ~= nil then
    if state.colorscheme == nil then
      state.colorscheme = vim.api.nvim_command_output('colorscheme')
    end
    vim.cmd('colorscheme ' .. data.colorscheme)
  else
    if state.colorscheme ~= nil then
      vim.cmd('colorscheme ' .. state.colorscheme)
      state.colorscheme = nil
    end
  end

  for k, v in pairs(data.options) do
    if state.o[k] == nil then
      state.o[k] = vim.o[k]
    end
    vim.o[k] = v
  end

  for k, v in pairs(state.o) do
    if data.options[k] == nil then
      vim.o[k] = state.o[k]
      state.o[k] = nil
    end
  end

  if data.keymap ~= nil then
    for _, map in pairs(data.keymap) do
      local mode = map.mode or 'n'
      vim.keymap.set(mode, map.seq, function() vim.cmd(map.cmd) end, map.opt or { desc = map.desc or map.cmd })

      if not has_mapping(state.keymap, mode, map.seq) then
        table.insert(state.keymap, {mode = mode, seq = map.seq})
      end
    end
  end

  local count = #state.keymap

  for i=count,1,-1 do
    local v = state.keymap[i]
    if not has_mapping(data.keymap, v.mode, v.seq) then
      vim.api.nvim_del_keymap(v.mode, v.seq)
      table.remove(state.keymap, i)
    end
  end

  return true
end

local function init_file(filepath)
  local handle = vim.uv.new_fs_event()
  local flags = {}

  local function on_event(err, filename, events)
    vim.schedule(function()
      read_file(filepath)
    end)

    -- HACK
    vim.uv.fs_event_stop(handle)
    vim.uv.fs_event_start(handle, filepath, flags, on_event)
  end

  read_file(filepath)
  vim.uv.fs_event_start(handle, filepath, flags, on_event)
end

-- TODO Support multiple, prioritized files.
-- Need a way to incrementatlly load the files, or reload all when one changes.
--
-- TODO Support local (current folder) config. Reload/replace when changing folder inside nvim,
-- including :lcd/:tcd
init_file(vim.fs.joinpath(vim.fn.stdpath('config'), 'nvim.toml'))
-- init_file(vim.fs.joinpath(vim.env.HOME, '.nvim.toml'))
