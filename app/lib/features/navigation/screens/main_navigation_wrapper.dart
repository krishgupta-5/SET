import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:startup_expense_tracker/widgets/custom_bottom_nav.dart';
import 'package:startup_expense_tracker/features/home/screens/home_screen.dart';
import 'package:startup_expense_tracker/features/team/screens/team_screen.dart';
import 'package:startup_expense_tracker/features/expenses/screens/expenses_screen.dart';
import 'package:startup_expense_tracker/features/ai/screens/ai_screen_ui.dart';
import 'package:startup_expense_tracker/features/settings/screens/settings_screen.dart';
import 'package:startup_expense_tracker/theme/app_theme.dart';

class MainNavigationWrapper extends StatefulWidget {
  const MainNavigationWrapper({super.key});

  @override
  State<MainNavigationWrapper> createState() => _MainNavigationWrapperState();
}

class _MainNavigationWrapperState extends State<MainNavigationWrapper> {
  int _selectedIndex = 0;

  void _onTabSelected(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.appBackground,
      extendBodyBehindAppBar: true,
      resizeToAvoidBottomInset: false,
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: context.isDarkMode
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
        child: IndexedStack(
          // ✅ Keeps all screens alive
          index: _selectedIndex,
          children: [
            HomeScreen(onNavigateToTab: _onTabSelected),
            const TeamScreen(),
            const ExpensesScreen(),
            const AiScreen(),
            const SettingsScreen(),
          ],
        ),
      ),
      bottomNavigationBar: ModernNavBar(
        onTabSelected: _onTabSelected,
        selectedIndex: _selectedIndex,
      ),
    );
  }
}
