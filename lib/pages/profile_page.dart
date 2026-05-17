import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:drivara_driver_app/api_config.dart';
import 'package:drivara_driver_app/login_page.dart';
import 'package:drivara_driver_app/services/messaging_service.dart';
import 'package:drivara_driver_app/pages/loans_page.dart';

// Driver Profile — single place for the driver's licence, the vehicle on
// their currently-active job (RC), a Loans tile, and a destructive Logout.
//
// DL and RC are drawn as facsimile cards in the same visual style the web
// admin uses (client/src/components/DriverDLCard.tsx + VehicleRCCard.tsx):
//   • DL  — amber/cream gradient, blue header band, IN emblem, photo,
//           DL number, name, DOB, DOI, COV, blood group, address, validity.
//   • RC  — blue gradient, blue header band, IN emblem, reg number,
//           owner, make/model/colour, class/body/GVW, engine + chassis,
//           validity rows (RC / Insurance / PUC / Permit / Tax).
// Each card flips its status pill to red INACTIVE when any tracked date
// has expired, mirroring the web's logic.

final _fmtDateDdMmYyyy = DateFormat('dd/MM/yyyy');

String? _fmtDate(dynamic raw) {
  if (raw == null) return null;
  try { return _fmtDateDdMmYyyy.format(DateTime.parse(raw.toString()).toLocal()); } catch (_) { return raw.toString(); }
}

bool _isExpired(dynamic raw) {
  if (raw == null) return false;
  try { return DateTime.parse(raw.toString()).toLocal().isBefore(DateTime.now()); } catch (_) { return false; }
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
    try { await MessagingService().unregisterOnLogout(); } catch (_) {}
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
    final license = (p['license'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
    final vehicle = (p['active_vehicle'] as Map?)?.cast<String, dynamic>();
    final loans = (p['loans_summary'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
    final loanCount = (loans['active_count'] as num?)?.toInt() ?? 0;
    final loanOutstanding = (loans['outstanding_total'] as num?)?.toDouble() ?? 0;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _ProfileHeader(profile: p),
        const SizedBox(height: 16),
        Center(child: _DLCard(profile: p, license: license)),
        if (vehicle != null) ...[
          const SizedBox(height: 16),
          Center(child: _RCCard(vehicle: vehicle)),
        ],
        if (loanCount > 0) ...[
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              leading: const Icon(Icons.account_balance),
              title: Text('$loanCount active loan${loanCount == 1 ? '' : 's'}',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(
                'Outstanding: ${NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0).format(loanOutstanding)}',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LoansPage())),
            ),
          ),
        ],
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _confirmAndLogout,
            icon: Icon(Icons.logout, color: Colors.red.shade700),
            label: Text('Log out',
                style: TextStyle(color: Colors.red.shade700, fontWeight: FontWeight.w600)),
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

class _ProfileHeader extends StatelessWidget {
  final Map<String, dynamic> profile;
  const _ProfileHeader({required this.profile});

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
            _AvatarCircle(url: avatarUrl, initials: initial, size: 64),
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

class _AvatarCircle extends StatelessWidget {
  final String? url;
  final String initials;
  final double size;
  const _AvatarCircle({required this.url, required this.initials, required this.size});

  @override
  Widget build(BuildContext context) {
    final bg = Theme.of(context).colorScheme.primary.withOpacity(0.15);
    final fg = Theme.of(context).colorScheme.primary;
    final fallback = Container(
      width: size, height: size,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Text(initials, style: TextStyle(fontSize: size / 2.7, fontWeight: FontWeight.w700, color: fg)),
    );
    if (url == null || url!.isEmpty) return fallback;
    return ClipOval(
      child: SizedBox(
        width: size, height: size,
        child: Image.network(
          url!,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => fallback,
        ),
      ),
    );
  }
}

// ── DL card ────────────────────────────────────────────────────────────

class _DLCard extends StatelessWidget {
  final Map<String, dynamic> profile;
  final Map<String, dynamic> license;
  const _DLCard({required this.profile, required this.license});

  @override
  Widget build(BuildContext context) {
    final name = profile['name']?.toString() ?? '';
    final phone = profile['phone']?.toString();
    final avatarUrl = profile['avatar_url']?.toString();
    final initials = name.isNotEmpty ? name.trim().split(RegExp(r'\s+')).take(2).map((w) => w[0]).join().toUpperCase() : '?';

    final dlNo = license['number']?.toString();
    final klass = license['class']?.toString();
    final issuedState = license['issued_state']?.toString();
    final isLearner = license['is_learner'] == true;
    final dob = license['dob'];
    final doi = license['issue_date'];
    final expiry = license['expiry'];
    final transExpiry = license['transport_doe'];
    final fatherName = license['father_or_husband_name']?.toString();
    final blood = license['blood_group']?.toString();
    final badge = license['badge_number']?.toString();
    final address = license['address']?.toString();
    final state = license['state']?.toString();

    final anyExpired = _isExpired(expiry) || _isExpired(transExpiry);
    final activeStatus = !anyExpired;

    return Container(
      width: 340,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFDF6E3), Color(0xFFF5E6C8)],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFCD34D).withOpacity(0.6)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.20), blurRadius: 20, offset: const Offset(0, 8)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header band
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [Color(0xFF1E40AF), Color(0xFF1E3A8A)]),
            ),
            child: Row(
              children: [
                Container(
                  width: 18, height: 18,
                  decoration: const BoxDecoration(color: Color(0xFFFBBF24), shape: BoxShape.circle),
                  alignment: Alignment.center,
                  child: const Text('IN', style: TextStyle(fontSize: 7, fontWeight: FontWeight.w900, color: Color(0xFF1E3A8A))),
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('DRIVING LICENCE',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 11, letterSpacing: 1.0)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: activeStatus ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(activeStatus ? 'ACTIVE' : 'INACTIVE',
                      style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800)),
                ),
              ],
            ),
          ),
          // Photo + main details
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: SizedBox(
                    width: 64, height: 78,
                    child: (avatarUrl != null && avatarUrl.isNotEmpty)
                        ? Image.network(
                            avatarUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _photoFallback(initials),
                          )
                        : _photoFallback(initials),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (dlNo != null && dlNo.isNotEmpty || blood != null && blood.isNotEmpty)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (dlNo != null && dlNo.isNotEmpty)
                              Expanded(child: _miniField('DL No.', dlNo, bold: true)),
                            if (blood != null && blood.isNotEmpty)
                              Container(
                                margin: const EdgeInsets.only(top: 2),
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFDC2626),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(blood,
                                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)),
                              ),
                          ],
                        ),
                      const SizedBox(height: 4),
                      _miniField('Name', name),
                      if (isLearner)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF59E0B).withOpacity(0.20),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text('LEARNER',
                                style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Color(0xFFB45309))),
                          ),
                        ),
                      if (fatherName != null && fatherName.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: _miniField('S/W/D of', fatherName),
                        ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          if (dob != null) Padding(padding: const EdgeInsets.only(right: 16), child: _miniField('DOB', _fmtDate(dob) ?? '—')),
                          if (doi != null) _miniField('DOI', _fmtDate(doi) ?? '—'),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Badge + COV + Address
          if ((badge != null && badge.isNotEmpty) ||
              (klass != null && klass.isNotEmpty) ||
              (address != null && address.isNotEmpty) ||
              (state != null && state.isNotEmpty))
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (badge != null && badge.isNotEmpty)
                        Padding(padding: const EdgeInsets.only(right: 16), child: _miniField('Badge', badge)),
                      if (klass != null && klass.isNotEmpty)
                        Expanded(child: _miniField('COV', klass)),
                    ],
                  ),
                  if ((address != null && address.isNotEmpty) || (state != null && state.isNotEmpty))
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: _miniField('Address', address ?? state ?? ''),
                    ),
                  if (issuedState != null && issuedState.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: _miniField('Issued state', issuedState),
                    ),
                ],
              ),
            ),
          // Validity strip
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF3C7).withOpacity(0.5),
              border: Border(top: BorderSide(color: const Color(0xFFFCD34D).withOpacity(0.4))),
            ),
            child: Row(
              children: [
                if (expiry != null)
                  Expanded(child: _validityCell('Non-Trans Valid Till', expiry)),
                if (transExpiry != null)
                  Expanded(child: _validityCell('Trans Valid Till', transExpiry, alignEnd: true)),
              ],
            ),
          ),
          if (phone != null && phone.isNotEmpty)
            Container(
              width: double.infinity,
              color: const Color(0xFF1E3A8A).withOpacity(0.08),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Text(phone, style: TextStyle(fontSize: 10, color: Colors.grey.shade700)),
            ),
        ],
      ),
    );
  }
}

Widget _photoFallback(String initials) => Container(
      color: const Color(0xFFE2E8F0),
      alignment: Alignment.center,
      child: Text(initials,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF94A3B8))),
    );

Widget _miniField(String label, String value, {bool bold = false}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(label.toUpperCase(),
          style: TextStyle(fontSize: 8, fontWeight: FontWeight.w600, color: const Color(0xFFB45309).withOpacity(0.7), letterSpacing: 0.4)),
      Text(value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: bold ? 13 : 11,
            fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
            color: const Color(0xFF1E293B),
          )),
    ],
  );
}

Widget _validityCell(String label, dynamic raw, {bool alignEnd = false}) {
  final expired = _isExpired(raw);
  return Column(
    crossAxisAlignment: alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(label.toUpperCase(),
          style: TextStyle(fontSize: 8, fontWeight: FontWeight.w600, color: const Color(0xFFB45309).withOpacity(0.7), letterSpacing: 0.4)),
      Text(_fmtDate(raw) ?? '—',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: expired ? const Color(0xFFDC2626) : const Color(0xFF334155),
          )),
    ],
  );
}

// ── RC card ────────────────────────────────────────────────────────────

class _RCCard extends StatelessWidget {
  final Map<String, dynamic> vehicle;
  const _RCCard({required this.vehicle});

  @override
  Widget build(BuildContext context) {
    final reg = vehicle['registration_number']?.toString() ?? '—';
    final owner = vehicle['owner_name']?.toString();
    final make = vehicle['make']?.toString();
    final model = vehicle['model']?.toString();
    final color = vehicle['color']?.toString();
    final fuel = vehicle['fuel_type']?.toString();
    final klass = vehicle['vehicle_class']?.toString();
    final bodyType = vehicle['body_type']?.toString();
    final capacityKg = vehicle['capacity_kg'];
    final engine = vehicle['engine_number']?.toString();
    final chassis = vehicle['chassis_number']?.toString();
    final rcExp = vehicle['rc_expiry'];
    final insExp = vehicle['insurance_expiry'];
    final pucExp = vehicle['pollution_certificate_expiry'];
    final permitExp = vehicle['national_permit_expiry'] ?? vehicle['national_permit_upto'];
    final taxExp = vehicle['tax_paid_upto'] ?? vehicle['road_tax_expiry'];
    final financer = vehicle['financer']?.toString();
    final insCo = vehicle['insurance_company']?.toString();
    final rcStatus = vehicle['rc_status']?.toString();

    final anyExpired = [rcExp, insExp, pucExp, permitExp, taxExp].any(_isExpired);
    final activeStatus = !anyExpired && (rcStatus == null || rcStatus.toUpperCase() != 'INACTIVE');

    return Container(
      width: 340,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFEEF2FF), Color(0xFFDBEAFE)],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF93C5FD).withOpacity(0.6)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.20), blurRadius: 20, offset: const Offset(0, 8)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [Color(0xFF1E40AF), Color(0xFF1E3A8A)]),
            ),
            child: Row(
              children: [
                Container(
                  width: 18, height: 18,
                  decoration: const BoxDecoration(color: Color(0xFF60A5FA), shape: BoxShape.circle),
                  alignment: Alignment.center,
                  child: const Text('IN',
                      style: TextStyle(fontSize: 7, fontWeight: FontWeight.w900, color: Colors.white)),
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('REGISTRATION CERTIFICATE',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 11, letterSpacing: 0.8)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: activeStatus ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(activeStatus ? 'ACTIVE' : 'INACTIVE',
                      style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800)),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _rcField('Reg. No.', reg, bold: true)),
                    if (fuel != null && fuel.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.only(top: 2),
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF059669),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(fuel,
                            style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)),
                      ),
                  ],
                ),
                if (owner != null && owner.isNotEmpty)
                  Padding(padding: const EdgeInsets.only(top: 4), child: _rcField('Owner', owner)),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    children: [
                      if ((make != null && make.isNotEmpty) || (model != null && model.isNotEmpty))
                        Expanded(child: _rcField('Make / Model', [make, model].whereType<String>().where((s) => s.isNotEmpty).join(' '))),
                      if (color != null && color.isNotEmpty)
                        Padding(padding: const EdgeInsets.only(left: 12), child: _rcField('Color', color)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if ((klass != null && klass.isNotEmpty) ||
              (bodyType != null && bodyType.isNotEmpty) ||
              (capacityKg != null))
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
              child: Row(
                children: [
                  if (klass != null && klass.isNotEmpty)
                    Expanded(child: _rcField('Class', klass)),
                  if (bodyType != null && bodyType.isNotEmpty)
                    Padding(padding: const EdgeInsets.only(left: 12), child: _rcField('Body', bodyType)),
                  if (capacityKg != null)
                    Padding(padding: const EdgeInsets.only(left: 12), child: _rcField('GVW', '$capacityKg kg')),
                ],
              ),
            ),
          if ((engine != null && engine.isNotEmpty) || (chassis != null && chassis.isNotEmpty))
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
              child: Row(
                children: [
                  if (engine != null && engine.isNotEmpty)
                    Expanded(child: _rcMono('Engine No.', engine)),
                  if (chassis != null && chassis.isNotEmpty)
                    Padding(padding: const EdgeInsets.only(left: 12), child: SizedBox(width: 130, child: _rcMono('Chassis No.', chassis))),
                ],
              ),
            ),
          // Validity strip
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFDBEAFE).withOpacity(0.5),
              border: Border(top: BorderSide(color: const Color(0xFF93C5FD).withOpacity(0.4))),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(child: _rcValidity('RC Valid Till', rcExp)),
                    Expanded(child: _rcValidity('Insurance Till', insExp, alignEnd: true)),
                  ],
                ),
                if (pucExp != null || permitExp != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      children: [
                        Expanded(child: _rcValidity('PUC Till', pucExp)),
                        Expanded(child: _rcValidity('Permit Till', permitExp, alignEnd: true)),
                      ],
                    ),
                  ),
                if (taxExp != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      children: [
                        Expanded(child: _rcValidity('Tax Paid Upto', taxExp)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          if ((financer != null && financer.isNotEmpty) || (insCo != null && insCo.isNotEmpty))
            Container(
              width: double.infinity,
              color: const Color(0xFF1E3A8A).withOpacity(0.08),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Text(
                [if (insCo != null && insCo.isNotEmpty) 'Ins: $insCo', if (financer != null && financer.isNotEmpty) 'Fin: $financer'].join(' · '),
                style: TextStyle(fontSize: 10, color: Colors.grey.shade700),
                maxLines: 1, overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    );
  }
}

Widget _rcField(String label, String value, {bool bold = false}) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label.toUpperCase(),
            style: TextStyle(fontSize: 8, fontWeight: FontWeight.w600, color: const Color(0xFF1D4ED8).withOpacity(0.7), letterSpacing: 0.4)),
        Text(value,
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: bold ? 14 : 11,
              fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
              color: const Color(0xFF1E293B),
              letterSpacing: bold ? 0.6 : 0,
            )),
      ],
    );

Widget _rcMono(String label, String value) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label.toUpperCase(),
            style: TextStyle(fontSize: 8, fontWeight: FontWeight.w600, color: const Color(0xFF1D4ED8).withOpacity(0.7), letterSpacing: 0.4)),
        Text(value,
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 10, fontFamily: 'monospace', color: Color(0xFF475569))),
      ],
    );

Widget _rcValidity(String label, dynamic raw, {bool alignEnd = false}) {
  final expired = _isExpired(raw);
  return Column(
    crossAxisAlignment: alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(label.toUpperCase(),
          style: TextStyle(fontSize: 8, fontWeight: FontWeight.w600, color: const Color(0xFF1D4ED8).withOpacity(0.7), letterSpacing: 0.4)),
      Text(_fmtDate(raw) ?? '—',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: expired ? const Color(0xFFDC2626) : const Color(0xFF334155),
          )),
    ],
  );
}
