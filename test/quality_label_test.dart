import 'package:dream_manga_reader/features/anime/playback/quality_label.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a resolution lands in the tier viewers recognise', () {
    expect(qualityTierLabel(width: 3840, height: 2160), '4K');
    expect(qualityTierLabel(width: 1920, height: 1080), '1080P');
    expect(qualityTierLabel(width: 1280, height: 720), '720P');
    expect(qualityTierLabel(width: 854, height: 480), '480P');
    expect(qualityTierLabel(width: 640, height: 360), '360P');
  });

  test('letterboxing does not cost a tier', () {
    // 2.35:1 的宽银幕:画面只有 608 行,但它就是一部 1080P 的片子。
    expect(qualityTierLabel(width: 1920, height: 608), '1080P');
    expect(qualityTierLabel(width: 1280, height: 536), '720P');
  });

  test('a 4:3 frame is judged by its height, not its width', () {
    expect(qualityTierLabel(width: 1440, height: 1080), '1080P');
  });

  test('an off-by-a-few encode does not drop a whole tier', () {
    expect(qualityTierLabel(width: 1918, height: 1076), '1080P');
  });

  test('an unknown resolution has no tier to report', () {
    expect(qualityTierLabel(), isNull);
    expect(exactResolution(width: 1920), isNull);
  });

  test('the exact resolution reads the way a spec sheet does', () {
    expect(exactResolution(width: 1920, height: 608), '1920×608');
  });
}
