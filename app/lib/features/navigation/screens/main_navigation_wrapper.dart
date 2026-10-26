import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:startup_expense_tracker/widgets/custom_bottom_nav.dart';
import 'package:startup_expense_tracker/features/home/screens/home_screen.dart';
import 'package:startup_expense_tracker/features/team/screens/team_screen.dart';
import 'package:startup_expense_tracker/features/expenses/screens/expenses_screen.dart';
import 'package:startup_expense_tracker/features/expenses/screens/add_expense_screen.dart';
import 'package:startup_expense_tracker/features/expenses/screens/scan_expense_screen.dart';
import 'package:startup_expense_tracker/features/ai/screens/ai_screen_ui.dart';
import 'package:startup_expense_tracker/features/settings/screens/settings_screen.dart';
import 'package:startup_expense_tracker/theme/app_theme.dart';

class MainNavigationWrapper extends StatefulWidget {
  const MainNavigationWrapper({super.key});

  @override
  State<MainNavigationWrapper> createState() => _MainNavigationWrapperState();
}

class _MainNavigationWrapperState extends State<MainNavigationWrapper> {
  // Page indices inside the IndexedStack. Kept in the original order because
  // HomeScreen calls onNavigateToTab(4) from its avatar to open Settings.
  static const int _home = 0;
  static const int _team = 1;
  static const int _expenses = 2;
  static const int _ai = 3;
  static const int _settings = 4;

  // Tab bar order (left to right, the add button sits between 1 and 2),
  // mapped to the page each tab shows.
  static const List<int> _tabPages = [_home, _expenses, _team, _ai];
  static const List<RxTabItem> _tabs = [
    RxTabItem(icon: HugeIcons.strokeRoundedHome01, label: 'Home'),
    RxTabItem(icon: HugeIcons.strokeRoundedInvoice01, label: 'Expenses'),
    RxTabItem(icon: HugeIcons.strokeRoundedUserGroup, label: 'Team'),
    RxTabItem(icon: HugeIcons.strokeRoundedSparkles, label: 'AI CFO'),
  ];

  int _page = _home;

  // Bumped after the add flow returns so Home and Expenses reload their data.
  int _dataEpoch = 0;

  // Bumped every time a tab is opened, so its charts replay their entrance.
  int _visit = 0;

  void _openPage(int page) {
    if (page != _page) {
      setState(() {
        _page = page;
        _visit++;
      });
    }
  }

  Future<void> _onAddPressed() async {
    final action = await showAddExpenseSheet(context);
    if (action == null || !mounted) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => action == AddExpenseAction.scan
            ? const ScanExpenseScreen()
            : const AddExpenseScreen(),
      ),
    );
    if (mounted) setState(() => _dataEpoch++);
  }

  @override
  Widget build(BuildContext context) {
    final rx = context.rx;

    return PopScope(
      // System back from any tab other than Home returns to Home first.
      canPop: _page == _home,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _openPage(_home);
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        // Transparent nav bar so the page shows behind the gesture bar too.
        value: context.rxOverlayStyle,
        child: Scaffold(
          backgroundColor: rx.background,
          resizeToAvoidBottomInset: false,
          // The bar floats over the pages so content scrolls under the glass.
          // Pages keep their own bottom spacing (see RxTabBar.reservedHeight).
          body: Stack(
            children: [
              Positioned.fill(
                child: IndexedStack(
                  index: _page,
                  children: [
                    HomeScreen(
                      key: ValueKey('home-$_dataEpoch'),
                      onNavigateToTab: _openPage,
                      visit: _page == _home ? _visit : null,
                    ),
                    TeamScreen(visit: _page == _team ? _visit : null),
                    ExpensesScreen(
                      key: ValueKey('expenses-$_dataEpoch'),
                      visit: _page == _expenses ? _visit : null,
                    ),
                    AiScreen(
                      onAddExpense: _onAddPressed,
                      onOpenTeam: () => _openPage(_team),
                      // Re-check an empty AI screen after adding data or
                      // reopening the tab (e.g. after adding a team member).
                      refreshToken:
                          _page == _ai ? '$_dataEpoch-$_visit' : null,
                    ),
                    const SettingsScreen(),
                  ],
                ),
              ),
              // Clean strip under the bar, same on every tab.
              const Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: RxNavBackdrop(),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: RxTabBar(
                  items: _tabs,
                  // Settings has no tab, so nothing is highlighted there.
                  selectedIndex: _page == _settings
                      ? -1
                      : _tabPages.indexOf(_page),
                  onTabSelected: (i) => _openPage(_tabPages[i]),
                  onAddPressed: _onAddPressed,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
