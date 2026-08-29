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
    await tester.pumpWidget(_seekHost(
      position: const Duration(seconds: 8),
      duration: const Duration(seconds: 20),
      onSeek: seeks.add,
    ));

    await tester.tap(find.byTooltip('后退 5 秒'));
    await tester.tap(find.byTooltip('跳过片头(90 秒)'));

    expect(seeks, [const Duration(seconds: 3), const Duration(seconds: 20)]);
  });

  // 等距的 ±10 会让人在两个点之间来回弹:退回去发现退多了,再前进又回到原处。
  testWidgets('the seek steps are deliberately asymmetric', (tester) async {
    final seeks = <Duration>[];
    await tester.pumpWidget(_seekHost(
      position: const Duration(minutes: 5),
      duration: const Duration(minutes: 24),
      onSeek: seeks.add,
    ));

    await tester.tap(find.byTooltip('后退 5 秒'));
    await tester.tap(find.byTooltip('前进 15 秒'));

    expect(seeks, [
      const Duration(minutes: 4, seconds: 55),
      const Duration(minutes: 5, seconds: 15),
    ]);
  });

  // 90 秒是绝大多数番剧的 OP 长度 —— 一下按过去,代替自动识别片头。
  testWidgets('one button jumps a whole opening', (tester) async {
    final seeks = <Duration>[];
    await tester.pumpWidget(_seekHost(
      position: const Duration(seconds: 4),
      duration: const Duration(minutes: 24),
      onSeek: seeks.add,
    ));

    await tester.tap(find.byTooltip('跳过片头(90 秒)'));

    expect(seeks, [const Duration(seconds: 94)]);
  });

  // 看番时最常改的就是这三样,每一样都该在底栏直接够得着,而不是埋进右上角
  // 那块设置面板里。
  testWidgets('speed and quality read out their current value', (tester) async {
    await tester.pumpWidget(_actionsHost(
      rateLabel: '1.5x',
      qualityLabel: '1080P',
    ));

    expect(find.text('选集'), findsOneWidget);
    expect(find.text('1.5x'), findsOneWidget);
    expect(find.text('1080P'), findsOneWidget);
  });

  testWidgets('the generic names stand in until there is a value to report',
      (tester) async {
    await tester.pumpWidget(_actionsHost(rateLabel: '', qualityLabel: ''));

    expect(find.text('倍速'), findsOneWidget);
    expect(find.text('清晰度'), findsOneWidget);
  });

  testWidgets('an action with nothing behind it is not drawn', (tester) async {
    await tester.pumpWidget(_actionsHost(episodes: false));

    expect(find.text('选集'), findsNothing);
    expect(find.text('1.0x'), findsOneWidget);
  });

  // 44 是移动端触摸目标的下限,原来的 38 太小 —— 横屏拿着手机点不中。
  testWidgets('every control is at least a finger wide', (tester) async {
    await tester.pumpWidget(_actionsHost());

    for (final element in find.byType(IconButton).evaluate()) {
      final size = tester.getSize(find.byWidget(element.widget));
      expect(size.width, greaterThanOrEqualTo(44.0),
          reason: '${(element.widget as IconButton).tooltip} 太窄了');
      expect(size.height, greaterThanOrEqualTo(44.0));
    }
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

Widget _seekHost({
  required Duration position,
  required Duration duration,
  required ValueChanged<Duration> onSeek,
}) =>
    MaterialApp(
      locale: const Locale('zh'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Scaffold(
        body: AnimePlayerControls(
          position: position,
          duration: duration,
          playing: false,
          buffering: false,
          onPlayPause: () {},
          onScrubStart: (_) {},
          onSeek: (target, _) => onSeek(target),
          onOpenPanel: () {},
          onFullscreen: () {},
        ),
      ),
    );

Widget _actionsHost({
  String rateLabel = '1.0x',
  String qualityLabel = '1080P',
  bool episodes = true,
}) =>
    MaterialApp(
      locale: const Locale('zh'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Scaffold(
        body: AnimePlayerControls(
          position: const Duration(minutes: 1),
          duration: const Duration(minutes: 24),
          playing: true,
          buffering: false,
          rateLabel: rateLabel,
          qualityLabel: qualityLabel,
          onEpisodes: episodes ? () {} : null,
          onRate: () {},
          onQuality: () {},
          onPlayPause: () {},
          onScrubStart: (_) {},
          onSeek: (_, __) {},
          onOpenPanel: () {},
          onFullscreen: () {},
        ),
      ),
    );
