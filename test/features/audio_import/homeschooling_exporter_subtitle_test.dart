import 'package:echo_loop/features/audio_import/homeschooling_package_exporter.dart';
import 'package:echo_loop/models/sentence.dart';
import 'package:echo_loop/services/subtitle_parser.dart';
import 'package:echo_loop/utils/srt_generator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'AI transcription SRT is readable by the package exporter parser',
    () async {
      final srt = generateSrtContent(const [
        TranscriptSentence(
          text: 'First sentence.',
          startTime: Duration(milliseconds: 250),
          endTime: Duration(milliseconds: 1750),
        ),
        TranscriptSentence(
          text: 'Second sentence.',
          startTime: Duration(milliseconds: 1800),
          endTime: Duration(milliseconds: 3200),
        ),
      ]);

      final parsed = await SubtitleParser.parseSubtitleString(srt);

      expect(parsed.map((sentence) => sentence.text), [
        'First sentence.',
        'Second sentence.',
      ]);
    },
  );

  test('sentence slicing uses the encoder included in FFmpeg Kit min', () {
    final arguments = buildSentenceSliceArguments(
      sourcePath: '/input/source.m4a',
      outputPath: '/output/sentence.m4a',
      sentence: Sentence(
        index: 0,
        text: 'First sentence.',
        startTime: const Duration(milliseconds: 250),
        endTime: const Duration(milliseconds: 1750),
      ),
    );

    expect(arguments, containsAllInOrder(['-i', '/input/source.m4a']));
    expect(arguments, containsAllInOrder(['-ss', '0.250', '-t', '1.500']));
    expect(arguments, containsAllInOrder(['-c:a', 'aac', '-b:a', '96k']));
    expect(arguments, isNot(contains('libmp3lame')));
    expect(arguments.last, '/output/sentence.m4a');
  });
}
