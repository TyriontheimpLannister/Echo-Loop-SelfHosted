import "dart:convert";

import "package:echo_loop/features/audio_import/homeschooling_package.dart";
import "package:flutter_test/flutter_test.dart";

void main() {
  group("HomeschoolingPackage.tryParse", () {
    test("rejects unknown versions", () {
      final result = HomeschoolingPackage.tryParse({
        "version": 999,
        "items": <Map<String, dynamic>>[],
      });
      expect(result, isNull);
    });

    test("rejects non-list items", () {
      final result = HomeschoolingPackage.tryParse({
        "version": 1,
        "items": "oops",
      });
      expect(result, isNull);
    });

    test("parses a valid package and round-trips through JSON", () {
      final raw = {
        "version": 1,
        "source_app": "homeschooling",
        "source_id": "task:42",
        "title": "Lesson 1",
        "child_slug": "naomi",
        "lang": "en",
        "voice": "English_Friendly_Female_3",
        "speed": 1.0,
        "items": [
          {
            "text": "apple",
            "audio_format": "mp3",
            "audio_b64": "aGVsbG8=",
            "transcript_verified": true,
            "source": "minimax_speech_2_8_hd",
            "order": 0,
          },
        ],
        "skipped_count": 0,
      };
      final pkg = HomeschoolingPackage.tryParse(raw)!;
      expect(pkg.title, "Lesson 1");
      expect(pkg.items.length, 1);
      expect(pkg.items.first.text, "apple");
      expect(pkg.items.first.audioFormat, "mp3");
      expect(pkg.items.first.transcriptVerified, isTrue);
      expect(pkg.contentMode, "sentences");

      final encoded = pkg.encode();
      final decoded = jsonDecode(encoded) as Map<String, dynamic>;
      expect(decoded["source_app"], "homeschooling");
      expect(decoded["items"][0]["text"], "apple");
    });

    test("keeps the parent-selected passage mode", () {
      final pkg = HomeschoolingPackage.tryParse({
        "version": 1,
        "content_mode": "passage",
        "items": [
          {
            "text": "First sentence.",
            "audio_b64": "aGVsbG8=",
            "transcript_verified": true,
          },
        ],
      })!;
      expect(pkg.contentMode, "passage");
      expect(pkg.toJson()["content_mode"], "passage");
    });
  });

  group("HomeschoolingPackageItem.tryParse", () {
    test("drops items without text or audio", () {
      expect(
        HomeschoolingPackageItem.tryParse({
          "text": "   ",
          "audio_b64": "aGVsbG8=",
        }),
        isNull,
      );
      expect(
        HomeschoolingPackageItem.tryParse({"text": "apple", "audio_b64": ""}),
        isNull,
      );
    });

    test("keeps items that are explicitly not transcript-verified", () {
      final item = HomeschoolingPackageItem.tryParse({
        "text": "banana",
        "audio_b64": "aGVsbG8=",
        "transcript_verified": false,
      });
      expect(item, isNotNull);
      expect(item!.transcriptVerified, isFalse);
    });
  });
}
