import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:startup_expense_tracker/services/currency_preference_service.dart';

class ChatService {
  static String get baseUrl {
    if (kReleaseMode) {
      return "https://your-production-url.com"; // TODO: replace with env var
    }
    return Platform.isIOS ? "http://127.0.0.1:8000" : "http://10.0.2.2:8000";
  }

  /// Fetches the user's financial data from Firestore and sends it
  /// alongside the chat message so the backend always has context.
  static Future<String> sendMessage(String question, List<Map<String, dynamic>> history) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('User not authenticated. Please log in.');
    }

    final token = await user.getIdToken();
    if (token == null) {
      throw Exception('Failed to get auth token.');
    }

    // Fetch financial context from Firestore (client-side)
    final sectionData = await _fetchFinancialContext(user.uid);
    final currencyCode = await CurrencyPreferenceService.getCurrencyPreference();
    final currencySymbol = CurrencyPreferenceService.getCurrencySymbol(currencyCode);

    final requestBody = {
      "question": question,
      "history": history,
      "sectionData": sectionData,
      "currencySymbol": currencySymbol,
    };

    try {
      final res = await http.post(
        Uri.parse("$baseUrl/chat"),
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer $token",
        },
        body: jsonEncode(requestBody),
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return data["response"] ?? "I couldn't process that.";
      } else {
        throw Exception('Server error (${res.statusCode}): ${res.body}');
      }
    } catch (e) {
      throw Exception('Connection failed. Please ensure the server is running. Error: $e');
    }
  }

  /// Streams the user's financial data and yields LLM tokens for a typewriter effect.
  static Stream<String> streamMessage(String question, List<Map<String, dynamic>> history) async* {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('User not authenticated. Please log in.');
    }

    final token = await user.getIdToken();
    if (token == null) {
      throw Exception('Failed to get auth token.');
    }

    final sectionData = await _fetchFinancialContext(user.uid);
    final currencyCode = await CurrencyPreferenceService.getCurrencyPreference();
    final currencySymbol = CurrencyPreferenceService.getCurrencySymbol(currencyCode);

    final requestBody = {
      "question": question,
      "history": history,
      "sectionData": sectionData,
      "currencySymbol": currencySymbol,
    };

    final request = http.Request('POST', Uri.parse("$baseUrl/chat/stream"));
    request.headers.addAll({
      "Content-Type": "application/json",
      "Authorization": "Bearer $token",
    });
    request.body = jsonEncode(requestBody);

    try {
      final response = await http.Client().send(request);
      
      if (response.statusCode != 200) {
        throw Exception('Server error (${response.statusCode})');
      }

      await for (final chunk in response.stream.transform(utf8.decoder)) {
        final lines = chunk.split('\n');
        for (final line in lines) {
          if (line.startsWith('data: ')) {
            final data = line.substring(6).trim();
            if (data == '[DONE]') return;
            if (data.isEmpty) continue;
            
            try {
              final json = jsonDecode(data);
              if (json.containsKey('error')) {
                  throw Exception(json['error']);
              }
              final choices = json['choices'] as List?;
              if (choices != null && choices.isNotEmpty) {
                final content = choices[0]['delta']?['content'];
                if (content != null) {
                  yield content as String;
                }
              }
            } catch (_) {
              // Ignore parse errors for broken chunks
            }
          }
        }
      }
    } catch (e) {
      throw Exception('Connection failed. Error: $e');
    }
  }

  /// Gathers the user's expenses, company, teams, members from Firestore.
  static Future<Map<String, dynamic>> _fetchFinancialContext(String uid) async {
    try {
      final expensesSnapshot = await FirebaseFirestore.instance
          .collection('expenses')
          .where('uid', isEqualTo: uid)
          .orderBy('Date', descending: true)
          .limit(100)
          .get();

      final companySnapshot = await FirebaseFirestore.instance
          .collection('companies')
          .where('uid', isEqualTo: uid)
          .limit(1)
          .get();

      final teamsSnapshot = await FirebaseFirestore.instance
          .collection('teams')
          .where('uid', isEqualTo: uid)
          .get();

      final membersSnapshot = await FirebaseFirestore.instance
          .collection('members')
          .where('uid', isEqualTo: uid)
          .get();

      final cleanExpenses = expensesSnapshot.docs.map((doc) {
        final e = doc.data();
        return {
          "Amount": (e["Amount"] ?? 0).toDouble(),
          "Category": (e["Category"] ?? "unknown").toString(),
          "Type": (e["Type"] ?? "unknown").toString(),
          "Description": (e["Description"] ?? e["Title"] ?? "").toString(),
          "ExpenseType": (e["ExpenseType"] ?? "unknown").toString(),
          "TeamName": (e["TeamName"] ?? e["linkedTeamName"] ?? "general").toString(),
          "TeamMemberName": (e["TeamMemberName"] ?? "none").toString(),
          "PaymentMethod": (e["BankAccount"] ?? e["PaymentMethod"] ?? "unknown").toString(),
          "Date": (e["Date"] is Timestamp)
              ? (e["Date"] as Timestamp).toDate().toIso8601String()
              : e["Date"]?.toString() ?? "",
        };
      }).toList();

      final companyData = companySnapshot.docs.isNotEmpty
          ? _cleanTimestamps(companySnapshot.docs.first.data())
          : {};

      final teamsData = teamsSnapshot.docs
          .map((doc) => _cleanTimestamps(doc.data()))
          .toList();

      final membersData = membersSnapshot.docs
          .map((doc) => _cleanTimestamps(doc.data()))
          .toList();

      return {
        "expenses": cleanExpenses,
        "revenue": [],
        "company": companyData,
        "members": membersData,
        "teams": teamsData,
      };
    } catch (e) {
      debugPrint("ChatService: Failed to fetch financial context: $e");
      return {
        "expenses": [],
        "revenue": [],
        "company": {},
        "members": [],
        "teams": [],
      };
    }
  }

  /// Converts Firestore Timestamps to ISO strings for JSON serialization.
  static Map<String, dynamic> _cleanTimestamps(Map<String, dynamic> data) {
    return data.map((key, value) {
      if (value is Timestamp) {
        return MapEntry(key, value.toDate().toIso8601String());
      }
      return MapEntry(key, value);
    });
  }
}
