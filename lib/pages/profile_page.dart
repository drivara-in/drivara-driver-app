import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:drivara_driver_app/api_config.dart';
import 'package:drivara_driver_app/login_page.dart';
import 'package:drivara_driver_app/services/messaging_service.dart';
import 'package:drivara_driver_app/pages/loans_page.dart';

// Driver Profile screen — single place for:
//   • Driver basic info (avatar / name / phone)
//   • DL details (number, class, issue/expiry/state)
//   • Active vehicle's RC details (when the driver is on a job)
//   • A tile linking out to the existing Loans screen
//   • Logout (destructive, confirmation dialog)
// Replaces the bare Logout icon that used to live on the active-job toolbar
// and the full-width Logout button on the no-job page.

final _dateFmt = DateFormat('d MMM yyyy');

String _fmtDate(dynamic v) {
  if (v == null) return '—';
  try {
    return _dateFmt.format(DateTime.parse(v.toString()).toLocal());
  } catch (_) {
    return v.toString();
  }
}

/// Returns (label, color) reflecting how close `date` is to today.
({String label, Color color}) _expiryBadge(dynamic raw) {
  if (raw == null) return (label: '—', color: Colors.grey);
  DateTime? d;
  try {
    d = DateTime.parse(raw.toString()).toLocal();
  } catch (_) {
    return (label: '—', color: Colors.grey);
  }
  final today = DateTime.now();
  final days = d.difference(DateTime(today.year, today.month, today.day)).inDays;
  if (days < 0) return (label: 'EXPIRED', color: Colors.red.shade700);
  if (days <= 30) return (label: '$days days', color: Colors.orange.shade700);
  return (label: 'Valid', color: Colors.green.shade700);
}

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _profile;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await ApiConfig.dio.get('/driver/me/profile');
      setState(() {
        _profile = res.data is Map<String, dynamic>
            ? res.data as Map<String, dynamic>
            : <String, dynamic>{};
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Could not load profile. Pull to retry.';
        _loading = false;
      });
    }
  }

  Future<void> _confirmAndLogout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text("You'll need to enter your OTP again to sign back in."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red.shade700),
            child: const Text('Log out'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await MessagingService().unregisterOnLogout();
    } catch (_) { /* best-effort */ }
    await ApiConfig.logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: RefreshIndicator(
        onRefresh: _fetch,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? ListView(children: [Padding(padding: const EdgeInsets.all(24), child: Text(_error!))])
                : _profile == null
                    ? const Center(child: Text('No data'))
                    : _buildBody(context, _profile!),
      ),
    );
  }

  Widget _buildBody(BuildContext context, Map<String, dynamic> p) {
    final license = (p['license'] as Map?)?.cast<String, dynamic>() ?? const {};
    final vehicle = (p['active_vehicle'] as Map?)?.cast<String, dynamic>();
    final loans = (p['loans_summary'] as Map?)?.cast<String, dynamic>() ?? const {};
    final loanCount = (loans['active_count'] as num?)?.toInt() ?? 0;
    final loanOutstanding = (loans['outstanding_total'] as num?)?.toDouble() ?? 0;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _HeaderCard(profile: p),
        const SizedBox(height: 16),
        _SectionTitle('Driving Licence'),
        _LicenseCard(license: license),
        if (vehicle != null) ...[
          const SizedBox(height: 16),
          _SectionTitle('Vehicle (RC)'),
          _VehicleCard(vehicle: vehicle),
        ],
        if (loanCount > 0) ...[
          const SizedBox(height: 16),
          _SectionTitle('Loans'),
          _LoansSummaryCard(activeCount: loanCount, outstanding: loanOutstanding),
        ],
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _confirmAndLogout,
            icon: Icon(Icons.logout, color: Colors.red.shade700),
            label: Text('Log out', style: TextStyle(color: Colors.red.shade700, fontWeight: FontWeight.w600)),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              side: BorderSide(color: Colors.red.shade300),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
          color: Theme.of(context).textTheme.bodySmall?.color,
        ),
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  final Map<String, dynamic> profile;
  const _HeaderCard({required this.profile});

  @override
  Widget build(BuildContext context) {
    final name = (profile['name']?.toString() ?? 'Driver').trim();
    final phone = profile['phone']?.toString() ?? '';
    final avatarUrl = profile['avatar_url']?.toString();
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              radius: 32,
              backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.15),
              backgroundImage: (avatarUrl != null && avatarUrl.isNotEmpty)
                  ? NetworkImage(avatarUrl)
                  : null,
              child: (avatarUrl == null || avatarUrl.isEmpty)
                  ? Text(initial,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).colorScheme.primary,
                      ))
                  : null,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(phone, style: Theme.of(context).textTheme.bodyMedium),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LicenseCard extends StatelessWidget {
  final Map<String, dynamic> license;
  const _LicenseCard({required this.license});

  @override
  Widget build(BuildContext context) {
    final number = license['number']?.toString() ?? '—';
    final klass = license['class']?.toString() ?? '—';
    final issuedState = license['issued_state']?.toString() ?? '—';
    final isLearner = license['is_learner'] == true;
    final dob = license['dob'];
    final issueDate = license['issue_date'];
    final expiry = license['expiry'];
    final badge = _expiryBadge(expiry);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
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
                      Text(number,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                                fontFeatures: const [FontFeature.tabularFigures()],
                              )),
                      const SizedBox(height: 4),
                      Wrap(spacing: 8, runSpacing: 4, children: [
                        _chip(context, klass),
                        if (isLearner) _chip(context, 'LEARNER', color: Colors.orange),
                      ]),
                    ],
                  ),
                ),
                _expiryPill(badge),
              ],
            ),
            const Divider(height: 24),
            _kv(context, 'Expires', _fmtDate(expiry)),
            _kv(context, 'Issued', _fmtDate(issueDate)),
            _kv(context, 'State', issuedState),
            _kv(context, 'Date of birth', _fmtDate(dob)),
          ],
        ),
      ),
    );
  }
}

class _VehicleCard extends StatelessWidget {
  final Map<String, dynamic> vehicle;
  const _VehicleCard({required this.vehicle});

  @override
  Widget build(BuildContext context) {
    final reg = vehicle['registration_number']?.toString() ?? '—';
    final make = vehicle['make']?.toString();
    final model = vehicle['model']?.toString();
    final year = vehicle['model_year']?.toString();
    final klass = vehicle['vehicle_class']?.toString();
    final color = vehicle['color']?.toString();
    final tank = vehicle['fuel_tank_capacity'];
    final fuel = vehicle['fuel_type']?.toString();
    final owner = vehicle['owner_name']?.toString();
    final summaryParts = [make, model, year, klass].whereType<String>().where((s) => s.isNotEmpty);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(reg,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    )),
            if (summaryParts.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(summaryParts.join(' · '),
                    style: Theme.of(context).textTheme.bodyMedium),
              ),
            const SizedBox(height: 12),
            _expiryRow(context, 'RC', vehicle['rc_expiry']),
            _expiryRow(context, 'Insurance', vehicle['insurance_expiry']),
            _expiryRow(context, 'PUC', vehicle['pollution_certificate_expiry']),
            _expiryRow(context, 'National permit', vehicle['national_permit_expiry']),
            const Divider(height: 24),
            if (owner != null && owner.isNotEmpty) _kv(context, 'Owner', owner),
            if (color != null && color.isNotEmpty) _kv(context, 'Colour', color),
            if (fuel != null && fuel.isNotEmpty) _kv(context, 'Fuel', fuel),
            if (tank != null) _kv(context, 'Tank capacity', '${tank} L'),
            if (vehicle['permit_number'] != null && vehicle['permit_number'].toString().isNotEmpty)
              _kv(context, 'Permit number', vehicle['permit_number'].toString()),
            if (vehicle['insurance_company'] != null && vehicle['insurance_company'].toString().isNotEmpty)
              _kv(context, 'Insurer', vehicle['insurance_company'].toString()),
          ],
        ),
      ),
    );
  }
}

class _LoansSummaryCard extends StatelessWidget {
  final int activeCount;
  final double outstanding;
  const _LoansSummaryCard({required this.activeCount, required this.outstanding});

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
    return Card(
      child: ListTile(
        leading: const Icon(Icons.account_balance),
        title: Text('$activeCount active loan${activeCount == 1 ? '' : 's'}',
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text('Outstanding: ${currency.format(outstanding)}'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () {
          Navigator.push(context, MaterialPageRoute(builder: (_) => const LoansPage()));
        },
      ),
    );
  }
}

Widget _kv(BuildContext context, String label, String value) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 130,
          child: Text(label, style: Theme.of(context).textTheme.bodySmall),
        ),
        Expanded(
          child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
      ],
    ),
  );
}

Widget _expiryRow(BuildContext context, String label, dynamic raw) {
  final badge = _expiryBadge(raw);
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        SizedBox(
          width: 130,
          child: Text(label, style: Theme.of(context).textTheme.bodySmall),
        ),
        Expanded(
          child: Text(_fmtDate(raw), style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
        _expiryPill(badge),
      ],
    ),
  );
}

Widget _expiryPill(({String label, Color color}) badge) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: badge.color.withOpacity(0.12),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(
      badge.label,
      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: badge.color),
    ),
  );
}

Widget _chip(BuildContext context, String label, {Color? color}) {
  final c = color ?? Theme.of(context).colorScheme.primary;
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: c.withOpacity(0.10),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: c)),
  );
}
