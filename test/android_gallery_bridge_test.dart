import 'package:dream_manga_reader/core/platform/android_gallery_bridge.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('dream_manga_reader/gallery');
  final calls = <MethodCall>[];
  Object? Function(MethodCall call) handler = (_) => null;

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return handler(call);
    });
  });

  tearDown(() {
    handler = (_) => null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('an image goes to the platform with its name and type', () async {
    handler = (_) => 'DCIM/DreamMangaReader/shot.jpg';
    final bridge = AndroidGalleryBridge(channel: channel, enabled: true);

    final saved = await bridge.saveImage(
      bytes: Uint8List.fromList(const [1, 2, 3]),
      fileName: 'shot.jpg',
    );

    expect(saved, 'DCIM/DreamMangaReader/shot.jpg');
    expect(calls.single.method, 'saveImage');
    final arguments = calls.single.arguments as Map;
    expect(arguments['fileName'], 'shot.jpg');
    expect(arguments['mimeType'], 'image/jpeg');
    expect(arguments['bytes'], isA<Uint8List>());
  });

  // 桌面没有相册这回事。返回 null 让调用方落自己的目录 —— 把「这个平台没有」
  // 当成保存失败报给用户是错的。
  test('a platform without a gallery answers null without calling out',
      () async {
    final bridge = AndroidGalleryBridge(channel: channel, enabled: false);

    expect(
      await bridge.saveImage(
        bytes: Uint8List.fromList(const [1]),
        fileName: 'shot.jpg',
      ),
      isNull,
    );
    expect(calls, isEmpty);
  });

  test('a refused save surfaces as an error, not as a silent null', () async {
    handler = (_) => throw PlatformException(code: 'permission_denied');
    final bridge = AndroidGalleryBridge(channel: channel, enabled: true);

    expect(
      () => bridge.saveImage(
        bytes: Uint8List.fromList(const [1]),
        fileName: 'shot.jpg',
      ),
      throwsA(isA<PlatformException>()),
    );
  });
}
