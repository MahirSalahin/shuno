import 'package:flutter/material.dart';

import '../services/download_service.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';

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
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 12),
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
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => storage.setThemeKey(palette.id),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? palette.primary.withAlpha(28)
                              : theme.colorScheme.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(16),
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
                              width: 28,
                              height: 28,
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
                                      size: 16,
                                      color: Colors.black,
                                    )
                                  : null,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              palette.name.split(' ').last,
                              style: TextStyle(
                                fontSize: 11,
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
          const SizedBox(height: 16),

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
                leading: _buildIconBox(context, Icons.high_quality),
                title: const Text('Audio Quality'),
                subtitle: Text(
                  storage.audioQuality == 'high' ? 'High' : 'Data Saver',
                ),
                trailing: DropdownButton<String>(
                  value: storage.audioQuality,
                  underline: const SizedBox.shrink(),
                  dropdownColor: theme.colorScheme.surfaceContainerHigh,
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
          const SizedBox(height: 16),

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
                        onPressed: () {
                          showDialog(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('Delete all downloads?'),
                              content: const Text(
                                'This will remove all downloaded offline files from your device.',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.of(context).pop(),
                                  child: const Text('Cancel'),
                                ),
                                FilledButton(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: theme.colorScheme.error,
                                  ),
                                  onPressed: () async {
                                    await downloadService?.clearAllDownloads();
                                    if (context.mounted)
                                      Navigator.of(context).pop();
                                  },
                                  child: const Text('Delete All'),
                                ),
                              ],
                            ),
                          );
                        },
                        child: const Text('Clear'),
                      )
                    : null,
              ),
              const Divider(height: 1),
              ListTile(
                leading: _buildIconBox(context, Icons.history),
                title: const Text('Play History'),
                subtitle: Text('${storage.history.length} played tracks'),
                trailing: storage.history.isNotEmpty
                    ? TextButton(
                        onPressed: () => storage.clearHistory(),
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
                onTap: () {
                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Reset Shuno?'),
                      content: const Text(
                        'Are you sure you want to reset all data? This cannot be undone.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Cancel'),
                        ),
                        FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: theme.colorScheme.error,
                          ),
                          onPressed: () async {
                            await downloadService?.clearAllDownloads();
                            await storage.clearAllData();
                            if (context.mounted) {
                              Navigator.of(context).pop();
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('All data reset')),
                              );
                            }
                          },
                          child: const Text('Reset'),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 16),

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
                  borderRadius: BorderRadius.circular(10),
                  child: Image.asset(
                    'assets/shuno.png',
                    width: 38,
                    height: 38,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
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
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: effectiveColor.withAlpha(26),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, color: effectiveColor, size: 20),
    );
  }
}
