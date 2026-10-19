import 'package:flutter/material.dart';

import '../view_models/dashboard_view_model.dart';
import '../view_models/measurement_view_model.dart';
import 'history_screen.dart';
import 'monitor_screen.dart';
import 'settings_screen.dart';
import 'summary_screen.dart';

/// The signed-in app: four tabs, as in the wireframes.
///
/// This replaces an earlier single scrolling dashboard. One long page put the
/// live level, dose, threshold control and up to 100 history rows in one
/// column, so the control most users touch least (the threshold) sat between
/// the two things they look at most. Tabs give each task its own screen, and a
/// bottom navigation bar is the Material Design pattern for three to five
/// top-level destinations, which keeps the app consistent with the platform
/// conventions users already know (Nielsen, 1994: consistency and standards).
///
/// An [IndexedStack] keeps every tab alive, so switching tabs keeps each one's
/// scroll position rather than rebuilding it, and leaving Monitor does not
/// interrupt the live display.
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
    // Loaded once here, not per tab, because all four tabs show the same
    // readings and settings.
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
