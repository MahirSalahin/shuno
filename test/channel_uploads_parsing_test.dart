import 'package:flutter_test/flutter_test.dart';
import 'package:shuno/services/youtube_service.dart';

void main() {
  group('Channel Uploads JSON Parsing', () {
    late YoutubeService service;

    setUp(() {
      service = YoutubeService();
    });

    tearDown(() {
      service.dispose();
    });

    test('extracts real video title, duration, author, and continuation from lockupViewModel', () {
      final mockData = {
        'contents': {
          'twoColumnBrowseResultsRenderer': {
            'tabs': [
              {
                'tabRenderer': {
                  'content': {
                    'richGridRenderer': {
                      'contents': [
                        {
                          'richItemRenderer': {
                            'content': {
                              'lockupViewModel': {
                                'contentId': 'vid12345678',
                                'contentType': 'LOCKUP_CONTENT_TYPE_VIDEO',
                                'metadata': {
                                  'lockupMetadataViewModel': {
                                    'title': {
                                      'content': 'একটি নদীর নাম 2/2 | সুনীল গঙ্গোপাধ্যায় | Golpokothon',
                                    },
                                    'metadata': {
                                      'contentMetadataViewModel': {
                                        'metadataRows': [
                                          {
                                            'metadataParts': [
                                              {
                                                'text': {
                                                  'content': 'গল্পকথন by কল্লোল',
                                                }
                                              }
                                            ]
                                          }
                                        ]
                                      }
                                    }
                                  }
                                },
                                'contentImage': {
                                  'thumbnailViewModel': {
                                    'image': {
                                      'sources': [
                                        {'url': 'https://i.ytimg.com/vi/vid12345678/hqdefault.jpg'},
                                        {'url': 'https://i.ytimg.com/vi/vid12345678/maxresdefault.jpg'},
                                      ]
                                    },
                                    'overlays': [
                                      {
                                        'thumbnailBottomOverlayViewModel': {
                                          'badges': [
                                            {
                                              'thumbnailBadgeViewModel': {
                                                'text': '58:52',
                                              }
                                            }
                                          ]
                                        }
                                      }
                                    ]
                                  }
                                }
                              }
                            }
                          }
                        },
                        {
                          'continuationItemRenderer': {
                            'continuationEndpoint': {
                              'continuationCommand': {
                                'token': 'test_next_token_456',
                              }
                            }
                          }
                        }
                      ]
                    }
                  }
                }
              }
            ]
          }
        }
      };

      final result = service.extractChannelUploadsPageFromJson(
        mockData,
        'গল্পকথন by কল্লোল',
      );

      expect(result.items.length, 1);
      final item = result.items.first;
      expect(item.id, 'vid12345678');
      expect(item.title, 'একটি নদীর নাম 2/2 | সুনীল গঙ্গোপাধ্যায় | Golpokothon');
      expect(item.channelName, 'গল্পকথন by কল্লোল');
      expect(item.thumbnailUrl, 'https://i.ytimg.com/vi/vid12345678/maxresdefault.jpg');
      expect(item.duration, const Duration(minutes: 58, seconds: 52));
      expect(result.hasMore, isTrue);
      expect(result.continuation, 'test_next_token_456');
    });

    test('extracts legacy videoRenderer and gridVideoRenderer items', () {
      final mockData = {
        'contents': [
          {
            'videoRenderer': {
              'videoId': 'legacy12345',
              'title': {
                'runs': [
                  {'text': 'Legacy Track Title'}
                ]
              },
              'ownerText': {
                'runs': [
                  {'text': 'Legacy Author'}
                ]
              },
              'lengthText': {'simpleText': '04:15'},
              'thumbnail': {
                'thumbnails': [
                  {'url': 'https://i.ytimg.com/vi/legacy12345/hqdefault.jpg'}
                ]
              }
            }
          },
          {
            'gridVideoRenderer': {
              'videoId': 'grid1234567',
              'title': {'simpleText': 'Grid Track Title'},
              'shortBylineText': {
                'runs': [
                  {'text': 'Grid Author'}
                ]
              },
              'thumbnailOverlays': [
                {
                  'thumbnailOverlayTimeStatusRenderer': {
                    'text': {'simpleText': '1:02:30'}
                  }
                }
              ]
            }
          }
        ]
      };

      final result = service.extractChannelUploadsPageFromJson(mockData, 'Default');

      expect(result.items.length, 2);
      expect(result.items[0].title, 'Legacy Track Title');
      expect(result.items[0].channelName, 'Legacy Author');
      expect(result.items[0].duration, const Duration(minutes: 4, seconds: 15));

      expect(result.items[1].title, 'Grid Track Title');
      expect(result.items[1].channelName, 'Grid Author');
      expect(result.items[1].duration, const Duration(hours: 1, minutes: 2, seconds: 30));
      expect(result.hasMore, isFalse);
    });
  });
}
