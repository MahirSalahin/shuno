import 'package:flutter/material.dart';

import '../services/download_service.dart';
import '../services/storage_service.dart';

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
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          // Playback Settings Section
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'PLAYBACK',
              style: theme.textTheme.labelMedium?.copyWith(
                letterSpacing: 1.2,
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          SwitchListTile(
            title: const Text('Autoplay'),
            subtitle: const Text(
              'Automatically play related songs when the queue ends',
            ),
            value: storage.autoplay,
            onChanged: (val) => storage.setAutoplay(val),
          ),
          ListTile(
            title: const Text('Audio Quality'),
            subtitle: Text(
              storage.audioQuality == 'high'
                  ? 'High Quality (Best available audio bitrate)'
                  : 'Data Saver (Medium bitrate, saves data)',
            ),
            trailing: DropdownButton<String>(
              value: storage.audioQuality,
              underline: const SizedBox.shrink(),
              items: const [
                DropdownMenuItem(value: 'high', child: Text('High Quality')),
                DropdownMenuItem(value: 'saver', child: Text('Data Saver')),
              ],
              onChanged: (val) {
                if (val != null) storage.setAudioQuality(val);
              },
            ),
          ),
          const Divider(),

          // Storage & Data Section
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'STORAGE & DATA',
              style: theme.textTheme.labelMedium?.copyWith(
                letterSpacing: 1.2,
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          ListTile(
            title: const Text('Downloaded Music'),
            subtitle: Text('${storage.downloads.length} tracks ($totalMB MB)'),
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
                                if (context.mounted) Navigator.of(context).pop();
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
          ListTile(
            title: const Text('Play History'),
            subtitle: Text('${storage.history.length} played songs recorded'),
            trailing: storage.history.isNotEmpty
                ? TextButton(
                    onPressed: () => storage.clearHistory(),
                    child: const Text('Clear'),
                  )
                : null,
          ),
          ListTile(
            title: const Text('Reset All Data'),
            subtitle: const Text('Clears favorites, playlists, history, and downloads'),
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
          const Divider(),

          // About Section
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'ABOUT',
              style: theme.textTheme.labelMedium?.copyWith(
                letterSpacing: 1.2,
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          ListTile(
            title: const Text('Shuno'),
            subtitle: const Text('Personal YouTube Audio Experiment • v0.1.0'),
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.asset(
                'assets/shuno.png',
                width: 36,
                height: 36,
                fit: BoxFit.cover,
              ),
            ),
          ),
          const ListTile(
            title: Text('Built with'),
            subtitle: Text('Flutter • just_audio • youtube_explode_dart • audio_service'),
            leading: Icon(Icons.code),
          ),
        ],
      ),
    );
  }
}
