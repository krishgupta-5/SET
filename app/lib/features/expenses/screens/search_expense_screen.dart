import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:startup_expense_tracker/widgets/rx_ui.dart';
import 'package:flutter/services.dart';
import 'package:startup_expense_tracker/widgets/rx_pickers.dart';
import 'package:hugeicons/hugeicons.dart';
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
    final rx = context.rx;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: context.rxOverlayStyle,
      child: Scaffold(
        backgroundColor: rx.background,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              // --- HEADER & SEARCH ---
              _buildHeader(),
              const SizedBox(height: 14),

              // --- FILTERS ---
              // 1. Year, exact date and sort, as compact pickers.
              SizedBox(
                height: 36,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  children: [
                    _buildDropdownTrigger(
                      label: _selectedYear,
                      onTap: () => _showYearSelector(),
                    ),
                    const SizedBox(width: 8),
                    _buildDropdownTrigger(
                      label: _exactDate != null
                          ? rxFormatDate(_exactDate!)
                          : 'Exact date',
                      leading: HugeIcons.strokeRoundedCalendar03,
                      active: _exactDate != null,
                      onTap: () => _showDatePicker(),
                    ),
                    const SizedBox(width: 8),
                    _buildDropdownTrigger(
                      label: _sortOrder == 'newest' ? "Newest" : "Oldest",
                      leading: HugeIcons.strokeRoundedSorting05,
                      onTap: () => _showSortSelector(),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              // 2. MONTH ROW
              _buildChipRow(
                keys: _months.keys.toList(),
                labelOf: (k) => _months[k]!,
                isSelected: (k) =>
                    _selectedMonthKey.toLowerCase() == k.toLowerCase() &&
                    _exactDate == null,
                onTap: (key) {
                  setState(() {
                    _selectedMonthKey = key;
                    _exactDate =
                        null; // Clear exact date if user clicks a month
                    _lastDocument =
                        null; // Reset pagination when filter changes
                  });
                },
              ),
              const SizedBox(height: 8),

              // 3. CATEGORY ROW
              _buildChipRow(
                keys: _categories.keys.toList(),
                labelOf: (k) => _categories[k]!,
                isSelected: (k) => _selectedCategoryKey == k,
                onTap: (key) {
                  setState(() {
                    _selectedCategoryKey = key;
                    _lastDocument = null; // Reset pagination
                  });
                },
              ),
              const SizedBox(height: 12),
              Container(height: 1, color: rx.hairline),

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

  /// Horizontal row of pill filters. Selection is instant (frequent action).
  Widget _buildChipRow({
    required List<String> keys,
    required String Function(String) labelOf,
    required bool Function(String) isSelected,
    required ValueChanged<String> onTap,
  }) {
    final rx = context.rx;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: keys.length,
        separatorBuilder: (context, index) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final key = keys[index];
          final selected = isSelected(key);
          return Semantics(
            button: true,
            selected: selected,
            child: GestureDetector(
              onTap: () => onTap(key),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected ? rx.inverse : rx.surface,
                  borderRadius: BorderRadius.circular(100),
                  border: Border.all(
                    color: selected || !isDark
                        ? Colors.transparent
                        : rx.hairline,
                  ),
                  boxShadow: selected ? null : rx.cardShadow,
                ),
                child: Text(
                  labelOf(key),
                  style:
                      RxText.label(
                        context,
                        color: selected ? rx.onInverse : rx.textSecondary,
                      ).copyWith(
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w500,
                      ),
                ),
              ),
            ),
          );
        },
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

        return ListView.separated(
          padding: EdgeInsets.fromLTRB(
            20,
            4,
            20,
            MediaQuery.paddingOf(context).bottom + 24,
          ),
          physics: const BouncingScrollPhysics(),
          itemCount: searchFiltered.length,
          separatorBuilder: (context, index) => const RxDivider(indent: 52),
          itemBuilder: (context, index) {
            return _buildTransactionRow(searchFiltered[index]);
          },
        );
      },
    );
  }

  Widget _buildHeader() {
    final rx = context.rx;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const RxTopBar(title: 'Search expenses'),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: Container(
            height: 48,
            padding: const EdgeInsets.only(left: 14, right: 8),
            decoration: BoxDecoration(
              color: rx.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: rx.textPrimary.withValues(alpha: 0.12)),
            ),
            child: Row(
              children: [
                HugeIcon(
                  icon: HugeIcons.strokeRoundedSearch01,
                  color: rx.textSecondary,
                  size: 19,
                  strokeWidth: 1.8,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    onTapOutside: (event) => FocusScope.of(context).unfocus(),
                    style: RxText.body(context),
                    cursorColor: rx.textPrimary,
                    decoration: InputDecoration(
                      hintText: "Search by title",
                      hintStyle: RxText.body(
                        context,
                        color: rx.textTertiary,
                      ).copyWith(fontWeight: FontWeight.w400),
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
                  IconButton(
                    tooltip: 'Clear search',
                    onPressed: () {
                      setState(() {
                        _searchQuery = "";
                        _searchController.clear();
                        _lastDocument = null;
                      });
                    },
                    icon: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: rx.surfaceMuted,
                        shape: BoxShape.circle,
                      ),
                      child: HugeIcon(
                        icon: HugeIcons.strokeRoundedCancel01,
                        color: rx.textPrimary,
                        size: 12,
                        strokeWidth: 2.2,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDropdownTrigger({
    required String label,
    required VoidCallback onTap,
    List<List<dynamic>>? leading,
    bool active = false,
  }) {
    final rx = context.rx;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fg = active ? rx.onInverse : rx.textPrimary;
    return RxPressable(
      onTap: onTap,
      semanticLabel: label,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? rx.inverse : rx.surface,
          borderRadius: BorderRadius.circular(100),
          border: Border.all(
            color: active || !isDark ? Colors.transparent : rx.hairline,
          ),
          boxShadow: active ? null : rx.cardShadow,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (leading != null) ...[
              HugeIcon(icon: leading, color: fg, size: 15, strokeWidth: 1.9),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: RxText.label(
                context,
                color: fg,
              ).copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 4),
            HugeIcon(
              icon: HugeIcons.strokeRoundedArrowDown01,
              color: active ? fg : rx.textSecondary,
              size: 15,
              strokeWidth: 2,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTransactionRow(Map<String, dynamic> data) {
    final rx = context.rx;
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
      dateStr = rxFormatDate((data['Date'] as Timestamp).toDate());
    }

    return RxPressable(
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
      scale: 0.98,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            RxIconTile(
              icon: RxCategory.icon(rawCategory),
              size: 40,
              iconSize: 19,
              background: RxCategory.soft(context, rawCategory),
              foreground: RxCategory.color(context, rawCategory),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: RxText.body(context),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text("$category · $dateStr", style: RxText.caption(context)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                "${isFunding ? '+' : ''}${_isLoadingCountry ? CurrencyFormatter.formatByCountryCompact(amount, '+91') : CurrencyFormatter.formatByCountryCompact(amount, _userCountryCode)}",
                style: RxText.amount(
                  context,
                  color: isFunding ? rx.positive : rx.textPrimary,
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
    final isError =
        message.startsWith('Failed') || message.contains('not logged');
    return Center(
      child: RxEmptyState(
        icon: isError
            ? HugeIcons.strokeRoundedAlert02
            : HugeIcons.strokeRoundedSearchRemove,
        title: isError ? "Couldn't load expenses" : 'Nothing found',
        message: isError ? message : '$message. Try another search or filter.',
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 16),
      ),
    );
  }

  Future<void> _showDatePicker() async {
    final year = int.parse(_selectedYear);
    final date = await showRxDatePicker(
      context,
      initialDate: _exactDate ?? DateTime.now(),
      firstDate: DateTime(year - 2, 1),
      lastDate: DateTime(year + 2, 12, 31),
      title: 'Exact date',
      onClear: _exactDate == null
          ? null
          : () => setState(() => _exactDate = null),
    );
    if (date != null && mounted) {
      setState(() {
        _exactDate = date;
        _selectedYear = date.year.toString();
        _selectedMonthKey = _months.keys.elementAt(date.month); // 1 = Jan, etc.
        _lastDocument = null;
      });
    }
  }

  Future<void> _showYearSelector() async {
    final int currentYear = DateTime.now().year;
    final years = [
      (currentYear + 1).toString(),
      currentYear.toString(),
      (currentYear - 1).toString(),
      (currentYear - 2).toString(),
      (currentYear - 3).toString(),
    ];

    final year = await showRxSelectSheet<String>(
      context,
      title: 'Year',
      selected: _selectedYear,
      options: [for (final y in years) RxOption(y, y)],
    );
    if (year != null && mounted) {
      setState(() {
        _selectedYear = year;
        _exactDate = null;
        _lastDocument = null;
      });
    }
  }

  Future<void> _showSortSelector() async {
    final sortOptions = ['Newest', 'Oldest'];
    final option = await showRxSelectSheet<String>(
      context,
      title: 'Sort order',
      selected: _sortOrder,
      options: [
        for (final o in sortOptions)
          RxOption(
            o.toLowerCase(),
            o,
            icon: o == 'Newest'
                ? HugeIcons.strokeRoundedArrowDown01
                : HugeIcons.strokeRoundedArrowUp01,
          ),
      ],
    );
    if (option != null && mounted) {
      setState(() {
        _sortOrder = option;
        _lastDocument = null;
      });
    }
  }
}
