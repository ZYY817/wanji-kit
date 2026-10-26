// 3D simplex 噪声（Gustavson 移植）——驱动液态球面顶点扰动
import 'dart:math' as math;

class SimplexNoise {
  SimplexNoise([int seed = 0]) {
    final rnd = math.Random(seed);
    _perm = List<int>.filled(512, 0);
    final p = List<int>.generate(256, (i) => i)..shuffle(rnd);
    for (var i = 0; i < 512; i++) {
      _perm[i] = p[i & 255];
    }
  }

  late final List<int> _perm;

  static const _grad = [
    [1, 1, 0], [-1, 1, 0], [1, -1, 0], [-1, -1, 0],
    [1, 0, 1], [-1, 0, 1], [1, 0, -1], [-1, 0, -1],
    [0, 1, 1], [0, -1, 1], [0, 1, -1], [0, -1, -1],
  ];

  static const _f3 = 1.0 / 3.0;
  static const _g3 = 1.0 / 6.0;

  /// 返回 [-1, 1]
  double noise3(double xin, double yin, double zin) {
    final perm = _perm;
    final s = (xin + yin + zin) * _f3;
    final i = (xin + s).floor();
    final j = (yin + s).floor();
    final k = (zin + s).floor();
    final t = (i + j + k) * _g3;
    final x0 = xin - i + t;
    final y0 = yin - j + t;
    final z0 = zin - k + t;

    int i1, j1, k1, i2, j2, k2;
    if (x0 >= y0) {
      if (y0 >= z0) {
        i1 = 1; j1 = 0; k1 = 0; i2 = 1; j2 = 1; k2 = 0;
      } else if (x0 >= z0) {
        i1 = 1; j1 = 0; k1 = 0; i2 = 1; j2 = 0; k2 = 1;
      } else {
        i1 = 0; j1 = 0; k1 = 1; i2 = 1; j2 = 0; k2 = 1;
      }
    } else {
      if (y0 < z0) {
        i1 = 0; j1 = 0; k1 = 1; i2 = 0; j2 = 1; k2 = 1;
      } else if (x0 < z0) {
        i1 = 0; j1 = 1; k1 = 0; i2 = 0; j2 = 1; k2 = 1;
      } else {
        i1 = 0; j1 = 1; k1 = 0; i2 = 1; j2 = 1; k2 = 0;
      }
    }

    final x1 = x0 - i1 + _g3, y1 = y0 - j1 + _g3, z1 = z0 - k1 + _g3;
    final x2 = x0 - i2 + 2 * _g3, y2 = y0 - j2 + 2 * _g3, z2 = z0 - k2 + 2 * _g3;
    final x3 = x0 - 1 + 3 * _g3, y3 = y0 - 1 + 3 * _g3, z3 = z0 - 1 + 3 * _g3;

    final ii = i & 255, jj = j & 255, kk = k & 255;
    var n = 0.0;
    n += _corner(perm[ii + perm[jj + perm[kk]]] % 12, x0, y0, z0);
    n += _corner(
        perm[ii + i1 + perm[jj + j1 + perm[kk + k1]]] % 12, x1, y1, z1);
    n += _corner(
        perm[ii + i2 + perm[jj + j2 + perm[kk + k2]]] % 12, x2, y2, z2);
    n += _corner(
        perm[ii + 1 + perm[jj + 1 + perm[kk + 1]]] % 12, x3, y3, z3);
    return 32.0 * n;
  }

  static double _corner(int gi, double x, double y, double z) {
    var t = 0.6 - x * x - y * y - z * z;
    if (t < 0) return 0.0;
    t *= t;
    final g = _grad[gi];
    return t * t * (g[0] * x + g[1] * y + g[2] * z);
  }
}
