import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tippani/listen/abs/abs_models.dart';
import 'package:tippani/listen/abs/abs_token_store.dart';

const _connection = AbsConnection(
  serverUrl: 'https://abs.example',
  tokens: AbsTokens(access: 'a', refresh: 'r', userId: 'u1', username: 'test'),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the vault channel', () {
    const channel = MethodChannel('io.github.aaronified.tippani/abs_vault');
    final held = <String, String>{};
    final calls = <MethodCall>[];

    setUp(() {
      held.clear();
      calls.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            final account = (call.arguments as Map)['account'] as String;
            switch (call.method) {
              case 'get':
                return held[account];
              case 'put':
                held[account] = (call.arguments as Map)['value'] as String;
                return true;
              case 'clear':
                held.remove(account);
                return true;
            }
            return null;
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('writes the connection as text and reads it back', () async {
      final store = VaultAbsTokenStore(channel);
      await store.write('acct-1', _connection);
      final back = await store.read('acct-1');
      expect(back!.serverUrl, 'https://abs.example');
      expect(back.tokens.access, 'a');
      expect(back.tokens.refresh, 'r');
      expect(back.tokens.username, 'test');
    });

    test('an account with nothing kept reads as null', () async {
      expect(await VaultAbsTokenStore(channel).read('nobody'), isNull);
    });

    test('accounts do not see each other', () async {
      final store = VaultAbsTokenStore(channel);
      await store.write('acct-1', _connection);
      expect(await store.read('acct-2'), isNull);
      await store.clear('acct-1');
      expect(await store.read('acct-1'), isNull);
    });

    test('the account id is the only thing named besides the value', () async {
      await VaultAbsTokenStore(channel).write('acct-1', _connection);
      expect((calls.single.arguments as Map).keys, {'account', 'value'});
    });

    test(
      'an entry that is not a connection reads as null, not an error',
      () async {
        held['acct-1'] = 'not json';
        expect(await VaultAbsTokenStore(channel).read('acct-1'), isNull);
        held['acct-1'] = '{"serverUrl":"https://x"}';
        expect(await VaultAbsTokenStore(channel).read('acct-1'), isNull);
      },
    );
  });

  test('the memory store keeps accounts apart', () async {
    final store = MemoryAbsTokenStore();
    await store.write('a', _connection);
    expect(await store.read('b'), isNull);
    expect((await store.read('a'))!.tokens.userId, 'u1');
    await store.clear('a');
    expect(await store.read('a'), isNull);
  });

  test('new tokens replace the old and keep the address', () {
    const fresh = AbsTokens(
      access: 'a2',
      refresh: 'r2',
      userId: 'u1',
      username: 'test',
    );
    final c = _connection.withTokens(fresh);
    expect(c.serverUrl, 'https://abs.example');
    expect(c.tokens.access, 'a2');
  });
}
