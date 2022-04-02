--
-- This is file `coder-util.lua',
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
local md5   = _ENV.md5
local kpse  = _ENV.kpse
local rep   = string.rep
local lpeg  = require("lpeg")
local P, Cg, Cp, V = lpeg.P, lpeg.Cg, lpeg.Cp, lpeg.V
local json  = require('lualibs-util-jsn')
local CDR_PY_PATH = kpse.find_file('coder-tool.py')
local function set_python_path(self, path_var)
  local path, mode, _, __
  if path_var then
    path = assert(token.get_macro(path_var))
    mode,_,__ = lfs.attributes(path,'mode')
    print('**** CDR mode', path, mode)
  end
  if not mode then
    path = io.popen([[which python]]):read('a'):match("^%s*(.-)%s*$")
    mode,_,__ = lfs.attributes(path,'mode')
    print('**** CDR mode', path, mode)
  end
  if mode == 'file' or mode == 'link' then
    self.PYTHON_PATH = path
     print('**** CDR python path', self.PYTHON_PATH)
   path = path:match("^(.+/)")..'pygmentize'
   mode,_,__ = lfs.attributes(path,'mode')
   print('**** CDR path, mode', path, mode)
    if mode == 'file' or mode == 'link' then
     tex.print('true')
    else
     tex.print('false')
    end
  else
    self.PYTHON_PATH = nil
  end
end
local JSON_boolean_true = {
  __cls__ = 'BooleanTrue',
}
local JSON_boolean_false = {
  __cls__ = 'BooleanFalse',
}
local function is_truthy(s)
  return s == JSON_boolean_true or s == 'true'
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
  local s = fh:read('a')
  fh:close()
  tex.print(s)
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
local function load_exec(self, chunk)
  local env = setmetatable({ self = self, tex = tex }, _ENV)
  local func, err = load(chunk, 'coder-tool', 't', env)
  if func then
    local ok
    ok, err = pcall(func)
    if not ok then
      print("coder-util.lua Execution error:", err)
      print('chunk:', chunk)
    end
  else
    print("coder-util.lua Compilation error:", err)
    print('chunk:', chunk)
  end
end
local parse_pattern
do
  local tag = P('!') + '*' + '?'
  local stp = '>>>>>'
  local cmd = (P(1) - stp)^0
  parse_pattern = P({
    P('<<<<<') * Cg(tag) * 'LUA:' * Cg(cmd) * stp * Cp() + 1 * V(1)
  })
end
local function load_exec_output(self, s)
  local i, tag, cmd
  i = 1
  while true do
    tag, cmd, i = parse_pattern:match(s, i)
    if tag == '!' then
      self:load_exec(cmd)
    elseif tag == '*' then
      local eqs = safe_equals(cmd)
      cmd = '['..eqs..'['..cmd..']'..eqs..']'
      tex.print([[%
\directlua{CDR:load_exec(]]..cmd..[[)}%
]])
    elseif tag == '?' then
      print('\nDEBUG/coder: '..cmd)
    else
      return
    end
  end
end
local function hilight_set(self, key, value)
  local args = self['.arguments']
  local t = args
  if t[key] == nil then
    t = args.pygopts
    if t[key] == nil then
      t = args.texopts
      if t[key] == nil then
        t = args.fv_opts
        assert(t[key] ~= nil)
      end
    end
  end
  if t[key] == JSON_boolean_true or t[key] == JSON_boolean_false then
    t[key] = value == true and JSON_boolean_true or JSON_boolean_false
  else
    t[key] = value
  end
end

local function hilight_set_var(self, key, var)
  self:hilight_set(key, assert(token.get_macro(var or 'l_CDR_tl')))
end
local function hilight_source(self, sty, src)
  if not self.PYTHON_PATH then
    return
  end
  local args = self['.arguments']
  local texopts = args.texopts
  local pygopts = args.pygopts
  local inline = self.is_truthy(texopts.is_inline)
  local use_cache = self.is_truthy(args.cache)
  local use_py = false
  local cmd = self.PYTHON_PATH..' '..self.CDR_PY_PATH
  local debug = args.debug
  local pyg_sty_p
  if sty then
    pyg_sty_p = self.dir_p..pygopts.style..'.pyg.sty'
    token.set_macro('l_CDR_pyg_sty_tl', pyg_sty_p)
    texopts.pyg_sty_p = pyg_sty_p
    local mode,_,__ = lfs.attributes(pyg_sty_p, 'mode')
    if not mode or not use_cache then
      use_py = true
      if debug then
        print('PYTHON STYLE:')
      end
      cmd = cmd..(' --create_style')
    end
    self:cache_record(pyg_sty_p)
  end
  local pyg_tex_p
  if src then
    local source
    if inline then
      source = args.source
    else
      local ll = self['.lines']
      source = table.concat(ll, '\n')
    end
    local hash = md5.sumhexa( ('%s:%s:%s'
      ):format(
        source,
        inline and 'code' or 'block',
        pygopts.style
      )
    )
    local base = self.dir_p..hash
    pyg_tex_p = base..'.pyg.tex'
    token.set_macro('l_CDR_pyg_tex_tl', pyg_tex_p)
    local mode,_,__ = lfs.attributes(pyg_tex_p,'mode')
    if not mode or not use_cache then
      use_py = true
      if debug then
        print('PYTHON SOURCE:', inline)
      end
      if not inline then
        local tex_p = base..'.tex'
        local f = assert(io.open(tex_p, 'w'))
        local ok, err = f:write(source)
        f:close()
        if not ok then
          print('File error('..tex_p..'): '..err)
        end
        if debug then
          print('OUTPUT: '..tex_p)
        end
      end
      cmd = cmd..(' --base=%q'):format(base)
    end
  end
  if use_py then
    local json_p = self.json_p
    local f = assert(io.open(json_p, 'w'))
    local ok, err = f:write(json.tostring(args, true))
    f:close()
    if not ok then
      print('File error('..json_p..'): '..err)
    end
    cmd = cmd..('  %q'):format(json_p)
    if debug then
      print('CDR>'..cmd)
    end
    local o = io.popen(cmd):read('a')
    self:load_exec_output(o)
    if debug then
      print('PYTHON', o)
    end
  end
  self:cache_record(
    sty and pyg_sty_p or nil,
    src and pyg_tex_p or nil
  )
end
local function hilight_code_setup(self)
  self['.arguments'] = {
    __cls__ = 'Arguments',
    source  = '',
    cache   = JSON_boolean_true,
    debug   = JSON_boolean_false,
    pygopts = {
      __cls__ = 'PygOpts',
      lang    = 'tex',
      style   = 'default',
      mathescape   = JSON_boolean_false,
      escapeinside = '',
    },
    texopts = {
      __cls__ = 'TeXOpts',
      tags    = '',
      is_inline = JSON_boolean_true,
      pyg_sty_p = '',
    },
    fv_opts = {
      __cls__ = 'FVOpts',
    }
  }
  self.hilight_json_written = false
end
local function hilight_block_setup(self, tags_clist_var)
  local tags_clist = assert(token.get_macro(assert(tags_clist_var)))
  self['.tags clist'] = tags_clist
  self['.lines'] = {}
  self['.arguments'] = {
    __cls__ = 'Arguments',
    cache   = JSON_boolean_false,
    debug   = JSON_boolean_false,
    source  = nil,
    pygopts = {
      __cls__ = 'PygOpts',
      lang = 'tex',
      style = 'default',
      texcomments  = JSON_boolean_false,
      mathescape   = JSON_boolean_false,
      escapeinside = '',
    },
    texopts = {
      __cls__ = 'TeXOpts',
      tags    = tags_clist,
      is_inline = JSON_boolean_false,
      pyg_sty_p = '',
    },
    fv_opts = {
      __cls__ = 'FVOpts',
      firstnumber = 1,
      stepnumber  = 1,
    }
  }
  self.hilight_json_written = false
end
local function record_line(self, line_variable_name)
  local line = assert(token.get_macro(assert(line_variable_name)))
  local ll = assert(self['.lines'])
  ll[#ll+1] = line
end
local function hilight_block_teardown(self)
  local ll = assert(self['.lines'])
  if #ll > 0 then
    local records = self['.records'] or {}
    self['.records'] = records
    local t = {
      already = {},
      code = table.concat(ll,'\n')
    }
    for tag in self['.tags clist']:gmatch('([^,]+)') do
      local tt = records[tag] or {}
      records[tag] = tt
      tt[#tt+1] = t
    end
  end
end
local function export_file(self, file_name_var)
  self['.name'] = assert(token.get_macro(assert(file_name_var)))
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
  local raw = export.raw == 'true'
  local tt = {}
  local s
  if not raw then
    s = export.preamble
    if s and #s>0  then
      tt[#tt+1] = s
    end
  end
  for tag in string.gmatch(export.tags, '([^,]+)') do
    local Rs = records[tag]
    if Rs then
      for _,R in ipairs(Rs) do
        if not R.already[name] or not once then
          tt[#tt+1] = R.code
        end
        if once then
          R.already[name] = true
        end
      end
    end
  end
  if not raw then
    s = export.postamble
    if s and #s>0  then
      tt[#tt+1] = s
    end
  end
  if #tt>0 then
    local fh = assert(io.open(name,'w'))
    fh:write(table.concat(tt, '\n'))
    fh:close()
  end
  self['.name'] = nil
  self['.export'] = nil
end
local function cache_clean_all(self)
  local to_remove = {}
  for f in lfs.dir(self.dir_p) do
    to_remove[f] = true
  end
  for k,_ in pairs(to_remove) do
    os.remove(self.dir_p .. k)
  end
end
local function cache_record(self, pyg_sty_p, pyg_tex_p)
  if pyg_sty_p then
    self['.style_set']  [pyg_sty_p] = true
  end
  if pyg_tex_p then
    self['.colored_set'][pyg_tex_p] = true
  end
end
local function cache_clean_unused(self)
  local to_remove = {}
  for f in lfs.dir(self.dir_p) do
    f = self.dir_p .. f
    if not self['.style_set'][f] and not self['.colored_set'][f] then
      to_remove[f] = true
    end
  end
  for f,_ in pairs(to_remove) do
    os.remove(f)
  end
end
local _DESCRIPTION = [[Global coder utilities on the lua side]]
return {
  _DESCRIPTION       = _DESCRIPTION,
  _VERSION           = token.get_macro('fileversion'),
  date               = token.get_macro('filedate'),
  CDR_PY_PATH        = CDR_PY_PATH,
  set_python_path    = set_python_path,
  is_truthy          = is_truthy,
  escape             = escape,
  make_directory     = make_directory,
  load_exec          = load_exec,
  load_exec_output   = load_exec_output,
  record_line        = record_line,
  hilight_set        = hilight_set,
  hilight_set_var    = hilight_set_var,
  hilight_source     = hilight_source,
  hilight_code_setup = hilight_code_setup,
  hilight_block_setup    = hilight_block_setup,
  hilight_block_teardown = hilight_block_teardown,
  cache_clean_all    = cache_clean_all,
  cache_record       = cache_record,
  cache_clean_unused = cache_clean_unused,
  ['.style_set']     = {},
  ['.colored_set']   = {},
  ['.options']       = {},
  ['.export']        = {},
  ['.name']          = nil,
  already            = false,
  dir_p              = dir_p,
  json_p             = json_p,
  export_file        = export_file,
  export_file_info   = export_file_info,
  export_complete    = export_complete,
}
