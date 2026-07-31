import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/profile_service.dart';

final initialProfileProvider = Provider<EchoLoopProfile>((ref) {
  // Tests and embedded previews do not run main(); Francis is the
  // backwards-compatible default for those callers.
  return EchoLoopProfile.francis;
});

final initialProfileSelectionRequiredProvider = Provider<bool>((ref) {
  return false;
});

final activeProfileProvider = StateProvider<EchoLoopProfile>((ref) {
  return ref.read(initialProfileProvider);
});

final profileSelectionRequiredProvider = StateProvider<bool>((ref) {
  return ref.read(initialProfileSelectionRequiredProvider);
});
