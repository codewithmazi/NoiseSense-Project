import 'package:flutter/material.dart';

import '../view_models/dashboard_view_model.dart';
import '../view_models/measurement_view_model.dart';
import 'history_screen.dart';
import 'monitor_screen.dart';
import 'settings_screen.dart';
import 'summary_screen.dart';

/// The signed-in app: four tabs, as in the wireframes.
class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
    required this.dashboard,
    required this.measurement,
    required this.email,
    required this.onSignOut,
  });

  final DashboardViewModel dashboard;
  final MeasurementViewModel measurement;
  final String? email;
  final Future<void> Function() onSignOut;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    // Loaded once here, because all four tabs show the same data.
    widget.dashboard.load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: [
          MonitorScreen(
            dashboard: widget.dashboard,
            measurement: widget.measurement,
          ),
          HistoryScreen(dashboard: widget.dashboard),
          SummaryScreen(dashboard: widget.dashboard),
          SettingsScreen(
            dashboard: widget.dashboard,
            measurement: widget.measurement,
            email: widget.email,
            onSignOut: widget.onSignOut,
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.graphic_eq_outlined),
            selectedIcon: Icon(Icons.graphic_eq),
            label: 'Monitor',
          ),
          NavigationDestination(
            icon: Icon(Icons.history_outlined),
            selectedIcon: Icon(Icons.history),
            label: 'History',
          ),
          NavigationDestination(
            icon: Icon(Icons.insights_outlined),
            selectedIcon: Icon(Icons.insights),
            label: 'Summary',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
