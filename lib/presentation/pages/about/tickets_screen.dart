import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:nhasixapp/core/constants/design_tokens.dart';
import 'package:nhasixapp/core/constants/text_style_const.dart';
import 'package:nhasixapp/core/di/service_locator.dart';
import 'package:nhasixapp/core/services/tickets/tickets_service.dart';

/// Screen displaying open issues / tickets from kuron-mobile and kuron-extensions.
class TicketsScreen extends StatefulWidget {
  const TicketsScreen({
    super.key,
    this.service,
    this.urlLauncher,
  });

  final TicketsService? service;
  final Future<bool> Function(Uri uri)? urlLauncher;

  @override
  State<TicketsScreen> createState() => _TicketsScreenState();
}

class _TicketsScreenState extends State<TicketsScreen> {
  late TicketsService _service;
  bool _isLoading = true;
  String? _errorMessage;
  List<TicketItem> _tickets = [];
  String _selectedRepoFilter = 'all'; // 'all', 'kuron-mobile', 'kuron-extensions'

  @override
  void initState() {
    super.initState();
    _initServiceAndLoad();
  }

  Future<void> _initServiceAndLoad() async {
    if (widget.service != null) {
      _service = widget.service!;
    } else if (getIt.isRegistered<TicketsService>()) {
      _service = getIt<TicketsService>();
    } else {
      final prefs = await SharedPreferences.getInstance();
      final logger = getIt.isRegistered<Logger>() ? getIt<Logger>() : Logger(level: Level.off);
      _service = TicketsService(
        prefs: prefs,
        logger: logger,
        dio: Dio(),
      );
    }
    await _loadTickets();
  }

  Future<void> _loadTickets({bool forceRefresh = false}) async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final tickets = await _service.getOpenTickets(forceRefresh: forceRefresh);
      if (mounted) {
        setState(() {
          _tickets = tickets;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _openTicketUrl(String url) async {
    final uri = Uri.parse(url);
    if (widget.urlLauncher != null) {
      await widget.urlLauncher!(uri);
      return;
    }
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gagal membuka URL tiket')),
        );
      }
    }
  }

  List<TicketItem> get _filteredTickets {
    if (_selectedRepoFilter == 'all') return _tickets;
    return _tickets.where((t) => t.repo == _selectedRepoFilter).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Tickets',
          style: TextStyleConst.titleLarge.copyWith(color: colorScheme.onSurface),
        ),
        centerTitle: true,
        elevation: DesignTokens.elevationNone,
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Segarkan Tiket',
            onPressed: _isLoading ? null : () => _loadTickets(forceRefresh: true),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildFilterChips(theme),
          Expanded(
            child: _buildBody(theme),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChips(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          _buildChip('Semua', 'all', theme),
          const SizedBox(width: 8),
          _buildChip('kuron-mobile', 'kuron-mobile', theme),
          const SizedBox(width: 8),
          _buildChip('kuron-extensions', 'kuron-extensions', theme),
        ],
      ),
    );
  }

  Widget _buildChip(String label, String value, ThemeData theme) {
    final isSelected = _selectedRepoFilter == value;
    final colorScheme = theme.colorScheme;
    return FilterChip(
      selected: isSelected,
      label: Text(
        label,
        style: TextStyleConst.bodySmall.copyWith(
          color: isSelected ? colorScheme.onPrimary : colorScheme.onSurface,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      selectedColor: colorScheme.primary,
      backgroundColor: colorScheme.surfaceContainerHighest,
      checkmarkColor: colorScheme.onPrimary,
      showCheckmark: false,
      onSelected: (_) {
        setState(() {
          _selectedRepoFilter = value;
        });
      },
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_errorMessage != null && _tickets.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
              const SizedBox(height: 16),
              Text(
                'Gagal memuat tiket terbuka',
                style: TextStyleConst.titleMedium.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: TextStyleConst.bodySmall.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => _loadTickets(forceRefresh: true),
                icon: const Icon(Icons.refresh),
                label: const Text('Coba Lagi'),
              ),
            ],
          ),
        ),
      );
    }

    final filtered = _filteredTickets;
    if (filtered.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.check_circle_outline,
                size: 48,
                color: theme.colorScheme.primary.withValues(alpha: 0.6),
              ),
              const SizedBox(height: 16),
              Text(
                'Tidak ada tiket terbuka',
                style: TextStyleConst.titleMedium.copyWith(
                  color: theme.colorScheme.onSurface,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Semua issue pada repositori ini telah ditutup.',
                style: TextStyleConst.bodySmall.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _loadTickets(forceRefresh: true),
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: filtered.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final ticket = filtered[index];
          return _buildTicketCard(ticket, theme);
        },
      ),
    );
  }

  Widget _buildTicketCard(TicketItem ticket, ThemeData theme) {
    final colorScheme = theme.colorScheme;
    final isExtensions = ticket.repo == 'kuron-extensions';
    final repoBadgeColor = isExtensions ? colorScheme.tertiary : colorScheme.primary;

    return Card(
      elevation: DesignTokens.elevationNone,
      color: colorScheme.surfaceContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
        onTap: () => _openTicketUrl(ticket.htmlUrl),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: repoBadgeColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
                    ),
                    child: Text(
                      ticket.repo,
                      style: TextStyleConst.bodySmall.copyWith(
                        color: repoBadgeColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '#${ticket.number}',
                    style: TextStyleConst.bodySmall.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    Icons.open_in_new,
                    size: 16,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                ticket.title,
                style: TextStyleConst.bodyLarge.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
              if (ticket.labels.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: ticket.labels.map((label) {
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
                        border: Border.all(
                          color: colorScheme.outline.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Text(
                        label,
                        style: TextStyleConst.caption.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontSize: 10,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(
                    Icons.person_outline,
                    size: 13,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    ticket.author,
                    style: TextStyleConst.caption.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Icon(
                    Icons.schedule,
                    size: 13,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${ticket.createdAt.year}-${ticket.createdAt.month.toString().padLeft(2, '0')}-${ticket.createdAt.day.toString().padLeft(2, '0')}',
                    style: TextStyleConst.caption.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
