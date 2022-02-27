#! /usr/bin/env python3
# -*- coding: utf-8 -*-

__version__ = '0.10'
__YEAR__    = '2022'
__docformat__ = 'restructuredtext'

from posixpath import split
import sys
import argparse
import re
from os.path import splitext
from pathlib import Path
from io import StringIO
import hashlib
import json

from pygments import highlight
from pygments.styles import get_style_by_name
from pygments.lexers import get_lexer_by_name
from pygments.formatters.latex import LatexFormatter, escape_tex, _get_ttype_name
from pygments.util import get_bool_opt, get_int_opt, ClassNotFound
from pygments.lexer import Lexer
from pygments.token import Token
from pygments.util import guess_decode

###################################################
# From pygments-2.0
###################################################
class NLNLatexFormatter(LatexFormatter):
    r"""
    This is an enhanced LaTeX formatter.
    """
    name = 'NLNLaTeX'
    aliases = []

    def __init__(self, **options):
        LatexFormatter.__init__(self, **options)
        self.escapeinside = options.get('escapeinside', '')
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
            if ttype in Token.Comment:
                if self.texcomments:
                    # Try to guess comment starting lexeme and escape it ...
                    start = value[0:1]
                    for i in range(1, len(value)):
                        if start[0] != value[i]:
                            break
                        start += value[i]

                    value = value[len(start):]
                    start = escape_tex(start, self.commandprefix)

                    # ... but do not escape inside comment.
                    value = start + value
                elif self.mathescape:
                    # Only escape parts not inside a math environment.
                    parts = value.split('$')
                    in_math = False
                    for i, part in enumerate(parts):
                        if not in_math:
                            parts[i] = escape_tex(part, self.commandprefix)
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
                                value += escape_tex(a, self.commandprefix) + b
                            else:
                                value += escape_tex(a + sep1 + b, self.commandprefix)
                        else:
                            value = value + escape_tex(a, self.commandprefix)
                else:
                    value = escape_tex(value, self.commandprefix)
            elif ttype not in Token.Escape:
                value = escape_tex(value, self.commandprefix)
            styles = []
            while ttype is not Token:
                try:
                    styles.append(t2n[ttype])
                except KeyError:
                    # not in current style
                    styles.append(_get_ttype_name(ttype))
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
            realoutfile.write(DOC_TEMPLATE %
                dict(docclass  = self.docclass,
                     preamble  = self.preamble,
                     title     = self.title,
                     encoding  = self.encoding or 'latin1',
                     styledefs = self.get_style_defs(),
                     code      = outfile.getvalue()))

class LatexEmbeddedLexer(Lexer):
    r"""
    This lexer takes one lexer as argument, the lexer for the language
    being formatted, and the left and right delimiters for escaped text.

    First everything is scanned using the language lexer to obtain
    strings and comments. All other consecutive tokens are merged and
    the resulting text is scanned for escaped segments, which are given
    the Token.Escape type. Finally text that is not escaped is scanned
    again with the language lexer.
    """
    def __init__(self, left, right, lang, **options):
        self.left = left
        self.right = right
        self.lang = lang
        Lexer.__init__(self, **options)

    def get_tokens_unprocessed(self, text):
        buf = ''
        for i, t, v in self.lang.get_tokens_unprocessed(text):
            if t in Token.Comment or t in Token.String:
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
                    yield index + len(sep1), Token.Escape, b
                    index += len(sep1) + len(b) + len(sep2)
                else:
                    yield index, Token.Error, sep1
                    index += len(sep1)
                    text = b

class Controller:
    _re_display = re.compile(
        r'^<@@NLN@display@(\d+)\n(.*)\n([\s\S]*?)\n>@@NLN@display@\1$',
        re.MULTILINE)

    _re_inline = re.compile(
        r'^<@@NLN@inline@(\d+)\n(.*)\n([\s\S]*?)\n>@@NLN@inline@\1$',
        re.MULTILINE)

    _re_input = re.compile(
        r'^<@@NLN@input@(\d+)\n(.*)\n([\s\S]*?)\n>@@NLN@input@\1$',
        re.MULTILINE)

    GENERIC_DEFINITIONS_1 = r'''% -*- mode: latex -*-
\makeatletter
'''

    GENERIC_DEFINITIONS_2 = r'''\makeatother
'''

    SNIPPET_TEMPLATE = r'''\
\tl_set:cn {NLN/colored} {%%
  \group_begin:
  \NLN@do@linenos:n{%(linenumbers)s}%%
  \begin{NLN/colored/%(mode)s}%%
  %(body)s%%
  \end{NLN/colored/%(mode)s}%%
  \group_end:
}
'''

    @property
    def code(self):
        return self.arguments.code

    _json_p = None
    @property
    def json_p(self):
        p = self._json_p
        if p:
            return p
        else:
            p = self.arguments.input
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

    _output_p = None
    @property
    def output_p(self):
        p = self._output_p
        if p:
            return p
        p = self.arguments.output
        if p:
            p = Path(p).resolve()
        else:
            p = self.json_p
            if p:
                p = p.with_suffix(".pyg.tex")
        self._output_p = p
        return p

    _outsty_p = None
    @property
    def outsty_p(self):
        p = self._outsty_p
        if p:
            return p
        p = self.arguments.output
        if p:
            p = Path(p).resolve()
        else:
            p = self.json_p
            if p:
                p = p.with_suffix(".pyg.tex")
        self._output_p = p
        return p

    class Object(object):
        def __new__(cls, d={}, *args, **kvargs):
            if d.get('__cls__', 'arguments') == 'options':
                return super(Controller.Object, cls).__new__(Controller.Options, *args, **kvargs)
            else:
                return super(Controller.Object, cls).__new__(Controller.Arguments, *args, **kvargs)

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
        sty = 'default'
        texcomments = False
        mathescape =  False
        linenos = False
        linenostart = 1
        linenostep = 1
        linenosep = '0pt'
        encoding = 'guess'

    class Arguments(Object):
        cache = False
        code = ""
        input = ""
        options = None
        directory = ""


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
            "-v","--version",
            help="Print the version and exit",
            action='version',
            version='inline-helper version %s, (c) %s by Jérôme LAURENS.' % __version__ % __YEAR__
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
        print("OUTPUT", self.output_p)

    def read_input(self, filename, encoding):
        with open(filename, 'rb') as infp:
            code = infp.read()
        if not encoding or encoding == 'guess':
            code, encoding = guess_decode(code)
        else:
            code = code.decode(encoding)

        return code, encoding

    def process(self):
        """
        Main command line entry point.
        """
        arguments = self.arguments
        if self.convert_code():
            self.convert_code()
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

    def pyg(self, outfile, outencoding, n, options, extra_opts, text, usedstyles, inline_delim = True):
        try:
            lexer = get_lexer_by_name(options['lang'])
        except ClassNotFound as err:
            sys.stderr.write('Error: ')
            sys.stderr.write(str(err))
            return ""

        # global _fmter
        _fmter = NLNLatexFormatter()

        escapeinside = options.get('escapeinside', '')
        if len(escapeinside) == 2:
            left = escapeinside[0]
            right = escapeinside[1]
            _fmter.escapeinside = escapeinside
            _fmter.left = left
            _fmter.right = right
            lexer = LatexEmbeddedLexer(left, right, lexer)

        gobble = abs(get_int_opt(options, 'gobble', 0))
        if gobble:
            lexer.add_filter('gobble', n=gobble)

        tabsize = abs(get_int_opt(options, 'tabsize', 0))
        if tabsize:
            lexer.tabsize = tabsize

        lexer.encoding = ''
        # _fmter.encoding = outencoding

        stylename = options['sty']

        _fmter.style = get_style_by_name(stylename)
        _fmter._create_stylesheet()

        _fmter.texcomments = get_bool_opt(options, 'texcomments', False)
        _fmter.mathescape = get_bool_opt(options, 'mathescape', False)

        if stylename not in usedstyles:
            styledefs = _fmter.get_style_defs() \
                .replace('#', '##') \
                .replace(r'\##', r'\#') \
                .replace(r'\makeatletter', '') \
                .replace(r'\makeatother', '') \
                .replace('\n', '%\n')
            outfile.write(
                '\\def\\PYstyle{0}{{%\n{1}%\n}}%\n'.format(stylename, styledefs))
            usedstyles.append(stylename)

        x = highlight(text, lexer, _fmter)

        m = re.match(r'\\begin\{Verbatim}(.*)\n([\s\S]*?)\n\\end\{Verbatim}(\s*)\Z',
                    x)
        if m:
            linenos = get_bool_opt(options, 'linenos', False)
            linenostart = abs(get_int_opt(options, 'linenostart', 1))
            linenostep = abs(get_int_opt(options, 'linenostep', 1))
            lines0 = m.group(2).split('\n')
            numbers = []
            lines = []
            counter = linenostart
            for line in lines0:
                line = re.sub(r'^ ', r'\\vphantom{Xy} ', line)
                line = re.sub(r' ', '~', line)
                if linenos:
                    if (counter - linenostart) % linenostep == 0:
                        line = r'\NLN_get:n {lineno:} {' + str(counter) + '}' + line
                        numbers.append(str(counter))
                    counter = counter + 1
                lines.append(line)
            outfile.write(Controller.SNIPPET_TEMPLATE %
                dict(
                    mode = 'inline' if inline_delim else 'display',
                    linenumbers = ','.join(numbers),
                    body      = '\\newline\n'.join(lines),
                )
            )

    def to_boolean(self,what):
        if what and type(what)==str:
            return re.match("^\s*[tTyY]") != None
        return not not what

    def pyg_code(self, text, inline_delim = True):
        options = self.options
        try:
            lexer = get_lexer_by_name(options.lang)
        except ClassNotFound as err:
            sys.stderr.write('Error: ')
            sys.stderr.write(str(err))
            return ""

        formatter = NLNLatexFormatter()

        escapeinside = options.escapeinside
        if len(escapeinside) == 2:
            left = escapeinside[0]
            right = escapeinside[1]
            formatter.escapeinside = escapeinside
            formatter.left = left
            formatter.right = right
            lexer = LatexEmbeddedLexer(left, right, lexer)

        gobble = abs(int(options.gobble))
        if gobble:
            lexer.add_filter('gobble', n=gobble)

        tabsize = abs(int(options.tabsize))
        if tabsize:
            lexer.tabsize = tabsize

        lexer.encoding = ''

        stylename = options.sty

        formatter.style = get_style_by_name(stylename)
        formatter._create_stylesheet()

        formatter.texcomments = self.to_boolean(options.texcomments)
        formatter.mathescape = self.to_boolean(options.mathescape)

        styledefs = formatter.get_style_defs() \
            .replace('#', '##') \
            .replace(r'\##', r'\#') \
            .replace(r'\makeatletter', '') \
            .replace(r'\makeatother', '') \
            .replace('\n', '%\n')
        ans_style = '\\def\\PYstyle{0}{{%\n{1}%\n}}%\n'.format(stylename, styledefs)

        ans_code = []

        m = re.match(
            r'\\begin\{Verbatim}(.*)\n([\s\S]*?)\n\\end\{Verbatim}(\s*)\Z',
            highlight(text, lexer, formatter)
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
                line = re.sub(r'^ ', r'\\vphantom{Xy} ', line)
                line = re.sub(r' ', '~', line)
                if linenos:
                    if (counter - linenostart) % linenostep == 0:
                        line = rf'\NLN_get:n {{lineno:}}{{{counter}}}' + line
                        numbers.append(str(counter))
                    counter += 1
                lines.append(line)
            if inline_delim:
                ans_code.append(self.SNIPPET_TEMPLATE %
                    dict(
                        mode = 'inline',
                        number    = 'zero',
                        body      = '\\newline\n'.join(lines)
                    )
                )
            else:
                if linenos:
                    template = self.DISPLAY_LINENOS_SNIPPET_TEMPLATE
                else:
                    template = self.DISPLAY_SNIPPET_TEMPLATE
                ans_code.append(template %
                    dict(number      = 'zero',
                        style       = stylename,
                        options     = '',
                        linenosep   = options.linenosep,
                        linenumbers = ','.join(numbers),
                        body        = '\\newline\n'.join(lines)))
        ans_code = "".join(ans_code)
        ans_code = re.sub(
            r"\\expandafter\\def\\csname\s*(.*?)\\endcsname",
            r'\\cs_new:cpn{\1}',
            ans_code,
            flags=re.M
        )
        ans_code = re.sub(
            r"\\csname\s*(.*?)\\endcsname",
            r'\\use:c{\1}',
            ans_code,
            flags=re.M
        )
        return ans_code, ans_style


    def parse_opts(self, basedic, opts):
        dic = basedic.copy()
        for opt in re.split(r'\s*,\s*', opts):
            x = re.split(r'\s*=\s*', opt)
            if len(x) == 2 and x[0] and x[1]:
                dic[x[0]] = x[1]
            elif len(x) == 1 and x[0]:
                dic[x[0]] = True
        return dic


    def convert(self, code, outfile, outencoding):
        """
        Convert ``code``
        """
        outfile.write(Controller.GENERIC_DEFINITIONS_1)

        opts = { 'lang'      : 'c',
                'sty'       : 'default',
                'linenosep' : '0pt',
                'tabsize'   : '8',
                'encoding'  : 'guess',
            }

        usedstyles = [ ]

        pos = 0

        while pos < len(code):
            if code[pos].isspace():
                pos = pos + 1
                continue

            m = Controller._re_inline.match(code, pos)
            if m:
                self.pyg(outfile,
                    outencoding,
                    m.group(1),
                    self.parse_opts(opts, m.group(2)),
                    '',
                    m.group(3),
                    usedstyles,
                    True)
                pos = m.end()
                continue

            m = Controller._re_display.match(code, pos)
            if m:
                self.pyg(outfile,
                    outencoding,
                    m.group(1),
                    self.parse_opts(opts, m.group(2)),
                    '',
                    m.group(3),
                    usedstyles)
                pos = m.end()
                continue

            m = Controller._re_input.match(code, pos)
            if m:
                opts_new = self.parse_opts(opts, m.group(2))
                try:
                    filecontents, inencoding = self.read_input(m.group(3), opts_new['encoding'])
                except Exception as err:
                    print('Error: cannot read input file: ', err, file=sys.stderr)
                else:
                    self.pyg(outfile,
                        outencoding,
                        m.group(1),
                        opts_new,
                        "",
                        filecontents,
                        usedstyles)
                pos = m.end()
                continue

            sys.stderr.write('Error: invalid input file contents: ignoring')
            break

        outfile.write(Controller.GENERIC_DEFINITIONS_2)

    @property
    def debug(self):
        return self.to_boolean(self.arguments.debug)

    def tex_command(self, cmd):
        print(f'<tex command>{cmd}</tex command>')

    def convert_code(self):
        """
        Convert ``code``
        """
        code = self.arguments.code
        if not code:
            return False
        h = hashlib.md5(str(code).encode('utf-8'))
        out_p = (self.directory_p / h.hexdigest()).with_suffix(".pyg.tex")
        if self.arguments.cache and out_p.exists():
            print("Already available")
            return 0
        with out_p.open(mode='w',encoding='utf-8') as f:
            f.write(self.GENERIC_DEFINITIONS_1)
            opts = {
                'lang'      : 'c',
                'sty'       : 'default',
                'linenosep' : '0pt',
                'tabsize'   : '4',
                'encoding'  : 'guess',
            }
            self.options = self.Options(
                self.arguments.pygment_options,
                opts
            )
            #if self.debug:
            print(f'DEBUG:{self.options}')
            f.write(self.pyg_code(code,True))
            f.write(self.GENERIC_DEFINITIONS_2)

        print("PREMATURE EXIT")
        self.tex_command(rf"""%
\\let\\NLN@snippet@zero\\relax
\\input{self.output_p}%
\\NLN@snippet@zero
""")
        exit(1)


if __name__ == '__main__':
    
    try:
        ctrl = Controller()
        sys.exit(ctrl.process())
    except KeyboardInterrupt:
        sys.exit(1)
