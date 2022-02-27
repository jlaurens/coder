#! /usr/bin/env python3
# -*- coding: utf-8 -*-

"""
    PygmenTeX
    ~~~~~~~~~

    PygmenTeX is a converter that do syntax highlighting of snippets of
    source code extracted from a LaTeX file.

    :copyright: Copyright 2020 by José Romildo Malaquias
    :license: BSD, see LICENSE for details
"""

__version__ = '0.10'
__docformat__ = 'restructuredtext'

from posixpath import split
import sys
import argparse
import re
from os.path import splitext
from pathlib import Path
from io import StringIO
import hashlib

from pygments import highlight
from pygments.styles import get_style_by_name
from pygments.lexers import get_lexer_by_name
from pygments.formatters.latex import LatexFormatter, escape_tex, _get_ttype_name
from pygments.util import get_bool_opt, get_int_opt, ClassNotFound
from pygments.lexer import Lexer
from pygments.token import Token
from pygments.util import guess_decode

###################################################
# The following code is in >=pygments-2.0
###################################################
class EnhancedLatexFormatter(LatexFormatter):
    r"""
    This is an enhanced LaTeX formatter.
    """
    name = 'EnhancedLaTeX'
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
###################################################

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

    INLINE_SNIPPET_TEMPLATE = r'''\expandafter\def\csname NLN@snippet@%(number)s\endcsname{%%
\NLN@snippet@inlined{%%
%(body)s%%
}}'''

    DISPLAY_SNIPPET_TEMPLATE = r'''\
\expandafter\def\csname NLN@snippet@%(number)s\endcsname{%%
\begin{NLN@snippet@framed}%%
%(body)s%%
\end{NLN@snippet@framed}%%
}\
'''

    DISPLAY_LINENOS_SNIPPET_TEMPLATE = r'''\
\expandafter\def\csname NLN@snippet@%(number)s\endcsname{%%
\begingroup
    \def\NLN@alllinenos{(%(linenumbers)s)}%%
    \begin{NLN@snippet@framed}%%
%(body)s%%
    \end{NLN@snippet@framed}%%
\endgroup
}
'''

    @property
    def code(self):
        return self.arguments.code

    _input_p = None
    @property
    def input_p(self):
        p = self._input_p
        if p:
            return p
        else:
            p = self.arguments.input
            if p:
                p = Path(p).resolve()
        self._input_p = p
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
            p = self.input_p
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
            p = self.input_p
            if p:
                p = p.with_suffix(".pyg.tex")
        self._output_p = p
        return p

    class Arguments:
        cache = False
        code = ""
        input = ""
        output = ""
        directory = ""

        def __repr__(self):
            return f'<Arguments: {repr(self.__dict__)}>'

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
            version='XPygmenTeX version %s, (c) 2022 by Jérôme LAURENS.' % __version__
        )
        group = parser.add_argument_group('pygmentize')
        group.add_argument(
            "-d","--directory",
            help="""\
name of the directory where the pygmented file are collected,
either input or output.
""",
            default=None,
        )
        group.add_argument(
            "-m","--mode",
            help="switch to inline or display mode",
            choices=("code","inline","display"),
            default=None,
        )
        group.add_argument(
            "-e","--escape",
            help="""\
Enables escaping to LaTex. Text delimited by the <left>
and <right> characters is read as LaTeX code and typeset accordingly. It
has no effect in string literals. It has no effect in comments if
`texcomments` or `mathescape` is set.
""",
            action='store_true'
        )
        group.add_argument(
            "-i","--input",
            default=None,
            help="""\
input file name, including the extension, which is in general ".txt".
    The input file should consist of a sequence of source code snippets, as
produced by the `pygmentex` LaTeX package. Each code snippet is
highlighted using Pygments, and a LaTeX command that expands to the
highlighted code snippet is written to the output file.\
"""
        )
        group.add_argument(
            "-c","--code",
            default=None,
            help="raw input code snippet to be furher processed by pygment"
        )
        group.add_argument(
            "-p","--pygment-options",
            default=None,
            help="cumulated options forwarded to pygment",
            action='append'
        )
        group.add_argument(
            "--debug",
            default=None,
            help="display informations useful for debugging"
        )
        return parser

    class Options:
        lang = ""
        escapeinside = ""
        gobble = 0
        tabsize = 0
        sty = 'default'
        texcomments = False
        mathescape =  False
        linenos = False
        linenostart = 1
        linenostep = 1
        def __init__(self, pygment_options, defaults):
            if defaults:
                for k, v in defaults.items():
                    setattr(self, k, v)
            if pygment_options:
                for o in pygment_options:
                    m = re.match(r'^(.*?)\s*=\s*(.*)$', o)
                    if m:
                        setattr(self, m.group(1), m.group(2))
                    else:
                        setattr(self, o, True)

        def __repr__(self):
            return f"<Pygment options: {repr(self.__dict__)}>"

    def __init__(self, argv = sys.argv):
        argv = argv[1:] if re.match(".*pygmentex\.py$", argv[0]) else argv
        arguments = self.Arguments()
        self.parser.parse_args(
            argv if len(argv) else ['-h'],
            namespace=arguments
        )
        print(arguments)
        self.arguments = arguments
        print("INPUT", self.input_p)
        print("OUTPUT DIR", self.directory_p)
        print("OUTPUT", self.output_p)

    def process(self):
        """
        Main command line entry point.
        """
        arguments = self.arguments
        if arguments.code:
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

    def pyg(self, outfile, outencoding, n, opts, extra_opts, text, usedstyles, inline_delim = True):
        try:
            lexer = get_lexer_by_name(opts['lang'])
        except ClassNotFound as err:
            sys.stderr.write('Error: ')
            sys.stderr.write(str(err))
            return ""

        # global _fmter
        _fmter = EnhancedLatexFormatter()

        escapeinside = opts.get('escapeinside', '')
        if len(escapeinside) == 2:
            left = escapeinside[0]
            right = escapeinside[1]
            _fmter.escapeinside = escapeinside
            _fmter.left = left
            _fmter.right = right
            lexer = LatexEmbeddedLexer(left, right, lexer)

        gobble = abs(get_int_opt(opts, 'gobble', 0))
        if gobble:
            lexer.add_filter('gobble', n=gobble)

        tabsize = abs(get_int_opt(opts, 'tabsize', 0))
        if tabsize:
            lexer.tabsize = tabsize

        lexer.encoding = ''
        # _fmter.encoding = outencoding

        stylename = opts['sty']

        _fmter.style = get_style_by_name(stylename)
        _fmter._create_stylesheet()

        _fmter.texcomments = get_bool_opt(opts, 'texcomments', False)
        _fmter.mathescape = get_bool_opt(opts, 'mathescape', False)

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
            linenos = get_bool_opt(opts, 'linenos', False)
            linenostart = abs(get_int_opt(opts, 'linenostart', 1))
            linenostep = abs(get_int_opt(opts, 'linenostep', 1))
            lines0 = m.group(2).split('\n')
            numbers = []
            lines = []
            counter = linenostart
            for line in lines0:
                line = re.sub(r'^ ', r'\\vphantom{Xy} ', line)
                line = re.sub(r' ', '~', line)
                if linenos:
                    if (counter - linenostart) % linenostep == 0:
                        line = r'\NLN@lineno@do{' + str(counter) + '}' + line
                        numbers.append(str(counter))
                    counter = counter + 1
                lines.append(line)
            if inline_delim:
                outfile.write(Controller.INLINE_SNIPPET_TEMPLATE %
                    dict(number    = n,
                        style     = stylename,
                        options   = extra_opts,
                        body      = '\\newline\n'.join(lines)))
            else:
                if linenos:
                    template = Controller.DISPLAY_LINENOS_SNIPPET_TEMPLATE
                else:
                    template = Controller.DISPLAY_SNIPPET_TEMPLATE
                outfile.write(template %
                    dict(number      = n,
                        style       = stylename,
                        options     = extra_opts,
                        linenosep   = opts['linenosep'],
                        linenumbers = ','.join(numbers),
                        body        = '\\newline\n'.join(lines)))


    def to_boolean(self,what):
        if what and type(what)==str:
            return re.match("^\s*[tTyY]") != None
        return not not what

    def pyg_code(self, text, inline_delim = True):
        opts = self.options
        try:
            lexer = get_lexer_by_name(opts.lang)
        except ClassNotFound as err:
            sys.stderr.write('Error: ')
            sys.stderr.write(str(err))
            return ""

        # global _fmter
        _fmter = EnhancedLatexFormatter()

        escapeinside = opts.escapeinside
        if len(escapeinside) == 2:
            left = escapeinside[0]
            right = escapeinside[1]
            _fmter.escapeinside = escapeinside
            _fmter.left = left
            _fmter.right = right
            lexer = LatexEmbeddedLexer(left, right, lexer)

        gobble = abs(int(opts.gobble))
        if gobble:
            lexer.add_filter('gobble', n=gobble)

        tabsize = abs(int(opts.tabsize))
        if tabsize:
            lexer.tabsize = tabsize

        lexer.encoding = ''
        # _fmter.encoding = outencoding

        stylename = opts.sty

        _fmter.style = get_style_by_name(stylename)
        _fmter._create_stylesheet()

        _fmter.texcomments = self.to_boolean(opts.texcomments)
        _fmter.mathescape = self.to_boolean(opts.mathescape)

        styledefs = _fmter.get_style_defs() \
            .replace('#', '##') \
            .replace(r'\##', r'\#') \
            .replace(r'\makeatletter', '') \
            .replace(r'\makeatother', '') \
            .replace('\n', '%\n')
        ans = []
        ans.append('\\def\\PYstyle{0}{{%\n{1}%\n}}%\n'.format(stylename, styledefs))

        x = highlight(text, lexer, _fmter)

        m = re.match(r'\\begin\{Verbatim}(.*)\n([\s\S]*?)\n\\end\{Verbatim}(\s*)\Z',
                    x)
        if m:
            linenos = self.to_boolean(opts.linenos)
            linenostart = abs(int(opts.linenostart))
            linenostep = abs(int(opts.linenostep))
            lines0 = m.group(2).split('\n')
            numbers = []
            lines = []
            counter = linenostart
            for line in lines0:
                line = re.sub(r'^ ', r'\\vphantom{Xy} ', line)
                line = re.sub(r' ', '~', line)
                if linenos:
                    if (counter - linenostart) % linenostep == 0:
                        line = rf'\NLN@lineno@do{{{counter}}}' + line
                        numbers.append(str(counter))
                    counter = counter + 1
                lines.append(line)
            if inline_delim:
                ans.append(self.INLINE_SNIPPET_TEMPLATE %
                    dict(number    = 'zero',
                        style     = stylename,
                        options   = '',
                        body      = '\\newline\n'.join(lines)))
            else:
                if linenos:
                    template = self.DISPLAY_LINENOS_SNIPPET_TEMPLATE
                else:
                    template = self.DISPLAY_SNIPPET_TEMPLATE
                ans.append(template %
                    dict(number      = '00',
                        style       = stylename,
                        options     = '',
                        linenosep   = opts.linenosep,
                        linenumbers = ','.join(numbers),
                        body        = '\\newline\n'.join(lines)))
        ans = "".join(ans)
        ans = re.sub(
            r"\\expandafter\\def\\csname\s*(.*?)\\endcsname",
            r'\\cs_new:cpn{\1}',
            ans,
            flags=re.M
        )
        ans = re.sub(
            r"\\csname\s*(.*?)\\endcsname",
            r'\\use:c{\1}',
            ans,
            flags=re.M
        )
        return ans


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
                'tabsize'   : '8',
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

    def read_input(self, filename, encoding):
        with open(filename, 'rb') as infp:
            code = infp.read()
        if not encoding or encoding == 'guess':
            code, encoding = guess_decode(code)
        else:
            code = code.decode(encoding)

        return code, encoding


if __name__ == '__main__':
    
    try:
        ctrl = Controller()
        sys.exit(ctrl.process())
    except KeyboardInterrupt:
        sys.exit(1)
