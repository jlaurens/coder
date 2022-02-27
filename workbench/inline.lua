---@diagnostic disable-next-line: lowercase-global
local lfs = require("lfs")

local NLN = {
  PYGMENTEX_PATH = io.popen([[kpsewhich pygmentex.py]]):read('a'):match("^%s*(.-)%s*$"),
}
function NLN.make_directory(self, path)
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
function NLN.start_recording(self)
  self.records = {}
  function self.records.append (t,v)
    t[#t+1]=v
    return t
  end
end
function NLN.setup(self, jobname)
  self.jobname = jobname
  self.dir = "_temp_pyg/"
  if self:make_directory(self.dir) == nil then
    self.dir = "./"
  end
  self.tmpname = os.tmpname():match("/(.-)$")
  self.pyg = self.dir .. jobname .. [[.pyg]]
end

function NLN.process_inline(self, what)
  local fh = assert(io.open(self.pyg,'w'))
  assert(fh:write([[<@@NLN@inline@0
]]))
  assert(fh:write(what))
  assert(fh:write([[>@@NLN@inline@0
]]))
  assert(fh:close())
  print([=[NLN Info: file written ]=]..self.pyg)
  print([=[NLN Info: content ]=]..what)
  fh = assert(io.popen("python3 pygmentex.py "..self.pyg))
  local s = fh:read('a')
  print('NLN DIAGNOSTIC: '..s)
end

NLN.DESCRIPTION=[[Global inline object on the dark side]]

return {
  NLN = NLN,
}