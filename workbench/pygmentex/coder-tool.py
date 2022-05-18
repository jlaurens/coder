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

import sys
import os
import argparse
import re
from pathlib import Path
import json
from pygments import highlight as hilight
from pygments.formatters.latex import LatexEmbeddedLexer, LatexFormatter
from pygments.lexers import get_lexer_by_name
from pygments.util import ClassNotFound
class BaseOpts(object):
  def __init__(self, d={}):
    for k, v in d.items():
      setattr(self, k, v)
class TeXOpts(BaseOpts):
  tags      = ''
  is_inline  = True
  pyg_sty_p = None
  synctex_tag  = 0
  synctex_line = 0
  tabsize = 4
  sty_template=r'''% !TeX root=...
\makeatletter
\CDR@StyleDefine{<placeholder:style_name>}{%
  \CDR@Debug{Loading style <placeholder:style_name>...}%
  <placeholder:style_defs>%
  \CDR@Debug{... DONE}%
}%
\makeatother'''
  def __init__(self, *args, **kvargs):
    super().__init__(*args, **kvargs)
    self.pyg_sty_p = Path(self.pyg_sty_p or '')
    self.tabsize = abs(int(self.tabsize))
class PygOpts(BaseOpts):
  style = 'default'
  nobackground = False
  linenos = False
  linenostart = 1
  linenostep = 1
  commandprefix = 'Py'
  texcomments = False
  mathescape =  False
  escapeinside = ""
  envname = 'Verbatim'
  lang = 'tex'
  gobble = 0
  def __init__(self, *args, **kvargs):
    super().__init__(*args, **kvargs)
    self.linenostart = abs(int(self.linenostart))
    self.linenostep  = abs(int(self.linenostep))
    self.gobble  = abs(int(self.gobble))
class Arguments(BaseOpts):
  cache  = False
  debug  = False
  source = ""
  style  = "default"
  json   = ""
  directory = "."
  texopts = TeXOpts()
  pygopts = PygOpts()
class Controller:
  @staticmethod
  def object_hook(d):
    __cls__ = d.get('__cls__', 'Arguments')
    if __cls__ == 'PygOpts':
      return PygOpts(d)
    elif __cls__ == 'TeXOpts':
      return TeXOpts(d)
    elif __cls__ == 'BooleanTrue':
      return True
    elif __cls__ == 'BooleanFalse':
      return False
    else:
      return Arguments(d)
  @staticmethod
  def lua_command(cmd):
    print(f'<<<<<*LUA:{cmd}>>>>>')
  @staticmethod
  def lua_command_now(cmd):
    print(f'<<<<<!LUA:{cmd}>>>>>')
  @staticmethod
  def lua_debug(msg):
    print(f'<<<<<?LUA:{msg}>>>>>')
  @staticmethod
  def lua_text_escape(s):
    k = 0
    for m in re.findall('=+', s):
      if len(m) > k: k = len(m)
    k = (k + 1) * "="
    return f'[{k}[{s}]{k}]'
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
  @property
  def parser(self):
    parser = argparse.ArgumentParser(
      prog=sys.argv[0],
      description='''
Writes to the output file a set of LaTeX macros describing
the syntax hilighting of the input file as given by pygments.
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
      action='store_true',
      default=None,
      help="display informations useful for debugging"
    )
    parser.add_argument(
      "--create_style",
      action='store_true',
      default=None,
      help="create the style definitions"
    )
    parser.add_argument(
      "--base",
      action='store',
      default=None,
      help="the path of the file to be colored, with no extension"
    )
    parser.add_argument(
      "json",
      metavar="<json data file>",
      help="""
file name with extension, contains processing information.
"""
    )
    return parser

  def __init__(self, argv = sys.argv):
    argv = argv[1:] if re.match(".*coder\-tool\.py$", argv[0]) else argv
    ns = self.parser.parse_args(
      argv if len(argv) else ['-h']
    )
    with open(ns.json, 'r') as f:
      self.arguments = json.load(
        f,
        object_hook = Controller.object_hook
      )
    args = self.arguments
    args.json = ns.json
    texopts = self.texopts = args.texopts
    pygopts = self.pygopts = args.pygopts
    self.formatter = LatexFormatter(
      style = pygopts.style,
      nobackground = pygopts.nobackground,
      commandprefix = pygopts.commandprefix,
      texcomments  = pygopts.texcomments,
      mathescape   = pygopts.mathescape,
      escapeinside = pygopts.escapeinside,
      envname = 'CDR@Pyg@Verbatim',
    )

    try:
      lexer = self.lexer = get_lexer_by_name(pygopts.lang)
    except ClassNotFound as err:
      sys.stderr.write('Error: ')
      sys.stderr.write(str(err))

    escapeinside = pygopts.escapeinside
    # When using the LaTeX formatter and the option `escapeinside` is
    # specified, we need a special lexer which collects escaped text
    # before running the chosen language lexer.
    if len(escapeinside) == 2:
      left  = escapeinside[0]
      right = escapeinside[1]
      lexer = self.lexer = LatexEmbeddedLexer(left, right, lexer)
    elif len(escapeinside) == 3:
      left   = escapeinside[0]
      middle = escapeinside[1]
      right  = escapeinside[2]
      lexer  = self.lexer = LatexEmbeddedLexer(left, right, lexer)

    gobble = pygopts.gobble
    if gobble:
      lexer.add_filter('gobble', n=gobble)
    tabsize = texopts.tabsize
    if tabsize:
      lexer.tabsize = tabsize
    lexer.encoding = ''
    args.base = ns.base
    args.create_style = ns.create_style
    if ns.debug:
      args.debug = True
    # IN PROGRESS: support for extra keywords
    # EXTRA_KEYWORDS = set(('foo', 'bar', 'foobar', 'barfoo', 'spam', 'eggs'))
    # def over(self, text):
    #   for index, token, value in lexer.__class__.get_tokens_unprocessed(self, text):
    #     if token is Name and value in EXTRA_KEYWORDS:
    #       yield index, Keyword.Pseudo, value
    #   else:
    #       yield index, token, value
    # lexer.get_tokens_unprocessed = over.__get__(lexer)

  def create_style(self):
    args = self.arguments
    if not args.create_style:
      return
    texopts = args.texopts
    pyg_sty_p = texopts.pyg_sty_p
    if args.cache and pyg_sty_p.exists():
      return
    style = self.pygopts.style
    formatter = self.formatter
    style_defs = formatter.get_style_defs() \
      .replace(r'\makeatletter', '') \
      .replace(r'\makeatother', '') \
      .replace('\n', '%\n')
    sty = self.texopts.sty_template.replace(
      '<placeholder:style_name>',
      style,
    ).replace(
      '<placeholder:style_defs>',
      style_defs,
    ).replace(
      '{}%',
      '{%}\n}%{'
    ).replace(
      '[}%',
      '[%]\n}%'
    ).replace(
      '{]}%',
      '{%[\n]}%'
    )
    with pyg_sty_p.open(mode='w',encoding='utf-8') as f:
      f.write(sty)
    if args.debug:
      print('STYLE', os.path.relpath(pyg_sty_p))
  def pygmentize(self, source):
    source = hilight(source, self.lexer, self.formatter)
    m = re.match(
      r'\\begin{CDR@Pyg@Verbatim}.*?\n(.*?)\n\\end{CDR@Pyg@Verbatim}\s*\Z',
      source,
      flags=re.S
    )
    assert(m)
    hilighted = m.group(1)
    texopts = self.texopts
    if texopts.is_inline:
      s = r'\CDR@Setup{'
      if texopts.synctex_tag:
        s += f'synctex_tag={texopts.synctex_tag},'
      if texopts.synctex_line:
        s += f'synctex_line={texopts.synctex_line},'
      s+='}'
      return s + hilighted +r'\ignorespaces'
    lines = hilighted.split('\n')
    ans_code = []
    last = 0
    for line in lines:
      last += 1
      ans_code.append(rf'''\CDR@Line{{{last}}}{{{line}}}''')
    if last:
      s = r'\CDR@Setup{'
      s += f'last={last},'
      if texopts.synctex_tag:
        s += f'synctex_tag={texopts.synctex_tag},'
      if texopts.synctex_line:
        s += f'synctex_line={texopts.synctex_line},'
      s+='}'
      ans_code.insert(0, s)
    hilighted = '\n'.join(ans_code)
    return hilighted
  def create_pygmented(self):
    args = self.arguments
    base = args.base
    if not base:
      return False
    source = args.source
    if not source:
      tex_p = Path(base).with_suffix('.tex')
      with open(tex_p, 'r') as f:
        source = f.read()
    if args.debug:
      print('SOURCE', source)
    pyg_tex_p = Path(base).with_suffix('.pyg.tex')
    hilighted = self.pygmentize(source)
    with pyg_tex_p.open(mode='w',encoding='utf-8') as f:
      f.write(hilighted)
    if args.debug:
      print('HILIGHTED', os.path.relpath(pyg_tex_p), hilighted)
if __name__ == '__main__':
  try:
    ctrl = Controller()
    x = ctrl.create_style() or ctrl.create_pygmented()
    print(f'{sys.argv[0]}: done')
    sys.exit(x)
  except KeyboardInterrupt:
    sys.exit(1)
