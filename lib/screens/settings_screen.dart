import 'package:flutter/material.dart';

import '../services/settings_store.dart';

/// Settings. Currently just the theme, which is feature 10's manual toggle.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({required this.settings, super.key});

  final SettingsStore settings;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListenableBuilder(
        listenable: settings,
        builder: (context, _) => ListView(
          children: <Widget>[
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 20, 16, 8),
              child: Text(
                'APPEARANCE',
                style: TextStyle(fontSize: 11, letterSpacing: 0.8),
              ),
            ),
            // A checked list rather than RadioListTile: the radio-group API
            // has churned across recent Flutter versions and this needs no
            // state of its own.
            for (final mode in ThemeMode.values)
              ListTile(
                title: Text(settings.labelFor(mode)),
                trailing: mode == settings.themeMode
                    ? const Icon(Icons.check_rounded)
                    : null,
                onTap: () => settings.setThemeMode(mode),
              ),
          ],
        ),
      ),
    );
  }
}
