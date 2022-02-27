#!/usr/bin/env python3
# -*- coding: utf-8 -*-
#
# This is file `inline-helper.py',
# generated with the docstrip utility.
#
# The original source files were:
#
# inline.dtx  (with options: `py')
# 
# inline --- code inlined in a LuaLaTeX document.
# version: v0.1a
# date: 2022/02/06
# url: https:github.com/jlaurens/inline
# E-mail: jerome.laurens@u-bourgogne.fr
# Released under the LaTeX Project Public License v1.3c or later
# See http://www.latex-project.org/lppl.txt
# 
__version__ = '0.10'
__YEAR__  = '2022'
__docformat__ = 'restructuredtext'

from posixpath import split
import sys
import argparse
import re
from pathlib import Path
from io import StringIO
import hashlib
import json
import pygments as P
import pygments.formatters.latex as L
from pygments.token import Token as PyToken
class NLNLatexFormatter(L.LatexFormatter):
  name = 'NLNLaTeX'
  aliases = []
  def __init__(self, *args, **kvargs):
    super().__init__(self, *args, **kvargs)
    self.escapeinside = kvargs.get('escapeinside', '')
    if len(self.escapeinside) == 2:
      self.left = self.escapeinside[0]
      self.right = self.escapeinside[1]
    else:
      self.escapeinside = ''
  def format_unencoded(self, tokensource, outfile):
    # TODO: add support for background colors
    t2n = self.ttype2name
    cp = self.commandprefix
    if self.full:
      realoutfile = outfile
      outfile = StringIO()
    outfile.write(r'\begin{Verbatim}[commandchars=\\\{\}')
    if self.linenos:
      start, step = self.linenostart, self.linenostep
      outfile.write(',numbers=left' +
            (start and ',firstnumber=%d' % start or '') +
            (step and ',stepnumber=%d' % step or ''))
    if self.mathescape or self.texcomments or self.escapeinside:
      outfile.write(r',codes={\catcode`\$=3\catcode`\^=7\catcode`\_=8}')
    if self.verboptions:
      outfile.write(',' + self.verboptions)
    outfile.write(']\n')
    for ttype, value in tokensource:
      if ttype in PyToken.Comment:
        if self.texcomments:
          # Try to guess comment starting lexeme and escape it ...
          start = value[0:1]
          for i in range(1, len(value)):
            if start[0] != value[i]:
              break
            start += value[i]

          value = value[len(start):]
          start = L.escape_tex(start, self.commandprefix)

          # ... but do not escape inside comment.
          value = start + value
        elif self.mathescape:
          # Only escape parts not inside a math environment.
          parts = value.split('$')
          in_math = False
          for i, part in enumerate(parts):
            if not in_math:
              parts[i] = L.escape_tex(part, self.commandprefix)
            in_math = not in_math
          value = '$'.join(parts)
        elif self.escapeinside:
          text = value
          value = ''
          while len(text) > 0:
            a,sep1,text = text.partition(self.left)
            if len(sep1) > 0:
              b,sep2,text = text.partition(self.right)
              if len(sep2) > 0:
                value += L.escape_tex(a, self.commandprefix) + b
              else:
                value += L.escape_tex(a + sep1 + b, self.commandprefix)
            else:
              value = value + L.escape_tex(a, self.commandprefix)
        else:
          value = L.escape_tex(value, self.commandprefix)
      elif ttype not in PyToken.Escape:
        value = L.escape_tex(value, self.commandprefix)
      styles = []
      while ttype is not PyToken:
        try:
          styles.append(t2n[ttype])
        except KeyError:
          # not in current style
          styles.append(L._get_ttype_name(ttype))
        ttype = ttype.parent
      styleval = '+'.join(reversed(styles))
      if styleval:
        spl = value.split('\n')
        for line in spl[:-1]:
          if line:
            outfile.write("\\%s{%s}{%s}" % (cp, styleval, line))
          outfile.write('\n')
        if spl[-1]:
          outfile.write("\\%s{%s}{%s}" % (cp, styleval, spl[-1]))
      else:
        outfile.write(value)

    outfile.write('\\end{Verbatim}\n')

    if self.full:
      realoutfile.write(DOC_TEMPLATE % dict(
        docclass  = self.docclass,
        preamble  = self.preamble,
        title     = self.title,
        encoding  = self.encoding or 'latin1',
        style_defs = self.get_style_defs(),
        code      = outfile.getvalue()
      ) )

class Lexer(P.lexer.Lexer):

  def __init__(self, left, right, lang, *args, **kvargs):
    self.left = left
    self.right = right
    self.lang = lang
    super().__init__(self, *args, **kvargs)

  def get_tokens_unprocessed(self, text):
    buf = ''
    for i, t, v in self.lang.get_tokens_unprocessed(text):
      if t in P.token.Comment or t in P.token.String:
        if buf:
          for x in self.get_tokens_aux(idx, buf):
            yield x
          buf = ''
        yield i, t, v
      else:
        if not buf:
          idx = i
        buf += v
    if buf:
      for x in self.get_tokens_aux(idx, buf):
        yield x

  def get_tokens_aux(self, index, text):
    while text:
      a, sep1, text = text.partition(self.left)
      if a:
        for i, t, v in self.lang.get_tokens_unprocessed(a):
          yield index + i, t, v
          index += len(a)
      if sep1:
        b, sep2, text = text.partition(self.right)
        if sep2:
          yield index + len(sep1), P.token.Escape, b
          index += len(sep1) + len(b) + len(sep2)
        else:
          yield index, P.token.Error, sep1
          index += len(sep1)
          text = b
class Controller:
  STY_FORMAT = r'''%%
\NLN_put:nn {style/%(name)s}{%%
}%%
'''
  TEX_CALLBACK_FORMAT = r'''%%
\NLN_remove:n {colored:}%%
\NLN_style:nn {\tl_to_str:n {%(sty_p)s}}{\tl_to_str:n{%(name)s}}%%
\input {\tl_to_str:n {%(out_p)s}}%%
\NLN:n {colored:}%%
'''
  LUA_CALLBACK_FORMAT = r'''
NLN:cache_record(%(style)s),%(digest)s)
'''
  SNIPPET_FORMAT = r'''%%
\NLN_put:nn {colored} {%%
\group_begin:
\NLN:n {linenos:n} {%(line_numbers)s}%%
\begin{NLN/colored/%(mode)s/%(method)s}%%
\end{NLN/colored/%(mode)s/%(method)s}%%
\group_end:
}
'''
  PREAMBLE = r'''% -*- mode: latex -*-
\makeatletter
'''
  POSTAMBLE = r'''\makeatother
'''
  class Object(object):
    def __new__(cls, d={}, *args, **kvargs):
      if d.get('__cls__', 'arguments') == 'options':
        return super(Controller.Object, cls).__new__(
          Controller.Options, *args, **kvargs
        )
      else:
        return super(Controller.Object, cls).__new__(
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
      return f"{object.__repr__(self)}: {self.__dict__}"
  class Options(Object):
    lang = "tex"
    escapeinside = ""
    gobble = 0
    tabsize = 4
    style = 'default'
    texcomments = False
    mathescape =  False
    linenos = False
    linenostart = 1
    linenostep = 1
    linenosep = '0pt'
    encoding = 'guess'
    def __init__(self, *args, **kvargs):
      super().__init__(self, *args, **kvargs)
      try:
        lexer = P.lexers.get_lexer_by_name(self.lang)
      except P.util.ClassNotFound as err:
        sys.stderr.write('Error: ')
        sys.stderr.write(str(err))
      formatter = self.formatter = NLNLatexFormatter()
      escapeinside = self.escapeinside
      if len(escapeinside) == 2:
        left = escapeinside[0]
        right = escapeinside[1]
        formatter.escapeinside = escapeinside
        formatter.left = left
        formatter.right = right
        self.lexer = Lexer(left, right, lexer)
      gobble = abs(int(self.gobble))
      if gobble:
        lexer.add_filter('gobble', n=gobble)
      tabsize = abs(int(self.tabsize))
      if tabsize:
        lexer.tabsize = tabsize
      lexer.encoding = ''
      formatter.texcomments = self.texcomments
      formatter.mathescape = self.mathescape
      self.style = formatter.style = P.styles.get_style_by_name(self.style or self.sty)
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
      version=f'inline-helper version {__version__},'
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
    argv = argv[1:] if re.match(".*inline-helper\.py$", argv[0]) else argv
    ns = self.parser.parse_args(
      argv if len(argv) else ['-h']
    )
    with open(ns.json, 'r') as f:
      self.arguments = json.load(
        f,
        object_hook=Controller.Object
      )
    self.options = self.arguments.options
    print("INPUT", self.json_p)
    print("OUTPUT DIR", self.directory_p)
    print("OUTPUT", self.colored_p)
  def get_tex_p(self, digest):
    return (self.directory_p / digest).with_suffix(".pyg.tex")
  def read_input(self, filename, encoding):
    with open(filename, 'rb') as infp:
      code = infp.read()
    if not encoding or encoding == 'guess':
      code, encoding = P.util.guess_decode(code)
    else:
      code = code.decode(encoding)
    return code, encoding
  def process(self):
    arguments = self.arguments
    if self.convert_code():
      print('Done')
      return 0
    try:
      with open(self.arguments.output, 'w') as outfile:
        try:
          code, encoding = self.read_input(self.arguments.input, "guess")
        except Exception as err:
          print('Error: cannot read input file: ', err, file=sys.stderr)
          return 1
        self.convert(code, outfile, encoding)
    except Exception as err:
      print('Error: cannot open output file: ', err, file=sys.stderr)
      return 1
    print("Done")
    return 0
  def pygmentize(self, code, inline_delim=True):
    options = self.options
    formatter = options.formatter
    formatter._create_stylesheet()
    style_defs = formatter.get_style_defs() \
      .replace(r'\makeatletter', '') \
      .replace(r'\makeatother', '') \
      .replace('\n', '%\n')
    ans_style  = self.STY_FORMAT % dict(
      name = options.style,
      defs = style_defs,
    )
    ans_code = []
    m = re.match(
      r'\\begin\{Verbatim}(.*)\n([\s\S]*?)\n\\end\{Verbatim}(\s*)\Z',
      P.highlight(code, options.lexer, formatter)
    )
    if m:
      linenos = options.linenos
      linenostart = abs(int(options.linenostart))
      linenostep = abs(int(options.linenostep))
      lines0 = m.group(2).split('\n')
      numbers = []
      lines = []
      counter = linenostart
      for line in lines0:
        line = re.sub(r'^ ', r'\vphantom{Xy}~', line)
        line = re.sub(r' ', '~', line)
        if linenos:
          if (counter - linenostart) % linenostep == 0:
            line = rf'\NLN:n {{lineno:}}{{{counter}}}' + line
            numbers.append(str(counter))
          counter += 1
        lines.append(line)
      ans_code.append(self.SNIPPET_FORMAT % dict(
        mode         = 'inline' if inline_delim else 'display',
        method       = self.arguments.method or 'default',
        line_numbers = ','.join(numbers),
        body         = '\\newline\n'.join(lines)
      ) )
    ans_code = "".join(ans_code)
    ans_code = re.sub(
      r"\expandafter\def\csname\s*(.*?)\endcsname",
      r'\cs_new:cpn{\1}',
      ans_code,
      flags=re.M
    )
    ans_code = re.sub(
      r"\csname\s*(.*?)\endcsname",
      r'\use:c{\1}',
      ans_code,
      flags=re.M
    )
    return ans_style, ans_code
  def convert_code(self):
    code = self.arguments.code
    if not code:
      return False
    style, code = self.pygmentize(code,True)
    sty_p = self.sty_p
    if self.arguments.cache and sty_p.exists():
      print("Already available:", sty_p)
    else:
      with sty_p.open(mode='w',encoding='utf-8') as f:
        f.write(style)
    h = hashlib.md5(str(code).encode('utf-8'))
    out_p = self.get_tex_p(h.hexdigest())
    if self.arguments.cache and out_p.exists():
      print("Already available:", out_p)
    else:
      with out_p.open(mode='w',encoding='utf-8') as f:
        f.write(self.PREAMBLE)
        print(f'DEBUG:{self.options}')
        f.write(code)
        f.write(self.POSTAMBLE)
    self.tex_command( self.TEX_CALLBACK_FORMAT % dict(
      sty_p = sty_p,
      out_p = out_p,
      name  = self.style,
    ) )
    if sty_p.parent.stem != 'SHARED':
      self.lua_command_now( self.LUA_CALLBACK_FORMAT % dict(
        style  = sty_p.name,
        digest = out_p.name,
      ) )
    print("PREMATURE EXIT")
    exit(1)
if __name__ == '__main__':
  try:
    ctrl = Controller()
    sys.exit(ctrl.process())
  except KeyboardInterrupt:
    sys.exit(1)
