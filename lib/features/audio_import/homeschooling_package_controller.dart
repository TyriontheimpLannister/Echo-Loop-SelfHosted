// HomeSchooling 听写包导入/导出的 UI 控制器。
//
// 之所以单独抽 controller，是因为：
// 1. 导入与导出各自有进度状态，UI 要分别订阅；
// 2. 跨 build_runner 生成代码不直接挂 UI；服务类留在 service 文件里。
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../database/providers.dart';
import '../../providers/audio_library_provider.dart';
import '../../providers/collection_provider.dart';
import '../../providers/audio_sentences_provider.dart';
import '../../models/audio_item.dart';
import '../../models/sentence.dart';
import 'homeschooling_package_exporter.dart';
import 'homeschooling_package_importer.dart';
import 'homeschooling_package_receiver_service.dart';
import 'homeschooling_package.dart';

/// 导入进度状态。
sealed class HomeschoolingImportState {
  const HomeschoolingImportState();
}

class HomeschoolingImportIdle extends HomeschoolingImportState {
  const HomeschoolingImportIdle();
}

class HomeschoolingImportRunning extends HomeschoolingImportState {
  const HomeschoolingImportRunning();
}

class HomeschoolingImportSuccess extends HomeschoolingImportState {
  const HomeschoolingImportSuccess(
    this.addedCount,
    this.duplicateCount,
    this.failedCount,
    this.lastFileName,
  );

  final int addedCount;
  final int duplicateCount;
  final int failedCount;
  final String? lastFileName;
}

class HomeschoolingImportFailure extends HomeschoolingImportState {
  const HomeschoolingImportFailure(this.message);

  final String message;
}

class HomeschoolingImportController
    extends AutoDisposeNotifier<HomeschoolingImportState> {
  @override
  HomeschoolingImportState build() => const HomeschoolingImportIdle();

  Future<void> importFromFile(File file) async {
    state = const HomeschoolingImportRunning();
    try {
      final importer = HomeschoolingPackageImporter();
      final result = await importer.importJsonString(
        await file.readAsString(),
        dao: ref.read(audioItemDaoProvider),
        childSlug: '',
        audioLibrary: ref.read(audioLibraryProvider.notifier),
        audioLibraryState: ref.read(audioLibraryProvider),
        collectionList: ref.read(collectionListProvider.notifier),
        collectionState: ref.read(collectionListProvider),
      );
      state = HomeschoolingImportSuccess(
        result.added.length,
        result.duplicates.length,
        result.failed,
        file.uri.pathSegments.isNotEmpty ? file.uri.pathSegments.last : null,
      );
    } catch (error) {
      state = HomeschoolingImportFailure(error.toString());
    }
  }

  Future<void> receiveFromHomeSchooling({
    required String password,
    required String contentMode,
  }) async {
    state = const HomeschoolingImportRunning();
    try {
      final receiver = HomeSchoolingPackageReceiverService();
      final received = await receiver.receiveLatestPackage(
        password: password,
        contentMode: contentMode,
      );
      final result = await HomeschoolingPackageImporter().importPackage(
        received.package,
        dao: ref.read(audioItemDaoProvider),
        childSlug: '',
        audioLibrary: ref.read(audioLibraryProvider.notifier),
        audioLibraryState: ref.read(audioLibraryProvider),
        collectionList: ref.read(collectionListProvider.notifier),
        collectionState: ref.read(collectionListProvider),
      );
      state = HomeschoolingImportSuccess(
        result.added.length,
        result.duplicates.length,
        result.failed,
        received.package.title,
      );
    } catch (error) {
      state = HomeschoolingImportFailure(error.toString());
    }
  }

  void reset() {
    state = const HomeschoolingImportIdle();
  }
}

final homeschoolingImportControllerProvider =
    NotifierProvider.autoDispose<
      HomeschoolingImportController,
      HomeschoolingImportState
    >(HomeschoolingImportController.new);

/// 导出服务 provider（单例）。
final homeschoolingPackageExporterProvider =
    Provider<HomeschoolingPackageExporter>(
      (ref) => HomeschoolingPackageExporter(),
    );

/// 导出包时同步注入 [audioSentencesProvider] 的内存兜底，让 DB 列丢失时仍能
/// 拼出完整包（常见于旧设备首次升级 1.0.28 后）。
extension HomeschoolingExporterPrime on WidgetRef {
  Future<HomeschoolingPackage?> buildHomeschoolingPackage(
    AudioItem item,
  ) async {
    final exporter = read(homeschoolingPackageExporterProvider);
    invalidate(audioSentencesProvider(item.id));
    final sentences = await read(
      audioSentencesProvider(item.id).future,
    ).catchError((_) => const <Sentence>[]);
    if (sentences.isNotEmpty) {
      exporter.primeExtraSentences(sentences);
    }
    try {
      return await exporter.buildPackage(
        dao: read(audioItemDaoProvider),
        audioItem: item,
      );
    } finally {
      exporter.primeExtraSentences(const <Sentence>[]);
    }
  }
}
