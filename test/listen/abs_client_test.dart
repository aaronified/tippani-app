import 'package:flutter_test/flutter_test.dart';
import 'package:tippani/listen/abs/abs_client.dart';
import 'package:tippani/listen/abs/abs_models.dart';

import '../support/fake_abs.dart';

void main() {
  late FakeAbs abs;
  late List<AbsTokens> saved;

  AbsClient make({AbsTokens? tokens}) => AbsClient(
    'https://abs.example/',
    client: abs.client,
    tokens: tokens,
    onTokens: (t) async => saved.add(t),
  );

  setUp(() {
    abs = FakeAbs();
    saved = [];
  });

  Future<AbsClient> signedIn() async {
    final c = make();
    await c.loginWithPassword('test', '1234');
    return c;
  }

  group('status', () {
    test(
      'reads the version and the sign-in methods without a credential',
      () async {
        final s = await make().status();
        expect(s.version, '2.37.2');
        expect(s.hasPassword, isTrue);
        expect(s.hasOpenId, isTrue);
        expect(s.openIdButtonText, 'Login with Authelia');
      },
    );

    test('refuses an address that is not Audiobookshelf', () async {
      abs.isAbs = false;
      await expectLater(
        make().status(),
        throwsA(
          isA<AbsException>().having(
            (e) => e.failure,
            'failure',
            AbsFailure.badResponse,
          ),
        ),
      );
    });
  });

  group('password sign-in', () {
    test('keeps both tokens and tells the caller to store them', () async {
      final c = make();
      final t = await c.loginWithPassword('test', '1234');
      expect(t.access, 'access-1');
      expect(t.refresh, 'refresh-1');
      expect(t.username, 'test');
      expect(t.isRoot, isFalse);
      expect(saved.single.access, 'access-1');
      expect(c.signedIn, isTrue);
    });

    test('a wrong password is unauthorised and stores nothing', () async {
      final c = make();
      await expectLater(
        c.loginWithPassword('test', 'nope'),
        throwsA(
          isA<AbsException>().having(
            (e) => e.failure,
            'failure',
            AbsFailure.unauthorised,
          ),
        ),
      );
      expect(saved, isEmpty);
      expect(c.signedIn, isFalse);
    });

    test('too many failed logins is rateLimited', () async {
      abs.loginLimit = 2;
      final c = make();
      for (var i = 0; i < 2; i++) {
        await expectLater(c.loginWithPassword('test', 'x'), throwsA(anything));
      }
      await expectLater(
        c.loginWithPassword('test', '1234'),
        throwsA(
          isA<AbsException>().having(
            (e) => e.failure,
            'failure',
            AbsFailure.rateLimited,
          ),
        ),
      );
    });
  });

  group('browser sign-in', () {
    test(
      'returns the identity provider address and the cookie to send back',
      () async {
        final s = await make().startOpenId(
          redirectUri: 'tippani://oauth/abs',
          state: 'st',
          challenge: 'ch',
        );
        expect(s.authorizeUrl.host, 'au.example');
        expect(s.authorizeUrl.queryParameters['state'], 'st');
        // Only the name=value pairs go back, never the attributes.
        expect(s.cookie, 'auth_cb=abc123; other=1');
      },
    );

    test('an address missing from ABS\'s list is forbidden', () async {
      abs.allowedRedirects = ['audiobookshelf://oauth'];
      await expectLater(
        make().startOpenId(
          redirectUri: 'tippani://oauth/abs',
          state: 's',
          challenge: 'c',
        ),
        throwsA(
          isA<AbsException>().having(
            (e) => e.failure,
            'failure',
            AbsFailure.forbidden,
          ),
        ),
      );
    });

    test('the code, verifier and cookie finish the sign-in', () async {
      final c = make();
      final t = await c.finishOpenId(
        code: 'good-code',
        state: 'st',
        verifier: 'v',
        cookie: 'auth_cb=abc123',
      );
      expect(t.access, 'access-1');
      expect(saved, hasLength(1));
    });

    test('a wrong code is refused', () async {
      await expectLater(
        make().finishOpenId(
          code: 'bad',
          state: 's',
          verifier: 'v',
          cookie: 'auth_cb=1',
        ),
        throwsA(isA<AbsException>()),
      );
    });
  });

  group('refreshing', () {
    test(
      'an expired access token is refreshed once and the call repeated',
      () async {
        final c = await signedIn();
        abs.expireAccess = true;
        final libs = await c.libraries();
        expect(libs.map((l) => l.name), ['My Books', 'Podcasts']);
        expect(c.tokens!.access, 'access-2');
        expect(saved.map((t) => t.refresh), ['refresh-1', 'refresh-2']);
      },
    );

    test('calls made together share one refresh', () async {
      final c = await signedIn();
      abs.expireAccess = true;
      // One of these three is refused; the others may race it. A second refresh with the spent token
      // would sign the user out, so exactly one must happen.
      await Future.wait([c.libraries(), c.libraries(), c.libraries()]);
      expect(abs.calls.where((x) => x == 'POST /auth/refresh'), hasLength(1));
      expect(c.signedIn, isTrue);
    });

    test('a spent refresh token signs the client out', () async {
      final c = make(
        tokens: const AbsTokens(
          access: 'old',
          refresh: 'old-refresh',
          userId: 'u',
          username: 'test',
        ),
      );
      await expectLater(
        c.libraries(),
        throwsA(
          isA<AbsException>().having(
            (e) => e.failure,
            'failure',
            AbsFailure.unauthorised,
          ),
        ),
      );
      expect(c.signedIn, isFalse);
    });

    test('a refresh answer without a new refresh token keeps the old one', () {
      final t = AbsTokens.fromJson(
        {
          'user': {'accessToken': 'a2'},
        },
        previous: const AbsTokens(
          access: 'a1',
          refresh: 'r1',
          userId: 'u',
          username: 'test',
        ),
      )!;
      expect(t.refresh, 'r1');
      expect(t.username, 'test');
    });

    test(
      'without tokens a call is unauthorised and never reaches the server',
      () async {
        final c = make();
        await expectLater(c.libraries(), throwsA(isA<AbsException>()));
        expect(abs.calls, isEmpty);
      },
    );
  });

  group('library and book', () {
    test('lists books with the fields a card needs', () async {
      final c = await signedIn();
      final page = await c.books('lib-1');
      expect(page.total, 143);
      final b = page.books.single;
      expect(b.title, 'Sapiens');
      expect(b.author, 'Yuval Noah Harari');
      expect(b.narrator, 'Derek Perkins');
      expect(b.asin, 'B00ICN066A');
      expect(b.isbn, isEmpty, reason: 'a null ISBN becomes empty, not "null"');
      expect(b.numChapters, 2);
    });

    test('a book has chapters and tracks', () async {
      final c = await signedIn();
      final d = await c.book('li-1');
      expect(d.chapters.map((x) => x.title), ['One', 'Two']);
      expect(d.chapters.last.start, 600.5);
      expect(d.tracks.single.mimeType, 'audio/mp4');
    });

    test('me carries progress and bookmarks', () async {
      final c = await signedIn();
      final me = await c.me();
      expect(me.progress.single.currentTime, 30.5);
      expect(me.bookmarks, isEmpty);
    });

    test('streams need a bearer header, not a token in the address', () async {
      final c = await signedIn();
      expect(c.streamHeaders(), {'Authorization': 'Bearer access-1'});
      expect(
        c.streamUri('/api/items/li-1/file/1').toString(),
        'https://abs.example/api/items/li-1/file/1',
      );
    });
  });

  group('playing', () {
    test('opens a session, syncs it and closes it', () async {
      final c = await signedIn();
      final s = await c.openPlaySession('li-1', deviceId: 'dev');
      expect(s.startTime, 30.5);
      expect(s.tracks.single.contentUrl, '/api/items/li-1/file/1');
      await c.syncSession(
        s.id,
        currentTime: 60,
        listened: 30,
        duration: s.duration,
      );
      await c.closeSession(s.id, currentTime: 61, listened: 1);
      expect(abs.sessions[s.id]!['open'], isFalse);
    });

    test('a session that is gone is notFound', () async {
      final c = await signedIn();
      await expectLater(
        c.syncSession('nope', currentTime: 1, listened: 1, duration: 10),
        throwsA(
          isA<AbsException>().having(
            (e) => e.failure,
            'failure',
            AbsFailure.notFound,
          ),
        ),
      );
    });

    test('an offline session is uploaded', () async {
      final c = await signedIn();
      await c.uploadLocalSession({'id': 'x', 'libraryItemId': 'li-1'});
      expect(abs.calls, contains('POST /api/session/local'));
    });
  });

  group('bookmarks', () {
    test('create, list and delete by time', () async {
      final c = await signedIn();
      final b = await c.createBookmark('li-1', time: 30, title: 'here');
      expect(b.time, 30);
      expect((await c.me()).bookmarks.single.title, 'here');
      await c.deleteBookmark('li-1', 30);
      expect((await c.me()).bookmarks, isEmpty);
    });

    test(
      'two bookmarks in the same second are one: ABS keys by time',
      () async {
        final c = await signedIn();
        await c.createBookmark('li-1', time: 30, title: 'first');
        await c.createBookmark('li-1', time: 30, title: 'second');
        final marks = (await c.me()).bookmarks;
        expect(marks, hasLength(1));
        expect(marks.single.title, 'second');
      },
    );
  });
}
