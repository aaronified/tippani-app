import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tippani/app_controller.dart';
import 'package:tippani/people/people_console.dart';
import 'package:tippani/settings/settings_store.dart';

import '../support/fake_server.dart';

/// Choosing the work a character is added to: what the list prints under each title is what the server sends.
void main() {
  test(
    'works are listed with the creator and year the server names them',
    () async {
      SharedPreferences.setMockInitialValues({
        'server_url': 'https://q.example.org',
      });
      final server = FakeServer();
      final c = AppController(
        SettingsStore(
          await SharedPreferences.getInstance(),
          MemoryTokenVault(),
        ),
        clientFactory: server.factory,
      );
      await c.load();
      await c.pair('ABCD2345', 'My phone');
      server.seed('/books', {
        'title': 'Dracula',
        'author': 'Bram Stoker',
        'published_year': 1897,
      }, id: 1);
      server.seed('/movies', {
        'title': 'Nosferatu',
        'director': 'F. W. Murnau',
        'release_year': 1922,
      }, id: 2);
      final works = await PairedPeopleConsole(c).libraryWorks();
      expect(
        [for (final w in works) (w.title, w.creator, w.year)],
        [('Dracula', 'Bram Stoker', 1897), ('Nosferatu', 'F. W. Murnau', 1922)],
      );
    },
  );
}
