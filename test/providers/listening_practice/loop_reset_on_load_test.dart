/// 循环开关「不持久化、随加载新音频重置」回归测试
///
/// 验证：
/// 1. 加载一条**新**音频时，全文 tab 循环开关重置为关；收藏 tab 恢复默认的
///    「单句循环开 + 1 次 + 1 秒」。
/// 2. 重新加载**同一**音频（loadAudio 早返回路径）不动循环开关。
library;

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:echo_loop/database/app_database.dart' hide AudioItem;
import 'package:echo_loop/database/providers.dart';
import 'package:echo_loop/models/audio_item.dart';
import 'package:echo_loop/models/playback_settings.dart';
import 'package:echo_loop/models/sentence.dart';
import 'package:echo_loop/providers/audio_engine/audio_engine_provider.dart';
import 'package:echo_loop/providers/listening_practice/listening_practice_provider.dart';
import '../../helpers/mock_providers.dart';

/// 测试用引擎：loadAudio/loadTranscript 不触碰真实文件，直接返回预置句子。
class _LoadAudioEngine extends TestAudioEngine {
  final List<Sentence> sentences;
  _LoadAudioEngine(this.sentences);

  @override
  Future<Duration?> loadAudio(
    AudioItem audioItem,
    double speed, {
    String? subtitle,
  }) async => null;

  @override
  Future<List<Sentence>> loadTranscript(AudioItem audioItem) async => sentences;
}

/// 可注入初始 state 的子类（复用真实业务逻辑）。
class _TestableListeningPractice extends ListeningPractice {
  void seed({
    required AudioItem audioItem,
    required PlaybackSettings settings,
  }) {
    state = state.copyWith(currentAudioItem: audioItem, settings: settings);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final sentences = [
    Sentence(
      index: 0,
      text: '[INDISTINCT CHATTER]',
      startTime: Duration.zero,
      endTime: const Duration(seconds: 3),
    ),
    Sentence(
      index: 1,
      text: 'Second.',
      startTime: const Duration(seconds: 3),
      endTime: const Duration(seconds: 6),
    ),
  ];

  // 循环全开 + 非默认参数（用于验证参数被保留、开关被重置）
  const loopOnSettings = PlaybackSettings(
    loopWhole: true,
    loopSentence: true,
    sentenceLoopCount: 5,
    wholeLoopCount: 7,
  );

  late ProviderContainer container;
  late AppDatabase db;
  late _TestableListeningPractice lp;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase(
      NativeDatabase.memory(
        setup: (db) => db.execute('PRAGMA foreign_keys = ON'),
      ),
    );
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        audioEngineProvider.overrideWith(() => _LoadAudioEngine(sentences)),
        listeningPracticeProvider.overrideWith(
          () => _TestableListeningPractice(),
        ),
      ],
    );
    lp =
        container.read(listeningPracticeProvider.notifier)
            as _TestableListeningPractice;
    await Future<void>.delayed(Duration.zero); // 等 _setupListeners microtask
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  test('加载新音频时全文循环重置为关，收藏恢复默认循环', () async {
    lp.seed(
      audioItem: createTestAudioItem(id: 'audio-1'),
      settings: loopOnSettings,
    );

    await lp.loadAudio(createTestAudioItem(id: 'audio-2'));

    final state = container.read(listeningPracticeProvider);
    expect(state.fullSettings.loopWhole, isFalse);
    expect(state.fullSettings.loopSentence, isFalse);
    // 全文 tab 参数偏好仍保留
    expect(state.fullSettings.sentenceLoopCount, 5);
    expect(state.fullSettings.wholeLoopCount, 7);
    // 收藏 tab 恢复非连续收藏句的默认逐句跳播语义
    expect(state.bookmarkSettings.loopWhole, isFalse);
    expect(state.bookmarkSettings.loopSentence, isTrue);
    expect(state.bookmarkSettings.sentenceLoopCount, 1);
    expect(state.bookmarkSettings.sentenceInterval, const Duration(seconds: 1));
  });

  test('首次加载方括号字幕不自动收藏且文本原样显示', () async {
    await lp.loadAudio(createTestAudioItem(id: 'audio-brackets'));

    final state = container.read(listeningPracticeProvider);
    expect(state.bookmarkedIndices, isEmpty);
    expect(state.sentences.first.text, '[INDISTINCT CHATTER]');
    expect(state.sentences.first.isBookmarked, isFalse);
  });

  test('重新加载同一音频（早返回）不重置循环开关', () async {
    final item = createTestAudioItem(id: 'audio-1');
    lp.seed(audioItem: item, settings: loopOnSettings);

    // 同 id + 同 transcript：loadAudio 早返回，不进入重置路径
    await lp.loadAudio(createTestAudioItem(id: 'audio-1'));

    final settings = container.read(listeningPracticeProvider).settings;
    expect(settings.loopWhole, isTrue);
    expect(settings.loopSentence, isTrue);
  });
}
