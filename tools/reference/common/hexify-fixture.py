#!/usr/bin/env python3
"""Value-preserving conversion of a generated R fixture's decimal numerics to exact hex literals.

Usage: hexify-fixture.py INPUT_R OUTPUT_R

Development only; this is not an R parser. It accepts exactly the grammar that the fixture
generators produce (``json.dumps`` / ``dput`` / ``rnumeric`` output):

* ``#`` comments to end of line (skipped, any content);
* double-quoted strings with backslash escapes (skipped, any content);
* everything else is code, in which only numeric tokens are rewritten.

Outside that grammar the converter refuses to run rather than guess: single-quoted strings,
backtick names, R 4.0 raw strings (``r"(...)"``) and unterminated strings raise ``ValueError``. A
check of every current and previous generated direct fixture found none of these constructs.

In code, integer-valued digit tokens (<= 2**53) and ``NNNL`` integers are left alone, digit
tokens above 2**53 go through ``rnumeric.r_number`` (exact hex or ``ValueError``), and every other
decimal token is replaced by ``rnumeric.r_number(float(token))``. Python's ``float()`` is correctly
rounded, so the result is the binary64 value the generator printed with ``repr``. Each rewritten
token is verified (``float.fromhex(new) == float(old)``). Layout, whitespace and comments are
untouched.
"""
import pathlib, re, sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from rnumeric import MAX_EXACT_INT, r_number  # noqa: E402

NUMBER = re.compile(r'(?<![\w.])(\d+\.\d*(?:[eE][-+]?\d+)?|\d+[eE][-+]?\d+|\.\d+(?:[eE][-+]?\d+)?|\d+)(?![\w.])')


def split_code(text):
    """Yield (is_code, segment) pieces; comments and double-quoted strings are not code.

    Raises ValueError for syntax outside the accepted grammar (see the module docstring).
    """
    i, n, start = 0, len(text), 0
    while i < n:
        c = text[i]
        if c == '#':
            if i > start:
                yield True, text[start:i]
            j = text.find('\n', i)
            j = n if j < 0 else j
            yield False, text[i:j]
            i = start = j
        elif c == '"':
            if i > 0 and text[i - 1] in 'rR' and (i < 2 or not (text[i - 2].isalnum() or text[i - 2] in '_.')):
                raise ValueError('R raw string at offset %d is outside the accepted grammar' % (i - 1))
            if i > start:
                yield True, text[start:i]
            j = i + 1
            while j < n and text[j] != '"':
                j += 2 if text[j] == '\\' else 1
            if j >= n:
                raise ValueError('unterminated string starting at offset %d' % i)
            yield False, text[i:j + 1]
            i = start = j + 1
        elif c in "'`":
            raise ValueError('%s at offset %d is outside the accepted grammar (single-quoted strings '
                             'and backtick names are not produced by the generators)' % (repr(c), i))
        else:
            i += 1
    if start < n:
        yield True, text[start:]


def convert(text):
    count = [0]

    def repl(m):
        tok = m.group(1)
        if tok.isdigit():  # integer-valued digit token: exact as written when <= 2**53
            if int(tok) <= MAX_EXACT_INT:
                return tok
            return r_number(int(tok))
        old = float(tok)
        new = r_number(old)
        if float.fromhex(new) != old:
            raise ValueError('inexact conversion of %r' % tok)
        count[0] += 1
        return new

    out = ''.join(NUMBER.sub(repl, seg) if is_code else seg for is_code, seg in split_code(text))
    return out, count[0]


if __name__ == '__main__':
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    text = pathlib.Path(sys.argv[1]).read_text()
    converted, n = convert(text)
    pathlib.Path(sys.argv[2]).write_text(converted)
    print('converted %d decimal numeric tokens' % n, file=sys.stderr)
