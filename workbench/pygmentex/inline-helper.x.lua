--
-- This is file `inline-helper.x.lua',
-- generated with the docstrip utility.
--
-- The original source files were:
--
-- inline.dtx  (with options: `lua')
-- 
-- inline --- code inlined in a LuaLaTeX document.
-- version: v0.1a
-- date: 2022/02/06
-- url: https:github.com/jlaurens/inline
-- E-mail: jerome.laurens@u-bourgogne.fr
-- Released under the LaTeX Project Public License v1.3c or later
-- See http://www.latex-project.org/lppl.txt
-- 
local rep  = string.rep
local lpeg = require("lpeg")
local P, Cg, Cp, V = lpeg.P, lpeg.Cg, lpeg.Cp, lpeg.V
local lfs  = require("lfs")
local tex  = require("tex")
require("lualibs.lua")
local json = _ENV.utilities.json
local jobname = token.get_macro('jobname')
local NLN_PY_PATH = io.popen([[kpsewhich inline-helper.py]]):read('a'):match("^%s*(.-)%s*$")
local function escape(s)
    s = s:gsub('\\','\\\\')
    s = s:gsub('\r','\\r')
    s = s:gsub('\n','\\n')
    s = s:gsub('"','\\"')
    return s
end
local function make_directory(path)
  local mode,_,__ = lfs.attributes(path,"mode")
  if mode == "directory" then
    return true
  elseif mode ~= nil then
    return nil,path.." exist and is not a directory",1
  end
  if os["type"] == "windows" then
    path = path:gsub("/", "\\")
    _,_,__ = os.execute(
      "if not exist "  .. path .. "\\nul " .. "mkdir " .. path
    )
  else
    _,_,__ = os.execute("mkdir -p " .. path)
  end
  mode = lfs.attributes(path,"mode")
  if mode == "directory" then
    return true
  end
  return nil,path.." exist and is not a directory",1
end
local dir_p, json_p = './'..jobname..'.pygd/'
if make_directory(dir_p) == nil then
  dir_p = './'
  json_p = dir_p..jobname..'.pyg.json'
else
  json_p = dir_p..'input.pyg.json'
end
local function load_exec(chunk)
  local func, err = load(chunk)
  if func then
    local ok, err = pcall(func)
    if not ok then
      print("inline-helper.lua Execution error:", err)
      print('chunk:', chunk)
    end
  else
    print("inline-helper.lua Compilation error:", err)
    print('chunk:', chunk)
  end
end
local eq_pattern = P({ Cp() * P('=')^1 * Cp() + 1 * V(1) })
local function safe_equals(s)
  local i, j = 0
  local max = 0
  while true
    j, i = eq_pattern:match(s, i)
    if j == nil then
      return rep('=', max + 1)
    end
    j = i - j
    if j > max then
      max = j
    end
  end
end
local function options_reset(self)
  self.options = {}
end
local function option_add(self,k,v)
  self.options[k] = v
end
local function start_recording(self)
  self.records = {}
  function self.records.append (t,v)
    t[#t+1]=v
    return t
  end
end
local parse_pattern
do
  local tag = P('?TEX') + '!LUA' + '?LUA'
  local end = '>>>>>'
  local cmd = P(1)^0 - end
  parse_pattern = P({
    '<<<<<' * Cg(tag - ':') * ':' * Cg(cmd) * end * Cp() + 1 * V(1)
  })
end
local function load_exec_output(self, s)
  local i, tag, cmd = 0
  while true do
    tag, cmd, i = parse_pattern:match(s, i)
    if tag == '?TEX' then
      tex.print(cmd)
    elseif tag == '!LUA' then
      self.load_exec(cmd)
    elseif tag == '?LUA' then
      local eqs = self.safe_equals(cmd)
      tex.print([[%
\directlua{self.load_exec([=]]..eqs..[[]..cmd..[[]=]]..eqs..[[])}%
]])
    else
      return
    end
  end
end
local function process_run(self, name)
  if lfs.attributes(json_p,"mode") ~= nil then
    os.remove(json_p)
  end
  local t = {
    ['code']    = token.get_macro(name),
    ['jobname'] = self.jobname,
    ['options'] = self.options or {},
    ['already'] = self.already and 'true' or 'false'
  }
  local s = json.tostring(t,true)
  local fh = assert(io.open(json_p,'w'))
  fh:write(s, '\n')
  fh:close()
  local cmd = "python3 "..NLN_PY_PATH..' "'..\lua_escape:n {json_p}..'"'
  fh = assert(io.popen(cmd))
  self.already = true
  s = fh:read('a')
  self:load_exec_output(s)
end
local function cache_clean(self)
  local to_remove = {}
  for f in lfs.dir(dir_p) do
    to_remove[f] = true
  end
  for k,_ in pairs(to_remove) do
    os.remove(d .. k)
  end
end
local function cache_record(self, style, colored)
  self.style_set[style] = true
  self.colored_set[colored] = true
end
local function cache_clean_unused(self)
  local to_remove = {}
  for f in lfs.dir(dir_p) do
    if self.style_set[f] or self.colored_set[f] then
      continue
    end
    to_remove[f] = true
  end
  for k,_ in pairs(to_remove) do
    os.remove(d .. k)
  end
end
local _DESCRIPTION = [[Global inline helper on the lua side]]
return {
  _DESCRIPTION       = _DESCRIPTION,
  _VERSION           = token.get_macro('NLNFileVersion'),
  jobname            = jobname,
  date               = token.get_macro('NLNFileDate'),
  NLN_PY_PATH        = NLN_PY_PATH,
  escape             = escape,
  make_directory     = make_directory,
  load_exec          = load_exec,
  options_reset      = options_reset,
  option_add         = option_add,
  start_recording    = start_recording,
  process_run        = process_run,
  cache_clean_all    = cache_clean_all,
  cache_record       = cache_record,
  cache_clean_unused = cache_clean_unused,
  style_set          = {},
  colored_set        = {},
  already            = false,
}
