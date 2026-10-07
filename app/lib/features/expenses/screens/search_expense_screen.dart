import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:startup_expense_tracker/services/user_country_service.dart';
import '../../../utils/data_helpers.dart';
import '../../../utils/expense_expansion_helper.dart';
import '../../../services/currency_formatter.dart';
import '../../../theme/app_theme.dart';
import 'expense_details_screen.dart';

class SearchExpenseScreen extends StatefulWidget {
  const SearchExpenseScreen({super.key});

  @override
  State<SearchExpenseScreen> createState() => _SearchExpenseScreenState();
}

class _SearchExpenseScreenState extends State<SearchExpenseScreen> {
  // 1. CONTROLLERS
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = "";
  String _userCountryCode = '+1'; // Default to USD
  bool _isLoadingCountry = true;

  // 2. FILTER STATE
  late String _selectedYear;
  String _selectedMonthKey = "all";
  String _selectedCategoryKey = "all";
  String _sortOrder = "newest";

  // If this is set, it overrides the Month/Year filter to search for an exact day
  DateTime? _exactDate;

  // 3. CONSTANTS & MAPPINGS
  final Map<String, String> _months = {
    'all': 'All',
    'Jan': 'Jan',
    'Feb': 'Feb',
    'Mar': 'Mar',
    'Apr': 'Apr',
    'May': 'May',
    'Jun': 'Jun',
    'Jul': 'Jul',
    'Aug': 'Aug',
    'Sep': 'Sep',
    'Oct': 'Oct',
    'Nov': 'Nov',
    'Dec': 'Dec',
  };

  final Map<String, String> _categories = {
    'all': 'All',
    'marketing': 'Marketing',
    'infrastructure': 'Infrastructure',
    'office': 'Office',
    'software': 'Software',
    'hardware': 'Hardware',
    'transport': 'Transport',
    'design': 'Design',
    'travel': 'Travel',
    'meals': 'Meals',
    'contractors': 'Contractors',
    'legal': 'Legal',
    'others': 'Others',
  };

  @override
  void initState() {
    super.initState();
    _selectedYear = DateTime.now().year.toString();
    _loadUserCountryCode();
  }

  Future<void> _loadUserCountryCode() async {
    final countryCode = await UserCountryService.getUserCountryCode();
    if (mounted) {
      setState(() {
        _userCountryCode = countryCode;
        _isLoadingCountry = false;
      });
    }
  }

  // Pagination cursor (assigned in setState to trigger rebuilds on filter change)
  // ignore: unused_field
  DocumentSnapshot? _lastDocument;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.appBackground,
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: context.isDarkMode
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
        child: SafeArea(
          child: Column(
            children: [
              // --- HEADER & SEARCH ---
              _buildHeader(),
              const SizedBox(height: 24),

              // --- FILTERS ---
              // 1. TOP ROW: Year/Date Controls + Sort
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  children: [
                    // Year Dropdown
                    _buildDropdownTrigger(
                      label: "Year: $_selectedYear",
                      onTap: () => _showYearSelector(),
                    ),
                    const SizedBox(width: 8),

                    // Date Picker Button
                    GestureDetector(
                      onTap: () => _showDatePicker(),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: _exactDate != null
                              ? context.textPrimary
                              : context.cardBackground,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _exactDate != null
                                ? context.textPrimary
                                : context.borderColor,
                          ),
                        ),
                        child: Icon(
                          Icons.calendar_month,
                          color: _exactDate != null
                              ? context.appBackground
                              : context.textSecondary,
                          size: 20,
                        ),
                      ),
                    ),

                    const SizedBox(width: 8),

                    // Sort Dropdown
                    _buildDropdownTrigger(
                      label: _sortOrder == 'newest' ? "Newest" : "Oldest",
                      onTap: () => _showSortSelector(),
                      icon: Icons.sort,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // 2. MONTH ROW
              SizedBox(
                height: 36,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  itemCount: _months.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final key = _months.keys.elementAt(index);
                    final label = _months[key]!;
                    final isSelected =
                        _selectedMonthKey.toLowerCase() == key.toLowerCase() &&
                        _exactDate == null;

                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          _selectedMonthKey = key;
                          _exactDate =
                              null; // Clear exact date if user clicks a month
                          _lastDocument =
                              null; // Reset pagination when filter changes
                        });
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? context.textPrimary
                              : context.cardBackground,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected
                                ? context.textPrimary
                                : context.borderColor,
                          ),
                        ),
                        child: Text(
                          label,
                          style: TextStyle(
                            fontFamily: 'Satoshi',
                            color: isSelected
                                ? context.appBackground
                                : context.textSecondary,
                            fontSize: 12,
                            fontWeight: isSelected
                                ? FontWeight.w600
                                : FontWeight.w500,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),

              // 3. CATEGORY ROW
              SizedBox(
                height: 36,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  itemCount: _categories.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final key = _categories.keys.elementAt(index);
                    final label = _categories[key]!;
                    final isSelected = _selectedCategoryKey == key;

                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          _selectedCategoryKey = key;
                          _lastDocument = null; // Reset pagination
                        });
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? context.textPrimary
                              : context.cardBackground,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected
                                ? context.textPrimary
                                : context.borderColor,
                          ),
                        ),
                        child: Text(
                          label,
                          style: TextStyle(
                            fontFamily: 'Satoshi',
                            color: isSelected
                                ? context.appBackground
                                : context.textSecondary,
                            fontSize: 12,
                            fontWeight: isSelected
                                ? FontWeight.w600
                                : FontWeight.w500,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),

              const SizedBox(height: 24),
              Divider(color: context.borderColor, height: 1),

              // --- RESULTS LIST (FIREBASE STREAM) ---
              Expanded(
                child: GestureDetector(
                  onTap: () => FocusScope.of(context).unfocus(),
                  child: _buildFirebaseResults(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFirebaseResults() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return _buildEmptyState('User not logged in');

    // Calculate the upper bound date for expansion.
    // Always capped at DateTime.now() so recurring expenses never generate
    // phantom future occurrences that appear as "unwanted entries" in the list.
    final now = DateTime.now();
    DateTime maxDateLimit = now;
    if (_exactDate != null) {
      final endOfDay = _exactDate!
          .add(const Duration(days: 1))
          .subtract(const Duration(milliseconds: 1));
      maxDateLimit = endOfDay.isBefore(now) ? endOfDay : now;
    } else if (_selectedMonthKey != 'all') {
      final monthMap = {
        'Jan': 1,
        'Feb': 2,
        'Mar': 3,
        'Apr': 4,
        'May': 5,
        'Jun': 6,
        'Jul': 7,
        'Aug': 8,
        'Sep': 9,
        'Oct': 10,
        'Nov': 11,
        'Dec': 12,
      };
      final month = monthMap[_selectedMonthKey];
      if (month != null) {
        final year = int.tryParse(_selectedYear) ?? now.year;
        final endOfMonth = DateTime(
          year,
          month + 1,
          1,
        ).subtract(const Duration(milliseconds: 1));
        maxDateLimit = endOfMonth.isBefore(now) ? endOfMonth : now;
      }
    } else {
      final year = int.tryParse(_selectedYear) ?? now.year;
      final endOfYear = DateTime(
        year + 1,
        1,
        1,
      ).subtract(const Duration(milliseconds: 1));
      maxDateLimit = endOfYear.isBefore(now) ? endOfYear : now;
    }

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('expenses')
          .where('uid', isEqualTo: user.uid)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: context.textPrimary,
            ),
          );
        }

        if (snapshot.hasError) {
          return _buildEmptyState('Failed to load data');
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return _buildEmptyState(_getNotFoundMessage());
        }

        // Map documents
        final mappedExpenses = snapshot.data!.docs.map((doc) {
          final data = doc.data() as Map<String, dynamic>;
          return {...data, 'id': doc.id};
        }).toList();

        // Expand recurring expenses up to the filter's end date limit (capped at today).
        // allowFuture is intentionally omitted (defaults to false) so the helper's
        // DateTime.now() guard is always enforced — no phantom future rows.
        final expanded = ExpenseExpansionHelper.expandExpenses(
          mappedExpenses,
          maxDate: maxDateLimit,
        );

        // Filter by Date inside Dart
        final filteredByDate = expanded.where((data) {
          final dateVal = data['Date'] ?? data['date'];
          DateTime? dt;
          if (dateVal is Timestamp) {
            dt = dateVal.toDate();
          } else if (dateVal is DateTime) {
            dt = dateVal;
          }
          if (dt == null) return false;

          // Apply Date Filters
          if (_exactDate != null) {
            final startOfDay = DateTime(
              _exactDate!.year,
              _exactDate!.month,
              _exactDate!.day,
            );
            final endOfDay = startOfDay
                .add(const Duration(days: 1))
                .subtract(const Duration(milliseconds: 1));
            return dt.isAfter(
                  startOfDay.subtract(const Duration(seconds: 1)),
                ) &&
                dt.isBefore(endOfDay);
          } else if (_selectedMonthKey != 'all') {
            final monthMap = {
              'Jan': 1,
              'Feb': 2,
              'Mar': 3,
              'Apr': 4,
              'May': 5,
              'Jun': 6,
              'Jul': 7,
              'Aug': 8,
              'Sep': 9,
              'Oct': 10,
              'Nov': 11,
              'Dec': 12,
            };
            final month = monthMap[_selectedMonthKey];
            if (month != null) {
              final year = int.tryParse(_selectedYear) ?? DateTime.now().year;
              final startOfMonth = DateTime(year, month);
              final endOfMonth = DateTime(year, month + 1, 0, 23, 59, 59);
              return dt.isAfter(
                    startOfMonth.subtract(const Duration(seconds: 1)),
                  ) &&
                  dt.isBefore(endOfMonth.add(const Duration(seconds: 1)));
            }
          } else {
            final year = int.tryParse(_selectedYear) ?? DateTime.now().year;
            final startOfYear = DateTime(year, 1, 1);
            final endOfYear = DateTime(year, 12, 31, 23, 59, 59);
            return dt.isAfter(
                  startOfYear.subtract(const Duration(seconds: 1)),
                ) &&
                dt.isBefore(endOfYear.add(const Duration(seconds: 1)));
          }
          return true;
        }).toList();

        // Client-side case-insensitive title search filter
        final searchFiltered = _searchQuery.isEmpty
            ? filteredByDate
            : filteredByDate.where((data) {
                final title = (data['Title'] ?? '').toString().toLowerCase();
                return title.contains(_searchQuery.toLowerCase());
              }).toList();

        if (searchFiltered.isEmpty) {
          return _buildEmptyState(_getNotFoundMessage());
        }

        // Sort based on _sortOrder
        searchFiltered.sort((a, b) {
          final aDateVal = a['Date'] ?? a['date'];
          final bDateVal = b['Date'] ?? b['date'];
          DateTime? aDt;
          if (aDateVal is Timestamp) {
            aDt = aDateVal.toDate();
          } else if (aDateVal is DateTime) {
            aDt = aDateVal;
          }
          DateTime? bDt;
          if (bDateVal is Timestamp) {
            bDt = bDateVal.toDate();
          } else if (bDateVal is DateTime) {
            bDt = bDateVal;
          }

          if (aDt == null && bDt == null) return 0;
          if (aDt == null) return 1;
          if (bDt == null) return -1;

          if (_sortOrder == 'newest') {
            return bDt.compareTo(aDt);
          } else {
            return aDt.compareTo(bDt);
          }
        });

        return ListView.builder(
          padding: const EdgeInsets.all(24),
          physics: const BouncingScrollPhysics(),
          itemCount: searchFiltered.length,
          itemBuilder: (context, index) {
            return _buildTransactionRow(searchFiltered[index]);
          },
        );
      },
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 8,
                    horizontal: 4,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.arrow_back,
                        color: context.textSecondary,
                        size: 16,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        "Back",
                        style: TextStyle(
                          fontFamily: 'Satoshi',
                          color: context.textSecondary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 44),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            "Search Expenses",
            style: TextStyle(
              fontFamily: 'Satoshi',
              color: context.textPrimary,
              fontSize: 28,
              fontWeight: FontWeight.w700,
              letterSpacing: -1.0,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: context.isDarkMode
                  ? Colors.white.withValues(alpha: 0.04)
                  : Colors.black.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: context.borderColor),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.search_rounded,
                  color: context.textSecondary,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    onTapOutside: (event) => FocusScope.of(context).unfocus(),
                    style: TextStyle(
                      fontFamily: 'Satoshi',
                      color: context.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                    cursorColor: context.textPrimary,
                    decoration: InputDecoration(
                      hintText: "Search title...",
                      hintStyle: TextStyle(
                        fontFamily: 'Satoshi',
                        color: context.textTertiary,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                      border: InputBorder.none,
                      isDense: true,
                    ),
                    onChanged: (val) {
                      setState(() {
                        _searchQuery = val;
                        _lastDocument =
                            null; // Reset pagination when search changes
                      });
                    },
                  ),
                ),
                if (_searchQuery.isNotEmpty)
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _searchQuery = "";
                        _searchController.clear();
                        _lastDocument = null;
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: context.textSecondary.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.close_rounded,
                        color: context.textPrimary,
                        size: 12,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDropdownTrigger({
    required String label,
    required VoidCallback onTap,
    IconData icon = Icons.keyboard_arrow_down,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: context.cardBackground,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: context.borderColor),
          boxShadow: context.cardShadow,
        ),
        child: Row(
          children: [
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Satoshi',
                color: context.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 6),
            Icon(icon, color: context.textSecondary, size: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildTransactionRow(Map<String, dynamic> data) {
    final id = data['id'] as String? ?? '';

    final title = data['Title'] ?? 'Unnamed Expense';
    final amount = DataHelpers.safeParseDouble(data['Amount']);
    final isFunding = data['isFunding'] == true;

    final rawCategory = data['Category']?.toString() ?? 'General';
    final category = rawCategory.isNotEmpty
        ? '${rawCategory[0].toUpperCase()}${rawCategory.substring(1)}'
        : 'General';

    String dateStr = '';
    if (data['Date'] is Timestamp) {
      final date = (data['Date'] as Timestamp).toDate();
      final day = date.day.toString().padLeft(2, '0');
      final month = date.month.toString().padLeft(2, '0');
      dateStr = "$day/$month/${date.year}";
    }

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) =>
                ExpenseDetailsScreen(expenseId: id, expenseData: data),
          ),
        ).then((_) {
          // Trigger rebuild to refresh data if it was edited
          setState(() {
            _lastDocument = null;
          });
        });
      },
      child: Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: context.cardBackground,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: context.borderColor),
                boxShadow: context.cardShadow,
              ),
              child: Icon(
                Icons.receipt_long_outlined,
                color: context.textSecondary,
                size: 20,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontFamily: 'Satoshi',
                      color: context.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    "$category • $dateStr",
                    style: TextStyle(
                      fontFamily: 'Satoshi',
                      color: context.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // FIXED: FITTED BOX FOR LARGE NUMBERS
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                "${isFunding ? '+' : ''}${_isLoadingCountry ? CurrencyFormatter.formatByCountryCompact(amount, '+91') : CurrencyFormatter.formatByCountryCompact(amount, _userCountryCode)}",
                style: TextStyle(
                  fontFamily: 'Satoshi',
                  color: isFunding
                      ? const Color(0xFF30D158)
                      : context.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  fontFeatures: [const FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getNotFoundMessage() {
    // Check if any filters are active
    bool hasSearchFilter = _searchQuery.isNotEmpty;
    bool hasDateFilter = _exactDate != null || _selectedMonthKey != 'all';
    bool hasCategoryFilter = _selectedCategoryKey != 'all';

    if (hasSearchFilter && hasDateFilter && hasCategoryFilter) {
      return "No expenses found matching \"$_searchQuery\" for ${_selectedMonthKey == 'all' ? _selectedYear : _selectedMonthKey} in ${_getCategoryDisplayName()}";
    } else if (hasSearchFilter && hasDateFilter) {
      return "No expenses found matching \"$_searchQuery\" for ${_selectedMonthKey == 'all' ? _selectedYear : _selectedMonthKey}";
    } else if (hasSearchFilter && hasCategoryFilter) {
      return "No expenses found matching \"$_searchQuery\" in ${_getCategoryDisplayName()}";
    } else if (hasDateFilter && hasCategoryFilter) {
      return "No expenses found for ${_selectedMonthKey == 'all' ? _selectedYear : _selectedMonthKey} in ${_getCategoryDisplayName()}";
    } else if (hasSearchFilter) {
      return "No expenses found matching \"$_searchQuery\"";
    } else if (hasDateFilter) {
      return "No expenses found for ${_selectedMonthKey == 'all' ? _selectedYear : _selectedMonthKey}";
    } else if (hasCategoryFilter) {
      return "No expenses found in ${_getCategoryDisplayName()}";
    } else {
      return "No expenses found";
    }
  }

  String _getCategoryDisplayName() {
    return _categories[_selectedCategoryKey] ?? 'Unknown';
  }

  Widget _buildEmptyState(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
        child: Text(
          message,
          style: TextStyle(
            fontFamily: 'Satoshi',
            color: context.textSecondary,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  void _showDatePicker() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: context.appBackground,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: context.borderColor),
          ),
          child: Container(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "Select Date",
                      style: TextStyle(
                        fontFamily: 'Satoshi',
                        color: context.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(Icons.close, color: context.textSecondary),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                ShadCalendar(
                  selected: _exactDate ?? DateTime.now(),
                  fromMonth: DateTime(int.parse(_selectedYear) - 2, 1),
                  toMonth: DateTime(int.parse(_selectedYear) + 2, 12),
                  onChanged: (DateTime? date) {
                    if (date != null) {
                      setState(() {
                        _exactDate = date;
                        _selectedYear = date.year.toString();
                        _selectedMonthKey = _months.keys.elementAt(
                          date.month,
                        ); // 1 = Jan, etc.
                        _lastDocument = null;
                      });
                      Navigator.pop(context);
                    }
                  },
                ),
                if (_exactDate != null) ...[
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: TextButton(
                      onPressed: () {
                        setState(() => _exactDate = null);
                        Navigator.pop(context);
                      },
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFFFF453A),
                        backgroundColor: const Color(
                          0xFFFF453A,
                        ).withValues(alpha: 0.1),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        "Clear Exact Date",
                        style: TextStyle(
                          fontFamily: 'Satoshi',
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  void _showYearSelector() {
    final int currentYear = DateTime.now().year;
    final years = [
      (currentYear + 1).toString(),
      currentYear.toString(),
      (currentYear - 1).toString(),
      (currentYear - 2).toString(),
      (currentYear - 3).toString(),
    ];

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: context.appBackground,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: context.borderColor),
          ),
          child: Container(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "Select Year",
                      style: TextStyle(
                        fontFamily: 'Satoshi',
                        color: context.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(Icons.close, color: context.textSecondary),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                ...years.map(
                  (year) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          _selectedYear = year;
                          _exactDate = null;
                          _lastDocument = null;
                        });
                        Navigator.pop(context);
                      },
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          vertical: 14,
                          horizontal: 16,
                        ),
                        decoration: BoxDecoration(
                          color: _selectedYear == year
                              ? context.textPrimary
                              : context.cardBackground,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _selectedYear == year
                                ? context.textPrimary
                                : context.borderColor,
                          ),
                        ),
                        child: Text(
                          year,
                          style: TextStyle(
                            fontFamily: 'Satoshi',
                            color: _selectedYear == year
                                ? context.appBackground
                                : context.textSecondary,
                            fontSize: 14,
                            fontWeight: _selectedYear == year
                                ? FontWeight.w600
                                : FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showSortSelector() {
    final sortOptions = ['Newest', 'Oldest'];
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: context.appBackground,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: context.borderColor),
          ),
          child: Container(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "Sort Order",
                      style: TextStyle(
                        fontFamily: 'Satoshi',
                        color: context.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(Icons.close, color: context.textSecondary),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                ...sortOptions.map(
                  (option) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          _sortOrder = option.toLowerCase();
                          _lastDocument = null;
                        });
                        Navigator.pop(context);
                      },
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          vertical: 14,
                          horizontal: 16,
                        ),
                        decoration: BoxDecoration(
                          color: _sortOrder == option.toLowerCase()
                              ? context.textPrimary
                              : context.cardBackground,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _sortOrder == option.toLowerCase()
                                ? context.textPrimary
                                : context.borderColor,
                          ),
                        ),
                        child: Text(
                          option,
                          style: TextStyle(
                            fontFamily: 'Satoshi',
                            color: _sortOrder == option.toLowerCase()
                                ? context.appBackground
                                : context.textSecondary,
                            fontSize: 14,
                            fontWeight: _sortOrder == option.toLowerCase()
                                ? FontWeight.w600
                                : FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
