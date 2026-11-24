import 'package:flutter/material.dart';
import 'package:knowit/l10n/app_localizations.dart';
import 'package:knowit/screens/ai_generate_screen.dart';
import 'package:knowit/screens/collections_screen.dart';
import 'package:knowit/screens/search_screen.dart';
import 'package:knowit/screens/settings_screen.dart';
import 'package:knowit/tabs/stats_tab.dart';
import 'package:knowit/theme/app_icons.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: const [
          CollectionsScreen(),
          SearchScreen(),
          AiGenerateScreen(),
          _StatisticsPage(),
          SettingsScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (index) => setState(() => _index = index),
        destinations: [
          NavigationDestination(
            icon: const Icon(AppIcons.collections),
            selectedIcon: const Icon(AppIcons.collectionsSelected),
            label: l10n.collections,
          ),
          NavigationDestination(
            icon: const Icon(AppIcons.browse),
            selectedIcon: const Icon(AppIcons.browseSelected),
            label: l10n.browse,
          ),
          NavigationDestination(
            icon: const Icon(AppIcons.create),
            selectedIcon: const Icon(AppIcons.createSelected),
            label: l10n.create,
          ),
          NavigationDestination(
            icon: const Icon(AppIcons.statistics),
            selectedIcon: const Icon(AppIcons.statisticsSelected),
            label: l10n.statistics,
          ),
          NavigationDestination(
            icon: const Icon(AppIcons.settings),
            selectedIcon: const Icon(AppIcons.settingsSelected),
            label: l10n.settings,
          ),
        ],
      ),
    );
  }
}

class _StatisticsPage extends StatelessWidget {
  const _StatisticsPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.statistics)),
      body: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16),
        child: StatsTab(),
      ),
    );
  }
}
