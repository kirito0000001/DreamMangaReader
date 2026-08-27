import 'package:flutter/material.dart';

import '../../app/anime_library_store.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/source/models.dart';
import '../../core/source/source_registry.dart';
import '../common/transitions.dart';
import 'anime_detail_page.dart';

typedef AnimeHistoryDetailBuilder = Widget Function(
  SourceMeta meta,
  Manga anime,
);

/// 从历史记录打开一条番剧。
///
/// 落点是**详情页**,不是播放器。详情页自己会把「继续观看 · 第 N 集」摆在主按钮上,
/// 接着看仍然只要一下;而直接冲进播放器的话,想下载、想看简介、想挑另一集,都得退
/// 出去把这部番重新搜一遍。
Future<void> openAnimeHistory(
  BuildContext context,
  AnimeHistoryEntry entry, {
  List<SourceMeta>? sources,
  AnimeHistoryDetailBuilder detailBuilder = _buildDetail,
}) async {
  final catalog = sources ?? registeredSources;
  final meta = catalog
      .where((candidate) => candidate.id == entry.sourceId && candidate.isAnime)
      .firstOrNull;
  if (meta == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.anime_sourceUnavailable)),
    );
    return;
  }
  await pushPage(
    context,
    detailBuilder(
      meta,
      Manga(id: entry.animeId, title: entry.title, cover: entry.cover),
    ),
  );
}

Widget _buildDetail(SourceMeta meta, Manga anime) => AnimeDetailPage(
      meta: meta,
      anime: anime,
    );
