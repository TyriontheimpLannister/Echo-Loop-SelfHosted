import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/app_data_dir.dart';

/// The two local learners in the self-hosted build.
enum EchoLoopProfile {
  naomi('naomi', 'Naomi'),
  francis('francis', 'Francis');

  const EchoLoopProfile(this.id, this.displayName);

  final String id;
  final String displayName;

  static EchoLoopProfile? fromId(String? id) {
    for (final profile in values) {
      if (profile.id == id) return profile;
    }
    return null;
  }
}

const activeProfileKey = 'echo_loop_active_profile';

String profileDatabaseFileName(EchoLoopProfile profile) =>
    'echo_loop_${profile.id}.db';

/// Bootstrap the local profile system without changing the user's old data.
///
/// Before profiles existed, the production database was named
/// `echo_loop.db`. It is assigned to Francis exactly once, as requested.
Future<EchoLoopProfile> prepareProfile(SharedPreferences prefs) async {
  final stored = EchoLoopProfile.fromId(prefs.getString(activeProfileKey));
  if (stored != null) return stored;

  await _assignLegacyDatabaseToFrancis();
  return EchoLoopProfile.francis;
}

Future<void> markProfileSelected(
  SharedPreferences prefs,
  EchoLoopProfile profile,
) => prefs.setString(activeProfileKey, profile.id);

String homeSchoolingChildKey(EchoLoopProfile profile) =>
    'echo_loop_homeschooling_child_${profile.id}';

String? readHomeSchoolingChildSlug(
  SharedPreferences prefs,
  EchoLoopProfile profile,
) => prefs.getString(homeSchoolingChildKey(profile));

Future<void> saveHomeSchoolingChildSlug(
  SharedPreferences prefs,
  EchoLoopProfile profile,
  String slug,
) => prefs.setString(homeSchoolingChildKey(profile), slug);

Future<void> _assignLegacyDatabaseToFrancis() async {
  final directory = await getAppDataDirectory();
  final legacyBase = p.join(directory.path, 'echo_loop.db');
  final targetBase = p.join(
    directory.path,
    profileDatabaseFileName(EchoLoopProfile.francis),
  );

  // Do not overwrite a profile database if a previous interrupted upgrade
  // already created it. In that case the legacy file remains recoverable.
  if (!File(legacyBase).existsSync() || File(targetBase).existsSync()) return;

  for (final suffix in ['', '-wal', '-shm']) {
    final source = File('$legacyBase$suffix');
    if (!source.existsSync()) continue;
    await source.rename('$targetBase$suffix');
  }
}
