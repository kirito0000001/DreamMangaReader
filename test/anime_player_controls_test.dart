import 'package:dream_manga_reader/l10n/app_localizations.dart';
import 'package:dream_manga_reader/features/anime/anime_player_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the buffered head is drawn ahead of the playhead',
      (tester) async {
    await tester.pumpWidget(_controls(
      position: const Duration(minutes: 2),
      duration: const Duration(minutes: 10),
      buffered: const Duration(minutes: 3),
    ));

    final slider = tester.widget<Slider>(find.byType(Slider));
    expect(slider.secondaryTrackValue,
        const Duration(minutes: 3).inMilliseconds.toDouble());
    // 值传对了不代表画出来了 —— 轨道形状得真的铺一条缓冲色的段。
    expect(
      find.byType(Slider),
      paints
        ..something((method, arguments) =>
            method == #drawRect &&
            // 轨道颜色是 ColorTween 插出来的,浮点分量和字面量不逐位相等,
            // 比 32 位 ARGB。
            (arguments[1] as Paint).color.toARGB32() ==
                Colors.white38.toARGB32()),
    );
  });

  testWidgets('a buffer past the end of the media stays on the track',
      (tester) async {
    // Slider 断言 secondaryTrackValue 必须落在 [min, max] 里,越界会直接崩。
    await tester.pumpWidget(_controls(
      position: const Duration(minutes: 2),
      duration: const Duration(minutes: 10),
      buffered: const Duration(minutes: 30),
    ));

    final slider = tester.widget<Slider>(find.byType(Slider));
    expect(slider.secondaryTrackValue,
        const Duration(minutes: 10).inMilliseconds.toDouble());
  });

  testWidgets('an unknown duration draws no buffered head at all',
      (tester) async {
    await tester.pumpWidget(_controls(
      position: Duration.zero,
      duration: Duration.zero,
      buffered: const Duration(seconds: 20),
    ));

    final slider = tester.widget<Slider>(find.byType(Slider));
    expect(slider.secondaryTrackValue, isNull);
  });

  testWidgets('drag pauses first and commits one seek with prior play state',
      (tester) async {
    final events = <String>[];
    Duration? committed;
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('zh'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Scaffold(
        body: AnimePlayerControls(
          position: const Duration(minutes: 2),
          duration: const Duration(minutes: 10),
          playing: true,
          buffering: false,
          onPlayPause: () {},
          onScrubStart: (wasPlaying) => events.add('start:$wasPlaying'),
          onSeek: (target, resumeAfterSeek) {
            events.add('seek:$resumeAfterSeek');
            committed = target;
          },
          onOpenPanel: () {},
          onFullscreen: () {},
        ),
      ),
    ));

    await tester.drag(find.byType(Slider), const Offset(180, 0));
    await tester.pump();

    expect(events, ['start:true', 'seek:true']);
    expect(committed, isNotNull);
    expect(committed!, greaterThan(const Duration(minutes: 2)));
  });

  testWidgets('dragging while paused never requests resume', (tester) async {
    bool? resumeAfterSeek;
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('zh'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Scaffold(
        body: AnimePlayerControls(
          position: const Duration(minutes: 4),
          duration: const Duration(minutes: 10),
          playing: false,
          buffering: false,
          onPlayPause: () {},
          onScrubStart: (_) {},
          onSeek: (_, resume) => resumeAfterSeek = resume,
          onOpenPanel: () {},
          onFullscreen: () {},
        ),
      ),
    ));

    await tester.drag(find.byType(Slider), const Offset(80, 0));
    await tester.pump();

    expect(resumeAfterSeek, isFalse);
  });

  testWidgets('short seek clamps to the media boundaries', (tester) async {
    final seeks = <Duration>[];
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('zh'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Scaffold(
        body: AnimePlayerControls(
          position: const Duration(seconds: 5),
          duration: const Duration(seconds: 20),
          playing: false,
          buffering: false,
          onPlayPause: () {},
          onScrubStart: (_) {},
          onSeek: (target, _) => seeks.add(target),
          onOpenPanel: () {},
          onFullscreen: () {},
        ),
      ),
    ));

    await tester.tap(find.byTooltip('后退 10 秒'));
    await tester.tap(find.byTooltip('前进 10 秒'));

    expect(seeks, [Duration.zero, const Duration(seconds: 15)]);
  });

  // 移动端播放页本来就是沉浸式全屏,给个按钮点了没反应比没有更糟。
  testWidgets('没有窗口全屏的平台不显示全屏键', (tester) async {
    await tester.pumpWidget(_host(onFullscreen: null));

    expect(find.byTooltip('全屏'), findsNothing);
    expect(find.byTooltip('退出全屏'), findsNothing);
  });

  // 图标不跟着状态变的话,全屏之后用户看不出自己在哪个状态、该点哪儿回去。
  testWidgets('全屏中显示的是退出全屏', (tester) async {
    await tester.pumpWidget(_host(onFullscreen: () {}, fullscreen: false));
    expect(find.byTooltip('全屏'), findsOneWidget);
    expect(find.byIcon(Icons.fullscreen_rounded), findsOneWidget);

    await tester.pumpWidget(_host(onFullscreen: () {}, fullscreen: true));
    expect(find.byTooltip('退出全屏'), findsOneWidget);
    expect(find.byIcon(Icons.fullscreen_exit_rounded), findsOneWidget);
  });
}

Widget _host({required VoidCallback? onFullscreen, bool fullscreen = false}) =>
    MaterialApp(
      locale: const Locale('zh'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Scaffold(
        body: AnimePlayerControls(
          position: const Duration(minutes: 1),
          duration: const Duration(minutes: 10),
          playing: false,
          buffering: false,
          fullscreen: fullscreen,
          onPlayPause: () {},
          onScrubStart: (_) {},
          onSeek: (_, __) {},
          onOpenPanel: () {},
          onFullscreen: onFullscreen,
        ),
      ),
    );

Widget _controls({
  required Duration position,
  required Duration duration,
  required Duration buffered,
}) =>
    MaterialApp(
      locale: const Locale('zh'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Scaffold(
        body: AnimePlayerControls(
          position: position,
          duration: duration,
          buffered: buffered,
          playing: true,
          buffering: false,
          onPlayPause: () {},
          onScrubStart: (_) {},
          onSeek: (_, __) {},
          onOpenPanel: () {},
          onFullscreen: () {},
        ),
      ),
    );
