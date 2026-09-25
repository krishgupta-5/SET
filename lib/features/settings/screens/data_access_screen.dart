import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../theme/app_theme.dart';

class DataAccessScreen extends StatefulWidget {
  const DataAccessScreen({super.key});

  @override
  State<DataAccessScreen> createState() => _DataAccessScreenState();
}

class _DataAccessScreenState extends State<DataAccessScreen> {
  bool _allowSupportAccess = false;

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: context.appBackground,
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: context.isDarkMode
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(context),
                const SizedBox(height: 16),
                Text(
                  "Data Access Control",
                  style: TextStyle(
                    fontFamily: 'Satoshi',
                    color: context.textPrimary,
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -1.0,
                  ),
                ),
                const SizedBox(height: 32),

                _buildSectionLabel("TEMPORARY ACCESS"),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: context.cardBackground,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: context.borderColor),
                    boxShadow: context.cardShadow,
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0A84FF).withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.support_agent,
                          color: Color(0xFF0A84FF),
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Grant Support Access",
                              style: TextStyle(
                                fontFamily: 'Satoshi',
                                color: context.textPrimary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              "Allow support team to view data for 2h.",
                              style: TextStyle(
                                fontFamily: 'Satoshi',
                                color: context.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: _allowSupportAccess,
                        onChanged: (val) =>
                            setState(() => _allowSupportAccess = val),
                        activeThumbColor: const Color(0xFF0A84FF),
                        activeTrackColor: const Color(
                          0xFF0A84FF,
                        ).withValues(alpha: 0.3),
                        inactiveThumbColor: context.textSecondary,
                        inactiveTrackColor: context.borderColor,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 40),

                _buildSectionLabel("TEAM MEMBERS"),
                StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('members')
                      .where('uid', isEqualTo: currentUser?.uid)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: context.cardBackground,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: context.borderColor),
                          boxShadow: context.cardShadow,
                        ),
                        child: Center(
                          child: CircularProgressIndicator(
                            color: context.iconSecondary,
                            strokeWidth: 2,
                          ),
                        ),
                      );
                    }

                    if (snapshot.hasError) {
                      return Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: context.cardBackground,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: context.borderColor),
                          boxShadow: context.cardShadow,
                        ),
                        child: Text(
                          "Failed to load team members.",
                          style: TextStyle(
                            fontFamily: 'Satoshi',
                            color: const Color(0xFFFF453A),
                          ),
                        ),
                      );
                    }

                    final docs = snapshot.data?.docs ?? [];

                    if (docs.isEmpty) {
                      return Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: context.cardBackground,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: context.borderColor),
                          boxShadow: context.cardShadow,
                        ),
                        child: Center(
                          child: Text(
                            "No team members yet.",
                            style: TextStyle(
                              fontFamily: 'Satoshi',
                              color: context.textSecondary,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      );
                    }

                    return Container(
                      decoration: BoxDecoration(
                        color: context.cardBackground,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: context.borderColor),
                        boxShadow: context.cardShadow,
                      ),
                      child: Column(
                        children: docs.asMap().entries.map((entry) {
                          final idx = entry.key;
                          final data =
                              entry.value.data() as Map<String, dynamic>;

                          final String name =
                              data['fullName'] as String? ?? 'Unknown';
                          final String email = data['email'] as String? ?? '—';
                          final String status =
                              data['status'] as String? ?? 'Active';
                          final String role =
                              data['jobTitle'] as String? ?? 'Member';

                          Color statusColor;
                          switch (status) {
                            case 'Active':
                              statusColor = const Color(0xFF30D158);
                              break;
                            case 'Paused':
                              statusColor = const Color(0xFFFF9F0A);
                              break;
                            case 'Inactive':
                              statusColor = context.textSecondary;
                              break;
                            default:
                              statusColor = const Color(0xFF30D158);
                          }

                          return Column(
                            children: [
                              ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 10,
                                ),
                                title: Text(
                                  name,
                                  style: TextStyle(
                                    fontFamily: 'Satoshi',
                                    color: context.textPrimary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const SizedBox(height: 2),
                                    Text(
                                      email,
                                      style: TextStyle(
                                        fontFamily: 'Satoshi',
                                        color: context.textSecondary,
                                        fontSize: 12,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      role,
                                      style: TextStyle(
                                        fontFamily: 'Satoshi',
                                        color: context.textTertiary,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                                trailing: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: statusColor.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: statusColor.withValues(
                                        alpha: 0.25,
                                      ),
                                    ),
                                  ),
                                  child: Text(
                                    status,
                                    style: TextStyle(
                                      fontFamily: 'Satoshi',
                                      color: statusColor,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                              if (idx != docs.length - 1)
                                Divider(
                                  height: 1,
                                  color: context.borderColor,
                                  indent: 20,
                                  endIndent: 20,
                                ),
                            ],
                          );
                        }).toList(),
                      ),
                    );
                  },
                ),

                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            child: Row(
              children: [
                Icon(Icons.arrow_back, color: context.textSecondary, size: 16),
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
    );
  }

  Widget _buildSectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, left: 4),
      child: Text(
        text,
        style: TextStyle(
          fontFamily: 'Satoshi',
          color: context.textTertiary,
          fontSize: 10,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.5,
        ),
      ),
    );
  }
}
