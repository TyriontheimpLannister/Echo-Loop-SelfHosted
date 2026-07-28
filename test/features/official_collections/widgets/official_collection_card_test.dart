import 'package:echo_loop/features/official_collections/models/catalog.dart';
import 'package:echo_loop/features/official_collections/widgets/official_collection_card.dart';
import 'package:echo_loop/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('zh', 'CN'),
    home: Scaffold(body: child),
  );
}

void main() {
  testWidgets('官方合集卡片描述只显示一行并省略', (tester) async {
    const description = '虚拟人物Maya在美国学校生活，涵盖就医、租房、办银行卡、租车、买车、与老师沟通等场景';
    final item = CatalogCollection(
      id: 'c1',
      name: '留学生美国生活英语',
      description: description,
      coverUrl: null,
      publishedAt: DateTime(2026, 1, 1),
      audios: const [
        CatalogAudio(
          id: 'a1',
          title: 'Episode 1',
          durationSec: 60,
          sortOrder: 1,
          sha256: 'sha',
        ),
      ],
    );

    await tester.pumpWidget(
      _host(
        OfficialCollectionCard(
          item: item,
          enrolled: false,
          enrolling: false,
          onOpenDetail: () {},
          onEnroll: () {},
          onGoLearn: () {},
        ),
      ),
    );

    final text = tester.widget<Text>(find.text(description));
    expect(text.maxLines, 1);
    expect(text.overflow, TextOverflow.ellipsis);
  });
}
