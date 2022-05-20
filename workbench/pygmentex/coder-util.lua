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
local json  = require('lualibs-util-jsn')
local ltb = _ENV.luatexbase
local ltb_add_to_callback      = ltb.add_to_callback
local ltb_remove_from_callback = ltb.remove_from_callback
local lpeg  = require("lpeg")
local C       = lpeg.C
local Cg      = lpeg.Cg
local Cp      = lpeg.Cp
local Ct      = lpeg.Ct
local P       = lpeg.P
local V       = lpeg.V
ltb.provides_module{
  name = 'coder',
  date = token.get_macro('CDRFileDate'),
  version = token.get_macro('CDRFileVersion'),
  description = 'Code inside LaTeX, LaTeX inside code',
}
local CDR = {}
local TEST = {}
local utf8  = _ENV.unicode.utf8
local PYTHON_PATH, PYGMENTIZE_PATH
local CDR_PY_PATH = kpse.find_file('coder-tool.py')
local function f_noop (...)
end
local debug_msg = f_noop
local function f_debug_msg (...)
  local s = token.get_macro('CurrentFile')
  if #s == 0 then
    s = tex.jobname
  end
  print('*--* CDR:'..s..':'..tostring(tex.inputlineno)..':', ...)
end
TEST.debug_msg = function(...)
  debug_msg(...)
end
function CDR:debug_activate(yorn)
  if yorn then
    debug_msg = f_debug_msg
  else
    debug_msg = f_noop
  end
  self.debug_active = yorn
end
function CDR:test_activate(yorn)
  if yorn then
    self.TEST = TEST
  else
    self.TEST = nil
  end
end
function CDR.debug(...)
  debug_msg(...)
end
function CDR.print_now(...)
  local args = {...}
  tex.runtoks(function ()
    tex.print(table.unpack(args))
  end)
end
function CDR.sprint_now(...)
  local args = {...}
  tex.runtoks(function ()
    tex.sprint(table.unpack(args))
  end)
end
function CDR.run_toks(cctab, ...)
  local s = ''
  if type(cctab) == 'string' then
    s = cctab
    cctab = 0
  end
  for _,ss in ipairs({...}) do
    s = s .. ss
  end
  tex.scantoks('CDR@toks',cctab,s);
  tex.runtoks('CDR@toks');
end
do
  local function map(t,f)
    local tt = {}
    for k,v in pairs(t) do
      tt[k] = f(v)
    end
    return tt
  end
  local flows = {}
  local last = 1.0
  function CDR:flow_go__(key)
debug_msg('FLOW GO ', key)
    local flow = flows[key]
    flow.already__ = 1
    coroutine.resume(flow.co__, table.unpack(flow.args__ or {}))
  end
  function CDR:flow_resume__(key)
    local flow = flows[key]
debug_msg('FLOW RESUME '..key..'/'..flow.already__..'/'..table.concat(map(flow.args__,tostring) or {}, ","))
    coroutine.resume(flow.co__)
  end
  function CDR:flow_terminate__(key)
    local flow = flows[key]
    flow.key__ = nil
    flow.already__ = -1
    flows[key] = nil
debug_msg('FLOW TERMINATE '..key)
  end
  function CDR:flow_create (f)
    local key = last
    last = last+1.0
debug_msg('2 -> 9: FLOW CREATE '..key)
    local flow = {
      already__ = 0,
      key__ = key,
    }
    flows[key] = flow
    flow.co__ = coroutine.create(function (...)
debug_msg('4 -> 9: ENTER '..key..'/'..table.concat(map({...},tostring), ","))
      local ans = { f(...) }
debug_msg('EXIT '..key..'/')
      tex.sprint([[\directlua]]..'{CDR:flow_terminate__('..key..')}')
      return table.unpack(ans)
    end)
    function flow.go (this, ...)
      if this.key__ == nil then
        tex.sprint([[\CDRPackageError]]
          ..'{Going a flow twice is not supported}'
          ..'{Internal error, please report}'
        )
        return
      end
      if this.already__>0 then
debug_msg('6 -> 9: GO '..this.key__..'/'..this.already__..'/'..table.concat(map(this.args__, tostring) or {}, ","))
        tex.print([[\directlua]]..'{CDR:flow_resume__('..this.key__..')}')
        coroutine.yield()
      elseif this.already__ < 0 then
debug_msg('? -> 9: GO '..this.key__..'/'..this.already__..'/'..table.concat(map(this.args__,tostring) or {}, ","))
debug_msg('CDR: Already gone '..this.key__..'/')
      elseif this.args__ then
        tex.sprint([[\CDRPackageError]]
          ..'{Going a flow twice is not supported}'
          ..'{Internal error, please report}'
        )
      else
        this.args__ = { ... }
debug_msg('3 -> WILL GO '..this.key__..'/'..this.already__..'/'..table.concat(map(this.args__,tostring), ","))
        tex.sprint(-1,[[\directlua]]..'{CDR:flow_go__('..this.key__..')}')
      end
    end
    return flow
  end
end
local function callback_push(callback_name, callback, description)
debug_msg('callback_push', callback_name, description)
  local saved = {}
  for _,d in pairs(
    ltb.callback_descriptions(callback_name)
  ) do
    local v = ltb_remove_from_callback(callback_name, d )
    saved[d] = v
    break
  end
  ltb_add_to_callback(callback_name, callback, description)
  local fired
  return function ()
debug_msg('exclusive_callback_pop', callback_name, description)
    if not fired then
      fired = true
      local f, d = ltb_remove_from_callback(callback_name, description )
      for k, v in pairs(saved) do
        ltb_add_to_callback(callback_name, v, k)
      end
      return f, d
    end
  end
end
TEST.callback_push = callback_push
function CDR:set_python_path(path_var)
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
    PYTHON_PATH = path
    print('**** CDR python path', PYTHON_PATH)
    path = path:match("^(.+/)")..'pygmentize'
    mode,_,__ = lfs.attributes(path,'mode')
    print('**** CDR path, mode', path, mode)
    PYGMENTIZE_PATH = path
    if mode == 'file' or mode == 'link' then
      tex.sprint('true')
    else
      tex.sprint('false')
    end
  else
    PYTHON_PATH = nil
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
CDR.is_truthy = is_truthy
function CDR.escape(s)
  s = s:gsub(' ','\\ ')
  s = s:gsub('\\','\\\\')
  s = s:gsub('\r','\\r')
  s = s:gsub('\n','\\n')
  s = s:gsub('"','\\"')
  s = s:gsub("'","\\'")
  return s
end
function CDR.make_directory(path)
  local mode,_,__ = lfs.attributes(path,"mode")
  if mode == "directory" then
    return true
  elseif mode ~= nil then
    return nil,path.." exist and is not a directory",1
  end
  if os["type"] == "windows" then
    path = path:gsub("/", "\\")
    _,_,__ = os.execute(
      "if not exist "  .. path .. "\\nul " .. "mkdir " .. ("%q"):format(path)
    )
  else
    _,_,__ = os.execute("mkdir -p "..("%q"):format(path))
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
if CDR.make_directory(dir_p) == nil then
debug_msg('No directory', dir_p)
  CDR.can_clean = false
  dir_p = './'
  json_p = dir_p..jobname..'.pyg.json'
else
  CDR.can_clean = true
  json_p = dir_p..'input.pyg.json'
end
CDR.dir_p = dir_p
CDR.json_p = json_p
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
function CDR:load_exec(chunk)
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
function CDR:load_exec_output(s)
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
local inline_by_id = {}
function CDR:Code_list_all()
  print('**** CDR INFO: known Codes ***********')
  for k, v in pairs(inline_by_id) do
    print(k, '->', v)
  end
  print('**************************************')
end
local lines_by_id = {}
function CDR:Block_list_all()
  print('**** CDR INFO: known Blocks **********')
  for k, v in pairs(lines_by_id) do
    print(k, '->', v .. 'lines')
  end
  print('**************************************')
end
local Object = setmetatable({}, {
  __index = function (self, k)
    local ans
    if k == 'id' then
      ans = token.get_macro('l_CDR_id_tl')
    elseif k == 'delimiters' then
      ans = token.get_macro('l_CDR_delimiters_tl')
    elseif k == 'id_short' then
      ans = token.get_macro('l_CDR_id_short_tl')
    end
-- debug_msg('Object MT __index', k, ans)
    return ans
  end,
})
Object.__index = Object
TEST.Object = Object
local Code = setmetatable({}, {
  __index = Object
})
TEST.Code = Code
function Code:__index (k)
-- debug_msg('Code:__index', k)
  if k == 'inline' then
    return inline_by_id[self.id]
  elseif k == '.arguments' then
    local ans = {
      __cls__ = 'Arguments',
      source  = '',
      cache   = JSON_boolean_true,
      debug   = JSON_boolean_false,
      pygopts = {
        __cls__ = 'PygOpts',
        lang    = 'tex',
        style   = 'default',
        mathescape   = JSON_boolean_false,
        escapeinside = self.delimiters,
      },
      texopts = {
        __cls__ = 'TeXOpts',
        tags    = '',
        is_inline = JSON_boolean_true,
        pyg_sty_p = '',
        synctex_tag  = 0,
        synctex_line = 0,
      },
    }
    rawset(self, k, ans)
    return ans
  end
  return Code[k]
end
function Code:__newindex (k, v)
-- debug_msg('Code:__newindex', k, v)
  if k == 'inline' then
-- debug_msg('Setting inline')
    inline_by_id[self.id] = v
  else
    rawset(self, k, v)
  end
end
function Code:inline_save ()
  inline_by_id[self.id] = token.get_macro('l_CDR_peek_tl')
debug_msg('Code:inline_save', self.id, '->', inline_by_id[self.id])
end
function Code:sprint_known()
  if self.inline then
    tex.sprint('T')
  end
end
local sprint_active_f = function(s)
  tex.sprint(CDR.active_cctab, s)
end
local sprint_escape_f = function(s)
  tex.sprint(CDR.escape_cctab, s)
end
function Code:sprint_inline ()
  self:escape_inside_maker{
    active_f   = sprint_active_f,
    escape_f   = sprint_escape_f,
    alter_f    = f_noop,
  } ( self.inline or '' )
end
function Code:inline_to_ltx (mode)
  local cctab
  if mode == 'string' then
    cctab = CDR.string_cctab
  elseif mode == 'active' then
    cctab = CDR.active_cctab
  else
    cctab = -1
  end
  token.set_macro(
    cctab,
    self.id,
    self.inline or ''
  )
end
function Code:sprint_inline_string ()
  tex.sprint(CDR.string_cctab, self.inline or '')
end
function Code:sprint_inline_active ()
  tex.sprint(CDR.string_active, self.inline or '')
end
function Code:sprint_inline_escaped ()
  tex.sprint(CDR.string_escaped, self.inline or '')
end
function Code:peek_active_begin ( delimiter )
  local pop = callback_push (
    'process_input_buffer',
    function (input)
      if input then
        function self.status(this)
          tex.print('error')
        end
        return delimiter..input
      end
    end,
    'CDRCode',
    1
  )
  self.peek_active_end = function (this)
    pop()
  end
end
function Code:peek_active_end ()
  error('Build time error: unexpected Code.peek_active_end')
end
Code.status = f_noop
function CDR:Code_new()
  self.Code = setmetatable({
    ['..Code'] = self.Code,
    ['..Code_free'] = rawget(self, 'Code_free'),
  }, Code)
  self.Code_free = function (this)
    this.Code_free = this.Code['Code_free']
    this.Code = this.Code['..Code']
  end
end
function Code_free (self)
  error('Build time error: unexpected Code_free')
end
local Block = setmetatable({}, {
  __index = Object,
})
TEST.Block = Block
function Block:__index(k)
  local ans
  if k == 'lines' then
    ans = lines_by_id[self.id]
-- debug_msg('Block MT __index', k, self.id, ans)
    return ans
  elseif k == 'env' then
    ans = token.get_macro('@currenvir')
-- debug_msg('Block MT __index', k, ans)
    rawset(self, k, ans)
    return ans
  elseif k == 'gobble' then
    ans = token.get_macro('l_CDR_gobble_tl')
    return ans
  elseif k == '.arguments' then
    ans = {
      __cls__ = 'Arguments',
      cache = JSON_boolean_false,
      debug = JSON_boolean_false,
      pygopts = {
        __cls__ = 'PygOpts',
        lang = 'tex',
        style = 'default',
        texcomments= self.tex_comments
          and JSON_boolean_true
          or JSON_boolean_false,
        mathescape = JSON_boolean_false,
        escapeinside = self.delimiters,
      },
      texopts = {
        __cls__ = 'TeXOpts',
        tags  = self['.tags clist'],
        is_inline = JSON_boolean_false,
        pyg_sty_p = '',
        synctex_tag= 0,
        synctex_line = 0,
      },
    }
    rawset(self, k, ans)
    return ans
  end
  return Block[k]
end
function Block:__newindex(k, v)
-- debug_msg('Block:__newindex', k, v)
  if k == 'lines' then
-- debug_msg('Setting lines')
    lines_by_id[self.id] = v
  else
    rawset(self, k, v)
  end
end
function CDR:Block_new()
  self.Block = setmetatable({
    ['..Block'] = self.Block,
    ['..Block_free'] = rawget(self, 'Block_free'),
  }, Block)
  self.Block_free = function (this)
    this.Block_free = this.Block['..Block_free']
    this.Block = this.Block['..Block']
  end
end
function CDR:Block_free()
  error('Buid time error: unexpected Block_free')
end
function Block:save_begin ()
  local env = assert(self.env)
  local safe_env = env:gsub('[%%%^%$%(%)%.%[%]%*%+%-%?]', '%%%0')
debug_msg('Block:save_begin, environment name:', env, safe_env)
  local lines = {}
  self.lines = lines
  assert(lines == self.lines)
  local f_current
  local pop = callback_push (
    'process_input_buffer',
    function (input)
      if input then
        return f_current(input)
      else
        return ([[\CDRPackageError{Missing `\end{%s}'}{See %s documentation }]]):format(env, env)
      end
    end,
    'CDRBlock',
    1
  )
  if debug_msg ~= f_debug_msg then
    ltb_add_to_callback (
      'process_input_buffer',
      function (input)
        debug_msg('BUFFER:', '<'..input..'>')
        return input
      end,
      'CDRBlockDebug',
      1
    )
  end
  local function remove_from_callback ()
    if ltb.in_callback('process_input_buffer', 'CDRBlockDebug') then
      ltb_remove_from_callback(
        'process_input_buffer',
        'CDRBlockDebug'
      )
    end
    pop()
  end
  local f_start, f_options, f_body, f_line
  f_line = function (input)
    lines[#lines+1] = input
    return [[\relax]]
  end
  f_start = function (input)
debug_msg('CALLBACK:IN_START', '<'..input..'>')
    f_current = f_line
    token.set_char('l_CDR_before_eol_bool', 0)
    if input:match([[^%s*\end%s*]]
      ..'{'..safe_env..'}') then
debug_msg('WILL remove_from_callback')
      remove_from_callback()
debug_msg('SCAN:end', '<'..input..'>')
      return input
    else
debug_msg('CALLBACK:START', '<'..input..'>')
      return f_line(input)
    end
  end
  f_current = f_start
  f_options = function (input)
debug_msg('CALLBACK:IN_OPTIONS', '<'..input..'>')
    local d, v, b = input:match([[^%s*(\\end)%s*]]
      ..'({'..safe_env..'})'..[[([^%]*)]])
    if d then
      remove_from_callback()--[
debug_msg('CALLBACK:END', '<'..input..'>')
      return ']'
        ..d..v
        ..[[\CDRPackageError]]
        ..[[{Unterminated\space options}]]
        ..'{'..[[a\space]]--}[
        ..']'
        ..[[\space is\space missing\space]]
        ..[[before\space\end]]..'{'..env..'}'--{
        ..'}'
        ..b
    else
      return input
    end
  end
  f_body = function (input)
debug_msg('CALLBACK:IN_BODY', '<'..input..'>')
    token.set_char('l_CDR_before_eol_bool', 0)
    if input:match([[^%s*\end%s*]]
      ..'{'..safe_env..'}') then
debug_msg('WILL remove_from_callback 2', [[\relax]]..input)
      remove_from_callback()
      return [[\relax]]..input
    else
      lines[#lines+1] = input
      return [[\relax]]
    end
  end
  self.enter_body = function (this)
debug_msg('Block:enter_body')
    debug_msg('Block.enter_body')
    f_current = f_body
  end
  self.enter_options = function (this)
debug_msg('Block:enter_options')
    f_current = f_options
  end
  self.exit_options = function (this)
debug_msg('Block:exit_options')
    f_current = f_body
  end
  self.save_end = function (this)
    debug_msg('Block:save_end... DONE')
  end
debug_msg('Block:save_begin... DONE')
end
function Block:save_end ()
  error('Buid time error: unexpected save_end')
end
function Block:enter_body ()
  error('Buid time error: unexpected enter_body')
end
function Block:enter_options ()
  error('Buid time error: unexpected enter_options')
end
function Block:exit_options ()
  error('Buid time error: unexpected exit_options')
end
function Block:sprint_known ()
  if self.lines then
    tex.sprint('T')
  end
end
function Block:sprint_count ()
  local lines = self.lines
  local ans = lines and #lines or -1
  tex.sprint(''..ans)
end
function Block:pre_setup ()
  local gobble = self.gobble
  local escape_inside = self:escape_inside_maker{
    active_f   = sprint_active_f,
    escape_f   = sprint_escape_f,
    alter_f    = f_noop,
  }
  self.sprint_line_ltx2 = function(this, n)
    CDR.sprint_escape([[\color{magenta!50!black}\bfseries ABCD]])
    CDR.sprint_string([[FAKE]])
  end
  self.sprint_line_ltx = function(this, n)
    local l = this.lines[n]
    l = utf8.sub(l, 1+gobble)
    if #l == 0 then
      return
    end
    escape_inside(l)
  end
end
function Block:print_line_raw (n)
  tex.print(CDR.string_cctab, self.lines[n])
end
function Block:print_line_active (n)
  tex.print(CDR.active_cctab, self.lines[n])
end
function Block:print_line_escape (n)
  error('Build time error: unexpected print_line')
end
function Block:sprint_line_ltx (n)
  error('Build time error: unexpected sprint_line_ltx')
end
function Block:sprint_comment_ltx ()
  error('Build time error: unexpected sprint_comment_ltx')
end
function Block:exe_makeatletter (torf)
  if torf ~= false then
    tex.print([[\makeatletter]])
    self.exe_makeatother = function (this)
      tex.print([[\makeatother]])
    end
  end
end
function Block:exe_makeatother ()
end
function Block:exeExplSyntaxOn (yorn)
  if yorn ~= false then
    tex.print([[\ExplSyntaxOn]])
    self.exeExplSyntaxOff = function (this)
      tex.print([[\ExplSyntaxOff]])
    end
  end
end
function Block:exeExplSyntaxOff ()
end
local function input_virtual_file (reader_f, close_f)
  local pop_frf = callback_push(
    'find_read_file',
    function (id_number, asked_name)
      return asked_name
    end,
    'CDRInputVirtualFile'
  )
  local pop_orf
  pop_orf = callback_push(
    'open_read_file',
    function (file_name)
debug_msg('CDRInputVirtualFile open_read_file', file_name)
      return {
        reader = function(env)
          if env.close == nil then
            env.close = function (this)
debug_msg('CDRInputVirtualFile close', file_name)
              if close_f then
                close_f(this)
              end
              this:did_close()
            end
          end
          return reader_f(env)
        end,
        did_close = function (env)
          pop_orf()
          pop_frf()
        end,
      }
    end,
    'CDRInputVirtualFile'
  )
  tex.print([[\input{...}]])
end
function Block:exe_begin ()
  self.exe_end = function (this)
    if #this.lines == 0 then
      return
    end
    local i = 0
    local lines = { table.unpack(this.lines) }
    input_virtual_file(
      function(env)
        i = i+1
        return lines[i]
      end
    )
  end
end
function Block:exe_end ()
  error('Build time error: unexpected exe_end')
end
function Object:pyg_set(kvargs)
  assert(kvargs, 'Missing required table argument')
  local args = self['.arguments']
  for key, value in pairs(kvargs) do
    local t = args
    if t[key] == nil then
      t = args.pygopts
      if t[key] == nil then
        t = args.texopts
        assert(t[key])
      end
    end
debug_msg('pyg_set', key, value)
    if t[key] == JSON_boolean_true or t[key] == JSON_boolean_false then
      t[key] = value == 'true' and JSON_boolean_true or JSON_boolean_false
    else
      t[key] = tostring(value)
    end
  end
end
function Object:pyg_set_var(key, var)
  self:pyg_set{
    [key] = assert(token.get_macro(var or 'l_CDR_a_tl'))
  }
end
function Object:pyg_source(sty, src)
debug_msg('pyg_source', sty, src)
  if not PYTHON_PATH then
    return
  end
  local args = self['.arguments']
  local texopts = args.texopts
  local pygopts = args.pygopts
  local inline = is_truthy(texopts.is_inline)
  local use_cache = is_truthy(args.cache)
  local use_py = false
  local cmd = PYTHON_PATH..' '..CDR_PY_PATH
  local debug = is_truthy(args.debug)
  if debug then
    cmd = cmd..' --debug'
  end
  local pyg_sty_p
  if sty then
    pyg_sty_p = CDR.dir_p..pygopts.style..'.pyg.sty'
    token.set_macro(-2, 'l_CDR_pyg_sty_tl', pyg_sty_p)
debug_msg('pyg_source: sty', token.get_macro('l_CDR_pyg_sty_tl'))
    texopts.pyg_sty_p = pyg_sty_p
    local mode,_,__ = lfs.attributes(pyg_sty_p, 'mode')
    if not mode or not use_cache then
      use_py = true
      if debug then
        print('PYTHON STYLE:')
      end
      cmd = cmd..(' --create_style')
    end
    CDR:cache_record(pyg_sty_p)
  end
  local pyg_tex_p
  if src then
    local ds = self.delimiters
    local n = utf8.len(ds)
    local l = n>0 and utf8.sub(ds, 1, 1) or ''
    local m = n>1 and utf8.sub(ds, 2, 2) or ''
    local r = n>2 and utf8.sub(ds, 3, 3) or nil
    local gobble = self.gobble
    local s
    local escape_inside = self:escape_inside_maker{
      active_f = function (ss)
        s = s .. ss
      end,
      escape_f = function (ss)
        s = s .. l .. ss .. (r or m )
      end
    }
    local source
    if inline then
      s = ''
      escape_inside(self.inline or '')
      source = s
      args.source = source
    else
      local lines = {}
      local gobble = self.gobble
      for _,l in ipairs(lines_by_id[self.id]) do
        s = ''
        escape_inside(utf8.sub(l, 1+gobble))
        lines[#lines+1] = s
      end
      source = table.concat(lines, '\n')
debug_msg('pyg_source', '<'..self.id..'>', lines, #lines)
    end
    local hash = md5.sumhexa( ('%s:%s:%s'
      ):format(
        source,
        inline and 'code' or 'block',
        pygopts.style
      )
    )
    local base = CDR.dir_p..hash
    pyg_tex_p = base..'.pyg.tex'
    token.set_macro(-2, 'l_CDR_pyg_tex_tl', pyg_tex_p)
debug_msg('pyg_source: sty', token.get_macro('l_CDR_pyg_tex_tl'))
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
debug_msg('JSON', json_p, json.tostring(args, true))
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
    CDR:load_exec_output(o)
    if debug then
      print('PYTHON', o)
    end
  elseif debug then
    print('SAVED>'..cmd)
  end
  CDR:cache_record(
    sty and pyg_sty_p or nil,
    src  and pyg_tex_p or nil
  )
end
function Code:pyg_setup()
  self.pyg_json_written = false
end
function Code:pyg_teardown()
  self:synctex_restore()
end

function Block:pyg_setup (tags_clist_var)
debug_msg('Block:pyg_setup')
  self['.tags clist'] = assert(
    token.get_macro(assert(tags_clist_var))
  )
  self.pyg_json_written = false
end
local records_by_tag = {}
local function escape_inside_old (text, delimiters)
  local i = 1
  local t = {}
  local r
  if delimiters:len() == 2 then
    r = '(.-)['..delimiters:sub(1,1)..'].-['
      ..delimiters:sub(2,2)..']()'
    for a, next_i in text:gmatch(r) do
      t[#t+1] = a
      i = next_i
    end
  elseif delimiters:len() == 3 then
    r = '(.-)['..delimiters:sub(1,1)..'].-['
      ..delimiters:sub(2,2)..'](.-)['
      ..delimiters:sub(3,3)..']()'
    for a, b, next_i in text:gmatch(r) do
      t[#t+1] = a
      t[#t+1] = b
      i = next_i
    end
  end
  if i > 1 then
    t[#t+1] = text:sub(i,-1)
    return table.concat(t,'')
  end
  return text
end
function Object:escape_inside_maker (kvargs)
  local p_1 = P(1)
  local pattern
  local escape_f  = kvargs.escape_f
  local do_escape = escape_f and function (s)
debug_msg('do_escape =', s)
    if #s>0 then
      return { escape_f, s }
    end
  end or f_noop
  local alter_f   = kvargs.alter_f
  local do_alter = alter_f and function (s)
debug_msg('do_alter =', s)
    if #s>0 then
      return { alter_f, s }
    end
  end or f_noop
  local active_f  = kvargs.active_f
  local do_active = active_f and function (s)
debug_msg('do_active =', s)
    if #s>0 then
      return { active_f, s }
    end
  end or f_noop
  local ds = self.delimiters
  local n = utf8.len(ds)
  if n>0 then
    local p_l = assert(P(utf8.sub(ds, 1, 1)))
    local p_u = C((p_1 - p_l)^0) / do_active
    local p_e
    if n>1 then
      local p_m = P(utf8.sub(ds, 2, 2))
      if n > 2 then
        local p_r = P(utf8.sub(ds, 3, 3))
        p_e = p_l
            * C((p_1 - p_m - p_r)^0) / do_escape
            * ( p_m * C((p_1 - p_r)^0) / do_alter )^-1
            * p_r^-1
      else
        p_e = p_l
            * C((p_1 - p_m)^0) / do_escape
            * p_m^-1
      end
      pattern = p_u * ( p_e * p_u )^0
    else
      p_e = p_l * C(p_1^0) / do_escape
      pattern = p_u * p_e^0
    end
  else
    pattern = C(p_1^0) / do_active
  end
  pattern = Ct( pattern )
  return function (l)
    local t = pattern:match(l)
debug_msg(t, #t)
    for _,v in ipairs(t) do
      v[1](v[2])
    end
  end
end
function Block:pyg_teardown()
  local ll = self.lines
  if #ll > 0 then
    local s
    local append_f = function (text)
      s = s..text
    end
    local escape_inside = self:escape_inside_maker {
      active_f   = append_f,
      escape_f   = f_noop,
      alter_f    = append_f,
    }
    local code
    local t = {}
    for _,l in ipairs(ll) do
      s = ''
      t[#t+1] = escape_inside(l)
    end
    code = table.concat(t,'\n')
    t = {
      already = {},
      code = code
    }
    for tag in self['.tags clist']:gmatch('([^,]+)') do
      local tt = records_by_tag[tag] or {}
      records_by_tag[tag] = tt
      tt[#tt+1] = t
    end
  end
end
function CDR:export_file(file_name_var)
  local name = assert(token.get_macro(assert(file_name_var)))
  local export = {
    preamble = {},
    postamble = {},
  }
  function self.export_file_info(_, key, value)
    value = assert(token.get_macro(assert(value)))
    if export[key] == JSON_boolean_true or export[key] == JSON_boolean_false then
      export[key] = (value == 'true') and JSON_boolean_true or JSON_boolean_false
    else
      export[key] = value
    end
  end
  function self.append_file_info(_, key, value)
    local t = export[key]
    value = assert(token.get_macro(assert(value)))
    t[#t+1] = value
  end
  function self.export_complete(this)
    local raw  = export.raw  == 'true'
    local once = export.once == 'true'
    local tags = export.tags
    local tt = {}
    local s, _
print('**** CDR', tags, raw, once)
    if not raw then
      s = export.preamble
      for _,t in ipairs(s) do
        tt[#tt+1] = t
      end
    end
    for tag in string.gmatch(export.tags, '([^,]+)') do
      local Rs = records_by_tag[tag]
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
      for _,t in ipairs(s) do
        tt[#tt+1] = t
      end
    end
print('**** CDR', name, #tt)
    if #tt>0 then
      if #tt[#tt] > 0 then
        tt[#tt+1] = ''
      end
      local fh = assert(io.open(name,'w'))
      fh:write(table.concat(tt, '\n'))
      fh:close()
    end
    this.export_file_info = nil
    this.append_file_info = nil
    this.export_complete = nil
  end
end
function Object:synctex_tag_set(tag)
debug_msg('Object.synctex_tag_set', tag)
  if assert(tag, 'Unexpected nil tag') > 0 then
    self.synctex_tag  = tag
  end
end
function CDR:synctex_tag_set(tag)
  if CDR.Block then
    CDR.Block:synctex_tag_set(tag)
  elseif CDR.Code then
    CDR.Code:synctex_tag_set(tag)
  end
end
function Object:synctex_line_set(line)
debug_msg('Object.synctex_line_set', line)
  if line >= 0 then
    self.synctex_line  = line
  end
end
function CDR:synctex_line_set(tag)
  if CDR.Block then
    CDR.Block:synctex_line_set(tag)
  elseif CDR.Code then
    CDR.Code:synctex_line_set(tag)
  end
end
function Object:synctex_save(offset)
  self:synctex_tag_set(tex.get_synctex_tag())
  self:synctex_line_set(tex.inputlineno+(offset or 0))
  self.synctex_mode = tex.get_synctex_mode()
  tex.set_synctex_mode(1)
end
function Object:synctex_restore()
  tex.force_synctex_tag(self.synctex_tag)
  tex.force_synctex_line(self.synctex_line)
  tex.set_synctex_mode(self.synctex_mode)
  self.synctex_tag = 0
  self.synctex_line = 0
end
function Object:synctex_target_set(line_number)
debug_msg('Object.synctex_target_set', self.synctex_tag, self.synctex_line, line_number )
  tex.force_synctex_tag( self.synctex_tag )
  tex.force_synctex_line(self.synctex_line + line_number )
end
local synctex_storage = {}
function Object:synctex_store(offset)
  self:synctex_save( offset )
  local storage = synctex_storage[self.id] or {}
  synctex_storage[self.id] = storage
  storage.tag = self.synctex_tag
  storage.line = self.synctex_line
  self:synctex_restore()
end
function Object:synctex_get(key)
  local storage = synctex_storage[self.id] or {}
  local ans = storage[key]
  if ans then
    return ans
  end
  local f = ({
    tag  = tex.get_synctex_tag,
    line = tex.get_synctex_line,
  })[key]
  if f then
    return f()
  end
  return 0
end
function Object:synctex_sprint_tag( )
  tex.sprint(self:synctex_get('tag'))
end
function Object:synctex_sprint_line( )
  tex.sprint(self:synctex_get('line'))
end
function Object:synctex_obey_lines()
  local storage = synctex_storage[self.id] or {}
  synctex_storage[self.id] = storage
  storage.line = 0
end
function CDR:cache_clean_all()
  if not self.can_clean then
    return
  end
  local to_remove = {}
  for f in lfs.dir(dir_p) do
    to_remove[f] = true
  end
  for k,_ in pairs(to_remove) do
    os.remove(dir_p .. k)
  end
end
local style_set = {}
local colored_set = {}
function CDR:cache_record(pyg_sty_p, pyg_tex_p)
  if pyg_sty_p then
    style_set  [pyg_sty_p] = true
  end
  if pyg_tex_p then
    colored_set[pyg_tex_p] = true
  end
end
function CDR:cache_clean_unused()
  if not self.can_clean then
    return
  end
debug_msg('CACHE CLEAN UNUSED', dir_p)
  local to_remove = {}
  for f in lfs.dir(dir_p) do
    f = dir_p .. f
    if not style_set[f] and not colored_set[f] then
      to_remove[f] = true
    end
  end
  for f,_ in pairs(to_remove) do
debug_msg('OS.REMOVE', f)
    os.remove(f)
  end
end
function CDR:import_driver_get(args)
  local name = args.driver
debug_msg('import_driver_get', name)
  local path
  if name:match('%.lua$') then
    path = kpse.find_file(name)
  else
    path = kpse.find_file('coder-driver-'..name..'.lua')
  end
debug_msg('import_driver_get', path)
  local f, err = loadfile(path)
  if not f then
    tex.print([[\CDRPackageError]]..'{Bad driver '
      ..name..'}{'..err..'}'
    )
    return
  end
  local status, driver = pcall(f)
  if status then
    if driver.setup then
      driver:setup(args)
    end
    driver.debug_msg = debug_msg
    return driver
  end
  tex.print([[\CDRPackageError]]..'{Syntax error in '
    ..path..'}{'..driver..'}'
  )
end
function Block:synctex_tag_catch(path)
debug_msg('synctex_tag_catch...', path)
  self:synctex_save()
  local pop = callback_push(
    'open_read_file',
    function (file_name)
debug_msg('synctex_tag_catch open_read_file', file_name)
      return {
        reader = function ()
debug_msg('synctex_tag_catch reader', tex.get_synctex_tag())
          self.synctex_tag_catched = tex.get_synctex_tag()
        end,
      }
    end,
    'CDRTagCatch'
  )
debug_msg('synctex_tag_catch... runtoks BEFORE INPUT')
  tex.runtoks(function ()
    debug_msg('BEFORE INPUT')
  end)
  CDR.run_toks('\\input{'..path..'}');
debug_msg('synctex_tag_catch... runtoks AFTER INPUT')
  tex.runtoks(function ()
    debug_msg('AFTER INPUT')
  end)
  pop()
  self:synctex_restore()
debug_msg('synctex_tag_catched... DONE', path,  self.synctex_tag_catched)
end
function Block:import_begin()
debug_msg('import_begin.......................................')
  token.set_macro('l_CDR_status_tl','')
  local args = {
    source = assert(token.get_macro('l_CDR_input_tl')),
    driver = assert(token.get_macro('l_CDR_driver_tl')),
    first_line = 1,
    last_line  = 0,
    show_code  = true,
    show_doc   = true,
  }
debug_msg('import_begin... DRIVER?')
  local d = CDR:import_driver_get(args)
  if not d then
    token.set_macro('l_CDR_status_tl', 'FAILED')
    return
  end
  local lines = {}
  local source = args.source
  local f = io.open(source)
  if not f then
    source = kpse.find_file(source)
    if source then
      f = io.open(source)
    end
    if not f then
      token.set_macro('l_CDR_status_tl', 'FAILED')
      tex.print([[\CDRPackageError]]..'{No source '
      ..args.source..
      '}'..[[{See \string\CDRBlockImport.}]])
      return
    end
  end
  for l in f:lines() do
    lines[#lines+1] = l
  end
  f:close()
debug_msg('\\CDRBlockImport raw file:', source, #lines)
  self.import_set_boolean = nil
  self:synctex_save()
  self.synctex_save = f_noop
  self.synctex_restore = f_noop
  local MT = {
    append = function (this, line)
      this.lines[#this.lines+1] = line
    end
  }
  local current
  local all = {}
  local function fi_code_new (n)
    current = setmetatable({
      is_code = true,
      n = n,
      lines = {},
    }, { __index = MT
    })
    all[#all+1] = current
  end
  local function fi_doc_new (n)
    current = setmetatable({
      is_doc = true,
      n = n,
      lines = {},
    }, { __index = MT
    })
    all[#all+1] = current
  end
  self:synctex_tag_set(self.synctex_tag_catched+1)
  self:synctex_line_set(0)
  local make_reader = function ()
    if #all == 0 then
      if args.first_line <= 0 then
        args.first_line = #lines + args.first_line
      end
      if args.last_line <= 0 then
        args.last_line = #lines + args.last_line
      end
debug_msg('\\CDRBlockImport make_reader', #lines,  args.first_line, args.last_line)
      fi_code_new(args.first_line)
      local depth = 0
      for i = args.first_line, args.last_line do
debug_msg('\\CDRBlockImport reader original', i, lines[i], d.open, d.close)
        local l = lines[i]
        if d.open and d:open(l) then
debug_msg('OPEN')
          depth = depth + 1
          if current.is_code then
            fi_doc_new(i)
          end
        elseif d.close and d:close(l) then
debug_msg('CLOSE')
          if depth > 0 then
            depth = depth - 1
          else
            tex.print([[\CDRPackageError]]..'{No source '
              ..args.source..
              '}'..[[{See \string\CDRBlockImport.}]])
            self.flow:go()
          end
          if depth == 0 then
            fi_code_new(i+1)
          end
        else
debug_msg('CONTINUE')
          current:append(l)
        end
      end
      if depth>0 then
        tex.sprint([[\CDRPackageError]]
          ..'{Unbalanced comments in '
          ..args.source..
          '}'..[[{See \string\CDRBlockImport.}]])
        self.flow:go()
      end
      local t = {}
      for _,tt in ipairs(all) do
        for _,line in ipairs(tt.lines) do
          if #line > 0 then
            t[#t+1] = tt
            break
          end
        end
      end
      all = t
      t = {}
      for _,tt in ipairs(all) do
        if tt.is_code then
          t[#t+1] = [[\begin{CDRBlock}]]
            ..'[first number='..(tt.n)..', obey lines, no export]'
          for _,line in ipairs(tt.lines) do
            t[#t+1] = line
          end
          t[#t+1] = [[\end{CDRBlock}]]
        else
          for i,l in ipairs(tt.lines) do
            local w, b = l:match("^(%s*)(.*)$")
            t[#t+1] = w..'\\SyncTeXLC{'..(i+tt.n)..'}{}'..b
          end
        end
      end
      all = t
      if CDR.debug_active then
        debug_msg('\\CDRBlockImport READER', #all)
        for i,l in ipairs(all) do
          texio.write_nl(i..':'..l)
        end
      end
    end
    local i = 0
    local close_expected
    return function (env)
      i = i+1
      if i>#all then
debug_msg('\\CDRBlockImport time to close', i, #all)
        assert(not close_expected, 'close MISSED')
        close_expected = true
      end
      debug_msg('\\CDRBlockImport reader', i, #all)
      return all[i]
    end
  end
  local pop = f_noop
  pop = callback_push (
    'open_read_file',
    function (file_name)
debug_msg('\\CDRBlockImport open_read_file', file_name)
      local close_f = function (env)
debug_msg('\\CDRBlockImport close', file_name)
        if d.teardown then
          d:teardown()
        end
        pop()
        pop = f_noop
        self.synctex_restore = nil
        self:synctex_restore()
      end
      local reader = make_reader()
debug_msg('\\CDRBlockImport READER ****************', #all)
      return {
        reader = function (env)
debug_msg('\\CDRBlockImport READER 1st, set close function and pop')
          env.close = close_f
          env.reader = reader
          pop()
          pop = f_noop
          return reader(env)
        end,
      }
    end,
    'CDRBlockImport'
  )
  function self.import_set_boolean(this, key, var)
    args[key] = assert(token.get_macro(var or 'l_CDR_a_tl')) == 'true'
debug_msg('import_set_boolean', key, args[key])
  end
  function self.import_set_integer(this, key, var)
    args[key] = tonumber(token.get_macro(var or 'l_CDR_a_tl'))
debug_msg('import_set_integer', key, args[key])
  end
debug_msg('import_begin...DONE')
end
function Block:import ()
  error('Build time error: unexpected import call.')
end
function Block:import_set_boolean ()
  error('Build time error: unexpected import_set_boolean call.')
end
function Block:import_set_integer ()
  error('Build time error: unexpected import_set_integer call.')
end
CDR.print_string = function(...)
debug_msg('CDR.print_string', ...)
  tex.print(CDR.string_cctab, ...)
end
CDR.sprint_string = function(...)
debug_msg('CDR.sprint_string', ...)
  tex.sprint(CDR.string_cctab, ...)
end
CDR.print_escape = function(...)
debug_msg('CDR.print_escape', ...)
  tex.print(CDR.escape_cctab, ...)
end
CDR.sprint_escape = function(...)
debug_msg('CDR.sprint_escape', ...)
  tex.sprint(CDR.escape_cctab, ...)
end
CDR._DESCRIPTION = [[Global coder utilities on the lua side]]
return setmetatable(CDR, {
  __index = function (self, k)
    local ans
    if k == '_VERSION' then
      ans = token.get_macro('CDRFileVersion')
    elseif k == 'date' then
      ans = token.get_macro('CDRFileDate')
    end
    if ans ~= nil then
      rawset(self, k, ans)
      return ans
    end
  end
})
