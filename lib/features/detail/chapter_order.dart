/// 章节表的顺序规则 —— 详情页列表 / 阅读器上一话下一话 共用。
///
/// **源自己给的顺序就是权威顺序**:源脚本的契约是升序返回(第1话在前;站点倒序的
/// 由脚本自己 reverse)。目录里的编号常常**不是全局单调**的 ——
///
///     序章 / 第01话…第85話 / 第三季第1话…第三季38话 / 第四季1话…第四季37话 / 第163话…第214话
///
/// 这种分季重编号只有源自己排得对;按解析出的话数重排会把三季按 1,1,1,2,2,2… 交错
/// 搅在一起,「序章」「完结篇」这类无号章还会被一并甩到表尾(线上实测过)。
/// 所以话数只用来做**跨源对齐**([chapterNumberOf]),不用来排序。
///
/// 唯一的例外是「按日期发布」型源(写真 / 图集站):章名里根本没有话数,先后全靠
/// 发布时间。整表都带 publishedAt 时按它升序归一,其余一律原样返回。
library;

import '../../core/source/chapter_number.dart';
import '../../core/source/models.dart';

/// 归一化章节顺序:整表都带发布时间 → 按时间升序;否则原样返回源给的顺序。
List<Chapter> orderedChapters(List<Chapter> chapters) {
  if (chapters.length < 2) return chapters;
  for (final c in chapters) {
    if (c.publishedAt == null) return chapters; // 有一话没日期 → 不是日期型源
  }
  // List.sort 不保证稳定,同一时间的多话用原下标兜底,保持源内先后。
  final indexed = [for (var i = 0; i < chapters.length; i++) (i, chapters[i])];
  indexed.sort((left, right) {
    final byDate = left.$2.publishedAt!.compareTo(right.$2.publishedAt!);
    return byDate != 0 ? byDate : left.$1.compareTo(right.$1);
  });
  return [for (final e in indexed) e.$2];
}

/// 跨源对齐用的话数:源自报的优先,没有则从章名解析;都拿不到 → null
/// (番外 / 序章 / 特别篇,不参与跨源对齐,但**照样留在原位**)。
double? chapterNumberOf(Chapter chapter) =>
    chapter.number ?? parseChapterNumber(chapter.name);
