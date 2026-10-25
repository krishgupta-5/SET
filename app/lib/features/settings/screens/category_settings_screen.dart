import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import '../../../widgets/rx_form.dart';
import '../../../widgets/rx_motion.dart';
import '../../../widgets/rx_ui.dart';

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
      showRxToast(context, 'Category already exists', isError: true);
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
    final rx = context.rx;
    final lower = _categories.map((e) => e.toLowerCase()).toSet();
    final suggestions = _allCategories
        .where((c) => !lower.contains(c.toLowerCase()))
        .toList();

    return Scaffold(
      backgroundColor: rx.background,
      body: AnnotatedRegion(
        value: context.rxOverlayStyle,
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              const RxTopBar(title: 'Categories'),
              Expanded(
                child: _isLoading
                    ? ListView(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                        children: const [
                          RxSkeleton(height: 52, radius: 14),
                          SizedBox(height: 28),
                          RxSkeleton(height: 260, radius: 22),
                        ],
                      )
                    : ListView(
                        physics: const BouncingScrollPhysics(),
                        padding: EdgeInsets.fromLTRB(
                          20,
                          12,
                          20,
                          MediaQuery.paddingOf(context).bottom + 32,
                        ),
                        children: [
                          RxReveal.index(
                            0,
                            child: RxTextInput(
                              controller: _categoryController,
                              label: 'Add a category',
                              hint: 'e.g. Research',
                              icon: HugeIcons.strokeRoundedTag01,
                              textCapitalization: TextCapitalization.words,
                              textInputAction: TextInputAction.done,
                              onSubmitted: (_) => _addCategory(),
                              suffix: RxPressable(
                                onTap: _addCategory,
                                semanticLabel: 'Add category',
                                child: Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: rx.inverse,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  alignment: Alignment.center,
                                  child: HugeIcon(
                                    icon: HugeIcons.strokeRoundedAdd01,
                                    color: rx.onInverse,
                                    size: 18,
                                    strokeWidth: 2,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          if (suggestions.isNotEmpty) ...[
                            const SizedBox(height: 24),
                            RxReveal.index(
                              1,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const RxSectionHeader(title: 'Suggestions'),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      for (final cat in suggestions)
                                        _suggestionChip(cat),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: 28),
                          RxReveal.index(
                            2,
                            child: Column(
                              children: [
                                RxSectionHeader(
                                  title:
                                      'Your categories · ${_categories.length}',
                                ),
                                if (_categories.isEmpty)
                                  const RxCard(
                                    child: RxEmptyState(
                                      icon: HugeIcons.strokeRoundedTag01,
                                      title: 'No categories yet',
                                      message:
                                          'Add one above or tap a suggestion',
                                    ),
                                  )
                                else
                                  RxCard(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 2,
                                    ),
                                    child: Column(
                                      children: [
                                        for (
                                          var i = 0;
                                          i < _categories.length;
                                          i++
                                        ) ...[
                                          if (i > 0)
                                            const RxDivider(indent: 50),
                                          _categoryRow(_categories[i]),
                                        ],
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _suggestionChip(String cat) {
    final rx = context.rx;
    return RxPressable(
      onTap: () => _addPredefinedCategory(cat),
      semanticLabel: 'Add $cat',
      child: Container(
        height: 36,
        padding: const EdgeInsets.only(left: 10, right: 14),
        decoration: BoxDecoration(
          color: rx.surface,
          borderRadius: BorderRadius.circular(100),
          border: Border.all(color: rx.hairline),
          boxShadow: rx.cardShadow,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            HugeIcon(
              icon: HugeIcons.strokeRoundedAdd01,
              color: rx.textSecondary,
              size: 15,
              strokeWidth: 2,
            ),
            const SizedBox(width: 6),
            Text(
              cat,
              style: RxText.label(
                context,
                color: rx.textPrimary,
              ).copyWith(fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }

  Widget _categoryRow(String cat) {
    final rx = context.rx;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          RxIconTile(
            icon: RxCategory.icon(cat),
            size: 36,
            iconSize: 18,
            background: RxCategory.soft(context, cat),
            foreground: RxCategory.color(context, cat),
          ),
          const SizedBox(width: 14),
          Expanded(child: Text(cat, style: RxText.body(context))),
          RxPressable(
            onTap: () => _removeCategory(cat),
            semanticLabel: 'Remove $cat',
            child: SizedBox(
              width: 40,
              height: 40,
              child: Center(
                child: HugeIcon(
                  icon: HugeIcons.strokeRoundedCancel01,
                  color: rx.textTertiary,
                  size: 18,
                  strokeWidth: 1.9,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
