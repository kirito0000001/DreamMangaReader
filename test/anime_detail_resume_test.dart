import 'dart:io';

import 'package:dream_manga_reader/app/anime_download_store.dart';
import 'package:dream_manga_reader/app/anime_library_store.dart';
import 'package:dream_manga_reader/app/download_coordinator_scope.dart';
import 'package:dream_manga_reader/app/library_store.dart';
import 'package:dream_manga_reader/app/theme/app_theme.dart';
import 'package:dream_manga_reader/core/downloads/download_coordinator.dart';
import 'package:dream_manga_reader/core/downloads/download_policy.dart';
import 'package:dream_manga_reader/core/source/models.dart';
import 'package:dream_manga_reader/core/source/source.dart';
import 'package:dream_manga_reader/core/source/source_registry.dart';
import 'package:dream_manga_reader/features/anime/anime_detail_page.dart';
import 'package:dream_manga_reader/features/anime/playback/hls_cache_gateway.dart';
import 'package:dream_manga_reader/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/download_fixtures.dart';

/// 从历史记录进来的人落在详情页(#26),所以「继续观看」这颗按钮就是那条历史
/// 唯一的出口 —— 它指到哪一集,得说得准。
void main() {
  testWidgets('the primary action continues at the episode the history names',
      (tester) async {
    final library = await _pumpDetail(
      tester,
      history: _history(episodeId: 'ep-2', episodeIndex: 0),
    );

    expect(find.text('继续 · 第二集'), findsOneWidget);
    await library.flushPending();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('an episode id the source dropped falls back to the saved index',
      (tester) async {
    final library = await _pumpDetail(
      tester,
      history: _history(episodeId: 'renumbered-7', episodeIndex: 1),
    );

    // id 对不上就退回序号,而不是把入口整个降级成「从头开始」。
    expect(find.text('继续 · 第二集'), findsOneWidget);
    expect(find.text('从头开始'), findsNothing);
    await library.flushPending();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a saved index past the end clamps to the last episode',
      (tester) async {
    final library = await _pumpDetail(
      tester,
      history: _history(episodeId: 'gone', episodeIndex: 99),
    );

    expect(find.text('继续 · 第三集'), findsOneWidget);
    await library.flushPending();
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

const _meta = SourceMeta(
  id: 'anime-source',
  name: '测试源',
  script: '',
  kind: 'anime',
);

AnimeHistoryEntry _history({
  required String episodeId,
  required int episodeIndex,
}) =>
    AnimeHistoryEntry(
      sourceId: _meta.id,
      animeId: 'show',
      title: '测试番剧',
      episodeId: episodeId,
      episodeName: '历史里那个过期的集名',
      episodeIndex: episodeIndex,
      positionSeconds: 83,
      durationSeconds: 1440,
      updatedAt: 10,
    );

Future<AnimeLibraryStore> _pumpDetail(
  WidgetTester tester, {
  required AnimeHistoryEntry history,
}) async {
  SharedPreferences.setMockInitialValues(const {});
  final library = LibraryStore();
  await library.load();
  addTearDown(library.dispose);
  final animeLibrary = AnimeLibraryStore(persistDelay: Duration.zero);
  await animeLibrary.load();
  addTearDown(animeLibrary.dispose);
  animeLibrary.saveProgress(
    sourceId: history.sourceId,
    animeId: history.animeId,
    title: history.title,
    episodeId: history.episodeId,
    episodeName: history.episodeName,
    episodeIndex: history.episodeIndex,
    position: Duration(seconds: history.positionSeconds),
    duration: Duration(seconds: history.durationSeconds),
  );

  // 详情页整页渲染要有下载作用域(主操作行旁边就是「下载全部」)。
  final root = (await tester.runAsync(
    () => Directory.systemTemp.createTemp('anime-detail-resume-test-'),
  ))!;
  addTearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });
  final downloads = AnimeDownloadStore(
    rootProvider: () async => root.path,
    trackProvider: (_, __, ___) async => const [],
    upstream: _UnusedUpstream(),
  );
  await tester.runAsync(downloads.load);
  addTearDown(downloads.dispose);
  final coordinator = DownloadCoordinator(
    repository: RecordingDownloadTaskRepository(),
    environment: () async => unrestrictedEnvironment,
    settings: DownloadPolicySettings.new,
  );
  await coordinator.load();
  addTearDown(coordinator.dispose);

  await tester.pumpWidget(MaterialApp(
    theme: buildTheme(AppThemeVariant.light),
    locale: const Locale('zh'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    home: LibraryScope(
      store: library,
      child: AnimeLibraryScope(
        store: animeLibrary,
        child: DownloadCoordinatorScope(
          coordinator: coordinator,
          child: AnimeDownloadScope(
            store: downloads,
            child: AnimeDetailPage(
              meta: _meta,
              anime: const Manga(id: 'show', title: '测试番剧'),
              sourceBuilder: (_) => _FakeAnimeSource(),
              bangumiLookup: (_) async => null,
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.pump();
  await tester.pump();
  return animeLibrary;
}

class _FakeAnimeSource implements MangaSource {
  @override
  String get id => _meta.id;
  @override
  String get name => _meta.name;
  @override
  String get lang => 'zh';
  @override
  String get baseUrl => '';
  @override
  int get version => 1;
  @override
  bool get nsfw => false;
  @override
  Future<Manga> getMangaDetail(String mangaId) async => const Manga(
        id: 'show',
        title: '测试番剧',
        cover: 'https://img.test/full.jpg',
      );
  @override
  Future<Paged<Chapter>> getChapters(String mangaId, {int? page}) async =>
      const Paged([
        Chapter(id: 'ep-1', name: '第一集'),
        Chapter(id: 'ep-2', name: '第二集'),
        Chapter(id: 'ep-3', name: '第三集'),
      ]);
  @override
  void dispose() {}
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _UnusedUpstream implements HlsUpstreamClient {
  @override
  Future<HlsUpstreamResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    int? rangeStart,
    int? rangeLength,
  }) =>
      throw StateError('network not expected');
}
