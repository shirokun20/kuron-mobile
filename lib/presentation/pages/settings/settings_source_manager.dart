part of 'settings_screen.dart';

/// Dedicated screen for installed content sources: install, health-check,
/// activate, and uninstall — moved out of the main settings list so a large
/// catalog doesn't stretch the settings screen.
class SourceManagerScreen extends StatefulWidget {
  const SourceManagerScreen({super.key});

  @override
  State<SourceManagerScreen> createState() => _SourceManagerScreenState();
}

class _SourceManagerScreenState extends State<SourceManagerScreen>
    with WidgetsBindingObserver {
  final SourceHealthMonitor _healthMonitor = getIt<SourceHealthMonitor>();
  Map<String, SourceHealthStatus> _sourceHealthStatuses = {};
  StreamSubscription<Map<String, SourceHealthStatus>>? _healthSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _runHealthCheck();
  }

  @override
  void dispose() {
    _healthSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    if (lifecycle == AppLifecycleState.resumed) _runHealthCheck();
  }

  void _runHealthCheck() {
    _healthSub?.cancel();
    _healthSub = _healthMonitor.healthStream.listen((statuses) {
      if (mounted) setState(() => _sourceHealthStatuses = statuses);
    });
    unawaited(_healthMonitor.checkAll());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.availableSources)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _buildAvailableSourcesSection(
            theme,
            l10n,
            context,
            _sourceHealthStatuses,
            _runHealthCheck,
          ),
        ],
      ),
    );
  }
}
