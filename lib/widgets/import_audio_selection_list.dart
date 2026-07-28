import 'package:flutter/material.dart';

import '../features/audio_import/audio_import_models.dart';
import '../l10n/app_localizations.dart';

/// 音频导入确认列表。
///
/// 本地文件导入与网盘导入共用：只展示将要导入的音频，同名字幕用 CC 徽章标记；
/// 音频文件大小列固定宽度，保证长文件名不会挤乱列表。
class ImportAudioSelectionList extends StatefulWidget {
  const ImportAudioSelectionList({
    super.key,
    required this.items,
    this.maxHeight = 240,
    this.progress,
    this.summary,
    this.onRemove,
  });

  final List<AudioImportSelectionItem> items;
  final double maxHeight;
  final AudioImportSelectionProgress? progress;
  final AudioImportSelectionSummary? summary;
  final ValueChanged<String>? onRemove;

  double get _effectiveMaxHeight => maxHeight.isFinite ? maxHeight : 240;

  @override
  State<ImportAudioSelectionList> createState() =>
      _ImportAudioSelectionListState();
}

class _ImportAudioSelectionListState extends State<ImportAudioSelectionList> {
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final boundedHeight = constraints.hasBoundedHeight;
        final fileList = boundedHeight
            ? _buildListContainer(context, shrinkWrap: false)
            : ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: widget._effectiveMaxHeight,
                ),
                child: _buildListContainer(context, shrinkWrap: true),
              );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(context),
            boundedHeight ? Expanded(child: fileList) : fileList,
            if (widget.progress != null) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(value: widget.progress!.value),
              const SizedBox(height: 4),
              Text(
                widget.progress!.label,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (widget.summary != null) ...[
              const SizedBox(height: 12),
              _ImportSelectionSummaryView(summary: widget.summary!),
            ],
          ],
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final totalBytes = widget.items.fold<int>(
      0,
      (sum, item) => sum + item.fileSize,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        '${l10n.filesSelected(widget.items.length)}'
        '  ·  ${formatImportFileSize(totalBytes)}',
        style: theme.textTheme.labelMedium?.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _buildListContainer(BuildContext context, {required bool shrinkWrap}) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Scrollbar(
        controller: _scrollController,
        child: ListView.separated(
          controller: _scrollController,
          primary: false,
          shrinkWrap: shrinkWrap,
          padding: const EdgeInsets.symmetric(vertical: 4),
          itemCount: widget.items.length,
          separatorBuilder: (_, __) => Divider(
            height: 1,
            thickness: 1,
            indent: 44,
            color: colorScheme.outlineVariant.withValues(alpha: 0.4),
          ),
          itemBuilder: (context, index) =>
              _buildFileRow(context, widget.items[index], colorScheme),
        ),
      ),
    );
  }

  bool get _showStatusColumn {
    return widget.progress != null ||
        widget.summary != null ||
        widget.items.any(
          (item) => item.status != AudioImportSelectionStatus.pending,
        );
  }

  Widget _buildFileRow(
    BuildContext context,
    AudioImportSelectionItem item,
    ColorScheme colorScheme,
  ) {
    final theme = Theme.of(context);
    final canRemove =
        widget.onRemove != null &&
        item.status == AudioImportSelectionStatus.pending;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      child: Row(
        children: [
          Icon(Icons.graphic_eq, size: 18, color: colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.displayName,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (item.status == AudioImportSelectionStatus.skipped &&
                    item.duplicateExistingName != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      AppLocalizations.of(
                        context,
                      )!.duplicateExistingFileName(item.duplicateExistingName!),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 22,
            child: item.hasSubtitle
                ? Tooltip(
                    message: AppLocalizations.of(context)!.subtitlePairedBadge,
                    child: Icon(
                      Icons.closed_caption_outlined,
                      size: 18,
                      color: colorScheme.primary,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 64,
            child: Text(
              formatImportFileSize(item.fileSize),
              textAlign: TextAlign.right,
              style: theme.textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          if (_showStatusColumn)
            SizedBox(
              width: 32,
              child: _SelectionStatusIcon(status: item.status),
            ),
          if (canRemove) ...[
            const SizedBox(width: 4),
            Tooltip(
              message: AppLocalizations.of(context)!.removeFile,
              child: IconButton(
                onPressed: () => widget.onRemove!(item.id),
                icon: const Icon(Icons.delete_outline, size: 20),
                color: colorScheme.onSurfaceVariant,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(
                  width: 32,
                  height: 32,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SelectionStatusIcon extends StatelessWidget {
  const _SelectionStatusIcon({required this.status});

  final AudioImportSelectionStatus status;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final warningColor = Colors.orange.shade700;
    return Center(
      child: switch (status) {
        AudioImportSelectionStatus.pending => Icon(
          Icons.schedule,
          size: 18,
          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.72),
        ),
        AudioImportSelectionStatus.importing => SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: colorScheme.primary,
          ),
        ),
        AudioImportSelectionStatus.added => Icon(
          Icons.check_circle,
          size: 19,
          color: colorScheme.primary,
        ),
        AudioImportSelectionStatus.skipped => Icon(
          Icons.warning_amber_rounded,
          size: 19,
          color: warningColor,
        ),
      },
    );
  }
}

class _ImportSelectionSummaryView extends StatelessWidget {
  const _ImportSelectionSummaryView({required this.summary});

  final AudioImportSelectionSummary summary;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final warningColor = Colors.orange.shade700;
    final successParts = <String>[
      l10n.audioImportedCount(summary.addedCount),
      if (summary.addedCount > 0)
        l10n.audioImportedWithSubtitleCount(summary.subtitleCount),
    ];
    final summaryStyle = theme.textTheme.bodyMedium?.copyWith(
      fontWeight: FontWeight.w600,
      color: colorScheme.onSurface,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ImportSelectionSummaryRow(
          icon: Icons.check_circle,
          iconColor: colorScheme.primary,
          label: successParts.join(' · '),
          textStyle: summaryStyle,
        ),
        if (summary.skippedCount > 0) ...[
          const SizedBox(height: 4),
          _ImportSelectionSummaryRow(
            icon: Icons.warning_amber_rounded,
            iconColor: warningColor,
            label: l10n.duplicatesSkipped(summary.skippedCount),
            textStyle: summaryStyle,
          ),
        ],
      ],
    );
  }
}

class _ImportSelectionSummaryRow extends StatelessWidget {
  const _ImportSelectionSummaryRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.textStyle,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: iconColor, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textStyle,
          ),
        ),
      ],
    );
  }
}

/// 导入列表共用文件大小格式。
String formatImportFileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
