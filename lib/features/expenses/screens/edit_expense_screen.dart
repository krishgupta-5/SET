import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../../../utils/data_helpers.dart';
import '../../../services/currency_preference_service.dart';
import '../../../services/currency_formatter.dart';
import '../../../services/bank_account_service.dart';
import '../../../services/team_member_service.dart';
import '../../../services/expense_service.dart';


import '../../../widgets/avatar_widget.dart';
import '../../../theme/app_theme.dart';

class EditExpenseScreen extends StatefulWidget {
  final String expenseId;
  final Map<String, dynamic> expenseData;

  const EditExpenseScreen({
    super.key,
    required this.expenseId,
    required this.expenseData,
  });

  @override
  State<EditExpenseScreen> createState() => _EditExpenseScreenState();
}

class _EditExpenseScreenState extends State<EditExpenseScreen> {
  // 1. CONTROLLERS & STATE
  late TextEditingController _amountController;
  late TextEditingController _titleController;
  late TextEditingController _notesController;
  late TextEditingController _dateController;

  bool _isLoading = false;
  bool _isLoadingBanks = true;
  String _userCountryCode = '+1';
  bool _isLoadingCountry = true;

  // Attachment state
  String? _attachmentFileId;
  String? _fileName;
  bool _isUploading = false;

  final categories = {
    'marketing': 'Marketing',
    'infrastructure': 'Infrastructure',
    'office': 'Office Rent',
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
  
  final types = {
    'one_time': 'One-time',
    'recurring': 'Recurring',
  };

  Map<String, String> _bankAccounts = {};
  List<TeamMember> _teamMembers = [];
  List<Team> _teams = [];
  
  TeamMember? _selectedTeamMember;
  Team? _selectedTeam;
  String _expenseType = "team"; // "team" or "member"

  late String _selectedCategory;
  late String _selectedType;
  String? _selectedBankAccount;
  late DateTime _selectedDate;

  // Recurring Details State
  late String _recurrenceFrequency;
  late bool _isOngoing;
  late TextEditingController _tenureController;

  @override
  void initState() {
    super.initState();
    _loadUserCountryCode();

    // 2. PRE-FILL DATA FROM FIREBASE
    _amountController = TextEditingController(
      text: widget.expenseData['Amount']?.toString() ?? "",
    );
    _titleController = TextEditingController(
      text: widget.expenseData['Title'] ?? "",
    );
    _notesController = TextEditingController(
      text: widget.expenseData['Description'] ?? "",
    );

    _attachmentFileId = widget.expenseData['AttachmentFileId'] as String?;

    String fetchedCategory =
        widget.expenseData['Category']?.toString().toLowerCase() ?? 'marketing';
    _selectedCategory = categories.containsKey(fetchedCategory)
        ? fetchedCategory
        : 'marketing';

    String fetchedType =
        widget.expenseData['Type']?.toString().toLowerCase() ?? 'one_time';
    _selectedType = types.containsKey(fetchedType) ? fetchedType : 'one_time';

    _recurrenceFrequency = widget.expenseData['recurrenceFrequency']?.toString() ?? 'monthly';
    final dynamic fetchedTenure = widget.expenseData['recurringTenureMonths'];
    _isOngoing = fetchedTenure == null;
    _tenureController = TextEditingController(
      text: fetchedTenure?.toString() ?? '',
    );

    if (widget.expenseData['Date'] is Timestamp) {
      _selectedDate = (widget.expenseData['Date'] as Timestamp).toDate();
    } else {
      _selectedDate = DateTime.now();
    }

    _dateController = TextEditingController(
      text: "${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}",
    );

    _expenseType = widget.expenseData['ExpenseType'] ?? 'team';

    _fetchBankAccounts();
    _fetchTeamMembers();
    _fetchTeams();
  }

  void _loadUserCountryCode() {
    CurrencyPreferenceService.currencyNotifier.addListener(_onCurrencyChanged);
    _userCountryCode = CurrencyPreferenceService.getCurrencyPreferenceSync();
    setState(() => _isLoadingCountry = false);
  }

  void _onCurrencyChanged() {
    if (mounted) {
      setState(() {
        _userCountryCode =
            CurrencyPreferenceService.getCurrencyPreferenceSync();
      });
    }
  }

  @override
  void dispose() {
    CurrencyPreferenceService.currencyNotifier.removeListener(
      _onCurrencyChanged,
    );
    _amountController.dispose();
    _titleController.dispose();
    _notesController.dispose();
    _dateController.dispose();
    _tenureController.dispose();
    super.dispose();
  }

  // --- DATA FETCHING ---

  Future<void> _fetchBankAccounts() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      final companyId = userDoc.data()?['companyId'];
      if (companyId == null) return;

      final doc = await FirebaseFirestore.instance
          .collection('companies')
          .doc(companyId)
          .get();

      if (doc.exists && doc.data()!.containsKey('Bank Accounts')) {
        final accounts = doc.data()!['Bank Accounts'] as List<dynamic>;
        Map<String, String> loadedBanks = {};

        for (var acc in accounts) {
          final String name = acc['name'] ?? acc['bankName'] ?? 'Unknown Bank';
          final String rawLast4 =
              acc['last4']?.toString() ?? acc['number']?.toString() ?? '';
          final String last4 = rawLast4.isNotEmpty
              ? BankAccountService.extractLast4(rawLast4)
              : '';
          final String key = "$name-$last4";
          final String label = last4.isNotEmpty ? "$name (****$last4)" : name;
          loadedBanks[key] = label;
        }

        setState(() {
          _bankAccounts = loadedBanks;
          _bankAccounts["Cash-"] = "Cash";

          // Pre-fill the bank account if it exists
          String? savedBank = widget.expenseData['BankAccount'];
          if (savedBank != null && _bankAccounts.containsKey(savedBank)) {
            _selectedBankAccount = savedBank;
          } else if (_bankAccounts.isNotEmpty) {
            _selectedBankAccount = _bankAccounts.keys.first;
          }
        });
      } else {
        setState(() {
          _bankAccounts = {"Cash-": "Cash"};
          _selectedBankAccount = "Cash-";
        });
      }
    } catch (e) {
      debugPrint("Failed to load bank accounts: $e");
    } finally {
      if (mounted) setState(() => _isLoadingBanks = false);
    }
  }

  Future<void> _fetchTeamMembers() async {
    try {
      final members = await TeamMemberService.getTeamMembers();
      if (mounted) {
        setState(() {
          _teamMembers = members;
          
          // Pre-fill member if exists
          String? savedMemberId = widget.expenseData['TeamMemberId'];
          if (savedMemberId != null) {
            try {
              _selectedTeamMember = members.firstWhere((m) => m.id == savedMemberId);
            } catch (e) {
              _selectedTeamMember = null;
            }
          }
        });
      }
    } catch (e) {
      debugPrint("Failed to load team members: $e");
    }
  }

  Future<void> _fetchTeams() async {
    try {
      final teams = await TeamMemberService.getTeams();
      if (mounted) {
        setState(() {
          _teams = teams;

          // Pre-fill team if exists
          String? savedTeamId = widget.expenseData['TeamId'];
          if (savedTeamId != null) {
            try {
              _selectedTeam = teams.firstWhere((t) => t.id == savedTeamId);
            } catch (e) {
              _selectedTeam = null;
            }
          }
        });
      }
    } catch (e) {
      debugPrint("Failed to load teams: $e");
    }
  }

  // --- TELEGRAM ATTACHMENT LOGIC ---

  Future<String?> uploadToTelegram(String filePath) async {
    try {
      await dotenv.load(fileName: ".env.local");
      final botToken = dotenv.env['TELEGRAM_BOT_TOKEN'];

      if (botToken == null) {
        throw Exception('Telegram bot token not found in environment');
      }

      final isImage =
          filePath.toLowerCase().endsWith('.jpg') ||
          filePath.toLowerCase().endsWith('.jpeg') ||
          filePath.toLowerCase().endsWith('.png') ||
          filePath.toLowerCase().endsWith('.gif');

      final uri = Uri.parse(
        "https://api.telegram.org/bot$botToken/${isImage ? 'sendPhoto' : 'sendDocument'}",
      );

      var request = http.MultipartRequest('POST', uri);
      request.fields['chat_id'] = '-1003885930746';

      if (isImage) {
        request.files.add(await http.MultipartFile.fromPath('photo', filePath));
      } else {
        request.files.add(
          await http.MultipartFile.fromPath('document', filePath),
        );
      }

      final response = await request.send();

      if (response.statusCode == 200) {
        final res = await http.Response.fromStream(response);
        final data = jsonDecode(res.body);

        if (isImage) {
          return data['result']['photo'].last['file_id'];
        } else {
          return data['result']['document']['file_id'];
        }
      } else {
        throw Exception("Upload failed: ${response.statusCode}");
      }
    } catch (e) {
      debugPrint('Error uploading to Telegram: $e');
      return null;
    }
  }

  Future<void> _uploadFile(String filePath, String fileName) async {
    try {
      setState(() {
        _isUploading = true;
        _fileName = fileName;
      });

      final fileId = await uploadToTelegram(filePath);

      if (fileId == null) {
        throw Exception('Failed to upload file to Telegram');
      }

      setState(() {
        _isUploading = false;
        _attachmentFileId = fileId;
      });

      _showMinimalToast("File uploaded successfully!");
    } catch (e) {
      debugPrint('Error uploading file: $e');
      setState(() {
        _isUploading = false;
        _fileName = null;
      });

      if (mounted) {
        _showMinimalToast("Failed to upload file: $e", isError: true);
      }
    }
  }

  Future<void> _showFilePicker() async {
    try {
      await showModalBottomSheet(
        context: context,
        backgroundColor: context.cardBackground,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (context) => Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "Select Attachment",
                style: GoogleFonts.inter(
                  color: context.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 20),
              ListTile(
                leading: Icon(Icons.camera_alt, color: context.textPrimary),
                title: Text(
                  "Take Photo",
                  style: GoogleFonts.inter(color: context.textPrimary),
                ),
                onTap: () async {
                  Navigator.pop(context);
                  final picker = ImagePicker();
                  final XFile? image = await picker.pickImage(
                    source: ImageSource.camera,
                    imageQuality: 80,
                  );
                  if (image != null) {
                    await _uploadFile(image.path, image.name);
                  }
                },
              ),
              ListTile(
                leading: Icon(Icons.photo_library, color: context.textPrimary),
                title: Text(
                  "Choose Photo / Video",
                  style: GoogleFonts.inter(color: context.textPrimary),
                ),
                onTap: () async {
                  Navigator.pop(context);
                  final picker = ImagePicker();
                  final XFile? media = await picker.pickMedia();
                  if (media != null) {
                    await _uploadFile(media.path, media.name);
                  }
                },
              ),
              ListTile(
                leading: Icon(
                  Icons.insert_drive_file,
                  color: context.textPrimary,
                ),
                title: Text(
                  "Choose PDF / Document",
                  style: GoogleFonts.inter(color: context.textPrimary),
                ),
                onTap: () async {
                  Navigator.pop(context);
                  final result = await FilePicker.platform.pickFiles(
                    type: FileType.custom,
                    allowedExtensions: [
                      'pdf', 'doc', 'docx', 'xls', 'xlsx', 'txt', 'csv',
                    ],
                    allowMultiple: false,
                  );
                  if (result != null && result.files.single.path != null) {
                    await _uploadFile(
                      result.files.single.path!,
                      result.files.single.name,
                    );
                  }
                },
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      debugPrint("File pick error: $e");
      if (mounted) {
        _showMinimalToast("Could not open file picker.", isError: true);
      }
    }
  }

  IconData _getFileIcon(String? filePath) {
    if (filePath == null) return Icons.insert_drive_file;
    final extension = filePath.toLowerCase().split('.').last;
    switch (extension) {
      case 'pdf': return Icons.picture_as_pdf;
      case 'doc': case 'docx': return Icons.description;
      case 'xls': case 'xlsx': return Icons.table_chart;
      case 'jpg': case 'jpeg': case 'png': case 'gif': return Icons.image;
      case 'mp4': case 'avi': case 'mov': return Icons.video_file;
      default: return Icons.insert_drive_file;
    }
  }

  // --- UNIFIED MINIMAL TOAST ---
  void _showMinimalToast(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.check_circle_outline,
              color: isError
                  ? const Color(0xFFFF453A)
                  : const Color(0xFF30D158),
              size: 18,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: GoogleFonts.inter(
                  color: context.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: context.cardBackground,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: context.borderColor),
        ),
        duration: const Duration(seconds: 3),
        elevation: 0,
      ),
    );
  }

  // 3. FIREBASE UPDATE LOGIC
  Future<void> _updateExpense() async {
    FocusScope.of(context).unfocus();

    final double? amount = CurrencyFormatter.parse(_amountController.text.trim());
    if (amount == null || amount <= 0) {
      _showMinimalToast("Please enter a valid amount.", isError: true);
      return;
    }
    if (_titleController.text.trim().isEmpty) {
      _showMinimalToast("Please enter a title.", isError: true);
      return;
    }
    final isRecurringOrSub = _selectedType == "recurring" || _selectedType == "subscription";
    if (!isRecurringOrSub && _selectedDate.isAfter(DateTime.now())) {
      _showMinimalToast("Date cannot be in the future.", isError: true);
      return;
    }

    int? recurringTenure;
    if (isRecurringOrSub && !_isOngoing) {
      final tenureText = _tenureController.text.trim();
      if (tenureText.isEmpty) {
        _showMinimalToast("Please enter a tenure for the recurring expense.", isError: true);
        return;
      }
      recurringTenure = int.tryParse(tenureText);
      if (recurringTenure == null || recurringTenure <= 0) {
        _showMinimalToast("Tenure must be a positive number.", isError: true);
        return;
      }
    }

    if (_selectedBankAccount == null) {
      _showMinimalToast("Please select a payment method.", isError: true);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('User not authenticated');

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      final companyId = userDoc.data()?['companyId'];
      if (companyId == null) throw Exception('Company not found');

      final double newAmount = CurrencyFormatter.parse(_amountController.text.trim())!;
      final double oldAmount = DataHelpers.safeParseDouble(
        widget.expenseData['Amount'],
      );
      final double diff = newAmount - oldAmount;

      final expenseType = widget.expenseData['ExpenseType'] as String?;
      final teamId = widget.expenseData['TeamId'] as String?;
      final teamMemberId = widget.expenseData['TeamMemberId'] as String?;

      if (diff != 0 && expenseType == 'member' && teamMemberId != null) {
        final memberDoc = await FirebaseFirestore.instance
            .collection('members')
            .doc(teamMemberId)
            .get();
        if (memberDoc.exists) {
          final data = memberDoc.data() as Map<String, dynamic>;
          final salary = (data['salary'] as num?)?.toDouble() ?? 0.0;
          final currentExpenses = (data['totalExpenses'] as num?)?.toDouble() ?? 0.0;
          final newMemberExpenses = currentExpenses + diff;
          if (newMemberExpenses > salary) {
            if (mounted) {
              _showMinimalToast(
                "Cannot update: Expense amount exceeds remaining salary for ${data['fullName'] ?? 'member'}",
                isError: true,
              );
              setState(() => _isLoading = false);
            }
            return;
          }
        }
      }

      await ExpenseService().updateExpense(
        expenseId: widget.expenseId,
        companyId: companyId,
        diff: diff,
        newAmount: newAmount,
        title: _titleController.text.trim(),
        description: _notesController.text.trim(),
        date: _selectedDate,
        category: _selectedCategory,
        type: _selectedType,
        bankAccount: _selectedBankAccount,
        attachmentFileId: _attachmentFileId,
        expenseType: _expenseType,
        teamId: _selectedTeam?.id,
        teamName: _selectedTeam?.teamName,
        teamMemberId: _selectedTeamMember?.id,
        teamMemberName: _selectedTeamMember?.fullName,
        isRecurringOrSub: isRecurringOrSub,
        recurrenceFrequency: _recurrenceFrequency,
        recurringTenure: recurringTenure,
      );

      if (mounted) {
        _showMinimalToast("Expense updated successfully");
        await Future.delayed(const Duration(milliseconds: 300));
        if (mounted) Navigator.pop(context);
      }
    } on FirebaseException catch (e) {
      if (mounted) {
        _showMinimalToast(
          e.message ?? 'Failed to update expense',
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.appBackground,
      resizeToAvoidBottomInset: true,
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: Theme.of(context).brightness == Brightness.dark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(context),
              Expanded(
                child: GestureDetector(
                  onTap: () => FocusScope.of(context).unfocus(),
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 24),

                        Center(
                          child: Column(
                            children: [
                              _buildSectionLabel("AMOUNT"),
                              const SizedBox(height: 8),
                              _buildAmountInput(),
                            ],
                          ),
                        ),

                        const SizedBox(height: 40),

                        _buildSectionLabel('EXPENSE DETAILS'),
                        const SizedBox(height: 8),
                        _buildTextInput(
                          'Expense Title',
                          'e.g. Client Lunch',
                          _titleController,
                        ),

                        const SizedBox(height: 24),

                        Row(
                          children: [
                            Expanded(
                              child: _buildSelectField(
                                label: 'Category',
                                currentValue: _selectedCategory,
                                items: categories,
                                icon: Icons.pie_chart_outline,
                                onChanged: (val) {
                                  FocusScope.of(context).unfocus();
                                  setState(() => _selectedCategory = val!);
                                },
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: _buildSelectField(
                                label: 'Type',
                                currentValue: _selectedType,
                                items: types,
                                icon: Icons.repeat,
                                onChanged: (val) {
                                  FocusScope.of(context).unfocus();
                                  setState(() => _selectedType = val!);
                                },
                              ),
                            ),
                          ],
                        ),

                        AnimatedCrossFade(
                          duration: const Duration(milliseconds: 300),
                          crossFadeState: (_selectedType == 'recurring' || _selectedType == 'subscription')
                              ? CrossFadeState.showFirst
                              : CrossFadeState.showSecond,
                          firstChild: _buildRecurringDetailsCard(),
                          secondChild: const SizedBox.shrink(),
                        ),

                        const SizedBox(height: 24),

                        if (!_isLoadingBanks && _bankAccounts.isNotEmpty) ...[
                          _buildSelectField(
                            label: "Payment Method",
                            currentValue: _selectedBankAccount ?? "",
                            items: _bankAccounts,
                            icon: Icons.account_balance,
                            onChanged: (val) {
                              FocusScope.of(context).unfocus();
                              setState(() => _selectedBankAccount = val!);
                            },
                          ),
                          const SizedBox(height: 24),
                        ],

                        _buildDateSelector(),
                        _buildTextArea("Description / Notes", _notesController),
                        const SizedBox(height: 24),
                        _buildSectionLabel("EXPENSE TYPE"),
                        const SizedBox(height: 8),
                        _buildExpenseTypeSelector(),
                        const SizedBox(height: 24),
                        
                        _buildSectionLabel("LINK MEMBER (OPTIONAL)"),
                        const SizedBox(height: 16),
                        if (_expenseType == "member") ...[
                          _buildTeamSelector(),
                          const SizedBox(height: 32),
                        ] else ...[
                          _buildTeamSelector(),
                          const SizedBox(height: 32),
                        ],


                        _buildSectionLabel("ATTACHMENT"),
                        const SizedBox(height: 16),
                        _buildAttachmentZone(),

                        const SizedBox(height: 40),
                      ],
                    ),
                  ),
                ),
              ),

              _buildUpdateButton(),
            ],
          ),
        ),
      ),
    );
  }

  // --- WIDGET BUILDERS ---

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: context.cardBackground,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: context.borderColor),
              ),
              child: Icon(Icons.close, color: context.textPrimary, size: 20),
            ),
          ),
          Text(
            "Edit Expense",
            style: GoogleFonts.inter(
              color: context.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 44),
        ],
      ),
    );
  }

  Widget _buildSectionLabel(String text) {
    return Text(
      text.toUpperCase(),
      style: GoogleFonts.inter(
        color: context.textSecondary,
        fontSize: 11,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.2,
      ),
    );
  }

  Widget _buildAmountInput() {
    return SizedBox(
      width: double.infinity,
      child: TextField(
        controller: _amountController,
        keyboardType: TextInputType.text,
        textAlign: TextAlign.center,
        onTapOutside: (event) => FocusScope.of(context).unfocus(),
        textInputAction: TextInputAction.next,
        style: GoogleFonts.inter(
          color: context.textPrimary,
          fontSize: 56,
          fontWeight: FontWeight.w600,
          letterSpacing: -2,
        ),
        cursorColor: const Color(0xFF30D158),
        decoration: InputDecoration(
          hintText: "0.00",
          hintStyle: GoogleFonts.inter(
            color: context.textSecondary.withValues(alpha: 0.3),
            fontSize: 56,
            fontWeight: FontWeight.w600,
          ),
          border: InputBorder.none,
          contentPadding: EdgeInsets.zero,
          prefixText: _isLoadingCountry
              ? '₹'
              : "${CurrencyFormatter.getCurrencySymbol(_userCountryCode)} ",
          prefixStyle: GoogleFonts.inter(
            color: context.textSecondary,
            fontSize: 32,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildTextInput(
    String label,
    String placeholder,
    TextEditingController controller,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: context.cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.borderColor),
      ),
      child: TextField(
        controller: controller,
        onTapOutside: (event) => FocusScope.of(context).unfocus(),
        textInputAction: TextInputAction.next,
        style: GoogleFonts.inter(color: context.textPrimary, fontSize: 15),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: GoogleFonts.inter(color: context.textSecondary, fontSize: 13),
          hintText: placeholder,
          hintStyle: GoogleFonts.inter(color: context.textSecondary.withValues(alpha: 0.5)),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
          floatingLabelBehavior: FloatingLabelBehavior.auto,
        ),
      ),
    );
  }

  Widget _buildSelectField({
    required String label,
    required String currentValue,
    required Map<String, String> items,
    required IconData icon,
    required Function(String?) onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionLabel(label),
        const SizedBox(height: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: double.infinity),
          child: ShadSelect<String>(
            placeholder: Text(
              'Select $label',
              style: GoogleFonts.inter(color: context.textSecondary, fontSize: 14),
            ),
            initialValue: currentValue.isNotEmpty ? currentValue : null,
            options: [
              ...items.entries.map(
                (e) => ShadOption(value: e.key, child: Text(e.value)),
              ),
            ],
            selectedOptionBuilder: (context, value) => Text(
              items[value] ?? "Select",
              style: GoogleFonts.inter(
                color: context.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  Widget _buildDateSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionLabel('DATE'),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          decoration: BoxDecoration(
            color: context.cardBackground,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: context.borderColor),
          ),
          child: TextField(
            readOnly: true,
            style: GoogleFonts.inter(color: context.textPrimary, fontSize: 15),
            decoration: InputDecoration(
              icon: Icon(
                Icons.calendar_today,
                color: context.textSecondary,
                size: 20,
              ),
              hintText: 'Select date',
              labelText: 'Date',
              labelStyle: GoogleFonts.inter(
                color: context.textSecondary,
                fontSize: 13,
              ),
              hintStyle: GoogleFonts.inter(color: context.textSecondary.withValues(alpha: 0.5)),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 14),
              suffixIcon: Icon(
                Icons.calendar_month,
                color: context.textSecondary,
              ),
            ),
            // Use the persistent _dateController — avoids creating a new
            // TextEditingController (and leaking it) on every build call.
            controller: _dateController,
            onTap: () {
              FocusScope.of(context).unfocus();
              _showShadCalendar();
            },
          ),
        ),
      ],
    );
  }

  void _showShadCalendar() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: context.cardBackground,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.8,
            ),
            child: SingleChildScrollView(
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
                          style: GoogleFonts.inter(
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
                    ShadCalendar(
                      selected: _selectedDate,
                      fromMonth: DateTime(_selectedDate.year - 1, 1),
                      toMonth: DateTime(_selectedDate.year + 1, 12),
                      onChanged: (DateTime? date) {
                        if (date != null) {
                          setState(() {
                            _selectedDate = date;
                            _dateController.text =
                                "${date.day}/${date.month}/${date.year}";
                          });
                          // Update the persistent controller so the field reflects the new date
                          _dateController.text =
                              '${date.day}/${date.month}/${date.year}';
                          Navigator.pop(context);
                        }
                      },
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: context.textPrimary,
                          foregroundColor: context.appBackground,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          "Done",
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTextArea(String label, TextEditingController controller) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionLabel(label),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          decoration: BoxDecoration(
            color: context.cardBackground,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: context.borderColor),
          ),
          child: TextField(
            controller: controller,
            onTapOutside: (event) => FocusScope.of(context).unfocus(),
            textInputAction: TextInputAction.done,
            style: GoogleFonts.inter(color: context.textPrimary, fontSize: 15),
            maxLines: 4,
            minLines: 3,
            decoration: InputDecoration(
              hintText: "Enter details...",
              hintStyle: GoogleFonts.inter(color: context.textSecondary.withValues(alpha: 0.5)),
              border: InputBorder.none,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildExpenseTypeSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: context.cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.borderColor),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _expenseType = "team";
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: _expenseType == "team"
                      ? const Color(0xFF30D158).withValues(alpha: 0.2)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  "Team Expense",
                  style: GoogleFonts.inter(
                    color: _expenseType == "team"
                        ? const Color(0xFF30D158)
                        : context.textSecondary,
                    fontSize: 14,
                    fontWeight: _expenseType == "team"
                        ? FontWeight.w600
                        : FontWeight.w400,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _expenseType = "member";
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: _expenseType == "member"
                      ? const Color(0xFF0A84FF).withValues(alpha: 0.2)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  "Member Expense",
                  style: GoogleFonts.inter(
                    color: _expenseType == "member"
                        ? const Color(0xFF0A84FF)
                        : context.textSecondary,
                    fontSize: 14,
                    fontWeight: _expenseType == "member"
                        ? FontWeight.w600
                        : FontWeight.w400,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }


  // 🔥 CLEANED UP UI: Shows ONLY avatar and name (Matches Add Expenses)
  Widget _buildTeamSelector() {
    final isTeamExpense = _expenseType == "team";
    final items = isTeamExpense ? _teams : _teamMembers;

    if (items.isEmpty) {
      return Container(
        height: 96,
        decoration: BoxDecoration(
          color: context.cardBackground,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: context.borderColor),
        ),
        child: Center(
          child: Text(
            isTeamExpense ? "No teams available" : "No team members available",
            style: GoogleFonts.inter(color: context.textSecondary, fontSize: 14),
          ),
        ),
      );
    }

    return SizedBox(
      height: 96,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: items.length + 1, // +1 for "None" option
        itemBuilder: (context, index) {
          if (index == 0) {
            // "None" option to deselect
            return Padding(
              padding: const EdgeInsets.only(right: 12),
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    _selectedTeam = null;
                    _selectedTeamMember = null;
                  });
                },
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: context.borderColor,
                        ),
                        color:
                            (isTeamExpense
                                ? _selectedTeam == null
                                : _selectedTeamMember == null)
                            ? context.borderColor
                            : Colors.transparent,
                      ),
                      child: Icon(
                        isTeamExpense
                            ? Icons.group_outlined
                            : Icons.person_outline,
                        color:
                            (isTeamExpense
                                ? _selectedTeam == null
                                : _selectedTeamMember == null)
                            ? context.textPrimary
                            : context.textSecondary,
                        size: 22,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "None",
                      style: GoogleFonts.inter(
                        color:
                            (isTeamExpense
                                ? _selectedTeam == null
                                : _selectedTeamMember == null)
                            ? context.textPrimary
                            : context.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          if (isTeamExpense) {
            final team = _teams[index - 1];
            final isSelected = _selectedTeam?.id == team.id;
            return Padding(
              padding: const EdgeInsets.only(right: 12),
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    _selectedTeam = isSelected ? null : team;
                    _selectedTeamMember = null;
                  });
                },
                child: _buildTeamAvatar(team, isSelected),
              ),
            );
          } else {
            final member = _teamMembers[index - 1];
            final isSelected = _selectedTeamMember?.id == member.id;
            final avatarUrl = TeamMemberService.getMemberAvatarUrl(member);

            return Padding(
              padding: const EdgeInsets.only(right: 12),
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    _selectedTeamMember = isSelected ? null : member;
                    _selectedTeam = null;
                  });
                },
                child: _buildMemberAvatarWithName(
                  member,
                  avatarUrl,
                  isSelected,
                ),
              ),
            );
          }
        },
      ),
    );
  }

  Widget _buildTeamAvatar(Team team, bool isSelected) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: isSelected
                ? Border.all(color: context.textPrimary, width: 2)
                : Border.all(color: Colors.transparent),
          ),
          child: Stack(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: _getTeamColor(team.color).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _getTeamIcon(team),
                  color: _getTeamColor(team.color),
                  size: 22,
                ),
              ),
              if (isSelected)
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: const Color(0xFF30D158),
                      shape: BoxShape.circle,
                      border: Border.all(color: context.appBackground, width: 2),
                    ),
                    child: const Icon(
                      Icons.check,
                      color: Colors.white,
                      size: 10,
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: 70,
          child: Text(
            team.teamName,
            style: GoogleFonts.inter(
              color: isSelected ? context.textPrimary : context.textSecondary,
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Color _getTeamColor(String? colorName) {
    switch (colorName?.toLowerCase()) {
      case 'blue': return const Color(0xFF0A84FF);
      case 'orange': return const Color(0xFFFF9F0A);
      case 'purple': return const Color(0xFFA259FF);
      case 'green': return const Color(0xFF30D158);
      case 'red': return const Color(0xFFFF453A);
      default: return const Color(0xFF0A84FF);
    }
  }

  IconData _getTeamIcon(Team team) {
    if (team.iconCodePoint != null && team.iconFontFamily != null) {
      switch (int.tryParse(team.iconCodePoint!)) {
        case 0xe3af: return Icons.work;
        case 0xe0af: return Icons.business;
        case 0xe7fd: return Icons.group;
        case 0xe226: return Icons.code;
        case 0xe86c: return Icons.design_services;
        case 0xe85d: return Icons.computer;
        case 0xe53b: return Icons.build;
        case 0xe251: return Icons.lightbulb;
        case 0xe7f1: return Icons.trending_up;
        case 0xe8b6: return Icons.people;
        default: return Icons.group;
      }
    }
    return Icons.group;
  }

  Widget _buildMemberAvatarWithName(
    TeamMember member,
    String? avatarUrl,
    bool isSelected,
  ) {
    return SizedBox(
      width: 76,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: isSelected
                  ? Border.all(color: context.textPrimary, width: 2)
                  : Border.all(color: Colors.transparent),
            ),
            child: Stack(
              children: [
                _buildMemberAvatarWithTelegram(
                  member.fullName,
                  52,
                  avatarUrl ?? '',
                ),
                if (isSelected)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: const Color(0xFF30D158),
                        shape: BoxShape.circle,
                        border: Border.all(color: context.appBackground, width: 2),
                      ),
                      child: const Icon(
                        Icons.check,
                        color: Colors.white,
                        size: 10,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            member.fullName,
            style: GoogleFonts.inter(
              color: isSelected ? context.textPrimary : context.textSecondary,
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildMemberAvatarWithTelegram(
    String name,
    double size,
    String avatarUrl,
  ) {
    if (avatarUrl.startsWith('telegram:')) {
      final telegramFileId = TeamMemberService.getTelegramFileId(avatarUrl);
      if (telegramFileId != null) {
        return FutureBuilder<String>(
          future: TeamMemberService.getTelegramImageUrl(telegramFileId),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  color: context.cardBackground,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: context.borderColor,
                  ),
                ),
                child: Center(
                  child: SizedBox(
                    width: size * 0.3,
                    height: size * 0.3,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: context.textSecondary,
                    ),
                  ),
                ),
              );
            } else if (snapshot.hasError || !snapshot.hasData) {
              return AvatarWidget(
                name: name,
                size: size,
                imageUrl: null,
                fontSize: size * 0.4,
              );
            } else {
              return AvatarWidget(
                name: name,
                size: size,
                imageUrl: snapshot.data!,
                fontSize: size * 0.4,
              );
            }
          },
        );
      }
    }

    return AvatarWidget(
      name: name,
      size: size,
      imageUrl: avatarUrl.isNotEmpty && !avatarUrl.contains('ui-avatars.com')
          ? avatarUrl
          : null,
      fontSize: size * 0.4,
    );
  }

  // --- ATTACHMENT ZONE (Matches Add Expense exactly) ---
  Widget _buildAttachmentZone() {
    if (_attachmentFileId != null && _attachmentFileId!.isNotEmpty && _fileName == null) {
      // Existing attachment from firebase without a new file picked yet
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.cardBackground,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: const Color(0xFF30D158).withValues(alpha: 0.3),
          ),
        ),

        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF30D158).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.receipt,
                color: Color(0xFF30D158),
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Receipt attached",
                    style: GoogleFonts.inter(
                      color: const Color(0xFF30D158),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    "Stored in Telegram",
                    style: GoogleFonts.inter(
                      color: context.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: Icon(
                _isUploading ? Icons.hourglass_empty : Icons.close,
                color: context.textSecondary,
                size: 20,
              ),
              onPressed: _isUploading
                  ? null
                  : () async {
                      try {
                        setState(() => _isUploading = true);

                        final batch = FirebaseFirestore.instance.batch();
                        final expenseRef = FirebaseFirestore.instance
                            .collection('expenses')
                            .doc(widget.expenseId);
                            
                        batch.update(expenseRef, {
                          "AttachmentFileId": FieldValue.delete(),
                        });

                        await batch.commit();

                        if (mounted) {
                          _showMinimalToast("Attachment removed successfully");
                          setState(() {
                            _isUploading = false;
                            _attachmentFileId = null;
                            _fileName = null;
                          });
                        }
                      } catch (e) {
                        if (mounted) {
                          _showMinimalToast(
                            "Failed to remove attachment",
                            isError: true,
                          );
                          setState(() => _isUploading = false);
                        }
                      }
                    },
            ),
          ],
        ),
      );
    }

    // New attachment zone UI matching Add Expense
    return GestureDetector(
      onTap: _isUploading ? null : _showFilePicker,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.cardBackground,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _isUploading
                ? const Color(0xFF0A84FF).withValues(alpha: 0.3)
                : context.borderColor,
          ),
        ),
        child: Row(
          children: [
            if (_isUploading)
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  color: const Color(0xFF0A84FF),
                  strokeWidth: 2,
                ),
              )
            else
              Icon(
                _fileName != null
                    ? _getFileIcon(_fileName!)
                    : Icons.attach_file,
                color: context.textSecondary,
              ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _isUploading
                    ? "Uploading to Telegram..."
                    : _fileName ?? "Upload attachment (any file)",
                style: TextStyle(
                  color: _isUploading
                      ? const Color(0xFF0A84FF)
                      : context.textSecondary,
                  fontSize: _isUploading ? 12 : 14,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (_fileName != null && !_isUploading)
              IconButton(
                icon: const Icon(Icons.close, color: Colors.redAccent),
                onPressed: () {
                  setState(() {
                    _fileName = null;
                    _attachmentFileId = null;
                  });
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildUpdateButton() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: context.appBackground,
        border: Border(
          top: BorderSide(color: context.borderColor),
        ),
      ),
      child: SizedBox(
        width: double.infinity,
        height: 56,
        child: ElevatedButton(
          onPressed: _isLoading ? null : _updateExpense,
          style: ElevatedButton.styleFrom(
            backgroundColor: context.textPrimary,
            foregroundColor: context.appBackground,
            disabledBackgroundColor: context.textSecondary.withValues(alpha: 0.3),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          child: _isLoading
              ? SizedBox(
                  height: 24,
                  width: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: context.appBackground,
                  ),
                )
              : Text(
                  "Update Expense",
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildRecurringDetailsCard() {
    final Map<String, String> frequencies = {
      'daily': 'Daily',
      'weekly': 'Weekly',
      'monthly': 'Monthly',
      'yearly': 'Yearly',
    };

    return Container(
      margin: const EdgeInsets.only(top: 24),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.cardBackground, // Glassy background
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.repeat_on_outlined,
                color: Color(0xFF0A84FF),
                size: 20,
              ),
              const SizedBox(width: 10),
              Text(
                "RECURRENCE DETAILS",
                style: GoogleFonts.inter(
                  color: const Color(0xFF0A84FF),
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Frequency selector row & Ongoing switch row
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionLabel("FREQUENCY"),
                    const SizedBox(height: 8),
                    ShadSelect<String>(
                      placeholder: Text(
                        'Select Frequency',
                        style: GoogleFonts.inter(color: context.textSecondary, fontSize: 14),
                      ),
                      initialValue: _recurrenceFrequency,
                      options: [
                        ...frequencies.entries.map(
                          (e) => ShadOption(value: e.key, child: Text(e.value)),
                        ),
                      ],
                      selectedOptionBuilder: (context, value) => Text(
                        frequencies[value] ?? "Monthly",
                        style: GoogleFonts.inter(
                          color: context.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() {
                            _recurrenceFrequency = val;
                          });
                        }
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionLabel("ONGOING EXPENSE"),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Switch(
                          value: _isOngoing,
                          activeThumbColor: const Color(0xFF30D158),
                          activeTrackColor: const Color(0xFF30D158).withValues(alpha: 0.2),
                          inactiveThumbColor: context.textSecondary,
                          inactiveTrackColor: context.borderColor,
                          onChanged: (val) {
                            setState(() {
                              _isOngoing = val;
                            });
                          },
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _isOngoing ? "Ongoing" : "Fixed Term",
                          style: GoogleFonts.inter(
                            color: context.textSecondary,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),

          // If not ongoing, show tenure field
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 250),
            crossFadeState: !_isOngoing ? CrossFadeState.showFirst : CrossFadeState.showSecond,
            firstChild: Padding(
              padding: const EdgeInsets.only(top: 20),
              child: _buildRecurringInputField(
                label: "TENURE (MONTHS / OCCURRENCES)",
                placeholder: "e.g. 12",
                controller: _tenureController,
              ),
            ),
            secondChild: const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _buildRecurringInputField({
    required String label,
    required String placeholder,
    required TextEditingController controller,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionLabel(label),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          decoration: BoxDecoration(
            color: context.cardBackground,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: context.borderColor),
          ),
          child: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            style: GoogleFonts.inter(color: context.textPrimary, fontSize: 15),
            decoration: InputDecoration(
              hintText: placeholder,
              hintStyle: GoogleFonts.inter(color: context.textSecondary.withValues(alpha: 0.5), fontSize: 14),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
      ],
    );
  }
}