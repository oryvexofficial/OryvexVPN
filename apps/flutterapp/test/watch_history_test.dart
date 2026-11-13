import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vexostream_app/api/watch_history.dart';

void main() {
  test('history entries keep only safe absolute HTTP(S) video links', () {
    expect(
      WatchHistoryEntry.fromJson('{"url":"javascript:alert(1)"}'),
      isNull,
    );
    expect(
      WatchHistoryEntry.fromJson('{"url":"https://example.com/watch/1"}'),
      isNotNull,
    );
  });

  test('Continue Watching omits completed items and preserves resume position',
      () {
    final partial = WatchHistoryEntry(
      url: 'https://example.com/watch/1',
      title: 'Test video',
      provider: 'sample',
      thumbnail: '',
      position: 30,
      duration: 100,
      updatedAt: 1,
    );
    final complete = WatchHistoryEntry(
      url: 'https://example.com/watch/2',
      title: 'Finished video',
      provider: 'sample',
      thumbnail: '',
      position: 98,
      duration: 100,
      updatedAt: 2,
    );

    expect(partial.canResume, isTrue);
    expect(partial.progress, 0.3);
    expect(partial.toVideo()['resumeAt'], 30);
    expect(complete.canResume, isFalse);
  });

  test('history is saved locally and can be cleared', () async {
    SharedPreferences.setMockInitialValues({});
    final entry = WatchHistoryEntry(
      url: 'https://example.com/watch/1',
      title: 'Test video',
      provider: 'sample',
      thumbnail: '',
      position: 30,
      duration: 100,
      updatedAt: 1,
    );

    await WatchHistoryStore.save(entry);
    expect((await WatchHistoryStore.list()).single.url, entry.url);
    await WatchHistoryStore.clear();
    expect(await WatchHistoryStore.list(), isEmpty);
  });
}
