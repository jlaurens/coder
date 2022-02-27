local lfs = require("lfs")
local tex = require("tex")

--require("lualibs.lua")
--local json = utilities.json

local PYGMENTEX_PATH = io.popen([[kpsewhich pygmentex.py]]):read('a'):match("^%s*(.-)%s*$")

local function escape(self, s)
    s = s:gsub('\\','\\\\')
    s = s:gsub('\r','\\r')
    s = s:gsub('\n','\\n')
    s = s:gsub('"','\\"')
    return s
end

local function make_directory(self, path)
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

local function setup(self, jobname)
  self.jobname = jobname
  self.dir_p = './'..jobname..'.pygd/'
  print('DEBUG setup:', self.dir_p)
  if self:make_directory(self.dir_p) == nil then
    self.dir_p = './'
    self.input_p = self.dir_p..jobname..'.pyg.data'
  else
    self.input_p = self.dir_p..'input.pyg.data'
  end
end

local function clear_options(self)
  self.options = {}
end

local function add_option(self,k,v)
  self.options[k] = v
end

local function start_recording(self)
  self.records = {}
  function self.records.append (t,v)
    t[#t+1]=v
    return t
  end
end

local function process_inline(self, what)
  if lfs.attributes(self.input_p,"mode") ~= nil then
    os.remove(self.input_p)
  end
  local t = {
    ['code']   = what,
    ['jobname']= self.jobname,
    ['options']= self.options or {},
  }
  local s = json.tostring(t,true)
  local fh = assert(io.open(self.input_p,'w'))
  fh:write(s, '\n')
  fh:close()
  local cmd = "python3 "..PYGMENTEX_PATH..' "'..self.input_p..'"'
  fh = assert(io.popen(cmd))
  local s = fh:read('a')
  _, _, cmd = s:find('<tex command>(.-)</tex command>')
  if cmd then
  tex.print(cmd)
  elseif s:len() > 0 then
    print('NLN DIAGNOSTIC: '..s)
  end
end

local DESCRIPTION = [[Global inline object on the dark side]]

return {
  _DESCRIPTION    = DESCRIPTION,
  PYGMENTEX_PATH  = PYGMENTEX_PATH,
  escape          = escape,
  make_directory  = make_directory,
  setup           = setup,
  clear_options   = clear_options,
  add_option      = add_option,
  start_recording = start_recording,
  process_inline  = process_inline,
}
