import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../utils/expense_expansion_helper.dart';
import 'user_country_service.dart';

class FinancialDataService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  // Simple in-memory cache
  static final Map<String, dynamic> _cache = {};
  static final Map<String, DateTime> _cacheTimestamps = {};
  static const Duration _cacheExpiry = Duration(minutes: 5);

  // Cache helper methods
  static bool _isCacheValid(String key) {
    final timestamp = _cacheTimestamps[key];
    return timestamp != null &&
        DateTime.now().difference(timestamp) < _cacheExpiry;
  }

  static T? _getCachedData<T>(String key) {
    if (_isCacheValid(key)) {
      return _cache[key] as T?;
    }
    _cache.remove(key);
    _cacheTimestamps.remove(key);
    return null;
  }

  static void _setCachedData(String key, dynamic data) {
    _cache[key] = data;
    _cacheTimestamps[key] = DateTime.now();
  }

  // Method to clear all cache (for testing)
  static void clearAllCache() {
    _cache.clear();
    _cacheTimestamps.clear();
    print('DEBUG: All cache cleared');
  }

  static Future<Map<String, dynamic>> getMonthlyBurnData() async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('User not authenticated');

    final cacheKey = 'monthly_burn_${user.uid}';
    final cachedData = _getCachedData<Map<String, dynamic>>(cacheKey);
    if (cachedData != null) {
      print('DEBUG: Returning cached monthly burn data');
      return cachedData;
    }

    final now = DateTime.now();
    final startOfMonth = DateTime(now.year, now.month, 1);
    final endOfMonth = DateTime(now.year, now.month + 1, 0, 23, 59, 59);

    try {
      final futures = await Future.wait([
        _firestore
            .collection('expenses')
            .where('uid', isEqualTo: user.uid)
            .get(),
        _getBudgetData(user.uid),
        _getRevenueForRange(user.uid, null, null),
        _firestore
            .collection('members')
            .where('uid', isEqualTo: user.uid)
            .get(),
      ]);

      final allExpensesSnapshot = futures[0] as QuerySnapshot;
      final budgetComparison = futures[1] as Map<String, dynamic>;
      final allRevenue = futures[2] as List<QueryDocumentSnapshot>;
      final teamMembersSnapshot = futures[3] as QuerySnapshot;

      // Map Firestore docs to dynamic maps, adding doc.id as 'id'
      final allExpensesMapped = allExpensesSnapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return {...data, 'id': doc.id};
      }).toList();

      // Expand recurring/subscription templates dynamically
      final expandedExpenses = ExpenseExpansionHelper.expandExpenses(
        allExpensesMapped,
        maxDate: endOfMonth,
        allowFuture: true,
      );

      // Filter in Dart
      final currentMonthExpenses = expandedExpenses.where((data) {
        final dateVal = data['Date'] ?? data['date'];
        DateTime? dt;
        if (dateVal is Timestamp) {
          dt = dateVal.toDate();
        } else if (dateVal is DateTime) {
          dt = dateVal;
        }
        final isFunding = data['isFunding'] == true;
        return !isFunding &&
            dt != null &&
            dt.isAfter(startOfMonth.subtract(const Duration(seconds: 1))) &&
            dt.isBefore(endOfMonth.add(const Duration(seconds: 1)));
      }).toList();

      final currentMonthRevenue = allRevenue
          .where((doc) {
            final date =
                (doc.data() as Map<String, dynamic>)['Date'] as Timestamp?;
            return date != null &&
                date.toDate().isAfter(
                  startOfMonth.subtract(const Duration(seconds: 1)),
                ) &&
                date.toDate().isBefore(
                  endOfMonth.add(const Duration(seconds: 1)),
                );
          })
          .fold(
            0.0,
            (total, doc) =>
                total +
                (double.tryParse(
                      (doc.data() as Map<String, dynamic>)['Amount']
                              ?.toString() ??
                          '0',
                    ) ??
                    0),
          );

      final trendData = _calculateSixMonthTrend(
        expandedExpenses,
        teamMembersSnapshot.docs,
      );

      double totalExpenses = 0;
      double salariesTotal = 0;
      Map<String, double> categoryTotals = {};
      Map<String, double> vendorTotals = {};

      for (final data in currentMonthExpenses) {
        final amount = double.tryParse(data['Amount']?.toString() ?? '0') ?? 0;
        String category = data['Category']?.toString() ?? 'Other';
        if (category.toLowerCase() == 'salary') category = 'salaries';
        final vendor = data['Vendor']?.toString() ?? 'Unknown';

        totalExpenses += amount;
        categoryTotals[category] = (categoryTotals[category] ?? 0) + amount;
        vendorTotals[vendor] = (vendorTotals[vendor] ?? 0) + amount;
      }

      for (var doc in teamMembersSnapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        salariesTotal +=
            double.tryParse(
              (data['salary'] ?? data['Salary'])?.toString() ?? '0',
            ) ??
            0;
      }

      final result = {
        'grossBurn': totalExpenses,
        'netBurn': totalExpenses - currentMonthRevenue,
        'revenue': currentMonthRevenue,
        'categoryBreakdown': categoryTotals,
        'vendorBreakdown': vendorTotals,
        'teamCosts': salariesTotal,
        'trendData': trendData,
        'budgetComparison': budgetComparison,
        'totalExpenses': totalExpenses,
        'month': now.month,
        'year': now.year,
      };

      _setCachedData(cacheKey, result);
      return result;
    } catch (e) {
      throw Exception('Failed to fetch financial data: $e');
    }
  }

  // Fetches all revenue docs without date filter (filter in Dart to avoid composite index)
  static Future<List<QueryDocumentSnapshot>> _getRevenueForRange(
    String uid,
    DateTime? start,
    DateTime? end,
  ) async {
    try {
      final revenueSnapshot = await _firestore
          .collection('revenue')
          .where('uid', isEqualTo: uid)
          .get();
      return revenueSnapshot.docs;
    } catch (e) {
      return [];
    }
  }

  // Compute 6-month trend synchronously from already-fetched maps (no extra Firestore calls)
  static List<Map<String, dynamic>> _calculateSixMonthTrend(
    List<Map<String, dynamic>> allExpenses,
    List<QueryDocumentSnapshot> teamMemberDocs,
  ) {
    final now = DateTime.now();
    final trendData = <Map<String, dynamic>>[];

    for (int i = 5; i >= 0; i--) {
      final monthStart = DateTime(now.year, now.month - i, 1);
      final monthEnd = DateTime(now.year, now.month - i + 1, 1);

      double expensesTotal = 0;
      for (var data in allExpenses) {
        if (data['isFunding'] == true) continue;
        final dateVal = data['Date'] ?? data['date'];
        DateTime? date;
        if (dateVal is Timestamp) {
          date = dateVal.toDate();
        } else if (dateVal is DateTime) {
          date = dateVal;
        }
        if (date == null) continue;
        if (date.isAfter(monthStart.subtract(const Duration(seconds: 1))) &&
            date.isBefore(monthEnd)) {
          expensesTotal +=
              double.tryParse(data['Amount']?.toString() ?? '0') ?? 0;
        }
      }

      trendData.add({
        'month': _getMonthAbbreviation(monthStart.month),
        'amount': expensesTotal,
        'isCurrentMonth': i == 0,
      });
    }

    return trendData;
  }

  static Future<Map<String, dynamic>> _getBudgetData(String uid) async {
    try {
      // Fetch all teams for the user
      final teamsSnapshot = await _firestore
          .collection('teams')
          .where('uid', isEqualTo: uid)
          .get();

      if (teamsSnapshot.docs.isEmpty) {
        print('DEBUG: No teams found, returning empty budget');
        return {};
      }

      // Aggregate budget data by team
      Map<String, dynamic> budgetData = {};
      double totalBudget = 0.0;

      for (var doc in teamsSnapshot.docs) {
        final teamData = doc.data();
        final teamName = teamData['teamName'] as String? ?? 'Unknown Team';
        final rawBudget = teamData['monthlyBudget'];
        final monthlyBudget = rawBudget is double
            ? rawBudget
            : rawBudget is int
            ? rawBudget.toDouble()
            : double.tryParse(rawBudget?.toString() ?? '0') ?? 0.0;

        if (monthlyBudget > 0) {
          budgetData[teamName] = monthlyBudget;
          totalBudget += monthlyBudget;
        }

        print('DEBUG: Team $teamName has budget: $monthlyBudget');
      }

      // Add total
      budgetData['Total'] = totalBudget;

      print('DEBUG: Final budget data: $budgetData');
      return budgetData;
    } catch (e) {
      print('DEBUG: Error fetching team budget data: $e');
      return {};
    }
  }

  static String _getMonthAbbreviation(int month) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return months[month - 1];
  }

  static Future<Map<String, dynamic>> getUnifiedTeamCostData() async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('User not authenticated');

    final cacheKey = 'unified_team_cost_${user.uid}';
    final cachedData = _getCachedData<Map<String, dynamic>>(cacheKey);
    if (cachedData != null) {
      return cachedData;
    }

    try {
      // Get all teams for the user
      final teamsSnapshot = await _firestore
          .collection('teams')
          .where('uid', isEqualTo: user.uid)
          .get();

      if (teamsSnapshot.docs.isEmpty) {
        final emptyResult = {'teamCosts': [], 'totalCost': 0};
        _setCachedData(cacheKey, emptyResult);
        return emptyResult;
      }

      // Get actual spending data and team names in parallel
      final futures = await Future.wait([
        getActualSpendingPerTeam(),
        Future.wait(
          teamsSnapshot.docs.map((doc) async {
            final teamData = doc.data();
            return {
              'id': doc.id,
              'name': teamData['teamName']?.toString() ?? 'Unknown Team',
              'budget': teamData['monthlyBudget'] ?? 0.0,
            };
          }),
        ),
      ]);

      final actualSpending = futures[0] as Map<String, double>;
      final teamsData = futures[1] as List<Map<String, dynamic>>;

      Map<String, double> teamCosts = {};
      double totalCost = 0;

      // Use actual spending for each team, fallback to 0 if no spending
      for (var team in teamsData) {
        final teamName = team['name'] as String;
        final spending = actualSpending[teamName] ?? 0.0;
        teamCosts[teamName] = spending;
        totalCost += spending;
      }

      // Convert to list format for display
      final teamCostList = <Map<String, dynamic>>[];
      for (var entry in teamCosts.entries) {
        teamCostList.add({
          'name': entry.key,
          'cost': entry.value, // Return raw numeric value
          'pct': totalCost > 0 ? (entry.value / totalCost) : 0.0,
        });
      }

      // Ensure percentages add up to 1.0 by normalizing
      if (totalCost > 0 && teamCostList.isNotEmpty) {
        final calculatedTotal = teamCostList.fold<double>(
          0.0,
          (sum, team) => sum + (team['pct'] as double),
        );

        // Normalize if there are floating point precision issues
        if ((calculatedTotal - 1.0).abs() > 0.001) {
          for (var team in teamCostList) {
            team['pct'] = (team['pct'] as double) / calculatedTotal;
          }
        }
      }

      // Sort by cost (highest first)
      teamCostList.sort(
        (a, b) => (b['pct'] as double).compareTo(a['pct'] as double),
      );

      final result = {'teamCosts': teamCostList, 'totalCost': totalCost};
      _setCachedData(cacheKey, result);
      return result;
    } catch (e) {
      throw Exception('Failed to fetch unified team cost data: $e');
    }
  }

  static Future<Map<String, dynamic>> getTeamCostDistribution() async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('User not authenticated');

    // Get user's main currency country code
    final countryCode = await UserCountryService.getUserCountryCode();
    final cacheKey = 'team_cost_${user.uid}_$countryCode';
    final cachedData = _getCachedData<Map<String, dynamic>>(cacheKey);
    if (cachedData != null) {
      return cachedData;
    }

    try {
      // Get all teams for the user
      final teamsSnapshot = await _firestore
          .collection('teams')
          .where('uid', isEqualTo: user.uid)
          .get();

      if (teamsSnapshot.docs.isEmpty) {
        final emptyResult = {'teamCosts': [], 'totalCost': 0};
        _setCachedData(cacheKey, emptyResult);
        return emptyResult;
      }

      // Get all members in parallel for better performance
      final memberFutures = teamsSnapshot.docs.map((teamDoc) async {
        final membersSnapshot = await _firestore
            .collection('members')
            .where('teamId', isEqualTo: teamDoc.id)
            .get();

        final teamData = teamDoc.data();
        final teamName = teamData['teamName']?.toString() ?? 'Unknown Team';

        double teamCost = 0;
        for (var memberDoc in membersSnapshot.docs) {
          final memberData = memberDoc.data();
          final cost =
              double.tryParse(memberData['monthlyCost']?.toString() ?? '0') ??
              0;
          final status = memberData['status']?.toString() ?? 'Active';

          if (status == 'Active') {
            teamCost += cost;
          }
        }

        return {'name': teamName, 'cost': teamCost};
      }).toList();

      final teamResults = await Future.wait(memberFutures);

      Map<String, double> departmentCosts = {};
      double totalCost = 0;

      for (var result in teamResults) {
        departmentCosts[result['name'] as String] = result['cost'] as double;
        totalCost += result['cost'] as double;
      }

      // Convert to list format for display
      final teamCostList = <Map<String, dynamic>>[];
      for (var entry in departmentCosts.entries) {
        teamCostList.add({
          'name': entry.key,
          'cost': entry.value, // Return raw numeric value
          'pct': totalCost > 0 ? (entry.value / totalCost) : 0.0,
        });
      }

      // Ensure percentages add up to 1.0 by normalizing
      if (totalCost > 0 && teamCostList.isNotEmpty) {
        final calculatedTotal = teamCostList.fold<double>(
          0.0,
          (sum, team) => sum + (team['pct'] as double),
        );

        // Normalize if there are floating point precision issues
        if ((calculatedTotal - 1.0).abs() > 0.001) {
          for (var team in teamCostList) {
            team['pct'] = (team['pct'] as double) / calculatedTotal;
          }
        }
      }

      // Sort by cost (highest first)
      teamCostList.sort(
        (a, b) => (b['pct'] as double).compareTo(a['pct'] as double),
      );

      final result = {'teamCosts': teamCostList, 'totalCost': totalCost};
      _setCachedData(cacheKey, result);
      return result;
    } catch (e) {
      throw Exception('Failed to fetch team cost data: $e');
    }
  }

  static Future<List<Map<String, dynamic>>> getRawTeamsData() async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('User not authenticated');

    final cacheKey = 'raw_teams_${user.uid}';
    final cachedData = _getCachedData<List<Map<String, dynamic>>>(cacheKey);
    if (cachedData != null) {
      return cachedData;
    }

    try {
      final teamsSnapshot = await _firestore
          .collection('teams')
          .where('uid', isEqualTo: user.uid)
          .get();

      final result = teamsSnapshot.docs.map((doc) => doc.data()).toList();
      _setCachedData(cacheKey, result);
      return result;
    } catch (e) {
      throw Exception('Failed to fetch teams data: $e');
    }
  }

  static Future<Map<String, double>> getActualSpendingPerTeam() async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('User not authenticated');

    final cacheKey = 'team_spending_${user.uid}';
    final cachedData = _getCachedData<Map<String, double>>(cacheKey);
    if (cachedData != null) {
      return cachedData;
    }

    try {
      final now = DateTime.now();
      final startOfMonth = DateTime(now.year, now.month, 1);
      final endOfMonth = DateTime(now.year, now.month + 1, 0, 23, 59, 59);

      // Run queries in parallel — also fetch members to include salaries per team
      final futures = await Future.wait([
        // Get all expenses for current month
        _firestore
            .collection('expenses')
            .where('uid', isEqualTo: user.uid)
            .get(),
        // Get all teams to map team names
        _firestore.collection('teams').where('uid', isEqualTo: user.uid).get(),
        // Get all members to aggregate salaries per team
        _firestore
            .collection('members')
            .where('uid', isEqualTo: user.uid)
            .get(),
      ]);

      final expensesSnapshot = futures[0] as QuerySnapshot;
      final teamsSnapshot = futures[1] as QuerySnapshot;
      final membersSnapshot = futures[2] as QuerySnapshot;

      Map<String, String> teamIdToName = {};
      for (var teamDoc in teamsSnapshot.docs) {
        final teamData = teamDoc.data() as Map<String, dynamic>?;
        if (teamData == null) continue;

        final teamName = teamData['teamName']?.toString() ?? 'Unknown';
        teamIdToName[teamDoc.id] = teamName;
      }

      Map<String, double> teamSpending = {};

      // --- Add member salaries per team ---
      for (var memberDoc in membersSnapshot.docs) {
        final memberData = memberDoc.data() as Map<String, dynamic>;
        final status = memberData['status']?.toString() ?? 'Active';
        if (status != 'Active') continue; // only count active members

        final memberTeamId = memberData['teamId']?.toString();
        if (memberTeamId == null) continue;

        final teamName = teamIdToName[memberTeamId];
        if (teamName == null) continue; // team not owned by this user

        final salary =
            double.tryParse(
              (memberData['salary'] ?? memberData['Salary'])?.toString() ?? '0',
            ) ??
            0.0;
        teamSpending[teamName] = (teamSpending[teamName] ?? 0) + salary;
      }

      final mappedExpenses = expensesSnapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return {...data, 'id': doc.id};
      }).toList();

      final expandedExpenses = ExpenseExpansionHelper.expandExpenses(
        mappedExpenses,
        maxDate: endOfMonth,
        allowFuture: true,
      );

      // Process expenses and categorize by team
      for (final data in expandedExpenses) {
        if (data['isFunding'] == true) continue;

        // Skip salary-category expense docs — member salaries are already
        // included above from the members collection, preventing double-counting.
        final category = data['Category']?.toString() ?? 'Other';
        if (category.toLowerCase() == 'salary' ||
            category.toLowerCase() == 'salaries') {
          continue;
        }

        final amount = double.tryParse(data['Amount']?.toString() ?? '0') ?? 0;
        final teamName = data['TeamName']?.toString();

        final dateVal = data['Date'] ?? data['date'];
        DateTime? expenseDate;
        if (dateVal is Timestamp) {
          expenseDate = dateVal.toDate();
        } else if (dateVal is DateTime) {
          expenseDate = dateVal;
        }

        // Filter by date in code
        if (expenseDate != null &&
            expenseDate.isAfter(
              startOfMonth.subtract(const Duration(days: 1)),
            ) &&
            expenseDate.isBefore(endOfMonth.add(const Duration(days: 1)))) {
          // Use TeamName field if it exists, otherwise map by category
          String assignedTeam;
          if (teamName != null && teamName.isNotEmpty) {
            assignedTeam = teamName;
          } else {
            assignedTeam = _mapCategoryToTeam(category, teamIdToName);
          }

          teamSpending[assignedTeam] =
              (teamSpending[assignedTeam] ?? 0) + amount;
        }
      }

      _setCachedData(cacheKey, teamSpending);
      return teamSpending;
    } catch (e) {
      throw Exception('Failed to fetch team spending: $e');
    }
  }

  static Future<Map<String, double>> getCategoryBudgets(String uid) async {
    try {
      // Get user document to find companyId
      final userDoc = await _firestore.collection('users').doc(uid).get();

      final companyId = userDoc.data()?['companyId'];
      if (companyId == null) {
        print('DEBUG: No companyId found for user $uid');
        return {};
      }

      // Get company document with budgets
      final companyDoc = await _firestore
          .collection('companies')
          .doc(companyId)
          .get();

      if (!companyDoc.exists) {
        print('DEBUG: No company document found for companyId $companyId');
        return {};
      }

      final companyData = companyDoc.data() as Map<String, dynamic>;
      final budgets = companyData['budgets'] as Map<String, dynamic>? ?? {};

      Map<String, double> categoryBudgets = {};

      // Convert all budget values to double
      for (var entry in budgets.entries) {
        final amount = double.tryParse(entry.value.toString()) ?? 0.0;
        if (amount > 0) {
          categoryBudgets[entry.key] = amount;
          print('DEBUG: Category budget - ${entry.key}: $amount');
        }
      }

      print('DEBUG: Final category budgets: $categoryBudgets');
      return categoryBudgets;
    } catch (e) {
      print('DEBUG: Error fetching category budgets: $e');
      return {};
    }
  }

  static Future<Map<String, double>> getActualSpendingPerCategory(
    String uid,
  ) async {
    try {
      final now = DateTime.now();
      final startOfMonth = DateTime(now.year, now.month, 1);
      final endOfMonth = DateTime(now.year, now.month + 1, 0, 23, 59, 59);

      print(
        'DEBUG: Fetching category spending from ${startOfMonth.toIso8601String()} to ${endOfMonth.toIso8601String()}',
      );

      // Get all expenses for user to cover recurring ones starting in the past
      final expensesSnapshot = await _firestore
          .collection('expenses')
          .where('uid', isEqualTo: uid)
          .get();

      final mappedExpenses = expensesSnapshot.docs.map((doc) {
        final data = doc.data();
        return {...data, 'id': doc.id};
      }).toList();

      final expandedExpenses = ExpenseExpansionHelper.expandExpenses(
        mappedExpenses,
        maxDate: endOfMonth,
        allowFuture: true,
      );

      Map<String, double> categorySpending = {};

      for (final data in expandedExpenses) {
        if (data.isEmpty) continue;
        if (data['isFunding'] == true) continue;

        final dateVal = data['Date'] ?? data['date'];
        DateTime? dt;
        if (dateVal is Timestamp) {
          dt = dateVal.toDate();
        } else if (dateVal is DateTime) {
          dt = dateVal;
        }

        // Filter by date range in Dart
        if (dt == null || dt.isBefore(startOfMonth) || dt.isAfter(endOfMonth)) {
          continue;
        }

        final amount = double.tryParse(data['Amount']?.toString() ?? '0') ?? 0;
        String category =
            data['Category']?.toString().toLowerCase().trim() ?? 'other';

        // Map transaction categories to budget category keys
        if (category == 'salary') {
          category = 'salaries'; // Map to match budget key
        }

        if (amount > 0) {
          categorySpending[category] =
              (categorySpending[category] ?? 0) + amount;
          print('DEBUG: Category spending - $category: $amount');
        }
      }

      print('DEBUG: Final category spending: $categorySpending');
      return categorySpending;
    } catch (e) {
      print('DEBUG: Error fetching category spending: $e');
      return {};
    }
  }

  static Future<Map<String, Map<String, dynamic>>> getBudgetVarianceAnalysis(
    String uid,
  ) async {
    try {
      // Get budgets and actual spending in parallel
      final futures = await Future.wait([
        getCategoryBudgets(uid),
        getActualSpendingPerCategory(uid),
      ]);

      final categoryBudgets = futures[0];
      final actualSpending = futures[1];

      Map<String, Map<String, dynamic>> varianceAnalysis = {};

      // Process all categories that have either budget or spending
      final allCategories = {...categoryBudgets.keys, ...actualSpending.keys};

      for (String category in allCategories) {
        final budget = categoryBudgets[category] ?? 0.0;
        final actual = actualSpending[category] ?? 0.0;
        final variance = budget - actual;
        final variancePercentage = budget > 0
            ? ((variance / budget) * 100)
            : 0.0;

        varianceAnalysis[category] = {
          'budget': budget,
          'actual': actual,
          'variance': variance,
          'variancePercentage': variancePercentage,
          'isOverBudget': variance < 0,
          'hasBudget': budget > 0,
        };

        print(
          'DEBUG: Category $category - Budget: $budget, Actual: $actual, Variance: $variance (${variancePercentage.toStringAsFixed(1)}%)',
        );
      }

      return varianceAnalysis;
    } catch (e) {
      print('DEBUG: Error calculating budget variance: $e');
      return {};
    }
  }

  static String _mapCategoryToTeam(
    String category,
    Map<String, String> teamIdToName,
  ) {
    // Normalize category for easier matching
    final normalizedCategory = category.toLowerCase();

    // Try exact team name matches first
    for (String teamName in teamIdToName.values) {
      if (normalizedCategory.contains(teamName.toLowerCase()) ||
          teamName.toLowerCase().contains(normalizedCategory)) {
        return teamName;
      }
    }

    // Comprehensive mapping for website development categories
    if (normalizedCategory.contains('website') ||
        normalizedCategory.contains('developer') ||
        normalizedCategory.contains('development') ||
        normalizedCategory.contains('web') ||
        normalizedCategory.contains('programming') ||
        normalizedCategory.contains('coding') ||
        normalizedCategory.contains('frontend') ||
        normalizedCategory.contains('backend') ||
        normalizedCategory.contains('fullstack') ||
        normalizedCategory.contains('ui') ||
        normalizedCategory.contains('ux') ||
        normalizedCategory.contains('design')) {
      return teamIdToName.values.firstWhere(
        (name) =>
            name.toLowerCase().contains('website') ||
            name.toLowerCase().contains('developer'),
        orElse: () => 'Website Developer',
      );
    } else if (normalizedCategory.contains('marketing') ||
        normalizedCategory.contains('advertising') ||
        normalizedCategory.contains('promotion') ||
        normalizedCategory.contains('social media')) {
      return teamIdToName.values.firstWhere(
        (name) => name.toLowerCase().contains('marketing'),
        orElse: () => 'Marketing',
      );
    } else if (normalizedCategory.contains('testing') ||
        normalizedCategory.contains('qa') ||
        normalizedCategory.contains('quality') ||
        normalizedCategory.contains('test') ||
        normalizedCategory.contains('testing') ||
        normalizedCategory.contains('automation') ||
        normalizedCategory.contains('manual testing')) {
      return teamIdToName.values.firstWhere(
        (name) =>
            name.toLowerCase().contains('testing') ||
            name.toLowerCase().contains('qa'),
        orElse: () => 'Testing',
      );
    } else if (normalizedCategory.contains('engineering') ||
        normalizedCategory.contains('tech') ||
        normalizedCategory.contains('salaries') ||
        normalizedCategory.contains('salary') ||
        normalizedCategory.contains('infrastructure') ||
        normalizedCategory.contains('servers')) {
      // Check if we have a Website Developer team first
      if (teamIdToName.values.any(
        (name) =>
            name.toLowerCase().contains('website') ||
            name.toLowerCase().contains('developer'),
      )) {
        return teamIdToName.values.firstWhere(
          (name) =>
              name.toLowerCase().contains('website') ||
              name.toLowerCase().contains('developer'),
          orElse: () => 'Engineering',
        );
      }
      return teamIdToName.values.firstWhere(
        (name) =>
            name.toLowerCase().contains('engineering') ||
            name.toLowerCase().contains('tech'),
        orElse: () => 'Engineering',
      );
    } else if (normalizedCategory.contains('operations') ||
        normalizedCategory.contains('office') ||
        normalizedCategory.contains('admin')) {
      return teamIdToName.values.firstWhere(
        (name) =>
            name.toLowerCase().contains('operations') ||
            name.toLowerCase().contains('admin'),
        orElse: () => 'Operations',
      );
    }

    // Fallback to a general "Other" or first available team if no specific match
    return teamIdToName.isNotEmpty ? teamIdToName.values.first : 'Other';
  }
}
