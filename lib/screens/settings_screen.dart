import 'dart:io';

import 'package:flutter/material.dart';

import '../services/book_service.dart';
import '../services/download_service.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';
import '../widgets/confirm_dialog.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.storage,
    this.downloadService,
  });

  final StorageService storage;
  final DownloadService? downloadService;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final totalBytes = storage.downloads.fold<int>(
      0,
      (sum, d) => sum + d.fileSize,
    );
    final totalMB = (totalBytes / (1024 * 1024)).toStringAsFixed(1);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Settings',
          style: theme.textTheme.titleMedium?.copyWith(
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: ListTileTheme(
        data: ListTileThemeData(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
          titleTextStyle: theme.textTheme.titleMedium?.copyWith(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.onSurface,
          ),
          subtitleTextStyle: theme.textTheme.bodyMedium?.copyWith(
            fontSize: 11.5,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            // Section: Appearance & Theme
            _buildSectionHeader(context, 'APPEARANCE & THEME'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: AppPalette.values.map((palette) {
                  final isSelected = storage.themeKey == palette.id;
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => storage.setThemeKey(palette.id),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? palette.primary.withAlpha(28)
                                : theme.colorScheme.surfaceContainerLow,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: isSelected
                                  ? palette.primary
                                  : theme.colorScheme.outlineVariant.withAlpha(
                                      80,
                                    ),
                              width: isSelected ? 2 : 1,
                            ),
                            boxShadow: isSelected
                                ? [
                                    BoxShadow(
                                      color: palette.primary.withAlpha(60),
                                      blurRadius: 10,
                                    ),
                                  ]
                                : null,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  color: palette.primary,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white.withAlpha(180),
                                    width: 1.5,
                                  ),
                                ),
                                child: isSelected
                                    ? const Icon(
                                        Icons.check,
                                        size: 14,
                                        color: Colors.black,
                                      )
                                    : null,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                palette.name.split(' ').last,
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: isSelected
                                      ? FontWeight.bold
                                      : FontWeight.w500,
                                  color: isSelected
                                      ? palette.primary
                                      : theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 14),

            // Section: Playback
            _buildSectionHeader(context, 'PLAYBACK'),
            _buildGroupedCard(
              context,
              children: [
                SwitchListTile(
                  secondary: _buildIconBox(context, Icons.autorenew),
                  title: const Text('Autoplay'),
                  subtitle: const Text('Play similar songs when queue ends'),
                  value: storage.autoplay,
                  onChanged: (val) => storage.setAutoplay(val),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: _buildIconBox(context, Icons.speed),
                  title: const Text('Playback Speed'),
                  subtitle: Text(
                    storage.playbackSpeed == 1.0
                        ? '1.0x (Normal)'
                        : '${storage.playbackSpeed}x',
                  ),
                  trailing: DropdownButton<double>(
                    value: storage.playbackSpeed,
                    underline: const SizedBox.shrink(),
                    dropdownColor: theme.colorScheme.surfaceContainerHigh,
                    style: theme.textTheme.bodyMedium?.copyWith(fontSize: 13),
                    items: const [
                      DropdownMenuItem(value: 0.5, child: Text('0.5x')),
                      DropdownMenuItem(value: 0.75, child: Text('0.75x')),
                      DropdownMenuItem(value: 1.0, child: Text('1.0x Normal')),
                      DropdownMenuItem(value: 1.25, child: Text('1.25x')),
                      DropdownMenuItem(value: 1.5, child: Text('1.5x')),
                      DropdownMenuItem(value: 1.75, child: Text('1.75x')),
                      DropdownMenuItem(value: 2.0, child: Text('2.0x')),
                    ],
                    onChanged: (val) {
                      if (val != null) storage.setPlaybackSpeed(val);
                    },
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: _buildIconBox(context, Icons.high_quality),
                  title: const Text('Audio Quality'),
                  subtitle: Text(
                    storage.audioQuality == 'high' ? 'High' : 'Data Saver',
                  ),
                  trailing: DropdownButton<String>(
                    value: storage.audioQuality,
                    underline: const SizedBox.shrink(),
                    dropdownColor: theme.colorScheme.surfaceContainerHigh,
                    style: theme.textTheme.bodyMedium?.copyWith(fontSize: 13),
                    items: const [
                      DropdownMenuItem(
                        value: 'high',
                        child: Text('High Quality'),
                      ),
                      DropdownMenuItem(value: 'saver', child: Text('Data Saver')),
                    ],
                    onChanged: (val) {
                      if (val != null) storage.setAudioQuality(val);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

          // Section: Storage & Data
          _buildSectionHeader(context, 'STORAGE & DATA'),
          _buildGroupedCard(
            context,
            children: [
              ListTile(
                leading: _buildIconBox(context, Icons.download_done),
                title: const Text('Downloaded Music'),
                subtitle: Text(
                  '${storage.downloads.length} tracks • $totalMB MB',
                ),
                trailing: storage.downloads.isNotEmpty
                    ? TextButton(
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          textStyle: const TextStyle(fontSize: 12.5),
                        ),
                        onPressed: () async {
                          final confirm = await showConfirmDialog(
                            context,
                            title: 'Delete all downloads?',
                            message:
                                'This will remove all downloaded offline files from your device.',
                            confirmLabel: 'Delete All',
                          );
                          if (confirm) {
                            await downloadService?.clearAllDownloads();
                          }
                        },
                        child: const Text('Clear'),
                      )
                    : null,
              ),
              const Divider(height: 1),
              FutureBuilder<List<File>>(
                future: BookService().getDownloadedBooks(),
                builder: (context, snapshot) {
                  final books = snapshot.data ?? [];
                  final totalBookBytes = books.fold<int>(
                    0,
                    (sum, f) => sum + (f.existsSync() ? f.lengthSync() : 0),
                  );
                  final booksMB = (totalBookBytes / (1024 * 1024)).toStringAsFixed(1);
                  return ListTile(
                    leading: _buildIconBox(context, Icons.menu_book),
                    title: const Text('Downloaded Books (PDFs)'),
                    subtitle: Text('${books.length} books • $booksMB MB'),
                    trailing: books.isNotEmpty
                        ? TextButton(
                            style: TextButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              textStyle: const TextStyle(fontSize: 12.5),
                            ),
                            onPressed: () => _showManageBooksModal(context),
                            child: const Text('Manage'),
                          )
                        : null,
                  );
                },
              ),
              const Divider(height: 1),
              ListTile(
                leading: _buildIconBox(context, Icons.history),
                title: const Text('Play History'),
                subtitle: Text('${storage.history.length} played tracks'),
                trailing: storage.history.isNotEmpty
                    ? TextButton(
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          textStyle: const TextStyle(fontSize: 12.5),
                        ),
                        onPressed: () async {
                          final confirm = await showConfirmDialog(
                            context,
                            title: 'Clear Play History?',
                            message:
                                'Are you sure you want to clear your playback history?',
                            confirmLabel: 'Clear',
                          );
                          if (confirm) {
                            storage.clearHistory();
                          }
                        },
                        child: const Text('Clear'),
                      )
                    : null,
              ),
              const Divider(height: 1),
              ListTile(
                leading: _buildIconBox(
                  context,
                  Icons.delete_forever,
                  color: theme.colorScheme.error,
                ),
                title: Text(
                  'Reset All Data',
                  style: TextStyle(color: theme.colorScheme.error),
                ),
                subtitle: const Text('Clear library, downloads, and history'),
                onTap: () async {
                  final confirm = await showConfirmDialog(
                    context,
                    title: 'Reset Shuno?',
                    message:
                        'Are you sure you want to reset all data? This cannot be undone.',
                    confirmLabel: 'Reset',
                  );
                  if (confirm) {
                    await downloadService?.clearAllDownloads();
                    await storage.clearAllData();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('All data reset')),
                      );
                    }
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Section: About
          _buildSectionHeader(context, 'ABOUT'),
          _buildGroupedCard(
            context,
            children: [
              ListTile(
                title: const Text(
                  'Shuno',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: const Text('YouTube Audio Client • v0.1.0'),
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.asset(
                    'assets/shuno.png',
                    width: 32,
                    height: 32,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
        ],
      ),
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 6),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 11,
          letterSpacing: 1.2,
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildGroupedCard(
    BuildContext context, {
    required List<Widget> children,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant.withAlpha(60),
          width: 0.8,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(mainAxisSize: MainAxisSize.min, children: children),
    );
  }

  Widget _buildIconBox(BuildContext context, IconData icon, {Color? color}) {
    final theme = Theme.of(context);
    final effectiveColor = color ?? theme.colorScheme.primary;
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: effectiveColor.withAlpha(26),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, color: effectiveColor, size: 18),
    );
  }

  void _showManageBooksModal(BuildContext context) {
    final bookService = BookService();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (modalCtx, setModalState) {
          final theme = Theme.of(ctx);
          return FutureBuilder<List<File>>(
            future: bookService.getDownloadedBooks(),
            builder: (context, snapshot) {
              final books = snapshot.data ?? [];
              return SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'DOWNLOADED BOOKS (${books.length})',
                              style: theme.textTheme.labelMedium?.copyWith(
                                letterSpacing: 1.2,
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (books.isNotEmpty)
                                  TextButton(
                                    style: TextButton.styleFrom(
                                      visualDensity: VisualDensity.compact,
                                      foregroundColor: theme.colorScheme.error,
                                    ),
                                    onPressed: () async {
                                      final confirm = await showConfirmDialog(
                                        context,
                                        title: 'Delete all books?',
                                        message:
                                            'This will remove all downloaded PDF books from your device to free storage space.',
                                        confirmLabel: 'Delete All',
                                      );
                                      if (confirm) {
                                        for (final b in books) {
                                          await bookService.deleteDownloadedPdf(b.path);
                                          await storage.purgePdf(b.path);
                                        }
                                        setModalState(() {});
                                        if (ctx.mounted) Navigator.of(ctx).pop();
                                      }
                                    },
                                    child: const Text('Clear All'),
                                  ),
                                IconButton(
                                  icon: const Icon(Icons.close),
                                  onPressed: () => Navigator.of(ctx).pop(),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      if (books.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(32),
                          child: Center(child: Text('No downloaded books stored on device.')),
                        )
                      else
                        Flexible(
                          child: ListView.separated(
                            shrinkWrap: true,
                            itemCount: books.length,
                            separatorBuilder: (context, index) => const Divider(height: 1),
                            itemBuilder: (itemCtx, index) {
                              final file = books[index];
                              final sizeBytes = file.existsSync() ? file.lengthSync() : 0;
                              final mb = (sizeBytes / (1024 * 1024)).toStringAsFixed(1);
                              final rawTitle = storage.getPdfTitle(file.path);
                              final fallback = file.path
                                  .split(Platform.pathSeparator)
                                  .last
                                  .replaceAll('.pdf', '')
                                  .replaceAll('_', ' ');
                              final savedTitle = BookService.sanitizeBookTitle(
                                rawTitle,
                                fallbackTitle: fallback,
                              );

                              return ListTile(
                                leading: Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.primaryContainer.withAlpha(120),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(
                                    Icons.picture_as_pdf,
                                    color: theme.colorScheme.primary,
                                    size: 22,
                                  ),
                                ),
                                title: Text(
                                  savedTitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
                                ),
                                subtitle: Text(
                                  '$mb MB • Stored locally',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                trailing: IconButton(
                                  icon: Icon(
                                    Icons.delete_outline,
                                    color: theme.colorScheme.error,
                                    size: 20,
                                  ),
                                  tooltip: 'Delete from device',
                                  onPressed: () async {
                                    final confirm = await showConfirmDialog(
                                      context,
                                      title: 'Delete Book File?',
                                      message:
                                          'Delete "$savedTitle" from device storage? This will free up storage space.',
                                      confirmLabel: 'Delete',
                                    );
                                    if (confirm) {
                                      await bookService.deleteDownloadedPdf(file.path);
                                      await storage.purgePdf(file.path);
                                      setModalState(() {});
                                    }
                                  },
                                ),
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
