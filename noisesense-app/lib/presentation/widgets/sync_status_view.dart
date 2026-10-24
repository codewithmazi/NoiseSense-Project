import 'package:flutter/material.dart';

import '../../domain/services/sync_engine.dart';
import '../theme/app_theme.dart';

/// Compact upload state for an app bar: the wireframe's "Synced" chip.
class SyncChip extends StatelessWidget {
  const SyncChip({super.key, required this.status});

  final SyncStatus status;

  @override
  Widget build(BuildContext context) {
    final waiting = status.pendingCount;
    final label = waiting == 0 ? 'Synced' : '$waiting waiting';
    return Semantics(
      label: waiting == 0
          ? 'All readings uploaded'
          : '$waiting ${waiting == 1 ? 'reading' : 'readings'} waiting to upload',
      excludeSemantics: true,
      child: Container(
        margin: const EdgeInsets.only(right: AppTheme.spaceMd),
        padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.spaceSm + 2,
          vertical: AppTheme.spaceXs,
        ),
        decoration: ShapeDecoration(
          color: waiting == 0 ? AppTheme.primary : AppTheme.warning,
          shape: const StadiumBorder(),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: AppTheme.onPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

/// One line of upload state, under a heading.
class SyncLine extends StatelessWidget {
  const SyncLine({super.key, required this.status});

  final SyncStatus status;

  @override
  Widget build(BuildContext context) {
    final parts = <String>[
      if (status.pendingCount > 0)
        '${status.pendingCount} '
            '${status.pendingCount == 1 ? 'reading' : 'readings'} saved on '
            'this phone, waiting to upload',
      if (status.isSyncing && status.pendingCount > 0) 'uploading now',
      if (!status.isSyncing && status.retryAt != null)
        'will retry automatically',
      if (status.rejectedCount > 0)
        '${status.rejectedCount} refused by the server and kept on this phone',
    ];
    if (parts.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: AppTheme.spaceXs),
      child: Semantics(
        liveRegion: true,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 1),
              child: Icon(
                Icons.cloud_upload_outlined,
                size: 16,
                color: AppTheme.onSurfaceMuted,
                semanticLabel: '',
              ),
            ),
            const SizedBox(width: AppTheme.spaceXs),
            Expanded(
              child: Text(
                '${parts.join(', ')}.',
                style: const TextStyle(
                  color: AppTheme.onSurfaceMuted,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
