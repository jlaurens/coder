#!/usr/bin/env python3
# -*- coding: utf-8 -*-
#
# This is file `coder-tool.py',
# generated with the docstrip utility.
#
# The original source files were:
#
# coder.dtx  (with options: `py')
# 
# coder --- code inlined in a LuaLaTeX document.
# version: v2.6a
# date: 2020-11-23
# url: https:github.com/jlaurens/coder
# E-mail: jerome.laurens@u-bourgogne.fr
# Released under the LaTeX Project Public License v1.3c or later
# See http://www.latex-project.org/lppl.txt
# 

#! /usr/bin/env python3
# -*- coding: utf-8 -*-
__version__ = '0.10'
__YEAR__  = '2022'
__docformat__ = 'restructuredtext'

from posixpath import split
import sys
import argparse
import re
from pathlib import Path
import hashlib
import json
from pygments import highlight
from pygments.formatters.latex import LatexEmbeddedLexer, LatexFormatter
from pygments.lexers import get_lexer_by_name
from pygments.util import ClassNotFound
from pygments.util import guess_decode
class Controller:
  @staticmethod
  def ensure_bool(x):
    if x == True or x == False: return x
    x = x[0:1]
    return x == 'T' or x == 't'
  class Object(object):
    def __new__(cls, d={}, *args, **kvargs):
      __cls__ = d.get('__cls__', 'arguments')
      if __cls__ == 'options':
        return super(Controller.Object, cls)['__new__'](
          Controller.Options, *args, **kvargs
        )
      elif __cls__ == 'FV':
        return super(Controller.Object, cls)['__new__'](
          Controller.FV, *args, **kvargs
        )
      else:
        return super(Controller.Object, cls)['__new__'](
          Controller.Arguments, *args, **kvargs
        )
    def __init__(self, d={}):
      for k, v in d.items():
        if type(v) == str:
          if v.lower() == 'true':
            setattr(self, k, True)
            continue
          elif v.lower() == 'false':
            setattr(self, k, False)
            continue
        setattr(self, k, v)
    def __repr__(self):
      return f"{object['__repr__'](self)}: {self['__dict__']}"
  class Options(Object):
    docclass = 'article'
    style = 'autumn'
    preamble = ''
    lang = 'tex'
    escapeinside = ""
    gobble = 0
    tabsize = 4
    style = 'default'
    already_style = False
    texcomments = False
    mathescape =  False
    linenos = False
    linenostart = 1
    linenostep = 1
    linenosep = '0pt'
    encoding = 'guess'
    verboptions = ''
    nobackground = False
    commandprefix = 'Py'
  class FV(Object):
    pass
  class Arguments(Object):
    cache = False
    debug = False
    code = ""
    json = ""
    options = None
    directory = ""
  _json_p = None
  @property
  def json_p(self):
    p = self._json_p
    if p:
      return p
    else:
      p = self.arguments.json
      if p:
        p = Path(p).resolve()
    self._json_p = p
    return p
  _directory_p = None
  @property
  def directory_p(self):
    p = self._directory_p
    if p:
      return p
    p = self.arguments.directory
    if p:
      p = Path(p)
    else:
      p = self.json_p
      if p:
        p = p.parent / p.stem
      else:
        p = Path('SHARED')
    if p:
      p = p.resolve().with_suffix(".pygd")
      p.mkdir(exist_ok=True)
    self._directory_p = p
    return p
  _colored_p = None
  @property
  def colored_p(self):
    p = self._colored_p
    if p:
      return p
    p = self.arguments.output
    if p:
      p = Path(p).resolve()
    else:
      p = self.json_p
      if p:
        p = p.with_suffix(".pyg.tex")
    self._colored_p = p
    return p
  @property
  def sty_p(self):
    return (self.directory_p / self.options.style).with_suffix(".pyg.sty")
  @property
  def parser(self):
    parser = argparse.ArgumentParser(
      prog=sys.argv[0],
      description='''
Writes to the output file a set of LaTeX macros describing
the syntax highlighting of the input file as given by pygments.
'''
    )
    parser.add_argument(
      "-v", "--version",
      help="Print the version and exit",
      action='version',
      version=f'coder-tool version {__version__},'
      ' (c) {__YEAR__} by Jérôme LAURENS.'
    )
    parser.add_argument(
      "--debug",
      default=None,
      help="display informations useful for debugging"
    )
    parser.add_argument(
      "json",
      metavar="json data file",
      help="""
file name with extension of information to specify which processing is required
"""
    )
    return parser

  @staticmethod
  def tex_command(cmd):
    print(f'<<<<<?TEX:{cmd}>>>>>')
  @staticmethod
  def lua_command(cmd):
    print(f'<<<<<?LUA:{cmd}>>>>>')
  @staticmethod
  def lua_command_new(cmd):
    print(f'<<<<<!LUA:{cmd}>>>>>')
  def __init__(self, argv = sys.argv):
    argv = argv[1:] if re.match(".*coder\-tool\.py$", argv[0]) else argv
    ns = self.parser.parse_args(
      argv if len(argv) else ['-h']
    )
    with open(ns.json, 'r') as f:
      self.arguments = json.load(
        f,
        object_hook=Controller.Object
      )
    options = self.options = self.arguments.options
    formatter = self.formatter = LatexFormatter(style=options.style)
    formatter.docclass = options.docclass
    formatter.preamble = options.preamble
    formatter.linenos = self.ensure_bool(options.linenos)
    formatter.linenostart = abs(options.linenostart)
    formatter.linenostep = abs(options.linenostep)
    formatter.verboptions = options.verboptions
    formatter.nobackground = self.ensure_bool(options.nobackground)
    formatter.commandprefix = options.commandprefix
    formatter.texcomments = self.ensure_bool(options.texcomments)
    formatter.mathescape = self.ensure_bool(options.mathescape)
    formatter.envname = u'CDR@Pyg@Verbatim'

    try:
      lexer = self.lexer = get_lexer_by_name(self.arguments.lang)
    except ClassNotFound as err:
      sys.stderr.write('Error: ')
      sys.stderr.write(str(err))

    escapeinside = options.escapeinside
    # When using the LaTeX formatter and the option `escapeinside` is
    # specified, we need a special lexer which collects escaped text
    # before running the chosen language lexer.
    if len(escapeinside) == 2:
      left  = escapeinside[0]
      right = escapeinside[1]
      lexer = self.lexer = LatexEmbeddedLexer(left, right, lexer)

    gobble = abs(int(self.gobble))
    if gobble:
      lexer.add_filter('gobble', n=gobble)
    tabsize = abs(int(self.tabsize))
    if tabsize:
      lexer.tabsize = tabsize
    lexer.encoding = ''

  def get_tex_p(self, digest):
    return (self.directory_p / digest).with_suffix(".pyg.tex")
  def process(self):
    self.create_style()
    self.create_pygmented()
    print('create_tool.py: done')
    return 0
  def create_style(self):
    options = self.options
    formatter = self.formatter
    style = None
    if not self.ensure_boolean(options.already_style):
      style = formatter.get_style_defs() \
        .replace(r'\makeatletter', '') \
        .replace(r'\makeatother', '') \
        .replace('\n', '%\n')
      style = re.sub(
        r"\expandafter\def\csname\s*(.*?)\endcsname",
        r'\cs_new:cpn{\1}',
        style,
        flags=re.M
      )
      style = re.sub(
        r"\csname\s*(.*?)\endcsname",
        r'\use:c{\1}',
        style,
        flags=re.M
      )
      style = fr'''%
\ExplSyntaxOn
\makeatletter
\CDR_style_gset:nn {{{options.style}}} {{%
{style}%
}}%
\makeatother
\ExplSyntaxOff
'''
    sty_p = self.sty_p
    if self.arguments.cache and sty_p.exists():
      print("Already available:", sty_p)
    else:
      with sty_p.open(mode='w',encoding='utf-8') as f:
        f.write(style)
  def pygmentize(self, code, inline=True):
    options = self.options
    formatter = self.formatter
    mode = 'Code' if inline else 'Block'
    envname = formatter.envname = rf'CDR@Pyg@{mode}'
    code = highlight(code, self.lexer, formatter)
    m = re.match(
      rf'(\begin{{{envname}}}.*?\n)(.*?)(\n'
      rf'\end{{{envname}}}\s*)\Z',
      code,
      flags=re.S
    )
    assert(m)
    if inline:
      ans_code = rf'''\bgroup
\CDRCode@Prepare:n {{{options.style}}}%
{m.group(2)}%
\egroup
'''
    else:
      ans_code = []
      linenos = options.linenos
      linenostart = abs(int(options.linenostart))
      linenostep = abs(int(options.linenostep))
      numbers = []
      lines = []
      counter = linenostart
      all_lines = m.group(2).split('\n')
      for line in all_lines:
        line = re.sub(r'^ ', r'\vphantom{Xy}~', line)
        line = re.sub(r' ', '~', line)
        if linenos:
          if (counter - linenostart) % linenostep == 0:
            line = rf'\CDR_lineno:n{{{counter}}}' + line
            numbers.append(str(counter))
          counter += 1
        lines.append(line)
      ans_code.append(fr'''%
\begin{{CDR/block/engine/{options.style}}}
\CDRBlock@linenos@used:n {{{','.join(numbers)}}}%
{m.group(1)}{'\n'.join(lines)}{m.group(3)}%
\end{{CDR/block/engine/{options.style}}}
''' )
      ans_code = "".join(ans_code)
    return ans_code
  def create_pygmented(self):
    code = self.arguments.code
    if not code:
      return False
    code = self.pygmentize(code, self.ensure_bool(self.arguments.inline))
    h = hashlib.md5(str(code).encode('utf-8'))
    out_p = self.get_tex_p(h.hexdigest())
    if self.arguments.cache and out_p.exists():
      print("Already available:", out_p)
    else:
      with out_p.open(mode='w',encoding='utf-8') as f:
        f.write(r'''% -*- mode: latex -*-
\makeatletter
''')
        f.write(code)
        f.write(r'''\makeatother
''')
    self.tex_command( rf'''%
\CDR_remove:n {{colored:}}%
\input {{ \tl_to_str:n {{{out_p}}} }}%
\CDR:n {{colored:}}%
''')
    sty_p = self.sty_p
    if sty_p.parent.stem != 'SHARED':
      self.lua_command_now( fr'''
CDR:cache_record({sty_p.name}),{out_p.name})
''' )
    print("PREMATURE EXIT")
    exit(1)
if __name__ == '__main__':
  try:
    ctrl = Controller()
    sys.exit(ctrl.process())
  except KeyboardInterrupt:
    sys.exit(1)
