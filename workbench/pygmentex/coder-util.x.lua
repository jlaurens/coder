--
-- This is file `coder-util.x.lua',
-- generated with the docstrip utility.
--
-- The original source files were:
--
-- coder.dtx  (with options: `lua')
-- 
-- coder --- code inlined in a LuaLaTeX document.
-- version: v2.6a
-- date: 2020-11-23
-- url: https:github.com/jlaurens/coder
-- E-mail: jerome.laurens@u-bourgogne.fr
-- Released under the LaTeX Project Public License v1.3c or later
-- See http://www.latex-project.org/lppl.txt
-- 

local lfs   = _ENV.lfs
local tex   = _ENV.tex
local token = _ENV.token
local rep   = string.rep
local lpeg  = require("lpeg")
local P, Cg, Cp, V = lpeg.P, lpeg.Cg, lpeg.Cp, lpeg.V
require("lualibs.lua")
local json   = _ENV.utilities.json
local CDR_PY_PATH = kpse.find_file('coder-tool.py')
local PYTHON_PATH = io.popen([[which python]]):read('a'):match("^%s*(.-)%s*$")
local function set_python_path(self, path_var)
  local path = assert(token.get_macro(assert(path_var)))
  if #path>0 then
    local mode,_,__ = lfs.attributes(self.PYTHON_PATH,'mode')
    assert(mode == 'file' or mode == 'link')
  else
    path = io.popen([[which python]]):read('a'):match("^%s*(.-)%s*$")
  end
  self.PYTHON_PATH = path
end
local function escape(s)
  s = s:gsub(' ','\\ ')
  s = s:gsub('\\','\\\\')
  s = s:gsub('\r','\\r')
  s = s:gsub('\n','\\n')
  s = s:gsub('"','\\"')
  s = s:gsub("'","\\'")
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
local dir_p, json_p
local jobname = tex.jobname
dir_p = './'..jobname..'.pygd/'
if make_directory(dir_p) == nil then
  dir_p = './'
  json_p = dir_p..jobname..'.pyg.json'
else
  json_p = dir_p..'input.pyg.json'
end
local function print_file_content(name)
  local p = token.get_macro(name)
  local fh = assert(io.open(p, 'r'))
  s = fh:read('a')
  fh:close()
  tex.print(s)
end
local function load_exec(chunk)
  local func, err = load(chunk)
  if func then
    local ok, err = pcall(func)
    if not ok then
      print("coder-util.lua Execution error:", err)
      print('chunk:', chunk)
    end
  else
    print("coder-util.lua Compilation error:", err)
    print('chunk:', chunk)
  end
end
local eq_pattern = P({ Cp() * P('=')^1 * Cp() + P(1) * V(1) })
local function safe_equals(s)
  local i, j = 0, 0
  local max = 0
  while true do
    i, j = eq_pattern:match(s, j)
    if i == nil then
      return rep('=', max + 1)
    end
    i = j - i
    if i > max then
      max = i
    end
  end
end
local parse_pattern
do
  local tag = P('!') + '?'
  local stp = '>>>>>'
  local cmd = (P(1) - stp)^0
  parse_pattern = P({
    P('<<<<<') * Cg(tag) * 'LUA:' * Cg(cmd) * stp * Cp() + 1 * V(1)
  })
end
local function load_exec_output(self, s)
  local i, tag, cmd
  i = 0
  while true do
    tag, cmd, i = parse_pattern:match(s, i)
    if tag == '!' then
      self.load_exec(cmd)
    elseif tag == '?' then
      local eqs = self.safe_equals(cmd)
      cmd = '['..eqs..'['..cmd..']'..eqs..']'
      tex.print([[%
\directlua{CDR:load_exec(]]..cmd..[[)}%
]])
    else
      return
    end
  end
end
local function options_reset(self)
  self['.options'] = {}
end
local function option_add(self, key, value_name)
  local p = self['.options']
  p[key] = token.get_macro(assert(value_name))
end
local function hilight_code(self, code_name)
  local args = {
    __cls__ = 'Arguments',
    code = assert(token.get_macro(assert(code_name))),
  }
  args.templates = {
    __cls__ = 'Templates',
  }
  args.pygopts = {
    __cls__ = 'PygOpts',
  }

end
local function process_block_new(self, tags_clist)
  local t = {}
  for tag in string.gmatch(tags_clist, '([^,]+)') do
    t[#t+1]=tag
  end
  self['block tags']  = tags_clist
  self['.lines'] = {}
end
local function process_line(self, line_variable_name)
  local line = assert(token.get_macro(assert(line_variable_name)))
  local ll = self['.lines']
  ll[#ll+1] = line
  local lt = self['lines by tag'] or {}
  self['lines by tag'] = lt
  for tag in self['block tags']:gmatch('([^,]+)') do
    ll = lt[tag] or {}
    lt[tag] = ll
    ll[#ll+1] = line
  end
end
local function hilight_block(self, block_name)
end
local function export_file(self, file_name)
  self['.name'] = assert(token.get_macro(assert(file_name)))
  self['.export'] = {}
end
local function export_file_info(self, key, value)
  local export = self['.export']
  value = assert(token.get_macro(assert(value)))
  export[key] = value
end
local function export_complete(self)
  local name    = self['.name']
  local export  = self['.export']
  local records = self['.records']
  local tt = {}
  local s = export.preamble
  if s then
    tt[#tt+1] = s
  end
  for _,tag in ipairs(export.tags) do
    s = records[tag]:concat('\n')
    tt[#tt+1] = s
    records[tag] = { [1] = s }
  end
  s = export.postamble
  if s then
    tt[#tt+1] = s
  end
  if #tt>0 then
    local fh = assert(io.open(name,'w'))
    fh:write(tt:concat('\n'))
    fh:close()
  end
  self['.file'] = nil
  self['.exportation'] = nil
end
local function cache_clean_all(self)
  local to_remove = {}
  for f in lfs.dir(dir_p) do
    to_remove[f] = true
  end
  for k,_ in pairs(to_remove) do
    os.remove(dir_p .. k)
  end
end
local function cache_record(self, style, colored)
  self['.style_set'][style] = true
  self['.colored_set'][colored] = true
end
local function cache_clean_unused(self)
  local to_remove = {}
  for f in lfs.dir(dir_p) do
    if not self['.style_set'][f] and not self['.colored_set'][f] then
      to_remove[f] = true
    end
  end
  for k,_ in pairs(to_remove) do
    os.remove(dir_p .. k)
  end
end
local _DESCRIPTION = [[Global coder utilities on the lua side]]
return {
  _DESCRIPTION       = _DESCRIPTION,
  _VERSION           = token.get_macro('fileversion'),
  date               = token.get_macro('filedate'),
  CDR_PY_PATH        = CDR_PY_PATH,
  PYTHON_PATH        = PYTHON_PATH,
  set_python_path    = set_python_path,
  escape             = escape,
  make_directory     = make_directory,
  load_exec          = load_exec,
  load_exec_output   = load_exec_output,
  record_line        = function(self,line) end,
  hilight_code       = hilight_code,
  process_block_new  = process_block_new,
  hilight_block      = hilight_block,
  cache_clean_all    = cache_clean_all,
  cache_record       = cache_record,
  cache_clean_unused = cache_clean_unused,
  options_reset      = options_reset,
  option_add         = option_add,
  ['.style_set']     = {},
  ['.colored_set']   = {},
  ['.options']       = {},
  ['.export']        = {},
  ['.name']          = nil,
  already            = false,
  json_p             = json_p,
}
