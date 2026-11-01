#!/usr/bin/env python3
"""Focused tests for hexify-fixture.py (development only).

Usage: python3 tools/reference/common/test_hexify_fixture.py
"""
import importlib.util, pathlib, sys, unittest

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
spec = importlib.util.spec_from_file_location('hexify_fixture', HERE / 'hexify-fixture.py')
hx = importlib.util.module_from_spec(spec)
spec.loader.exec_module(hx)
from rnumeric import r_number  # noqa: E402


def convert(text):
    return hx.convert(text)[0]


class AcceptedGrammar(unittest.TestCase):
    def test_numbers_in_code_are_rewritten_exactly(self):
        out = convert('list(a = 0.5, b = -9.536743128535363e-08, c = 3.4028234663852886e+38, d = 1e5)')
        self.assertEqual(out, 'list(a = %s, b = -%s, c = %s, d = %s)' % (
            r_number(0.5), r_number(9.536743128535363e-08), r_number(3.4028234663852886e+38), r_number(1e5)))

    def test_comments_and_double_quoted_strings_are_untouched(self):
        text = '# header 0.5 and \'quotes" in a comment\nlist(s = "x 0.25 \\"0.75\\" \'y\' 1e-5", n = 0.5)\n'
        out = convert(text)
        self.assertIn('# header 0.5 and \'quotes" in a comment', out)
        self.assertIn('"x 0.25 \\"0.75\\" \'y\' 1e-5"', out)       # string content verbatim, escapes included
        self.assertTrue(out.rstrip().endswith('n = %s)' % r_number(0.5)))

    def test_apostrophe_in_comment_or_string_is_not_a_single_quoted_string(self):
        self.assertEqual(convert("# don't convert 0.5\nx <- 1\n"), "# don't convert 0.5\nx <- 1\n")
        self.assertEqual(convert('x <- "it\'s 0.5"\n'), 'x <- "it\'s 0.5"\n')

    def test_integers_follow_the_rnumeric_contract(self):
        self.assertEqual(convert('c(7, 1000000000000000, 9007199254740992, 12L)'),
                         'c(7, 1000000000000000, 9007199254740992, 12L)')       # exact, untouched
        with self.assertRaises(ValueError):                                      # > 2**53 and not representable
            convert('c(9007199254740993)')
        self.assertEqual(convert('c(9007199254740994)'), 'c(%s)' % r_number(9007199254740994))  # exact -> hex

    def test_existing_hex_and_named_constants_are_untouched(self):
        text = 'c(0x1.8p+1, 0x0p+0, NaN, Inf, -Inf, NA_real_, TRUE)'
        self.assertEqual(convert(text), text)


class OutsideAcceptedGrammarFailsClosed(unittest.TestCase):
    def test_single_quoted_string_is_rejected(self):
        with self.assertRaises(ValueError):
            convert("list(s = 'x 0.5', n = 0.5)")

    def test_backtick_name_is_rejected(self):
        with self.assertRaises(ValueError):
            convert('`a b` <- 0.5')

    def test_raw_string_is_rejected(self):
        for text in ('x <- r"(0.5)"', 'x <- R"(a"b 0.5)"', 'f(r"[0.5]")'):
            with self.assertRaises(ValueError, msg=text):
                convert(text)
        # an identifier that merely ends in r followed by a separate string is not a raw-string prefix
        self.assertEqual(convert('paste(per, "0.5")'), 'paste(per, "0.5")')

    def test_unterminated_string_is_rejected(self):
        with self.assertRaises(ValueError):
            convert('x <- "0.5')


class RealFixtures(unittest.TestCase):
    def test_every_generated_direct_fixture_is_inside_the_grammar(self):
        root = HERE.parents[2] / 'tests' / 'testthat' / 'fixtures'
        files = sorted(root.glob('*-direct-v3.3.2.R'))
        self.assertGreaterEqual(len(files), 10)
        for f in files:
            converted, _ = hx.convert(f.read_text())
            self.assertEqual(converted, hx.convert(converted)[0], f.name)      # idempotent: nothing left to rewrite


if __name__ == '__main__':
    unittest.main(verbosity=2)
