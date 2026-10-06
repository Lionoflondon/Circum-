import 'dart:async';

import 'package:circum/app/sender_mobile/sender_profile_save_sequence.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('only an explicit backend acknowledgement confirms the write', () {
    requireSenderProfileAcknowledgement({'ok': true});
    for (final response in [
      null,
      [],
      {},
      {'ok': false},
      {'ok': 'true'}
    ]) {
      expect(() => requireSenderProfileAcknowledgement(response),
          throwsA(isA<SenderProfileSaveUnconfirmed>()));
    }
  });

  test('a write timeout is unconfirmed, never success or automatic retry',
      () async {
    var writes = 0;
    var reads = 0;
    await expectLater(
        saveSenderProfileSequence<String>(
          commitProfile: () async {
            writes++;
            throw TimeoutException('Response lost');
          },
          readCommittedProfile: () async {
            reads++;
            return 'unused';
          },
          mirrorDisplayName: () async {},
          isCurrentSession: () => true,
        ),
        throwsA(isA<SenderProfileSaveUnconfirmed>()));
    expect(writes, 1);
    expect(reads, 0);
  });

  testWidgets('slow Auth mirror stays bounded without repeating the save',
      (tester) async {
    final mirror = Completer<void>();
    final deferred = <Object>[];
    var writes = 0;
    final result = await saveSenderProfileSequence<String>(
      commitProfile: () async {
        writes++;
      },
      readCommittedProfile: () async => 'canonical profile',
      mirrorDisplayName: () => mirror.future,
      isCurrentSession: () => true,
      onMirrorDeferred: deferred.add,
    );
    expect(result, 'canonical profile');
    await tester.pump(const Duration(seconds: 21));
    expect(deferred.single, isA<TimeoutException>());
    expect(writes, 1);
    mirror.complete();
    await tester.pump();
  });

  test('acknowledges canonical save without waiting for the Auth mirror',
      () async {
    final events = <String>[];
    final mirror = Completer<void>();
    final result = await saveSenderProfileSequence<String>(
      commitProfile: () async => events.add('commit'),
      readCommittedProfile: () async {
        events.add('read');
        return 'canonical profile';
      },
      mirrorDisplayName: () {
        events.add('mirror');
        return mirror.future;
      },
      isCurrentSession: () => true,
    );
    expect(result, 'canonical profile');
    expect(events, ['commit', 'read', 'mirror']);
    expect(mirror.isCompleted, isFalse);
    mirror.complete();
  });

  test('an Auth mirror failure cannot turn a committed save into failure',
      () async {
    final deferred = <Object>[];
    var writes = 0;
    final result = await saveSenderProfileSequence<String>(
      commitProfile: () async {
        writes++;
      },
      readCommittedProfile: () async => 'canonical profile',
      mirrorDisplayName: () async => throw StateError('Auth unavailable'),
      isCurrentSession: () => true,
      onMirrorDeferred: deferred.add,
    );
    await Future<void>.delayed(Duration.zero);
    expect(result, 'canonical profile');
    expect(writes, 1);
    expect(deferred.single, isA<StateError>());
  });

  test('read failure distinguishes committed data from a failed write',
      () async {
    var writes = 0;
    var mirrors = 0;
    await expectLater(
        saveSenderProfileSequence<String>(
          commitProfile: () async {
            writes++;
          },
          readCommittedProfile: () async =>
              throw StateError('Read unavailable'),
          mirrorDisplayName: () async {
            mirrors++;
          },
          isCurrentSession: () => true,
        ),
        throwsA(isA<SenderProfileRefreshPending>()));
    expect(writes, 1);
    expect(mirrors, 0);
  });

  test('failed write is never acknowledged or retried', () async {
    var writes = 0;
    var reads = 0;
    await expectLater(
        saveSenderProfileSequence<String>(
          commitProfile: () async {
            writes++;
            throw StateError('Write denied');
          },
          readCommittedProfile: () async {
            reads++;
            return 'unused';
          },
          mirrorDisplayName: () async {},
          isCurrentSession: () => true,
        ),
        throwsA(isA<StateError>()));
    expect(writes, 1);
    expect(reads, 0);
  });

  test('session change discards an old account save result', () async {
    var current = true;
    var reads = 0;
    await expectLater(
        saveSenderProfileSequence<String>(
          commitProfile: () async {
            current = false;
          },
          readCommittedProfile: () async {
            reads++;
            return 'old account';
          },
          mirrorDisplayName: () async {},
          isCurrentSession: () => current,
        ),
        throwsA(isA<SenderProfileSaveSessionChanged>()));
    expect(reads, 0);
  });

  test('session change during refresh prevents an Auth mirror write', () async {
    var current = true;
    var mirrors = 0;
    await expectLater(
        saveSenderProfileSequence<String>(
          commitProfile: () async {},
          readCommittedProfile: () async {
            current = false;
            return 'old account';
          },
          mirrorDisplayName: () async {
            mirrors++;
          },
          isCurrentSession: () => current,
        ),
        throwsA(isA<SenderProfileSaveSessionChanged>()));
    expect(mirrors, 0);
  });
}
