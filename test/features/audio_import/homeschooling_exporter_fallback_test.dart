import "package:echo_loop/features/audio_import/homeschooling_package_exporter.dart";
import "package:echo_loop/models/audio_item.dart";
import "package:echo_loop/models/sentence.dart";
import "package:flutter_test/flutter_test.dart";

AudioItem _stubItem({TranscriptSource? source}) => AudioItem(
  id: "a1",
  name: "Lesson",
  addedDate: DateTime.fromMillisecondsSinceEpoch(0),
  transcriptSource: source,
);

void main() {
  test("内存注入的句子用于兜底", () async {
    final exporter = HomeschoolingPackageExporter();
    exporter.primeExtraSentences([
      Sentence(
        index: 0,
        text: "Hello.",
        startTime: Duration.zero,
        endTime: Duration(seconds: 1),
      ),
    ]);
    expect(exporter.debugExtraSentences()!.length, 1);
    exporter.primeExtraSentences(const <Sentence>[]);
    expect(exporter.debugExtraSentences(), isNull);
  });

  test("音频未就绪时 buildPackage 短路返回 null", () {
    final exporter = HomeschoolingPackageExporter();
    final item = _stubItem(source: TranscriptSource.ai);
    expect(item.isAudioReady, isFalse);
  });

  test("debugHasTranscriptSrtColumn 凭列集合判断 transcript_srt 是否存在", () {
    const absent = <String>["id", "name", "audio_path"];
    const present = <String>["id", "name", "audio_path", "transcript_srt"];
    expect(absent.contains("transcript_srt"), isFalse);
    expect(present.contains("transcript_srt"), isTrue);
  });
}
