import 'package:echo_loop/features/audio_import/subtitle_pairing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('matchSubtitlesForAudios', () {
    test('基本同名配对', () {
      final result = matchSubtitlesForAudios(['a.mp3', 'a.srt', 'b.m4a']);
      expect(result['a.mp3'], 'a.srt');
      expect(result['b.m4a'], isNull);
    });

    test('大小写不敏感配对', () {
      final result = matchSubtitlesForAudios(['Song.MP3', 'song.SRT']);
      expect(result['Song.MP3'], 'song.SRT');
    });

    test('同名多字幕按 srt > vtt > lrc 优先', () {
      final r1 = matchSubtitlesForAudios(['a.mp3', 'a.vtt', 'a.lrc', 'a.srt']);
      expect(r1['a.mp3'], 'a.srt');

      final r2 = matchSubtitlesForAudios(['a.mp3', 'a.vtt', 'a.lrc']);
      expect(r2['a.mp3'], 'a.vtt');

      final r3 = matchSubtitlesForAudios(['a.mp3', 'a.lrc']);
      expect(r3['a.mp3'], 'a.lrc');
    });

    test('多音频各自配对', () {
      final result = matchSubtitlesForAudios([
        'a.mp3',
        'a.srt',
        'b.mp3',
        'b.lrc',
        'c.wav',
      ]);
      expect(result['a.mp3'], 'a.srt');
      expect(result['b.mp3'], 'b.lrc');
      expect(result['c.wav'], isNull);
    });

    test('无扩展名与无关文件忽略', () {
      final result = matchSubtitlesForAudios([
        'a.mp3',
        'a.srt',
        'noext',
        'cover.jpg',
        'readme.txt',
      ]);
      expect(result.keys, ['a.mp3']);
      expect(result['a.mp3'], 'a.srt');
    });

    test('只有字幕没有音频时结果为空', () {
      final result = matchSubtitlesForAudios(['a.srt', 'b.vtt']);
      expect(result, isEmpty);
    });

    test('subtitleExtensionOf 返回小写扩展名', () {
      expect(subtitleExtensionOf('a.SRT'), 'srt');
      expect(subtitleExtensionOf('noext'), '');
    });

    test('同名多个不同音频后缀：都配对到同一字幕', () {
      final result = matchSubtitlesForAudios(['a.mp3', 'a.wav', 'a.srt']);
      expect(result['a.mp3'], 'a.srt');
      expect(result['a.wav'], 'a.srt');
    });

    test('文件名含点号：按最后一个扩展名切分 stem', () {
      final result = matchSubtitlesForAudios([
        'TPO-30.L1.m4a',
        'TPO-30.L1.srt',
      ]);
      expect(result['TPO-30.L1.m4a'], 'TPO-30.L1.srt');
    });

    test('字幕带音频扩展名前缀（song.m4a.srt）不与 song.m4a 匹配', () {
      // stem 分别为 song / song.m4a，视为不同名，按当前严格同名策略不配对。
      final result = matchSubtitlesForAudios(['song.m4a', 'song.m4a.srt']);
      expect(result['song.m4a'], isNull);
    });

    test('文件名含空格与中文正常配对', () {
      final result = matchSubtitlesForAudios(['第 1 课.mp3', '第 1 课.srt']);
      expect(result['第 1 课.mp3'], '第 1 课.srt');
    });

    test('大小写混合的扩展名也纳入白名单', () {
      final result = matchSubtitlesForAudios(['a.M4A', 'a.Srt']);
      expect(result['a.M4A'], 'a.Srt');
    });

    test('多个音频有的配对有的不配对', () {
      final result = matchSubtitlesForAudios([
        'a.mp3',
        'b.mp3',
        'c.mp3',
        'a.srt',
        'c.lrc',
      ]);
      expect(result['a.mp3'], 'a.srt');
      expect(result['b.mp3'], isNull);
      expect(result['c.mp3'], 'c.lrc');
    });

    test('空输入返回空', () {
      expect(matchSubtitlesForAudios([]), isEmpty);
    });

    test('同名字幕重复出现（同扩展名）不报错，稳定取其一', () {
      final result = matchSubtitlesForAudios(['a.mp3', 'a.srt', 'a.srt']);
      expect(result['a.mp3'], 'a.srt');
    });
  });

  group('classifyImportFiles', () {
    test('区分音频 / 字幕 / 不支持', () {
      final c = classifyImportFiles([
        'a.mp3',
        'a.srt',
        'b.m4a',
        'b.lrc',
        'cover.jpg',
        'notes.txt',
        'noext',
      ]);
      expect(c.audioNames, ['a.mp3', 'b.m4a']);
      expect(c.subtitleNames, ['a.srt', 'b.lrc']);
      expect(c.rejectedExtensions, ['jpg', 'txt', '?']);
    });

    test('全部音频时无字幕无拒绝', () {
      final c = classifyImportFiles(['a.mp3', 'b.wav', 'c.aac', 'd.flac']);
      expect(c.audioNames.length, 4);
      expect(c.subtitleNames, isEmpty);
      expect(c.rejectedExtensions, isEmpty);
    });

    test('全部字幕时无音频', () {
      final c = classifyImportFiles(['a.srt', 'b.vtt', 'c.lrc']);
      expect(c.audioNames, isEmpty);
      expect(c.subtitleNames.length, 3);
    });

    test('大写扩展名归类正确', () {
      final c = classifyImportFiles(['A.MP3', 'A.SRT', 'X.PDF']);
      expect(c.audioNames, ['A.MP3']);
      expect(c.subtitleNames, ['A.SRT']);
      expect(c.rejectedExtensions, ['pdf']);
    });

    test('空输入全为空', () {
      final c = classifyImportFiles([]);
      expect(c.audioNames, isEmpty);
      expect(c.subtitleNames, isEmpty);
      expect(c.rejectedExtensions, isEmpty);
    });

    test('保持输入顺序', () {
      final c = classifyImportFiles(['z.mp3', 'a.mp3', 'm.mp3']);
      expect(c.audioNames, ['z.mp3', 'a.mp3', 'm.mp3']);
    });
  });
}
