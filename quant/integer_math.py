"""작은 정수 계산의 기준. 실제 학습 모델의 exporter가 아니다.

Python int를 사용해 기준 구현의 중간 overflow를 피한다.
"""
from fractions import Fraction


def rne_div(value, divisor):
    """가장 가까운 정수, 정확한 동점은 짝수. 음수에도 같은 규칙 적용."""
    if divisor <= 0:
        raise ValueError("divisor must be positive")
    sign = -1 if value < 0 else 1
    q, r = divmod(abs(int(value)), int(divisor))
    if 2 * r > divisor or (2 * r == divisor and q % 2):
        q += 1
    return sign * q


def multiplier_shift(ratio, shift=24):
    if not 0 <= shift <= 31 or ratio < 0:
        raise ValueError("nonnegative ratio and shift 0..31 required")
    f = Fraction(str(ratio)) * (1 << shift)
    n = rne_div(f.numerator, f.denominator)
    if n > (1 << 31) - 1:
        raise ValueError("multiplier exceeds signed 32 bits; choose a smaller shift")
    return n, shift


def requantize(acc, multiplier, shift, zero_point=0, lo=-128, hi=127, relu=False):
    if not 0 <= shift <= 31 or multiplier < 0 or lo > hi or not lo <= zero_point <= hi:
        raise ValueError("invalid quantization contract")
    q = rne_div(int(acc) * int(multiplier), 1 << shift) + zero_point
    if relu:
        q = max(q, zero_point)
    return min(hi, max(lo, q))


def aligned_add(a, b, multiplier_a, multiplier_b, shift, zero_a=0, zero_b=0,
                zero_out=0, relu=True):
    # 공통 분모에서 더한 뒤 한 번만 반올림하는 계약.
    wide = (int(a) - zero_a) * multiplier_a + (int(b) - zero_b) * multiplier_b
    return requantize(wide, 1, shift, zero_out, relu=relu)
