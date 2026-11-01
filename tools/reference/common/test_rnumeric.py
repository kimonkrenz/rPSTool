#!/usr/bin/env python3
"""Python -> R round-trip tests for rnumeric.r_number (development only).

Every finite value is written as an R literal, evaluated by Rscript, returned through
``writeBin(x, raw(), size = 8)`` and compared as raw binary64 bits. Usage:

    python3 tools/reference/common/test_rnumeric.py

Rscript is run with the R build of the current machine, so run this on every platform
whose R parser matters (notably Apple Silicon).
"""
import math, pathlib, random, re, struct, subprocess, sys, tempfile, unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from rnumeric import MAX_EXACT_INT, r_number  # noqa: E402


def bits(x):
    """Big-endian binary64 hex (most significant byte first), matching R's endian="big"."""
    return struct.pack('>d', x).hex()


def r_roundtrip(literals):
    """Evaluate R literals; return per-element (raw binary64 hex, is_nan, is_inf, sign)."""
    code = ('x <- c(%s)\n' % ', '.join(literals) +
            'stopifnot(is.double(x), length(x) == %d)\n' % len(literals) +
            'raw_hex <- vapply(seq_along(x), function(i) paste(as.character(writeBin(x[i], raw(), size = 8L, endian = "big")), collapse = ""), "")\n'
            'cat(sprintf("%s %d %d %d", raw_hex, is.nan(x), is.infinite(x), !is.na(x) & x < 0), sep = "\\n")\n')
    # Rscript -e silently rejects long expressions, so always run a script file.
    with tempfile.TemporaryDirectory() as d:
        script = pathlib.Path(d) / 'roundtrip.R'
        script.write_text(code)
        out = subprocess.run(['Rscript', '--vanilla', str(script)], capture_output=True, text=True,
                             stdin=subprocess.DEVNULL, timeout=300)
    if out.returncode:
        raise RuntimeError(out.stderr)
    rows = []
    for line in out.stdout.strip().split('\n'):
        h, nan, inf, neg = line.split()
        rows.append((h, int(nan), int(inf), int(neg)))
    return rows


def decimal_double_only_parse(text):
    """Emulate R_strtod when `long double` is binary64 (documentation of the defect)."""
    neg = text.startswith('-')
    m = re.fullmatch(r'-?(\d*)\.?(\d*)(?:[eE]([-+]?\d+))?', text)
    ip, fp, ex = m.group(1), m.group(2), int(m.group(3) or 0)
    ans = 0.0
    for d in ip + fp:
        ans = 10.0 * ans + float(int(d))
    expn = ex - len(fp)
    p10, fac, n = 10.0, 1.0, abs(expn)
    while n:
        if n & 1:
            fac *= p10
        n >>= 1
        p10 *= p10
    ans = ans / fac if expn < 0 else ans * fac
    return -ans if neg else ans


class RNumericContract(unittest.TestCase):
    def test_float_hex_is_returned_unchanged(self):
        for v in (1.5, -0.0, 0.0, 5e-324, 1.7976931348623157e308, -9.536743128535363e-08):
            self.assertEqual(r_number(v), v.hex())

    def test_non_finites_and_types(self):
        self.assertEqual(r_number(float('nan')), 'NaN')
        self.assertEqual(r_number(math.inf), 'Inf')
        self.assertEqual(r_number(-math.inf), '-Inf')
        for bad in (True, False, None, '1', [1.0]):
            with self.assertRaises(TypeError):
                r_number(bad)

    def test_integer_contract_is_explicit(self):
        self.assertEqual(r_number(0), '0')
        self.assertEqual(r_number(-7), '-7')
        self.assertEqual(r_number(MAX_EXACT_INT), str(MAX_EXACT_INT))
        self.assertEqual(r_number(-MAX_EXACT_INT), str(-MAX_EXACT_INT))
        # beyond 2**53 only exactly representable integers are accepted, as hex
        self.assertEqual(r_number(2 ** 60), float(2 ** 60).hex())
        self.assertEqual(r_number(MAX_EXACT_INT + 2), float(MAX_EXACT_INT + 2).hex())
        with self.assertRaises(ValueError):
            r_number(MAX_EXACT_INT + 1)
        with self.assertRaises(ValueError):
            r_number(2 ** 64 + 1)
        with self.assertRaises(OverflowError):
            r_number(10 ** 400)

    def test_known_decimal_defects_are_real_and_hex_avoids_them(self):
        # Literals recorded from the actual Apple-Silicon failures.
        for v in (-9.536743128535363e-08, 3.4028234663852886e+38):
            self.assertNotEqual(decimal_double_only_parse(repr(v)), v, repr(v))


class RRoundTrip(unittest.TestCase):
    maxDiff = None

    def check(self, values):
        literals = [r_number(v) for v in values]
        rows = r_roundtrip(literals)
        self.assertEqual(len(rows), len(values))
        for v, lit, (h, isnan, isinf, neg) in zip(values, literals, rows):
            if isinstance(v, float) and math.isnan(v):
                self.assertEqual(isnan, 1, lit)
            elif isinstance(v, float) and math.isinf(v):
                self.assertEqual((isinf, neg), (1, int(v < 0)), lit)
            else:
                self.assertEqual(h, bits(float(v)), lit)

    def test_known_mac_parser_failures(self):
        self.check([-9.536743128535363e-08, 3.4028234663852886e+38, 1.0000000476837156,
                    -1.0000000953674313, 0.1, 1e-5, 4.5e-7, 123456789.12345679])

    def test_signed_zero(self):
        self.check([0.0, -0.0])
        rows = r_roundtrip([r_number(-0.0), r_number(0.0)])
        self.assertNotEqual(rows[0][0], rows[1][0])  # -0 and +0 have distinct bit patterns

    def test_non_finites(self):
        self.check([float('nan'), math.inf, -math.inf])

    def test_large_finite_floats(self):
        self.check([1.7976931348623157e308, -1.7976931348623157e308, 1e300, 3.4028234663852886e+38,
                    2.2250738585072014e-308, 1e22, 1e23, 9007199254740993.0 * 2.0])

    def test_integral_doubles_and_integers(self):
        self.check([0.0, 1.0, -3.0, 1e15, 2.0 ** 53, 2.0 ** 53 + 2.0, 4294967295.0,
                    0, 5, -7, MAX_EXACT_INT, -MAX_EXACT_INT, 2 ** 60, 2 ** 100])

    def test_subnormals(self):
        # smallest, boundary values, arbitrary mantissas, the largest subnormal and a negative one
        sub = [struct.unpack('>d', struct.pack('>Q', n))[0] for n in
               (1, 2, 3, 0x000FFFFFFFFFFFFF, 0x0008000000000000, 0x0000000100000001,
                0x8000000000000001, 0x800FFFFFFFFFFFFF)]
        sub += [5e-324, 2.5e-323, 2.225073858507201e-308]
        self.check(sub)

    def test_random_binary64_bits(self):
        rng = random.Random(20261011)
        vals = []
        while len(vals) < 4000:
            v = struct.unpack('>d', struct.pack('>Q', rng.getrandbits(64)))[0]
            if math.isfinite(v):
                vals.append(v)
        self.check(vals)

    def test_random_float32_widened_values(self):
        # fixtures mostly hold binary32 results widened to binary64
        rng = random.Random(7)
        vals = []
        while len(vals) < 4000:
            v = struct.unpack('>f', struct.pack('>I', rng.getrandbits(32)))[0]
            if math.isfinite(v):
                vals.append(float(v))
        self.check(vals)


if __name__ == '__main__':
    unittest.main(verbosity=2)
