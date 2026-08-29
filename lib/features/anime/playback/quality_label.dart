/// 把 HLS 变体的 `RESOLUTION` 折算成大家认得出的清晰度档。
///
/// 直接拿高当标签会得到「608p」:1920×608 是 2.35:1 的宽银幕番剧,画面确实只有
/// 608 行,数字没错,但没人这么叫它 —— 用户认的是「1080P / 720P」这一套。所以
/// 先把宽换算回 16:9 的等效高,和真实高取大者再归档;4:3 的 1440×1080 也就不会
/// 被算成 720P。
library;

const _tiers = [2160, 1440, 1080, 720, 576, 480, 360, 240];

/// 归档后的清晰度名;宽高都不知道时返回 null,由调用方回退到码率。
String? qualityTierLabel({int? width, int? height}) {
  final lines = _effectiveLines(width: width, height: height);
  if (lines == null) return null;
  for (final tier in _tiers) {
    // 留 5% 余量:1918×1076 这种非整数分辨率不该掉一整档。
    if (lines >= tier - tier ~/ 20) return tier == 2160 ? '4K' : '${tier}P';
  }
  return '${lines}P';
}

/// `1920×608`。归档撞车时补在档位后面,好让两条变体分得开。
String? exactResolution({int? width, int? height}) =>
    width == null || height == null ? null : '$width×$height';

int? _effectiveLines({int? width, int? height}) {
  final widthEquivalent = width == null ? null : (width * 9 / 16).round();
  final candidates = [height, widthEquivalent].whereType<int>();
  if (candidates.isEmpty) return null;
  return candidates.reduce((left, right) => left > right ? left : right);
}
