import 'package:dio/dio.dart';
import 'package:echo_loop/features/audio_import/audio_import_models.dart';
import 'package:echo_loop/features/baidu_netdisk/data/baidu_credential_repository.dart';
import 'package:echo_loop/features/baidu_netdisk/data/baidu_netdisk_api.dart';
import 'package:echo_loop/features/baidu_netdisk/data/baidu_netdisk_import_service.dart';
import 'package:echo_loop/features/baidu_netdisk/models/baidu_credential_bundle.dart';
import 'package:echo_loop/features/baidu_netdisk/models/baidu_oauth_session.dart';
import 'package:echo_loop/features/baidu_netdisk/models/baidu_oauth_session_status.dart';
import 'package:echo_loop/features/baidu_netdisk/models/cloud_drive_models.dart';
import 'package:echo_loop/features/baidu_netdisk/providers/baidu_netdisk_import_controller.dart';
import 'package:echo_loop/features/baidu_netdisk/services/baidu_oauth_launcher.dart';
import 'package:echo_loop/models/audio_item.dart';
import 'package:echo_loop/providers/audio_library_provider.dart';
import 'package:echo_loop/providers/collection_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeCredentialRepository implements BaiduCredentialRepository {
  _FakeCredentialRepository(this.accessToken);

  String? accessToken;
  bool cleared = false;

  @override
  Future<void> clearCredential() async {
    cleared = true;
    accessToken = null;
  }

  @override
  Future<BaiduOAuthSession> createSession(BaiduNetdiskPlatform platform) {
    throw UnimplementedError();
  }

  @override
  Future<BaiduOAuthSessionStatus> fetchStatus(BaiduOAuthSession session) {
    throw UnimplementedError();
  }

  @override
  Future<String?> getValidAccessToken() async => accessToken;

  @override
  Future<void> persistCompletedSession({
    required BaiduOAuthSession session,
    required BaiduCredentialBundle credential,
  }) async {}
}

class _FakeBaiduNetdiskApi implements BaiduNetdiskApi {
  List<CloudDriveEntry> entries = const <CloudDriveEntry>[];
  String? lastDir;

  @override
  Future<BaiduDownloadLink> fetchDownloadLink({
    required String accessToken,
    required int fsId,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<void> downloadToFile({
    required String accessToken,
    required String dlink,
    required String savePath,
    int? expectedSize,
    CancelToken? cancelToken,
    void Function(int receivedBytes, int? totalBytes)? onProgress,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<CloudDriveListPage> listDirectory({
    required String accessToken,
    String dir = '/',
    int start = 0,
    int limit = 100,
  }) async {
    lastDir = dir;
    return CloudDriveListPage(
      entries: entries,
      nextStart: entries.length,
      hasMore: false,
    );
  }
}

class _FakeImportService implements BaiduNetdiskImportService {
  List<CloudDriveEntry> importedEntries = const <CloudDriveEntry>[];
  List<CloudDriveEntry> importedSubtitleEntries = const <CloudDriveEntry>[];

  @override
  Future<AudioItem> importAudio({
    required CloudDriveEntry entry,
    required AudioLibrary audioLibrary,
    required AudioLibraryState audioLibraryState,
    CollectionList? collectionList,
    CollectionState? collectionState,
    String? collectionId,
    CancelToken? cancelToken,
    BaiduNetdiskImportProgressCallback? onProgress,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<CloudDriveImportOutcome> importAudios({
    required List<CloudDriveEntry> entries,
    List<CloudDriveEntry> subtitleEntries = const <CloudDriveEntry>[],
    required AudioLibrary audioLibrary,
    required AudioLibraryState audioLibraryState,
    CollectionList? collectionList,
    CollectionState? collectionState,
    String? collectionId,
    CancelToken? cancelToken,
    BaiduNetdiskImportProgressCallback? onProgress,
    BaiduNetdiskImportItemResultCallback? onItemResult,
  }) async {
    importedEntries = entries;
    importedSubtitleEntries = subtitleEntries;
    for (final entry in entries) {
      onProgress?.call(entry, entry.size, entry.size);
      final item = AudioItem(
        id: 'audio-${entry.fsId}',
        name: entry.name.replaceFirst(RegExp(r'\.[^.]+$'), ''),
        audioPath: 'audios/${entry.fsId}.mp3',
        addedDate: DateTime(2026, 1, 1),
      );
      await audioLibrary.addAudioItem(item);
      onItemResult?.call(
        CloudDriveImportItemResult.added(entry: entry, item: item),
      );
    }
    return CloudDriveImportOutcome(
      added: entries,
      addedItems: [
        for (final entry in entries)
          AudioItem(
            id: 'audio-${entry.fsId}',
            name: entry.name.replaceFirst(RegExp(r'\.[^.]+$'), ''),
            audioPath: 'audios/${entry.fsId}.mp3',
            addedDate: DateTime(2026, 1, 1),
          ),
      ],
    );
  }
}

class _NoopLauncher implements BaiduOAuthLauncher {
  @override
  Future<void> open(Uri authorizationUri) async {}
}

class _FakeAudioLibrary extends AudioLibrary {
  var contentCheckCalls = 0;

  @override
  AudioLibraryState build() => const AudioLibraryState();

  @override
  Future<void> addAudioItem(AudioItem item) async {
    state = state.copyWith(audioItems: [...state.audioItems, item]);
  }

  @override
  Future<void> checkAudioContent(
    String audioId, {
    int? decodedDurationSeconds,
  }) async {
    contentCheckCalls++;
  }
}

class _FakeCollectionList extends CollectionList {
  @override
  CollectionState build() => const CollectionState();
}

void main() {
  group('BaiduNetdiskImportController', () {
    late _FakeCredentialRepository credentialRepository;
    late _FakeBaiduNetdiskApi api;
    late _FakeImportService importService;
    late ProviderContainer container;
    late BaiduNetdiskImportController controller;

    const folder = CloudDriveEntry(
      fsId: 1,
      name: 'Folder',
      path: '/Folder',
      isDirectory: true,
      size: 0,
    );
    const audio = CloudDriveEntry(
      fsId: 2,
      name: 'lesson.mp3',
      path: '/lesson.mp3',
      isDirectory: false,
      size: 1024,
    );
    const text = CloudDriveEntry(
      fsId: 3,
      name: 'notes.txt',
      path: '/notes.txt',
      isDirectory: false,
      size: 10,
    );
    const subtitle = CloudDriveEntry(
      fsId: 4,
      name: 'lesson.srt',
      path: '/lesson.srt',
      isDirectory: false,
      size: 20,
    );
    const secondAudio = CloudDriveEntry(
      fsId: 5,
      name: 'review.mp3',
      path: '/review.mp3',
      isDirectory: false,
      size: 2048,
    );

    setUp(() {
      credentialRepository = _FakeCredentialRepository('access-token');
      api = _FakeBaiduNetdiskApi();
      importService = _FakeImportService();
      container = ProviderContainer(
        overrides: [
          audioLibraryProvider.overrideWith(_FakeAudioLibrary.new),
          collectionListProvider.overrideWith(_FakeCollectionList.new),
        ],
      );
      controller = BaiduNetdiskImportController(
        credentialRepository: credentialRepository,
        api: api,
        importService: importService,
        launcher: _NoopLauncher(),
        audioLibrary: container.read(audioLibraryProvider.notifier),
        readAudioLibraryState: () => container.read(audioLibraryProvider),
        collectionList: container.read(collectionListProvider.notifier),
        readCollectionState: () => container.read(collectionListProvider),
      );
    });

    tearDown(() {
      controller.dispose();
      container.dispose();
    });

    test('无 access token 时进入授权态', () async {
      credentialRepository.accessToken = null;

      await controller.loadInitial();

      expect(
        controller.state.phase,
        BaiduNetdiskImportPhase.authorizationRequired,
      );
    });

    test('加载目录时保留目录、音频和非音频文件', () async {
      api.entries = const [folder, audio, text];

      await controller.loadInitial();

      expect(controller.state.phase, BaiduNetdiskImportPhase.ready);
      expect(controller.state.entries, [folder, audio, text]);
      expect(api.lastDir, '/');
    });

    test('只能选择支持的音频和字幕文件', () async {
      api.entries = const [audio, subtitle, secondAudio, text];
      await controller.loadInitial();

      controller.toggleEntry(text);
      expect(controller.state.selectedFsIds, isEmpty);

      controller.toggleEntry(audio);
      expect(controller.state.selectedFsIds, {audio.fsId});
      expect(controller.state.selectedAudioEntries, [audio]);
      expect(controller.state.selectedSubtitleEntries, isEmpty);

      controller.toggleEntry(secondAudio);
      expect(controller.state.selectedFsIds, {audio.fsId, secondAudio.fsId});
      expect(controller.state.selectedAudioEntries, [audio, secondAudio]);
      expect(controller.state.selectedSubtitleEntries, isEmpty);

      controller.toggleEntry(subtitle);
      expect(controller.state.selectedFsIds, {
        audio.fsId,
        secondAudio.fsId,
        subtitle.fsId,
      });
      expect(controller.state.selectedAudioEntries, [audio, secondAudio]);
      expect(controller.state.selectedSubtitleEntries, [subtitle]);
    });

    test('全选只切换当前目录内可导入的音频和字幕', () async {
      api.entries = const [folder, audio, subtitle, text];
      await controller.loadInitial();

      controller.toggleSelectAll();

      expect(controller.state.selectedFsIds, {audio.fsId, subtitle.fsId});
      expect(controller.state.isAllSelectableSelected, isTrue);

      controller.toggleSelectAll();
      expect(controller.state.selectedFsIds, isEmpty);
    });

    test('选择音频和字幕并导入后进入完成态', () async {
      api.entries = const [audio, subtitle];
      await controller.loadInitial();

      controller.toggleEntry(audio);
      controller.toggleEntry(subtitle);
      await controller.importSelected();

      expect(importService.importedEntries, [audio]);
      expect(importService.importedSubtitleEntries, [subtitle]);
      expect(controller.state.phase, BaiduNetdiskImportPhase.completed);
      expect(controller.state.selectedFsIds, {audio.fsId, subtitle.fsId});
      expect(controller.state.importOutcome?.added, [audio]);
      expect(controller.state.importOutcome?.addedItems.single.name, 'lesson');
      expect(
        controller.state.importItemStatuses[audio.fsId],
        AudioImportSelectionStatus.added,
      );
      expect(
        container.read(audioLibraryProvider).audioItems.single.name,
        'lesson',
      );
      expect(
        (container.read(audioLibraryProvider.notifier) as _FakeAudioLibrary)
            .contentCheckCalls,
        0,
      );

      controller.returnToReady();

      expect(controller.state.phase, BaiduNetdiskImportPhase.ready);
      expect(controller.state.selectedFsIds, isEmpty);
      expect(controller.state.importOutcome, isNull);
    });
  });
}
