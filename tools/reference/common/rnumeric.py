"""Exact R numeric literals for development-only reference fixture generators.

R's decimal literal parser is not required to be correctly rounded: it accumulates
digits and scales by a power of ten in `long double`, so builds whose `long double`
is only binary64 (for example Apple Silicon) can differ from the intended double by
one ULP. Hexadecimal literals are exact on every supported R build, so direct-PST
reference fixtures must never contain non-integer decimal numerics.

Contract
--------
* ``float`` finite values  -> ``float.hex(v)`` unchanged (sign, signed zero, normal
  and subnormal values all round-trip to the identical binary64 bit pattern).
* ``float`` NaN            -> ``NaN`` (R has no portable payload; payloads and the
  sign of NaN are not preserved and are not part of the fixture contract).
* ``float`` +/-infinity    -> ``Inf`` / ``-Inf``.
* ``int`` with |v| <= 2**53 -> plain decimal digits. Digit accumulation is exact up
  to 2**53 in binary64 on every R build, and R reads the literal as a double.
* ``int`` with |v| > 2**53  -> ``float.hex(float(v))`` when ``float(v) == v`` (the
  integer is exactly representable); otherwise ``ValueError``, because no exact
  binary64 value exists.
* ``bool`` and every other type are rejected (``TypeError``); callers format them.

This module is a development tool. It is not installed with the package and has no
runtime role.
"""
import math

MAX_EXACT_INT = 2 ** 53


def r_number(v):
    """Return the R source literal for a Python int or float (see module contract)."""
    if isinstance(v, bool) or not isinstance(v, (int, float)):
        raise TypeError('r_number accepts int or float, not %s' % type(v).__name__)
    if isinstance(v, int):
        if abs(v) <= MAX_EXACT_INT:
            return str(v)
        f = float(v)  # OverflowError for ints beyond binary64 range
        if f != v:
            raise ValueError('integer %d is not exactly representable as binary64' % v)
        return f.hex()
    if math.isnan(v):
        return 'NaN'
    if math.isinf(v):
        return 'Inf' if v > 0 else '-Inf'
    return v.hex()
