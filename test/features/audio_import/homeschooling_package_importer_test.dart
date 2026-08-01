import 'package:echo_loop/features/audio_import/homeschooling_package.dart';
import 'package:echo_loop/features/audio_import/homeschooling_package_importer.dart';
import 'package:flutter_test/flutter_test.dart';

HomeschoolingPackageItem _item(String text, int order) {
  return HomeschoolingPackageItem(
    text: text,
    audioFormat: 'mp3',
    audioBase64: 'AA==',
    order: order,
  );
}

void main() {
  test('整篇字幕累加原始句子真实时长，不使用固定二次切句', () {
    final srt = buildHomeschoolingPassageSrt(
      [_item('First.', 0), _item('Second.', 1), _item('Third.', 2)],
      const [
        Duration(milliseconds: 1250),
        Duration(milliseconds: 2750),
        Duration(milliseconds: 500),
      ],
    );

    expect(srt, contains('00:00:00,000 --> 00:00:01,250\nFirst.'));
    expect(srt, contains('00:00:01,250 --> 00:00:04,000\nSecond.'));
    expect(srt, contains('00:00:04,000 --> 00:00:04,500\nThird.'));
    expect(srt, isNot(contains('00:00:02,000')));
  });

  test('句子数量与时长数量不一致时拒绝生成伪时间轴', () {
    expect(
      () => buildHomeschoolingPassageSrt(
        [_item('First.', 0), _item('Second.', 1)],
        const [Duration(seconds: 1)],
      ),
      throwsArgumentError,
    );
  });
}
