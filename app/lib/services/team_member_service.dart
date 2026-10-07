import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class TeamMember {
  final String id;
  final String fullName;
  final String? avatarUrl;
  final String? telegramFileId;
  final String teamId;
  final String? email;
  final String? role;
  final double? salary;
  final double? totalExpenses;

  TeamMember({
    required this.id,
    required this.fullName,
    this.avatarUrl,
    this.telegramFileId,
    required this.teamId,
    this.email,
    this.role,
    this.salary,
    this.totalExpenses,
  });

  factory TeamMember.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return TeamMember(
      id: doc.id,
      fullName: data['fullName'] ?? 'Unnamed Member',
      avatarUrl: data['avatarUrl'],
      telegramFileId: data['telegramFileId'],
      teamId: data['teamId'] ?? '',
      email: data['email'],
      role: data['role'],
      salary: (data['salary'] as num?)?.toDouble(),
      totalExpenses: (data['totalExpenses'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'fullName': fullName,
      'avatarUrl': avatarUrl,
      'telegramFileId': telegramFileId,
      'teamId': teamId,
      'email': email,
      'role': role,
      'salary': salary,
      'totalExpenses': totalExpenses,
    };
  }

  double? get remainingSalary {
    if (salary == null) return null;
    return salary! - (totalExpenses ?? 0.0);
  }

  double? get expensesPercentage {
    if (salary == null || salary == 0) return 0.0;
    return ((totalExpenses ?? 0) / salary!) * 100;
  }

  double? get remainingPercentage {
    if (salary == null || salary == 0) return 100.0;
    return ((salary! - (totalExpenses ?? 0)) / salary!) * 100;
  }
}

class Team {
  final String id;
  final String teamName;
  final String? iconCodePoint;
  final String? iconFontFamily;
  final String? color;
  final double? monthlyBudget;
  final double? usedBudget;

  Team({
    required this.id,
    required this.teamName,
    this.iconCodePoint,
    this.iconFontFamily,
    this.color,
    this.monthlyBudget,
    this.usedBudget,
  });

  factory Team.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Team(
      id: doc.id,
      teamName: data['teamName'] ?? 'Unnamed Team',
      iconCodePoint: data['iconCodePoint']?.toString(),
      iconFontFamily: data['iconFontFamily'],
      color: data['color'],
      monthlyBudget: (data['monthlyBudget'] as num?)?.toDouble(),
      usedBudget: (data['usedBudget'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'teamName': teamName,
      'iconCodePoint': iconCodePoint,
      'iconFontFamily': iconFontFamily,
      'color': color,
      'monthlyBudget': monthlyBudget,
      'usedBudget': usedBudget,
    };
  }
}

class TeamMemberService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final Map<String, String> _telegramPhotoCache = {};

  static Future<List<Team>> getTeams() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return [];

    try {
      final snapshot = await _firestore
          .collection('teams')
          .where('uid', isEqualTo: user.uid)
          .get();

      return snapshot.docs.map((doc) => Team.fromFirestore(doc)).toList();
    } catch (e) {
      debugPrint('Error fetching teams: $e');
      return [];
    }
  }

  static Stream<List<Team>> getTeamsStream() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return Stream.value([]);

    return _firestore
        .collection('teams')
        .where('uid', isEqualTo: user.uid)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs.map((doc) => Team.fromFirestore(doc)).toList();
        });
  }

  static Stream<List<TeamMember>> getTeamMembersStream() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return Stream.value([]);

    return _firestore
        .collection('members')
        .where('uid', isEqualTo: user.uid)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs
              .map((doc) => TeamMember.fromFirestore(doc))
              .toList();
        });
  }

  static Future<List<TeamMember>> getTeamMembers() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return [];

    try {
      final snapshot = await _firestore
          .collection('members')
          .where('uid', isEqualTo: user.uid)
          .get();

      return snapshot.docs.map((doc) => TeamMember.fromFirestore(doc)).toList();
    } catch (e) {
      debugPrint('Error fetching team members: $e');
      return [];
    }
  }

  static Future<List<TeamMember>> getTeamMembersByTeam(String teamId) async {
    try {
      final snapshot = await _firestore
          .collection('members')
          .where('teamId', isEqualTo: teamId)
          .get();

      return snapshot.docs.map((doc) => TeamMember.fromFirestore(doc)).toList();
    } catch (e) {
      debugPrint('Error fetching team members for team $teamId: $e');
      return [];
    }
  }

  static String? getMemberAvatarUrl(TeamMember member) {
    // Check for Telegram photo first, then regular avatar
    if (member.telegramFileId != null && member.telegramFileId!.isNotEmpty) {
      return 'telegram:${member.telegramFileId}';
    } else if (member.avatarUrl != null &&
        member.avatarUrl!.isNotEmpty &&
        !member.avatarUrl!.contains('ui-avatars.com')) {
      return member.avatarUrl;
    }
    return null;
  }

  static Future<String> getTelegramImageUrl(String fileId) async {
    // Check cache first
    if (_telegramPhotoCache.containsKey(fileId)) {
      return _telegramPhotoCache[fileId]!;
    }

    try {
      await dotenv.load(fileName: ".env.local");
      final botToken = dotenv.env['TELEGRAM_BOT_TOKEN'];
      if (botToken == null) {
        throw Exception('Telegram bot token not found in environment');
      }

      final res = await http.get(
        Uri.parse(
          "https://api.telegram.org/bot$botToken/getFile?file_id=$fileId",
        ),
      );

      final data = jsonDecode(res.body);
      final path = data['result']['file_path'];
      final imageUrl = "https://api.telegram.org/file/bot$botToken/$path";

      // Cache the result
      _telegramPhotoCache[fileId] = imageUrl;

      return imageUrl;
    } catch (e) {
      debugPrint('Error getting Telegram image URL: $e');
      rethrow;
    }
  }

  static String? getTelegramFileId(String avatarUrl) {
    if (avatarUrl.startsWith('telegram:')) {
      return avatarUrl.substring(9); // Remove 'telegram:' prefix
    }
    return null;
  }

  static Future<void> checkAndApplyFutureSalaries() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final now = DateTime.now();
      // Fetch all members for the user to evaluate locally (avoids needing a composite index)
      final snapshot = await _firestore
          .collection('members')
          .where('uid', isEqualTo: user.uid)
          .get();

      for (var doc in snapshot.docs) {
        final data = doc.data();
        final effectiveDate = data['futureSalaryDate'] as Timestamp?;

        if (effectiveDate != null && effectiveDate.toDate().isBefore(now)) {
          final newSalary = (data['futureSalary'] as num?)?.toDouble();
          final reason = data['futureSalaryReason'] as String?;

          if (newSalary != null) {
            // Promote future salary to active salary
            await doc.reference.update({
              'monthlyCost': newSalary,
              'salary': newSalary,
              'lastSalaryUpdateDate': effectiveDate,
              'lastSalaryUpdateReason': reason,
              'futureSalary': FieldValue.delete(),
              'futureSalaryDate': FieldValue.delete(),
              'futureSalaryReason': FieldValue.delete(),
            });

            // Log in salary history
            final currentSalary = (data['salary'] as num?)?.toDouble() ?? 0.0;
            await doc.reference.collection('salary_history').add({
              'previousSalary': currentSalary,
              'newSalary': newSalary,
              'delta': newSalary - currentSalary,
              'reason': reason ?? 'Scheduled Salary Update',
              'effectiveDate': effectiveDate,
              'changedAt': FieldValue.serverTimestamp(),
            });

            debugPrint(
              '✅ DEBUG: Applied future salary of $newSalary for member ${doc.id}',
            );
          }
        }
      }
    } catch (e) {
      debugPrint('❌ DEBUG: Error applying future salaries: $e');
    }
  }
}
