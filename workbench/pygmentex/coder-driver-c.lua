--
-- This is file `coder-driver-c.lua',
-- generated with the docstrip utility.
--
-- The original source files were:
--
-- coder.dtx  (with options: `driver-c')
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
This is the driver for the C programming language
and other languages with the same syntax regarding long comments.
The \pkg{coder} package  will pretty print embedded documentation formatted in \LaTeX\ that is delimited by special
comment markers. The beginning of a documentation block is delimited by
a full line matching the lua pattern \CDRCode[lang=lua]|^/%*+!latex:|.
The end of a documentation block is delimited by a full line matching
the lua pattern \CDRCode[lang=lua]|^%*+/|.
In both cases there must be at least one star.

The delimiting lines are removed and what is inside is typeset with \LaTeX{}.

See the \CDRCode|\CDRBlockImport| documentation for more information.
\end{coder}
--]=]
-- put here whatever statement you need
-- return a table
local ans = {
  open = function (self, line)
    return line:match(
      [[^/%*+!latex:]]
    ) ~= nil
  end,
  close = function (self, line)
    return line:match(
      [[^%*+/]]
    ) ~= nil
  end,
  short = function (self, line)
    return line:match(
      [[^//+!latex:%s*(.*)]]
    )
  end,
}
return ans
