import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'app_controller.dart';
import 'harness/app_log.dart';
import 'harness/harness.dart';
import 'settings/settings_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final settings = SettingsStore(prefs, SecureTokenVault());
  final controller = AppController(settings, log: appLog);
  final harness = Harness.open(settings, controller);
  await harness.start();
  runApp(TippaniApp(controller: controller, harness: harness));
}
