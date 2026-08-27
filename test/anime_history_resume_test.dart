import 'dart:async';

import 'package:dream_manga_reader/app/anime_library_store.dart';
import 'package:dream_manga_reader/core/source/models.dart';
import 'package:dream_manga_reader/core/source/source_registry.dart';
import 'package:dream_manga_reader/features/anime/anime_history_resume.dart';
import 'package:dream_manga_reader/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('history opens the detail page, carrying title and cover',
      (tester) async {
    late SourceMeta openedMeta;
    late Manga openedAnime;
    await tester.pumpWidget(_app(Builder(builder: (context) {
      return TextButton(
        onPressed: () => unawaited(openAnimeHistory(
          context,
          _history(),
          sources: const [_meta],
          detailBuilder: (meta, anime) {
            openedMeta = meta;
            openedAnime = anime;
            return const Scaffold(body: Text('详情页占位'));
          },
        )),
        child: const Text('恢复'),
      );
    })));

    await tester.tap(find.text('恢复'));
    await tester.pumpAndSettle();

    expect(openedMeta.id, _meta.id);
    expect(openedAnime.id, 'show');
    expect(openedAnime.title, '测试番剧');
    expect(openedAnime.cover, 'https://img.test/show.jpg');
    expect(find.text('详情页占位'), findsOneWidget);
  });

  testWidgets('a source that is no longer installed says so and opens nothing',
      (tester) async {
    var built = false;
    await tester.pumpWidget(_app(Scaffold(
      body: Builder(builder: (context) {
        return TextButton(
          onPressed: () => unawaited(openAnimeHistory(
            context,
            _history(),
            sources: const [],
            detailBuilder: (meta, anime) {
              built = true;
              return const Scaffold(body: Text('详情页占位'));
            },
          )),
          child: const Text('恢复'),
        );
      }),
    )));

    await tester.tap(find.text('恢复'));
    await tester.pump();

    expect(built, isFalse);
    expect(find.text('番剧源不可用'), findsOneWidget);
  });
}

Widget _app(Widget home) => MaterialApp(
      locale: const Locale('zh'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: home,
    );

const _meta = SourceMeta(
  id: 'anime-source',
  name: '测试源',
  script: '',
  kind: 'anime',
);

AnimeHistoryEntry _history() => const AnimeHistoryEntry(
      sourceId: 'anime-source',
      animeId: 'show',
      title: '测试番剧',
      cover: 'https://img.test/show.jpg',
      episodeId: 'ep-2',
      episodeName: '第二集',
      episodeIndex: 1,
      positionSeconds: 83,
      durationSeconds: 1440,
      updatedAt: 10,
    );
