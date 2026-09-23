import 'package:flutter/material.dart';

import '../models/youtube_channel_item.dart';

class ChannelTile extends StatelessWidget {
  const ChannelTile({
    super.key,
    required this.channel,
    required this.onTap,
  });

  final YoutubeChannelItem channel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subs = channel.formattedSubscribers;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 2.5),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withAlpha(60),
          width: 0.8,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              // Circular Channel Avatar
              ClipOval(
                child: channel.thumbnailUrl.isNotEmpty
                    ? Image.network(
                        channel.thumbnailUrl,
                        width: 48,
                        height: 48,
                        cacheWidth: 144,
                        cacheHeight: 144,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => Container(
                          width: 48,
                          height: 48,
                          color: theme.colorScheme.surfaceContainerHighest,
                          child: const Icon(Icons.person, size: 24),
                        ),
                      )
                    : Container(
                        width: 48,
                        height: 48,
                        color: theme.colorScheme.surfaceContainerHighest,
                        child: const Icon(Icons.person, size: 24),
                      ),
              ),
              const SizedBox(width: 14),

              // Channel Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      channel.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1.5,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primaryContainer.withAlpha(120),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'Channel',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w600,
                              fontSize: 10,
                            ),
                          ),
                        ),
                        if (subs != null) ...[
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              subs,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),

              // Trailing chevron
              Icon(
                Icons.chevron_right,
                color: theme.colorScheme.outline,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
