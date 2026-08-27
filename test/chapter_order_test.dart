import 'package:dream_manga_reader/app/library_store.dart';
import 'package:dream_manga_reader/core/source/models.dart';
import 'package:dream_manga_reader/core/source/source.dart';
import 'package:dream_manga_reader/core/source/source_registry.dart';
import 'package:dream_manga_reader/features/detail/chapter_merge.dart';
import 'package:dream_manga_reader/features/detail/chapter_order.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 详情页那张章节表的顺序 —— 用户唯一能看见的目录,排错了整本书就没法读。
void main() {
  group('orderedChapters', () {
    test('keeps the order the source handed us', () {
      // 分季重编号:话数解析出来是 1,1,1,2,2… 按它排就把三季搅在一起了。
      final chapters = [
        for (final name in _seasonedNames) Chapter(id: name, name: name),
      ];

      expect(orderedChapters(chapters), same(chapters));
    });

    test('sorts dated releases oldest first', () {
      // 写真/图集站:章名里没有话数,先后全靠发布时间,站点还常按最新在前给。
      final chapters = [
        const Chapter(id: 'new', name: '写真 No.11017 (75 photos)', publishedAt: 200),
        const Chapter(id: 'old', name: '写真 No.10982 (60 photos)', publishedAt: 100),
      ];

      expect([for (final c in orderedChapters(chapters)) c.id], ['old', 'new']);
    });

    test('leaves the source order alone when only some chapters carry a date', () {
      // 半带日期 ≠ 日期型源;拿零星几个 publishedAt 去排会打乱正常目录。
      final chapters = [
        const Chapter(id: 'b', name: '第2话'),
        const Chapter(id: 'a', name: '第1话', publishedAt: 100),
      ];

      expect(orderedChapters(chapters), same(chapters));
    });
  });

  group('mergeChapters', () {
    test('a reissued-by-season catalogue stays in source order', () {
      // 线上实测的《恶役只有死亡结局》(拷贝漫画):序章 → 第01…85话 →
      // 第三季1…38话 → 第四季1…37话 → 第163…214话。曾经按话数重排,
      // 结果是「第24话 / 第三季第24话 / 第四季24话 / 第25话 …」交错。
      final merged = mergeChapters(_source('copy', _seasonedNames), const []);

      expect([for (final row in merged) row.label], _seasonedNames);
    });

    test('numbers only align chapters across sources, never reorder them', () {
      final merged = mergeChapters(
        _source('copy', _seasonedNames),
        [_source('bzm', const ['第24话'])],
      );

      // 他源的第24话挂到当前源第一条 24(第24话),而不是第三/四季那两条。
      final row = merged.firstWhere((r) => r.label == '第24话');
      expect([for (final pv in row.providers) pv.meta.id], ['copy', 'bzm']);
      expect([for (final r in merged) r.label], _seasonedNames);
    });

    test('chapters only other sources have land next to their number', () {
      final merged = mergeChapters(
        _source('copy', const ['第1话', '第2话', '番外']),
        [
          _source('bzm', const ['第0话', '第1.5话', '第3话', '第4话']),
        ],
      );

      // 更小的排到最前,中间的插进对应缝里,更新更快的他源新话落到表尾。
      expect([for (final row in merged) row.label],
          ['第0话', '第1话', '第1.5话', '第2话', '番外', '第3话', '第4话']);
    });

    test('other sources alone still make a readable list', () {
      // 当前源章节挂了/一话都没解析出来时,别把他源的章节一起丢掉。
      final merged = mergeChapters(
        _source('copy', const []),
        [
          _source('bzm', const ['第2话', '第1话']),
          _source('yyds', const ['第1话', '第3话']),
        ],
      );

      expect([for (final row in merged) row.label], ['第1话', '第2话', '第3话']);
      expect([for (final pv in merged.first.providers) pv.meta.id],
          ['bzm', 'yyds']);
    });
  });

  test('new installs default to newest first and saved choices win', () async {
    SharedPreferences.setMockInitialValues({});
    final fresh = LibraryStore();
    await fresh.load();
    expect(fresh.chaptersDesc, true);
    fresh.dispose();

    SharedPreferences.setMockInitialValues({'lib.chaptersDesc': false});
    final restored = LibraryStore();
    await restored.load();
    expect(restored.chaptersDesc, false);
    restored.dispose();
  });
}

/// 拷贝漫画《恶役只有死亡结局》目录的形状(逐段取样,含它自己的繁简/写法漂移)。
const List<String> _seasonedNames = [
  '序章',
  '第01话', '第02话', '第24话', '第84話', '第85話',
  '第三季第1话', '第三季第2话', '第三季第24话', '第三季29话', '第三季完结篇',
  '第四季1话', '第四季24话', '第四季37话', '第四季完结篇',
  '第163话', '第214话',
];

ChapterSource _source(String id, List<String> names) => ChapterSource(
      SourceMeta(id: id, name: id, script: '', kind: 'manga'),
      _UnusedSource(),
      'work',
      [for (final name in names) Chapter(id: '$id:$name', name: name)],
    );

/// 合并只看章节表,不碰引擎 —— 真被调到就是回归。
class _UnusedSource implements MangaSource {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('${invocation.memberName} not expected');
}
