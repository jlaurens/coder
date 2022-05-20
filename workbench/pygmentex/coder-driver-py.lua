--
-- This is file `coder-driver-py.lua',
-- generated with the docstrip utility.
--
-- The original source files were:
--
-- coder.dtx  (with options: `driver-py')
-- 
-- coder --- code inlined in a LuaLaTeX document.
-- version: v2.6a
-- date: 2020-11-23
-- url: https:github.com/jlaurens/coder
-- E-mail: jerome.laurens@u-bourgogne.fr
-- Released under the LaTeX Project Public License v1.3c or later
-- See http://www.latex-project.org/lppl.txt
-- 

--[=[!latex:
\begin{coder}{Embedded documentation}
This is the driver for the python programming language.
The \pkg{coder} package  will pretty print embedded documentation formatted in \LaTeX\ that is delimited by special
comment markers. The beginning of a documentation block is delimited by
a full line matching the lua pattern
\CDRCode[lang=lua]|^('''|""")!latex:|.
The end of a documentation block is delimited by a full line
with the very same combination of quotes and spaces.

The delimiting lines are removed and what is inside is typeset with \LaTeX{}.

See the \CDRCode|\CDRBlockImport| documentation for more information.
\end{coder}
--]=]
-- put here whatever statement you need
-- return a table
return {
  open = function (self, line)
    local quotes = line:match(
      [[^(%s*""")!latex:]]
    )
    if quotes then
      local pattern = '^'..quotes
      self.close = function (this, l)
        return l:match(pattern) ~= nil
      end
      return true
    end
    quotes = line:match(
      [[^(%s*''')!latex:]]
    )
    if quotes then
      local pattern = '^'..quotes
      self.close = function (this, l)
        return l:match(pattern) ~= nil
      end
      return true
    end
  end,
}
