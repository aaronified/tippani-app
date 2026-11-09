import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart' show getDatabasesPath;

import 'app.dart';
import 'app_controller.dart';
import 'harness/app_log.dart';
import 'harness/harness.dart';
import 'library/library_store.dart';
import 'settings/settings_store.dart';
import 'theme/tabler_licence.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final settings = SettingsStore(prefs, SecureTokenVault());
  final controller = AppController(settings, log: appLog);
  // THE PHONE'S OWN LIBRARY, opened before anything else needs it: it is what lets the app work with no
  // server, and a server only ever adds to it.
  final library = await SqliteLibraryStore.open(
    '${await getDatabasesPath()}/library.db',
  );
  final harness = Harness.open(settings, controller, library: library);
  await harness.start();
  registerTablerLicence();
  runApp(TippaniApp(controller: controller, harness: harness));
}
