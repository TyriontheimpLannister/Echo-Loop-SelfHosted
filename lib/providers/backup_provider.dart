import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../database/app_database.dart';
import '../database/providers.dart';
import '../services/backup/backup_manifest.dart';
import '../services/backup/backup_progress.dart';
import '../services/backup/backup_service.dart';
import '../services/profile_service.dart';
import 'audio_library_provider.dart';
import 'collection_provider.dart';
import 'learning_progress_provider.dart';
import 'package_info_provider.dart';
import 'profile_provider.dart';
import 'tag_provider.dart';

/// BackupService Provider
final backupServiceProvider = Provider<BackupService>((ref) {
  return BackupService(ref.watch(appDatabaseProvider));
});

/// 导出数据，返回生成的 ZIP 文件路径
///
/// [onProgress] 回调报告进度。
Future<String> performExport(
  WidgetRef ref, {
  void Function(BackupProgress)? onProgress,
}) async {
  final service = ref.read(backupServiceProvider);
  final packageInfo = ref.read(packageInfoProvider);
  final tempDir = await getTemporaryDirectory();

  return service.exportData(
    outputDir: tempDir.path,
    appVersion: packageInfo.version,
    platform: _currentPlatform,
    onProgress: onProgress,
  );
}

/// 读取备份文件 manifest（导入前预览用）
Future<BackupManifest> readBackupManifest(WidgetRef ref, String path) {
  return ref.read(backupServiceProvider).readManifest(path);
}

/// 导入数据（含数据库热切换）
///
/// 完整流程：关闭旧数据库 → 导入 → 打开新数据库 → 刷新 Provider。
Future<BackupManifest> performImport(
  WidgetRef ref,
  String zipPath, {
  void Function(BackupProgress)? onProgress,
}) async {
  final service = ref.read(backupServiceProvider);

  // Step 1: 关闭当前数据库
  await closeCurrentDatabase();

  try {
    // Step 2: 导入（替换 db 文件 + 恢复 SP + 复制媒体）
    final manifest = await service.importData(
      zipPath: zipPath,
      onProgress: onProgress,
    );

    // Step 3: 重新打开数据库并热切换
    final profile = ref.read(activeProfileProvider);
    final newDb = AppDatabase(
      openConnectionWithName(profileDatabaseFileName(profile)),
    );
    switchAppDatabase(newDb, ref);

    // Step 4: 重新加载数据
    await ref.read(audioLibraryProvider.notifier).loadLibrary();
    ref.read(collectionListProvider.notifier).loadCollections();
    ref.read(tagListProvider.notifier).loadTags();
    await ref.read(learningProgressNotifierProvider.notifier).loadAll();

    return manifest;
  } catch (e) {
    // 恢复数据库连接
    final profile = ref.read(activeProfileProvider);
    final fallbackDb = AppDatabase(
      openConnectionWithName(profileDatabaseFileName(profile)),
    );
    switchAppDatabase(fallbackDb, ref);
    await ref.read(audioLibraryProvider.notifier).loadLibrary();
    ref.read(collectionListProvider.notifier).loadCollections();
    ref.read(tagListProvider.notifier).loadTags();
    await ref.read(learningProgressNotifierProvider.notifier).loadAll();
    rethrow;
  }
}

/// 获取当前平台标识
String get _currentPlatform {
  if (Platform.isIOS) return 'ios';
  if (Platform.isMacOS) return 'macos';
  if (Platform.isAndroid) return 'android';
  return defaultTargetPlatform.name;
}
