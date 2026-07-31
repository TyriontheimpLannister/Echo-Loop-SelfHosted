import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../database/app_database.dart';
import '../database/providers.dart';
import '../providers/profile_provider.dart';
import '../features/onboarding_survey/providers/onboarding_survey_provider.dart';
import '../router/app_router.dart';
import '../services/profile_service.dart';

class ProfileSelectionScreen extends ConsumerStatefulWidget {
  const ProfileSelectionScreen({super.key});

  @override
  ConsumerState<ProfileSelectionScreen> createState() =>
      _ProfileSelectionScreenState();
}

class _ProfileSelectionScreenState
    extends ConsumerState<ProfileSelectionScreen> {
  bool _busy = false;

  Future<void> _select(EchoLoopProfile profile) async {
    if (_busy) return;
    setState(() => _busy = true);

    try {
      final current = ref.read(activeProfileProvider);
      if (current != profile) {
        await closeCurrentDatabase();
        final database = AppDatabase(
          openConnectionWithName(profileDatabaseFileName(profile)),
        );
        switchAppDatabase(database, ref);
      }

      final prefs = ref.read(sharedPreferencesProvider);
      await markProfileSelected(prefs, profile);
      ref.read(activeProfileProvider.notifier).state = profile;
      ref.read(profileSelectionRequiredProvider.notifier).state = false;
      if (!mounted) return;
      context.go(AppRoutes.study);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.people_alt_outlined, size: 64),
                  const SizedBox(height: 20),
                  Text(
                    '选择学习者',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 28),
                  for (final profile in EchoLoopProfile.values) ...[
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.tonal(
                        onPressed: _busy ? null : () => _select(profile),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          child: Text(profile.displayName),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (_busy)
                    const Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: CircularProgressIndicator(),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
