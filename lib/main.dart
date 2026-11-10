import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String appName = 'GROUPEMENT FORESTIER KERSYLVA';
const String developerName = 'GROUPEMENT FORESTIER KERSYLVA';
const String supportEmail = 'support@kersylva.fr';
const bool screenshotMode = bool.fromEnvironment('SCREENSHOT_MODE');

const Color kForest = Color(0xFF0B2E22);
const Color kCanopy = Color(0xFF37533B);
const Color kMoss = Color(0xFF74815A);
const Color kGold = Color(0xFFC6B46D);
const Color kPaper = Color(0xFFF6F3E8);
const Color kInk = Color(0xFF18231D);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const KersylvaOpsApp());
}

class KersylvaOpsApp extends StatefulWidget {
  const KersylvaOpsApp({super.key});

  @override
  State<KersylvaOpsApp> createState() => _KersylvaOpsAppState();
}

class _KersylvaOpsAppState extends State<KersylvaOpsApp> {
  late final OperationsController _controller;

  @override
  void initState() {
    super.initState();
    _controller = OperationsController(screenshotMode: screenshotMode)..load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: kForest,
      brightness: Brightness.light,
      primary: kForest,
      secondary: kGold,
      tertiary: kCanopy,
      surface: Colors.white,
    );

    return OperationsScope(
      controller: _controller,
      child: MaterialApp(
        title: appName,
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: colorScheme,
          scaffoldBackgroundColor: kPaper,
          textTheme: ThemeData.light().textTheme.apply(
            bodyColor: kInk,
            displayColor: kInk,
          ),
          appBarTheme: const AppBarTheme(
            backgroundColor: kForest,
            foregroundColor: Colors.white,
            centerTitle: false,
            elevation: 0,
          ),
          cardTheme: CardThemeData(
            color: Colors.white,
            elevation: 0,
            margin: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(color: kForest.withValues(alpha: 0.08)),
            ),
          ),
          inputDecorationTheme: InputDecorationTheme(
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            filled: true,
            fillColor: Colors.white,
          ),
          navigationBarTheme: NavigationBarThemeData(
            backgroundColor: Colors.white,
            indicatorColor: kGold.withValues(alpha: 0.28),
            labelTextStyle: WidgetStateProperty.resolveWith((states) {
              final selected = states.contains(WidgetState.selected);
              return TextStyle(
                color: selected ? kForest : const Color(0xFF536156),
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                fontSize: 12,
              );
            }),
          ),
        ),
        home: const HomeShell(),
      ),
    );
  }
}

class OperationsScope extends InheritedNotifier<OperationsController> {
  const OperationsScope({
    required OperationsController controller,
    required super.child,
    super.key,
  }) : super(notifier: controller);

  static OperationsController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<OperationsScope>();
    assert(scope != null, 'OperationsScope is missing');
    return scope!.notifier!;
  }
}

class OperationsController extends ChangeNotifier {
  OperationsController({required this.screenshotMode});

  static const _expensesKey = 'expenses';
  static const _qualityKey = 'quality';
  static const _appointmentsKey = 'appointments';
  static const _settingsKey = 'settings';

  final bool screenshotMode;
  SharedPreferences? _preferences;
  bool isLoaded = false;
  bool compactCards = false;
  bool localPrivacyNoticeRead = false;
  List<Employee> employees = const [];
  List<ExpenseRecord> expenses = const [];
  List<QualityCheck> qualityChecks = const [];
  List<AppointmentRecord> appointments = const [];

  Future<void> load() async {
    employees = _seedEmployees();
    if (screenshotMode) {
      expenses = _seedExpenses();
      qualityChecks = _seedQuality();
      appointments = _seedAppointments();
      compactCards = false;
      localPrivacyNoticeRead = true;
      isLoaded = true;
      notifyListeners();
      return;
    }

    _preferences = await SharedPreferences.getInstance();
    expenses = _decodeList(
      _preferences!.getString(_expensesKey),
      ExpenseRecord.fromJson,
      _seedExpenses,
    );
    qualityChecks = _decodeList(
      _preferences!.getString(_qualityKey),
      QualityCheck.fromJson,
      _seedQuality,
    );
    appointments = _decodeList(
      _preferences!.getString(_appointmentsKey),
      AppointmentRecord.fromJson,
      _seedAppointments,
    );

    final settings = jsonDecode(_preferences!.getString(_settingsKey) ?? '{}');
    if (settings is Map<String, dynamic>) {
      compactCards = settings['compactCards'] == true;
      localPrivacyNoticeRead = settings['localPrivacyNoticeRead'] == true;
    }

    isLoaded = true;
    notifyListeners();
  }

  Future<void> addExpense({
    required String title,
    required double amount,
    required String category,
    required String notes,
  }) async {
    expenses = [
      ExpenseRecord(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        title: title,
        amount: amount,
        category: category,
        date: _shortDate(DateTime.now()),
        status: 'To review',
        notes: notes,
      ),
      ...expenses,
    ];
    await _saveRecords(_expensesKey, expenses.map((item) => item.toJson()));
    notifyListeners();
  }

  Future<void> approveExpense(String id) async {
    expenses = [
      for (final expense in expenses)
        if (expense.id == id) expense.copyWith(status: 'Approved') else expense,
    ];
    await _saveRecords(_expensesKey, expenses.map((item) => item.toJson()));
    notifyListeners();
  }

  Future<void> toggleQuality(String id, bool value) async {
    qualityChecks = [
      for (final check in qualityChecks)
        if (check.id == id) check.copyWith(done: value) else check,
    ];
    await _saveRecords(_qualityKey, qualityChecks.map((item) => item.toJson()));
    notifyListeners();
  }

  Future<void> addAppointment({
    required String visitor,
    required String purpose,
    required String date,
    required String time,
    required String owner,
  }) async {
    appointments = [
      AppointmentRecord(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        visitor: visitor,
        purpose: purpose,
        date: date,
        time: time,
        owner: owner,
        status: 'Booked',
      ),
      ...appointments,
    ];
    await _saveRecords(
      _appointmentsKey,
      appointments.map((item) => item.toJson()),
    );
    notifyListeners();
  }

  Future<void> toggleCompactCards(bool value) async {
    compactCards = value;
    await _saveSettings();
    notifyListeners();
  }

  Future<void> markPrivacyNoticeRead(bool value) async {
    localPrivacyNoticeRead = value;
    await _saveSettings();
    notifyListeners();
  }

  int get openQualityCount =>
      qualityChecks.where((check) => !check.done).length;

  double get pendingExpenseTotal => expenses
      .where((expense) => expense.status != 'Approved')
      .fold(0, (total, item) => total + item.amount);

  int get todaysAppointments => appointments.length;

  Future<void> _saveRecords(
    String key,
    Iterable<Map<String, dynamic>> records,
  ) async {
    if (screenshotMode) {
      return;
    }
    await _preferences?.setString(key, jsonEncode(records.toList()));
  }

  Future<void> _saveSettings() async {
    if (screenshotMode) {
      return;
    }
    await _preferences?.setString(
      _settingsKey,
      jsonEncode({
        'compactCards': compactCards,
        'localPrivacyNoticeRead': localPrivacyNoticeRead,
      }),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const _titles = [
    'Operations',
    'Directory',
    'Expenses',
    'Quality',
    'Appointments',
  ];

  void _selectTab(int index) {
    setState(() => _index = index);
  }

  @override
  Widget build(BuildContext context) {
    final controller = OperationsScope.of(context);

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            title: Text(_titles[_index]),
            actions: [
              IconButton(
                tooltip: 'Settings',
                icon: const Icon(Icons.settings_outlined),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const SettingsScreen(),
                    ),
                  );
                },
              ),
            ],
          ),
          body: controller.isLoaded
              ? IndexedStack(
                  index: _index,
                  children: [
                    OverviewScreen(onOpenTab: _selectTab),
                    const DirectoryScreen(),
                    const ExpensesScreen(),
                    const QualityScreen(),
                    const AppointmentsScreen(),
                  ],
                )
              : const Center(child: CircularProgressIndicator()),
          floatingActionButton: _buildActionButton(context, controller),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: _selectTab,
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.dashboard_outlined),
                selectedIcon: Icon(Icons.dashboard),
                label: 'Home',
              ),
              NavigationDestination(
                icon: Icon(Icons.badge_outlined),
                selectedIcon: Icon(Icons.badge),
                label: 'Team',
              ),
              NavigationDestination(
                icon: Icon(Icons.receipt_long_outlined),
                selectedIcon: Icon(Icons.receipt_long),
                label: 'Spend',
              ),
              NavigationDestination(
                icon: Icon(Icons.task_alt_outlined),
                selectedIcon: Icon(Icons.task_alt),
                label: 'Quality',
              ),
              NavigationDestination(
                icon: Icon(Icons.event_available_outlined),
                selectedIcon: Icon(Icons.event_available),
                label: 'Agenda',
              ),
            ],
          ),
        );
      },
    );
  }

  Widget? _buildActionButton(
    BuildContext context,
    OperationsController controller,
  ) {
    if (!controller.isLoaded) {
      return null;
    }
    if (_index == 2) {
      return FloatingActionButton.extended(
        heroTag: 'expense-action',
        onPressed: () => _showExpenseSheet(context),
        icon: const Icon(Icons.add_card_outlined),
        label: const Text('Expense'),
      );
    }
    if (_index == 4) {
      return FloatingActionButton.extended(
        heroTag: 'appointment-action',
        onPressed: () => _showAppointmentSheet(context),
        icon: const Icon(Icons.add_task_outlined),
        label: const Text('Book'),
      );
    }
    return null;
  }

  Future<void> _showExpenseSheet(BuildContext context) async {
    final controller = OperationsScope.of(context);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => AddExpenseSheet(controller: controller),
    );
  }

  Future<void> _showAppointmentSheet(BuildContext context) async {
    final controller = OperationsScope.of(context);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => AddAppointmentSheet(controller: controller),
    );
  }
}

class OverviewScreen extends StatelessWidget {
  const OverviewScreen({required this.onOpenTab, super.key});

  final ValueChanged<int> onOpenTab;

  @override
  Widget build(BuildContext context) {
    final controller = OperationsScope.of(context);
    final nextAppointment = controller.appointments.isEmpty
        ? null
        : controller.appointments.first;

    return AppScrollView(
      children: [
        const BrandHeader(),
        MetricGrid(
          metrics: [
            MetricData(
              label: 'Employees',
              value: '${controller.employees.length}',
              icon: Icons.groups_2_outlined,
              tone: kForest,
            ),
            MetricData(
              label: 'Pending spend',
              value: '${controller.pendingExpenseTotal.toStringAsFixed(0)} EUR',
              icon: Icons.account_balance_wallet_outlined,
              tone: const Color(0xFF725E21),
            ),
            MetricData(
              label: 'Open checks',
              value: '${controller.openQualityCount}',
              icon: Icons.fact_check_outlined,
              tone: const Color(0xFF496B3C),
            ),
            MetricData(
              label: 'Appointments',
              value: '${controller.todaysAppointments}',
              icon: Icons.event_note_outlined,
              tone: const Color(0xFF244F5A),
            ),
          ],
        ),
        SectionTitle(
          title: 'GROUPEMENT FORESTIER KERSYLVA',
          actionLabel: 'Quality board',
          onAction: () => onOpenTab(3),
        ),
        InfoCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const RowLabel(
                icon: Icons.park_outlined,
                label: 'Site coordination',
              ),
              const SizedBox(height: 10),
              Text(
                'Morning patrols, supplier invoices, and visitor slots are grouped for quick review before field teams leave the yard.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  StatusChip(
                    label: '${controller.openQualityCount} checks open',
                    color: kCanopy,
                  ),
                  StatusChip(
                    label: '${controller.expenses.length} expense lines',
                    color: const Color(0xFF725E21),
                  ),
                  StatusChip(
                    label: 'Local storage only',
                    color: const Color(0xFF244F5A),
                  ),
                ],
              ),
            ],
          ),
        ),
        SectionTitle(
          title: 'Next booking',
          actionLabel: 'Agenda',
          onAction: () => onOpenTab(4),
        ),
        if (nextAppointment != null)
          AppointmentTile(appointment: nextAppointment)
        else
          const EmptyState(
            icon: Icons.event_busy_outlined,
            title: 'No appointment booked',
            body: 'Use the agenda tab to add a visitor or supplier slot.',
          ),
        SectionTitle(
          title: 'Quick actions',
          actionLabel: 'Directory',
          onAction: () => onOpenTab(1),
        ),
        ActionGrid(
          actions: [
            QuickActionData(
              icon: Icons.badge_outlined,
              title: 'Find employee',
              body: 'Check role, location, and contact notes.',
              onTap: () => onOpenTab(1),
            ),
            QuickActionData(
              icon: Icons.add_card_outlined,
              title: 'Log expense',
              body: 'Record fuel, tools, or supplier costs.',
              onTap: () => onOpenTab(2),
            ),
          ],
        ),
      ],
    );
  }
}

class DirectoryScreen extends StatefulWidget {
  const DirectoryScreen({super.key});

  @override
  State<DirectoryScreen> createState() => _DirectoryScreenState();
}

class _DirectoryScreenState extends State<DirectoryScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = OperationsScope.of(context);
    final employees = controller.employees.where((employee) {
      final text = '${employee.name} ${employee.role} ${employee.location}'
          .toLowerCase();
      return text.contains(_query.toLowerCase());
    }).toList();

    return AppScrollView(
      children: [
        TextField(
          controller: _searchController,
          decoration: const InputDecoration(
            hintText: 'Search name, role, or site',
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: (value) => setState(() => _query = value),
        ),
        const SizedBox(height: 16),
        SectionTitle(title: 'Employee directory (${employees.length})'),
        for (final employee in employees) EmployeeTile(employee: employee),
      ],
    );
  }
}

class ExpensesScreen extends StatelessWidget {
  const ExpensesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = OperationsScope.of(context);

    return AppScrollView(
      bottomPadding: 96,
      children: [
        SectionTitle(title: 'Expense register'),
        InfoCard(
          child: Row(
            children: [
              const Icon(Icons.summarize_outlined, color: kForest),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '${controller.expenses.length} records kept on this device. Pending total is ${controller.pendingExpenseTotal.toStringAsFixed(2)} EUR.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (controller.expenses.isEmpty)
          const EmptyState(
            icon: Icons.receipt_long_outlined,
            title: 'No expenses yet',
            body: 'Add fuel, tooling, supplier, or travel costs locally.',
          )
        else
          for (final expense in controller.expenses)
            ExpenseTile(expense: expense),
      ],
    );
  }
}

class QualityScreen extends StatelessWidget {
  const QualityScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = OperationsScope.of(context);
    final completed = controller.qualityChecks
        .where((check) => check.done)
        .length;
    final total = controller.qualityChecks.length;

    return AppScrollView(
      children: [
        SectionTitle(title: 'Quality control checklist'),
        InfoCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '$completed of $total controls complete',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Text(
                    '${((completed / total) * 100).round()}%',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: kForest,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: completed / total,
                color: kCanopy,
                backgroundColor: kCanopy.withValues(alpha: 0.12),
                minHeight: 8,
                borderRadius: BorderRadius.circular(8),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        for (final check in controller.qualityChecks)
          QualityTile(check: check, controller: controller),
      ],
    );
  }
}

class AppointmentsScreen extends StatelessWidget {
  const AppointmentsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = OperationsScope.of(context);

    return AppScrollView(
      bottomPadding: 96,
      children: [
        SectionTitle(title: 'Appointment booking'),
        InfoCard(
          child: Row(
            children: [
              const Icon(Icons.lock_clock_outlined, color: kForest),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Plan visitor, client, and supplier slots without accounts, cloud sync, or calendar permissions.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (controller.appointments.isEmpty)
          const EmptyState(
            icon: Icons.event_available_outlined,
            title: 'No appointments yet',
            body: 'Book a visit with purpose, owner, date, and time.',
          )
        else
          for (final appointment in controller.appointments)
            AppointmentTile(appointment: appointment),
      ],
    );
  }
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = OperationsScope.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings & privacy')),
      body: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          return AppScrollView(
            children: [
              SectionTitle(title: 'Device workspace'),
              InfoCard(
                child: Column(
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Compact cards'),
                      subtitle: const Text(
                        'Use denser lists during field review.',
                      ),
                      value: controller.compactCards,
                      onChanged: controller.toggleCompactCards,
                    ),
                    const Divider(height: 20),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Privacy note reviewed'),
                      subtitle: const Text(
                        'Records remain in local app storage on this phone.',
                      ),
                      value: controller.localPrivacyNoticeRead,
                      onChanged: controller.markPrivacyNoticeRead,
                    ),
                  ],
                ),
              ),
              SectionTitle(title: 'Privacy'),
              InfoCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const RowLabel(
                      icon: Icons.shield_outlined,
                      label: 'No account or cloud sync',
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '$appName stores expenses, quality checks, appointments, and preferences on this device only. It does not collect analytics, location, contacts, photos, microphone input, payment information, or health data.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 14),
                    SelectableText(
                      'Support: $supportEmail',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: kForest,
                      ),
                    ),
                  ],
                ),
              ),
              SectionTitle(title: 'Local counts'),
              InfoCard(
                child: Column(
                  children: [
                    CountRow(
                      label: 'Expense records',
                      value: '${controller.expenses.length}',
                    ),
                    CountRow(
                      label: 'Quality checks',
                      value: '${controller.qualityChecks.length}',
                    ),
                    CountRow(
                      label: 'Appointments',
                      value: '${controller.appointments.length}',
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class BrandHeader extends StatelessWidget {
  const BrandHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: kForest,
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Image.asset(
            'docs/featured.png',
            height: 138,
            width: double.infinity,
            fit: BoxFit.cover,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  appName,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Daily coordination for people, costs, quality, and bookings.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.88),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class EmployeeTile extends StatelessWidget {
  const EmployeeTile({required this.employee, super.key});

  final Employee employee;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InfoCard(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => EmployeeDetailScreen(employee: employee),
            ),
          );
        },
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: kGold.withValues(alpha: 0.32),
              foregroundColor: kForest,
              child: Text(employee.initials),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    employee.name,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text('${employee.role} - ${employee.location}'),
                ],
              ),
            ),
            StatusChip(label: employee.status, color: kCanopy),
          ],
        ),
      ),
    );
  }
}

class EmployeeDetailScreen extends StatelessWidget {
  const EmployeeDetailScreen({required this.employee, super.key});

  final Employee employee;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Employee detail')),
      body: AppScrollView(
        children: [
          InfoCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: kGold.withValues(alpha: 0.32),
                      foregroundColor: kForest,
                      child: Text(employee.initials),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            employee.name,
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w900),
                          ),
                          Text(employee.role),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                CountRow(label: 'Location', value: employee.location),
                CountRow(label: 'Phone note', value: employee.phone),
                CountRow(label: 'Email note', value: employee.email),
                CountRow(label: 'Availability', value: employee.status),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ExpenseTile extends StatelessWidget {
  const ExpenseTile({required this.expense, super.key});

  final ExpenseRecord expense;

  @override
  Widget build(BuildContext context) {
    final controller = OperationsScope.of(context);
    final approved = expense.status == 'Approved';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InfoCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        expense.title,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 2),
                      Text('${expense.category} - ${expense.date}'),
                    ],
                  ),
                ),
                Text(
                  '${expense.amount.toStringAsFixed(2)} EUR',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: kForest,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            if (expense.notes.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(expense.notes),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                StatusChip(
                  label: expense.status,
                  color: approved ? kCanopy : const Color(0xFF8B6F22),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: approved
                      ? null
                      : () => controller.approveExpense(expense.id),
                  icon: const Icon(Icons.verified_outlined),
                  label: const Text('Approve'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class QualityTile extends StatelessWidget {
  const QualityTile({required this.check, required this.controller, super.key});

  final QualityCheck check;
  final OperationsController controller;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InfoCard(
        child: CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: check.done,
          onChanged: (value) =>
              controller.toggleQuality(check.id, value ?? false),
          title: Text(
            check.title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                StatusChip(label: check.area, color: kForest),
                StatusChip(label: check.due, color: const Color(0xFF244F5A)),
                StatusChip(
                  label: check.severity,
                  color: const Color(0xFF8B4E22),
                ),
              ],
            ),
          ),
          controlAffinity: ListTileControlAffinity.leading,
        ),
      ),
    );
  }
}

class AppointmentTile extends StatelessWidget {
  const AppointmentTile({required this.appointment, super.key});

  final AppointmentRecord appointment;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InfoCard(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: kForest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.schedule, color: Colors.white, size: 18),
                  Text(
                    appointment.time,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    appointment.visitor,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(appointment.purpose),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      StatusChip(label: appointment.date, color: kCanopy),
                      StatusChip(label: appointment.owner, color: kForest),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AddExpenseSheet extends StatefulWidget {
  const AddExpenseSheet({required this.controller, super.key});

  final OperationsController controller;

  @override
  State<AddExpenseSheet> createState() => _AddExpenseSheetState();
}

class _AddExpenseSheetState extends State<AddExpenseSheet> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _amountController = TextEditingController();
  final _notesController = TextEditingController();
  String _category = 'Fuel';

  @override
  void dispose() {
    _titleController.dispose();
    _amountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'New expense',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(labelText: 'Expense title'),
                textInputAction: TextInputAction.next,
                validator: (value) =>
                    value == null || value.trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _amountController,
                decoration: const InputDecoration(labelText: 'Amount EUR'),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                textInputAction: TextInputAction.next,
                validator: (value) {
                  final amount = double.tryParse(
                    value?.replaceAll(',', '.') ?? '',
                  );
                  return amount == null || amount <= 0
                      ? 'Enter an amount'
                      : null;
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _category,
                decoration: const InputDecoration(labelText: 'Category'),
                items: const [
                  DropdownMenuItem(value: 'Fuel', child: Text('Fuel')),
                  DropdownMenuItem(value: 'Tools', child: Text('Tools')),
                  DropdownMenuItem(value: 'Supplier', child: Text('Supplier')),
                  DropdownMenuItem(value: 'Travel', child: Text('Travel')),
                ],
                onChanged: (value) =>
                    setState(() => _category = value ?? 'Fuel'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _notesController,
                decoration: const InputDecoration(labelText: 'Notes'),
                maxLines: 2,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.save_outlined),
                label: const Text('Save expense'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    await widget.controller.addExpense(
      title: _titleController.text.trim(),
      amount: double.parse(_amountController.text.replaceAll(',', '.')),
      category: _category,
      notes: _notesController.text.trim(),
    );
    if (mounted) {
      Navigator.of(context).pop();
    }
  }
}

class AddAppointmentSheet extends StatefulWidget {
  const AddAppointmentSheet({required this.controller, super.key});

  final OperationsController controller;

  @override
  State<AddAppointmentSheet> createState() => _AddAppointmentSheetState();
}

class _AddAppointmentSheetState extends State<AddAppointmentSheet> {
  final _formKey = GlobalKey<FormState>();
  final _visitorController = TextEditingController();
  final _purposeController = TextEditingController();
  final _dateController = TextEditingController(text: 'May 13');
  final _timeController = TextEditingController(text: '09:30');
  String _owner = 'Operations';

  @override
  void dispose() {
    _visitorController.dispose();
    _purposeController.dispose();
    _dateController.dispose();
    _timeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Book appointment',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _visitorController,
                decoration: const InputDecoration(
                  labelText: 'Visitor or company',
                ),
                textInputAction: TextInputAction.next,
                validator: (value) =>
                    value == null || value.trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _purposeController,
                decoration: const InputDecoration(labelText: 'Purpose'),
                textInputAction: TextInputAction.next,
                validator: (value) =>
                    value == null || value.trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _dateController,
                      decoration: const InputDecoration(labelText: 'Date'),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                          ? 'Required'
                          : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _timeController,
                      decoration: const InputDecoration(labelText: 'Time'),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                          ? 'Required'
                          : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _owner,
                decoration: const InputDecoration(labelText: 'Owner'),
                items: const [
                  DropdownMenuItem(
                    value: 'Operations',
                    child: Text('Operations'),
                  ),
                  DropdownMenuItem(value: 'Finance', child: Text('Finance')),
                  DropdownMenuItem(value: 'Quality', child: Text('Quality')),
                  DropdownMenuItem(
                    value: 'Direction',
                    child: Text('Direction'),
                  ),
                ],
                onChanged: (value) =>
                    setState(() => _owner = value ?? 'Operations'),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.event_available_outlined),
                label: const Text('Save booking'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    await widget.controller.addAppointment(
      visitor: _visitorController.text.trim(),
      purpose: _purposeController.text.trim(),
      date: _dateController.text.trim(),
      time: _timeController.text.trim(),
      owner: _owner,
    );
    if (mounted) {
      Navigator.of(context).pop();
    }
  }
}

class AppScrollView extends StatelessWidget {
  const AppScrollView({
    required this.children,
    this.bottomPadding = 24,
    super.key,
  });

  final List<Widget> children;
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: EdgeInsets.fromLTRB(16, 16, 16, bottomPadding),
        children: children,
      ),
    );
  }
}

class InfoCard extends StatelessWidget {
  const InfoCard({required this.child, this.onTap, super.key});

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(padding: const EdgeInsets.all(14), child: child),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle({
    required this.title,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
          ),
          if (actionLabel != null && onAction != null)
            TextButton(onPressed: onAction, child: Text(actionLabel!)),
        ],
      ),
    );
  }
}

class MetricGrid extends StatelessWidget {
  const MetricGrid({required this.metrics, super.key});

  final List<MetricData> metrics;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.only(top: 14),
      itemCount: metrics.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 1.42,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemBuilder: (context, index) {
        final metric = metrics[index];
        return InfoCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(metric.icon, color: metric.tone),
              const Spacer(),
              Text(
                metric.value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: metric.tone,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 2),
              Text(metric.label, maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ),
        );
      },
    );
  }
}

class ActionGrid extends StatelessWidget {
  const ActionGrid({required this.actions, super.key});

  final List<QuickActionData> actions;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final action in actions) ...[
          Expanded(
            child: InfoCard(
              onTap: action.onTap,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(action.icon, color: kForest),
                  const SizedBox(height: 12),
                  Text(
                    action.title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(action.body),
                ],
              ),
            ),
          ),
          if (action != actions.last) const SizedBox(width: 10),
        ],
      ],
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    required this.icon,
    required this.title,
    required this.body,
    super.key,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return InfoCard(
      child: Column(
        children: [
          Icon(icon, color: kForest, size: 36),
          const SizedBox(height: 10),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          Text(body, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

class RowLabel extends StatelessWidget {
  const RowLabel({required this.icon, required this.label, super.key});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: kForest),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
      ],
    );
  }
}

class StatusChip extends StatelessWidget {
  const StatusChip({required this.label, required this.color, super.key});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w800,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

class CountRow extends StatelessWidget {
  const CountRow({required this.label, required this.value, super.key});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

class MetricData {
  const MetricData({
    required this.label,
    required this.value,
    required this.icon,
    required this.tone,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color tone;
}

class QuickActionData {
  const QuickActionData({
    required this.icon,
    required this.title,
    required this.body,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String body;
  final VoidCallback onTap;
}

class Employee {
  const Employee({
    required this.id,
    required this.name,
    required this.role,
    required this.location,
    required this.phone,
    required this.email,
    required this.status,
  });

  final String id;
  final String name;
  final String role;
  final String location;
  final String phone;
  final String email;
  final String status;

  String get initials {
    final parts = name.split(' ').where((part) => part.isNotEmpty).toList();
    if (parts.length == 1) {
      return parts.first.characters.first.toUpperCase();
    }
    return '${parts.first.characters.first}${parts.last.characters.first}'
        .toUpperCase();
  }
}

class ExpenseRecord {
  const ExpenseRecord({
    required this.id,
    required this.title,
    required this.amount,
    required this.category,
    required this.date,
    required this.status,
    required this.notes,
  });

  final String id;
  final String title;
  final double amount;
  final String category;
  final String date;
  final String status;
  final String notes;

  ExpenseRecord copyWith({String? status}) {
    return ExpenseRecord(
      id: id,
      title: title,
      amount: amount,
      category: category,
      date: date,
      status: status ?? this.status,
      notes: notes,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'amount': amount,
    'category': category,
    'date': date,
    'status': status,
    'notes': notes,
  };

  static ExpenseRecord fromJson(Map<String, dynamic> json) {
    return ExpenseRecord(
      id: json['id'] as String,
      title: json['title'] as String,
      amount: (json['amount'] as num).toDouble(),
      category: json['category'] as String,
      date: json['date'] as String,
      status: json['status'] as String,
      notes: json['notes'] as String? ?? '',
    );
  }
}

class QualityCheck {
  const QualityCheck({
    required this.id,
    required this.title,
    required this.area,
    required this.due,
    required this.severity,
    required this.done,
  });

  final String id;
  final String title;
  final String area;
  final String due;
  final String severity;
  final bool done;

  QualityCheck copyWith({bool? done}) {
    return QualityCheck(
      id: id,
      title: title,
      area: area,
      due: due,
      severity: severity,
      done: done ?? this.done,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'area': area,
    'due': due,
    'severity': severity,
    'done': done,
  };

  static QualityCheck fromJson(Map<String, dynamic> json) {
    return QualityCheck(
      id: json['id'] as String,
      title: json['title'] as String,
      area: json['area'] as String,
      due: json['due'] as String,
      severity: json['severity'] as String,
      done: json['done'] == true,
    );
  }
}

class AppointmentRecord {
  const AppointmentRecord({
    required this.id,
    required this.visitor,
    required this.purpose,
    required this.date,
    required this.time,
    required this.owner,
    required this.status,
  });

  final String id;
  final String visitor;
  final String purpose;
  final String date;
  final String time;
  final String owner;
  final String status;

  Map<String, dynamic> toJson() => {
    'id': id,
    'visitor': visitor,
    'purpose': purpose,
    'date': date,
    'time': time,
    'owner': owner,
    'status': status,
  };

  static AppointmentRecord fromJson(Map<String, dynamic> json) {
    return AppointmentRecord(
      id: json['id'] as String,
      visitor: json['visitor'] as String,
      purpose: json['purpose'] as String,
      date: json['date'] as String,
      time: json['time'] as String,
      owner: json['owner'] as String,
      status: json['status'] as String,
    );
  }
}

List<T> _decodeList<T>(
  String? source,
  T Function(Map<String, dynamic>) fromJson,
  List<T> Function() fallback,
) {
  if (source == null || source.isEmpty) {
    return fallback();
  }
  try {
    final decoded = jsonDecode(source);
    if (decoded is! List) {
      return fallback();
    }
    return [
      for (final item in decoded)
        if (item is Map<String, dynamic>) fromJson(item),
    ];
  } on FormatException {
    return fallback();
  }
}

String _shortDate(DateTime date) {
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
  return '${months[date.month - 1]} ${date.day}';
}

List<Employee> _seedEmployees() => const [
  Employee(
    id: 'emp-1',
    name: 'Claire Martin',
    role: 'Operations lead',
    location: 'Forest office',
    phone: 'Internal extension 101',
    email: 'claire.martin@local',
    status: 'On site',
  ),
  Employee(
    id: 'emp-2',
    name: 'Nicolas Peron',
    role: 'Quality inspector',
    location: 'North parcel',
    phone: 'Internal extension 118',
    email: 'nicolas.peron@local',
    status: 'Field round',
  ),
  Employee(
    id: 'emp-3',
    name: 'Amelie Robert',
    role: 'Finance assistant',
    location: 'Main office',
    phone: 'Internal extension 127',
    email: 'amelie.robert@local',
    status: 'Available',
  ),
  Employee(
    id: 'emp-4',
    name: 'Marc Legrand',
    role: 'Supplier coordinator',
    location: 'Log yard',
    phone: 'Internal extension 133',
    email: 'marc.legrand@local',
    status: 'Receiving',
  ),
];

List<ExpenseRecord> _seedExpenses() => const [
  ExpenseRecord(
    id: 'exp-1',
    title: 'Chainsaw maintenance kit',
    amount: 184.30,
    category: 'Tools',
    date: 'May 12',
    status: 'To review',
    notes: 'Replacement chains and oil for parcel team.',
  ),
  ExpenseRecord(
    id: 'exp-2',
    title: 'Truck fuel top-up',
    amount: 96.80,
    category: 'Fuel',
    date: 'May 11',
    status: 'Approved',
    notes: 'Log yard vehicle route.',
  ),
  ExpenseRecord(
    id: 'exp-3',
    title: 'Protective gloves order',
    amount: 72.00,
    category: 'Supplier',
    date: 'May 10',
    status: 'To review',
    notes: 'Crew stock refill.',
  ),
];

List<QualityCheck> _seedQuality() => const [
  QualityCheck(
    id: 'qc-1',
    title: 'Verify safety signage at north access',
    area: 'Access',
    due: 'Today',
    severity: 'High',
    done: false,
  ),
  QualityCheck(
    id: 'qc-2',
    title: 'Confirm moisture sheet for stored timber',
    area: 'Stock',
    due: 'Today',
    severity: 'Medium',
    done: true,
  ),
  QualityCheck(
    id: 'qc-3',
    title: 'Review tool return station',
    area: 'Workshop',
    due: 'Tomorrow',
    severity: 'Medium',
    done: false,
  ),
  QualityCheck(
    id: 'qc-4',
    title: 'Inspect visitor log completeness',
    area: 'Office',
    due: 'Friday',
    severity: 'Low',
    done: false,
  ),
];

List<AppointmentRecord> _seedAppointments() => const [
  AppointmentRecord(
    id: 'apt-1',
    visitor: 'Durand Supplies',
    purpose: 'Equipment delivery review',
    date: 'May 12',
    time: '10:30',
    owner: 'Operations',
    status: 'Booked',
  ),
  AppointmentRecord(
    id: 'apt-2',
    visitor: 'Regional forestry auditor',
    purpose: 'Quality walkthrough',
    date: 'May 12',
    time: '14:00',
    owner: 'Quality',
    status: 'Booked',
  ),
  AppointmentRecord(
    id: 'apt-3',
    visitor: 'Maintenance contractor',
    purpose: 'Yard gate service',
    date: 'May 13',
    time: '09:00',
    owner: 'Direction',
    status: 'Booked',
  ),
];
