import 'package:flutter/material.dart';
import 'package:startup_expense_tracker/theme/app_theme.dart';

class AiInsightCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String insightType;
  final Color insightColor;
  final List<InsightItem> items;

  const AiInsightCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.insightType,
    required this.insightColor,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: context.cardBackground,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.borderColor),
        boxShadow: context.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome, color: context.textPrimary, size: 16),
              const SizedBox(width: 12),
              Text(
                insightType,
                style: TextStyle(
                  fontFamily: 'Satoshi',
                  color: insightColor,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...items.map((item) => _buildInsightItem(item, context)),
        ],
      ),
    );
  }

  Widget _buildInsightItem(InsightItem item, BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item.title,
                  style: TextStyle(
                    fontFamily: 'Satoshi',
                    color: context.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (item.savings != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: item.color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(100),
                    border: Border.all(
                      color: item.color.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Text(
                    item.savings!,
                    style: TextStyle(
                      fontFamily: 'Satoshi',
                      color: item.color,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            item.description,
            style: TextStyle(
              fontFamily: 'Satoshi',
              color: context.textSecondary,
              fontSize: 12,
              height: 1.4,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}

class InsightItem {
  final String title;
  final String description;
  final String? savings;
  final Color color;

  InsightItem({
    required this.title,
    required this.description,
    this.savings,
    required this.color,
  });
}
