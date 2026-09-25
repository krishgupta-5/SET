import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../theme/app_theme.dart';

class CategorySettingsScreen extends StatefulWidget {
  const CategorySettingsScreen({super.key});

  @override
  State<CategorySettingsScreen> createState() => _CategorySettingsScreenState();
}

class _CategorySettingsScreenState extends State<CategorySettingsScreen> {
  final TextEditingController _categoryController = TextEditingController();
  List<String> _categories = [];
  bool _isLoading = true;

  final List<String> _allCategories = [
    "Marketing",
    "Infrastructure",
    "Office Rent",
    "Legal",
    "Software",
    "Hardware",
    "Design",
    "Travel",
    "Meals",
    "Contractors",
    "Transport",
    "Salary",
    "Others",
  ];

  @override
  void initState() {
    super.initState();
    _fetchCategories();
  }

  Future<void> _fetchCategories() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final companyId = userDoc.data()?['companyId'] as String?;
      if (companyId == null) return;

      final companyDoc = await FirebaseFirestore.instance
          .collection('companies')
          .doc(companyId)
          .get();
      if (companyDoc.exists) {
        final data = companyDoc.data()!;
        final cats =
            (data['Categories'] as List<dynamic>?)?.cast<String>() ?? [];
        if (mounted) {
          setState(() {
            _categories = cats;
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      debugPrint("Error fetching categories: $e");
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _addCategory() async {
    final newCategory = _categoryController.text.trim();
    if (newCategory.isEmpty) return;

    if (_categories
        .map((e) => e.toLowerCase())
        .contains(newCategory.toLowerCase())) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Category already exists',
            style: TextStyle(color: context.textPrimary),
          ),
          backgroundColor: context.cardBackground,
        ),
      );
      return;
    }

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final companyId = userDoc.data()?['companyId'] as String?;
      if (companyId == null) return;

      final updatedCategories = List<String>.from(_categories)
        ..add(newCategory);

      await FirebaseFirestore.instance
          .collection('companies')
          .doc(companyId)
          .update({'Categories': updatedCategories});

      if (!mounted) return;
      setState(() {
        _categories = updatedCategories;
        _categoryController.clear();
      });
      FocusScope.of(context).unfocus();
    } catch (e) {
      debugPrint("Error adding category: $e");
    }
  }

  Future<void> _addPredefinedCategory(String category) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final companyId = userDoc.data()?['companyId'] as String?;
      if (companyId == null) return;

      final updatedCategories = List<String>.from(_categories)..add(category);

      await FirebaseFirestore.instance
          .collection('companies')
          .doc(companyId)
          .update({'Categories': updatedCategories});

      if (!mounted) return;
      setState(() {
        _categories = updatedCategories;
      });
    } catch (e) {
      debugPrint("Error adding predefined category: $e");
    }
  }

  Future<void> _removeCategory(String category) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final companyId = userDoc.data()?['companyId'] as String?;
      if (companyId == null) return;

      final updatedCategories = List<String>.from(_categories)
        ..remove(category);

      await FirebaseFirestore.instance
          .collection('companies')
          .doc(companyId)
          .update({'Categories': updatedCategories});

      if (!mounted) return;
      setState(() {
        _categories = updatedCategories;
      });
    } catch (e) {
      debugPrint("Error removing category: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final btnBg = context.isDarkMode ? Colors.white : Colors.black;
    final btnText = context.isDarkMode ? Colors.black : Colors.white;

    return Scaffold(
      backgroundColor: context.appBackground,
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: context.isDarkMode
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              Expanded(
                child: _isLoading
                    ? Center(
                        child: CircularProgressIndicator(
                          color: context.iconSecondary,
                        ),
                      )
                    : SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 16,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 16),
                            Text(
                              "Expense Categories",
                              style: TextStyle(
                                fontFamily: 'Satoshi',
                                color: context.textPrimary,
                                fontSize: 28,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -1.0,
                              ),
                            ),
                            const SizedBox(height: 32),
                            Text(
                              "Manage the categories available when adding expenses.",
                              style: TextStyle(
                                fontFamily: 'Satoshi',
                                color: context.textSecondary,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 24),

                            // Add New Category Input
                            Row(
                              children: [
                                Expanded(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: context.cardBackground,
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: context.borderColor,
                                      ),
                                      boxShadow: context.cardShadow,
                                    ),
                                    child: TextField(
                                      controller: _categoryController,
                                      style: TextStyle(
                                        fontFamily: 'Satoshi',
                                        color: context.textPrimary,
                                        fontSize: 15,
                                      ),
                                      cursorColor: context.textPrimary,
                                      decoration: InputDecoration(
                                        hintText: "New Category Name",
                                        hintStyle: TextStyle(
                                          fontFamily: 'Satoshi',
                                          color: context.textTertiary,
                                          fontSize: 15,
                                        ),
                                        border: InputBorder.none,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                GestureDetector(
                                  onTap: _addCategory,
                                  child: Container(
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: btnBg,
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: Icon(
                                      Icons.add,
                                      color: btnText,
                                      size: 20,
                                    ),
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 32),

                            if (_allCategories
                                .where(
                                  (c) => !_categories
                                      .map((e) => e.toLowerCase())
                                      .contains(c.toLowerCase()),
                                )
                                .isNotEmpty) ...[
                              Text(
                                "AVAILABLE CATEGORIES",
                                style: TextStyle(
                                  fontFamily: 'Satoshi',
                                  color: context.textTertiary,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.5,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Wrap(
                                spacing: 12,
                                runSpacing: 12,
                                children: _allCategories
                                    .where(
                                      (c) => !_categories
                                          .map((e) => e.toLowerCase())
                                          .contains(c.toLowerCase()),
                                    )
                                    .map((cat) {
                                      return GestureDetector(
                                        onTap: () =>
                                            _addPredefinedCategory(cat),
                                        child: AnimatedContainer(
                                          duration: const Duration(
                                            milliseconds: 200,
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 10,
                                          ),
                                          decoration: BoxDecoration(
                                            color: context.cardBackground,
                                            borderRadius: BorderRadius.circular(
                                              20,
                                            ),
                                            border: Border.all(
                                              color: context.borderColor,
                                            ),
                                            boxShadow: context.cardShadow,
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                Icons.add,
                                                color: context.textPrimary,
                                                size: 14,
                                              ),
                                              const SizedBox(width: 6),
                                              Text(
                                                cat,
                                                style: TextStyle(
                                                  fontFamily: 'Satoshi',
                                                  color: context.textPrimary,
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    })
                                    .toList(),
                              ),
                              const SizedBox(height: 32),
                            ],

                            Text(
                              "YOUR CATEGORIES",
                              style: TextStyle(
                                fontFamily: 'Satoshi',
                                color: context.textTertiary,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.5,
                              ),
                            ),
                            const SizedBox(height: 16),

                            ..._categories.map(
                              (cat) => Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 20,
                                    vertical: 16,
                                  ),
                                  decoration: BoxDecoration(
                                    color: context.cardBackground,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: context.borderColor,
                                    ),
                                    boxShadow: context.cardShadow,
                                  ),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.category_outlined,
                                            color: context.iconSecondary,
                                            size: 18,
                                          ),
                                          const SizedBox(width: 12),
                                          Text(
                                            cat,
                                            style: TextStyle(
                                              fontFamily: 'Satoshi',
                                              color: context.textPrimary,
                                              fontSize: 15,
                                            ),
                                          ),
                                        ],
                                      ),
                                      GestureDetector(
                                        onTap: () => _removeCategory(cat),
                                        child: Icon(
                                          Icons.close,
                                          color: context.iconSecondary,
                                          size: 18,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
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
    );
  }
}
