// lib/screens/analytics_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import '../services/analytics_service.dart';
import '../services/currency_service.dart';
import '../lang/translations.dart';
import '../utils/category_helper.dart';
import '../providers/locale_provider.dart';

class AnalyticsScreen extends ConsumerStatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  ConsumerState<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends ConsumerState<AnalyticsScreen> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _error;
  DateTime? _lastUpdated;
  int _selectedDays = 7;
  int _section = 0;
  int? _touchedPieIndex;
  Map<String, dynamic> _currencySettings = {
    'display_currency': null,
    'show_both_prices': false,
    'exchange_rates': <dynamic>[],
  };

  static const _sectionCount = 6;
  static const _revenueColor = Color(0xFF3B82F6);
  static const _ordersColor = Color(0xFFEF4444);
  static const _storeCurrency = 'SYP';
  static const _usdExpenseCategories = {'subscription', 'sponsorship'};

  @override
  void initState() {
    super.initState();
    _loadData();
    _loadCurrencySettings();
    localeNotifier.addListener(_onLocaleChanged);
  }

  Future<void> _loadCurrencySettings() async {
    try {
      final settings = await CurrencyService.getCurrencySettings();
      if (mounted) {
        setState(() => _currencySettings = settings.toLegacyMap());
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    localeNotifier.removeListener(_onLocaleChanged);
    super.dispose();
  }

  void _onLocaleChanged() {
    if (mounted) _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await AnalyticsService.fetchDashboard(days: _selectedDays);
      final cacheTime = await AnalyticsService.getCacheTime();
      if (mounted) {
        setState(() {
          _data = data;
          _lastUpdated = cacheTime ?? DateTime.now();
          _loading = false;
        });
      }
    } catch (e) {
      final cached = await AnalyticsService.getCachedDashboard();
      final cacheTime = await AnalyticsService.getCacheTime();
      if (mounted) {
        setState(() {
          _data = cached;
          _lastUpdated = cacheTime;
          _loading = false;
          if (cached == null) _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final isWide = MediaQuery.sizeOf(context).width >= 900;

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(t('analytics')),
        actions: [
          if (_lastUpdated != null)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Center(
                child: Text(
                  '${t('last_updated')}: ${_formatTime(_lastUpdated!)}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: t('retry'),
            onPressed: _loading ? null : _loadData,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : _error != null
              ? _buildError(theme)
              : Column(
                  children: [
                    Padding(
                      padding: EdgeInsets.fromLTRB(isWide ? 24 : 16, 12, isWide ? 24 : 16, 0),
                      child: _buildPeriodSelector(theme, primary),
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: isWide ? 24 : 16),
                      child: _buildSectionNav(theme, primary),
                    ),
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: _loadData,
                        child: _buildSectionContent(context, _data!, theme, primary, isWide),
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildError(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.analytics_outlined, size: 56, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            Text(_error!, textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _loadData,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: Text(t('retry')),
            ),
          ],
        ),
      ),
    );
  }

  String _periodLabel() {
    if (_selectedDays == 1) return t('today');
    return '$_selectedDays ${t('days')}';
  }

  bool get _isHourlyView => _selectedDays == 1;

  List<Map<String, dynamic>> _activeSeries(Map<String, dynamic> data) {
    if (_isHourlyView) {
      final hourly = (data['hourly_series'] as List<dynamic>?) ?? [];
      if (hourly.isNotEmpty) {
        return hourly.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
      return List.generate(
        24,
        (h) => {'hour': h, 'revenue': 0, 'order_count': 0},
      );
    }
    final daily = (data['revenue_series'] as List<dynamic>?) ?? [];
    return daily.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  String _xAxisLabel(Map<String, dynamic> point) {
    if (_isHourlyView) {
      final hour = int.tryParse(point['hour']?.toString() ?? '') ?? 0;
      if (hour == 0) return '12a';
      if (hour == 12) return '12p';
      if (hour < 12) return '${hour}a';
      return '${hour - 12}p';
    }
    final day = point['day']?.toString() ?? '';
    return day.length >= 10 ? day.substring(5, 10) : day;
  }

  String _tooltipTimeLabel(Map<String, dynamic> point) {
    if (_isHourlyView) {
      final hour = int.tryParse(point['hour']?.toString() ?? '') ?? 0;
      return '${hour.toString().padLeft(2, '0')}:00';
    }
    return point['day']?.toString() ?? '';
  }

  String _trafficMonthLabel() => t('this_month');

  double _bottomListPadding(BuildContext context) {
    final inset = MediaQuery.paddingOf(context).bottom;
    return inset + (_section == 0 ? 96 : 32);
  }

  List<String> _sectionLabels() => [
        t('overview'),
        t('revenue'),
        t('orders'),
        t('sales_by_category'),
        t('top_products_by_revenue'),
        t('finance'),
      ];

  Widget _buildSectionNav(ThemeData theme, Color primary) {
    final labels = _sectionLabels();
    final surface = theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.45);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.dividerColor.withValues(
            alpha: theme.brightness == Brightness.dark ? 0.5 : 0.35,
          ),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.all(4),
        child: Row(
          children: List.generate(_sectionCount, (i) {
            final selected = _section == i;
            return Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => setState(() => _section = i),
                  borderRadius: BorderRadius.circular(8),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: selected ? primary.withValues(alpha: 0.12) : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: selected ? primary.withValues(alpha: 0.35) : Colors.transparent,
                      ),
                    ),
                    child: Text(
                      labels[i],
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: selected ? primary : theme.colorScheme.onSurfaceVariant,
                        fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  Widget _buildSectionContent(
    BuildContext context,
    Map<String, dynamic> data,
    ThemeData theme,
    Color primary,
    bool isWide,
  ) {
    final horizontal = isWide ? 24.0 : 16.0;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        horizontal,
        horizontal,
        horizontal,
        _bottomListPadding(context),
      ),
      children: [
        if (_section == 0) ...[
          _buildHeroKpis(data, theme, primary, isWide),
          const SizedBox(height: 16),
          _buildTrafficCard(data, theme, primary, isWide),
        ] else if (_section == 1)
          _buildRevenueChart(data, theme)
        else if (_section == 2)
          _buildOrdersChart(data, theme)
        else if (_section == 3)
          _buildCategoryDonut(data, theme, primary)
        else if (_section == 4)
          _buildTopProducts(data, theme, primary)
        else if (_section == 5) ...[
          _buildRevenueVsExpenses(data, theme, primary),
          const SizedBox(height: 16),
          _buildExpensesChart(data, theme, primary),
        ],
      ],
    );
  }

  // ── Period selector ──────────────────────────────────────────────
  Widget _buildPeriodSelector(ThemeData theme, Color primary) {
    final options = [
      (1, t('today')),
      (7, '7 ${t('days')}'),
      (30, '30 ${t('days')}'),
      (90, '90 ${t('days')}'),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: options.map((o) {
          final selected = _selectedDays == o.$1;
          return Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  if (o.$1 != _selectedDays) {
                    setState(() => _selectedDays = o.$1);
                    _loadData();
                  }
                },
                borderRadius: BorderRadius.circular(8),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: selected
                        ? primary.withValues(alpha: 0.14)
                        : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    o.$2,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: selected ? primary : theme.colorScheme.onSurfaceVariant,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── Hero KPI cards ───────────────────────────────────────────────
  Widget _buildHeroKpis(
    Map<String, dynamic> data,
    ThemeData theme,
    Color primary,
    bool isWide,
  ) {
    final series = _activeSeries(data);
    final periodRevenue = series.fold<double>(
      0,
      (s, e) => s + (double.tryParse(e['revenue'].toString()) ?? 0),
    );
    final periodOrders = series.fold<int>(
      0,
      (s, e) => s + (int.tryParse(e['order_count'].toString()) ?? 0),
    );

    final kpis = [
      _KpiData(
        icon: Icons.payments_outlined,
        label: _selectedDays == 1 ? t('today_revenue') : t('revenue'),
        value: _selectedDays == 1
            ? _formatCurrency(data['today_revenue'] ?? 0)
            : _formatCurrency(periodRevenue),
        subtitle: _selectedDays == 1 ? null : _periodLabel(),
        color: primary,
      ),
      _KpiData(
        icon: Icons.shopping_bag_outlined,
        label: _selectedDays == 1 ? t('today_orders') : t('orders'),
        value: _selectedDays == 1
            ? '${data['today_orders'] ?? 0}'
            : '$periodOrders',
        color: const Color(0xFFF59E0B),
      ),
      _KpiData(
        icon: Icons.storefront_outlined,
        label: t('store_visits_today'),
        value: '${data['store_visits_today'] ?? 0}',
        subtitle: '${data['store_visits_month'] ?? 0}',
        color: const Color(0xFF14B8A6),
      ),
      _KpiData(
        icon: Icons.visibility_outlined,
        label: t('product_views_today'),
        value: '${data['product_views_today'] ?? 0}',
        subtitle: '${data['product_views_month'] ?? 0}',
        color: const Color(0xFF6366F1),
      ),
      _KpiData(
        icon: Icons.warning_amber_rounded,
        label: t('low_stock'),
        value: '${data['low_stock_count'] ?? 0}',
        color: const Color(0xFFEF4444),
      ),
      _KpiData(
        icon: Icons.account_balance_wallet_outlined,
        label: t('outstanding_credits'),
        value: _formatCurrency(data['outstanding_credits'] ?? 0),
        color: const Color(0xFF8B5CF6),
      ),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: isWide ? 3 : 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: isWide ? 2.6 : 2.1,
      ),
      itemCount: kpis.length,
      itemBuilder: (_, i) => _kpiCard(kpis[i], theme),
    );
  }

  Widget _kpiCard(_KpiData kpi, ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            kpi.color.withValues(alpha: 0.14),
            kpi.color.withValues(alpha: 0.04),
          ],
        ),
        border: Border.all(color: kpi.color.withValues(alpha: 0.22)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(kpi.icon, size: 18, color: kpi.color),
              const Spacer(),
              if (kpi.subtitle != null)
                Text(
                  kpi.subtitle!,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            kpi.value,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            kpi.label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  // ── Revenue chart (blue) ─────────────────────────────────────────
  Widget _buildRevenueChart(Map<String, dynamic> data, ThemeData theme) {
    final series = _activeSeries(data);
    if (series.isEmpty) return _emptyCard(t('revenue'), theme);

    final spots = <FlSpot>[];
    for (int i = 0; i < series.length; i++) {
      spots.add(FlSpot(
        i.toDouble(),
        double.tryParse(series[i]['revenue'].toString()) ?? 0,
      ));
    }

    final xInterval = _isHourlyView
        ? 4.0
        : (series.length / 6).ceilToDouble().clamp(1.0, 30.0);

    return _chartCard(
      title: t('revenue'),
      subtitle: _isHourlyView ? t('today') : _periodLabel(),
      theme: theme,
      legend: _legendDot(_revenueColor, t('revenue')),
      child: SizedBox(
        height: 260,
        child: LineChart(
          LineChartData(
            clipData: const FlClipData.all(),
            minX: 0,
            maxX: (series.length - 1).toDouble(),
            gridData: FlGridData(
              show: true,
              drawVerticalLine: _isHourlyView,
              verticalInterval: _isHourlyView ? 4 : null,
              horizontalInterval: _getInterval(spots.map((s) => s.y).toList()),
              getDrawingHorizontalLine: (v) => FlLine(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.06),
                strokeWidth: 1,
              ),
              getDrawingVerticalLine: (v) => FlLine(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.04),
                strokeWidth: 1,
              ),
            ),
            titlesData: FlTitlesData(
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 48,
                  getTitlesWidget: (v, _) => Text(
                    _shortNum(v),
                    style: TextStyle(
                      fontSize: 10,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  interval: xInterval,
                  getTitlesWidget: (v, _) {
                    final idx = v.toInt();
                    if (idx < 0 || idx >= series.length) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        _xAxisLabel(series[idx]),
                        style: TextStyle(
                          fontSize: 9,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    );
                  },
                ),
              ),
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            ),
            borderData: FlBorderData(show: false),
            lineTouchData: LineTouchData(
              touchTooltipData: LineTouchTooltipData(
                getTooltipColor: (_) => theme.colorScheme.inverseSurface,
                getTooltipItems: (touched) => touched.map((s) {
                  final idx = s.x.toInt();
                  final time = idx >= 0 && idx < series.length
                      ? _tooltipTimeLabel(series[idx])
                      : '';
                  return LineTooltipItem(
                    '$time\n${_formatCurrency(s.y)}',
                    TextStyle(
                      color: theme.colorScheme.onInverseSurface,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  );
                }).toList(),
              ),
            ),
            lineBarsData: [
              LineChartBarData(
                spots: spots,
                isCurved: !_isHourlyView,
                curveSmoothness: 0.22,
                color: _revenueColor,
                barWidth: _isHourlyView ? 2 : 2.5,
                dotData: FlDotData(
                  show: !_isHourlyView || series.length <= 24,
                  getDotPainter: (_, __, ___, ____) => FlDotCirclePainter(
                    radius: _isHourlyView ? 2 : 3,
                    color: _revenueColor,
                    strokeWidth: 0,
                  ),
                ),
                belowBarData: BarAreaData(
                  show: true,
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      _revenueColor.withValues(alpha: 0.28),
                      _revenueColor.withValues(alpha: 0.02),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Orders chart (red) ───────────────────────────────────────────
  Widget _buildOrdersChart(Map<String, dynamic> data, ThemeData theme) {
    final series = _activeSeries(data);
    if (series.isEmpty) return _emptyCard(t('orders'), theme);

    final spots = <FlSpot>[];
    for (int i = 0; i < series.length; i++) {
      spots.add(FlSpot(
        i.toDouble(),
        (int.tryParse(series[i]['order_count'].toString()) ?? 0).toDouble(),
      ));
    }

    final xInterval = _isHourlyView
        ? 4.0
        : (series.length / 6).ceilToDouble().clamp(1.0, 30.0);

    return _chartCard(
      title: t('order_count'),
      subtitle: _isHourlyView ? t('today') : _periodLabel(),
      theme: theme,
      legend: _legendDot(_ordersColor, t('orders')),
      child: SizedBox(
        height: 260,
        child: LineChart(
          LineChartData(
            clipData: const FlClipData.all(),
            minX: 0,
            maxX: (series.length - 1).toDouble(),
            gridData: FlGridData(
              show: true,
              drawVerticalLine: _isHourlyView,
              verticalInterval: _isHourlyView ? 4 : null,
              horizontalInterval: _getInterval(spots.map((s) => s.y).toList()),
              getDrawingHorizontalLine: (v) => FlLine(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.06),
                strokeWidth: 1,
              ),
              getDrawingVerticalLine: (v) => FlLine(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.04),
                strokeWidth: 1,
              ),
            ),
            titlesData: FlTitlesData(
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 36,
                  getTitlesWidget: (v, _) => Text(
                    v.toInt().toString(),
                    style: TextStyle(
                      fontSize: 10,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  interval: xInterval,
                  getTitlesWidget: (v, _) {
                    final idx = v.toInt();
                    if (idx < 0 || idx >= series.length) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        _xAxisLabel(series[idx]),
                        style: TextStyle(
                          fontSize: 9,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    );
                  },
                ),
              ),
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            ),
            borderData: FlBorderData(show: false),
            lineTouchData: LineTouchData(
              touchTooltipData: LineTouchTooltipData(
                getTooltipColor: (_) => theme.colorScheme.inverseSurface,
                getTooltipItems: (touched) => touched.map((s) {
                  final idx = s.x.toInt();
                  final time = idx >= 0 && idx < series.length
                      ? _tooltipTimeLabel(series[idx])
                      : '';
                  return LineTooltipItem(
                    '$time\n${t('orders')}: ${s.y.toInt()}',
                    TextStyle(
                      color: theme.colorScheme.onInverseSurface,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  );
                }).toList(),
              ),
            ),
            lineBarsData: [
              LineChartBarData(
                spots: spots,
                isCurved: !_isHourlyView,
                curveSmoothness: 0.22,
                color: _ordersColor,
                barWidth: _isHourlyView ? 2 : 2.5,
                dotData: FlDotData(
                  show: !_isHourlyView || series.length <= 24,
                  getDotPainter: (_, __, ___, ____) => FlDotCirclePainter(
                    radius: _isHourlyView ? 2 : 3,
                    color: _ordersColor,
                    strokeWidth: 0,
                  ),
                ),
                belowBarData: BarAreaData(
                  show: true,
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      _ordersColor.withValues(alpha: 0.28),
                      _ordersColor.withValues(alpha: 0.02),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Category donut ───────────────────────────────────────────────
  Widget _buildCategoryDonut(Map<String, dynamic> data, ThemeData theme, Color primary) {
    final categories = (data['category_sales'] as List<dynamic>?) ?? [];
    if (categories.isEmpty) return _emptyCard(t('sales_by_category'), theme);

    final total = categories.fold<double>(
      0,
      (s, e) => s + (double.tryParse(e['total'].toString()) ?? 0),
    );
    final colors = _palette(theme, primary);

    return _chartCard(
      title: t('sales_by_category'),
      theme: theme,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    t('total'),
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      _formatCurrency(total),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 220,
            child: Row(
              children: [
                Expanded(
                  flex: 5,
                  child: PieChart(
                    PieChartData(
                      sectionsSpace: 3,
                      centerSpaceRadius: 36,
                      pieTouchData: PieTouchData(
                        touchCallback: (event, response) {
                          setState(() {
                            if (!event.isInterestedForInteractions ||
                                response?.touchedSection == null) {
                              _touchedPieIndex = null;
                              return;
                            }
                            _touchedPieIndex =
                                response!.touchedSection!.touchedSectionIndex;
                          });
                        },
                      ),
                      sections: categories.asMap().entries.map((entry) {
                        final i = entry.key;
                        final val = double.tryParse(entry.value['total'].toString()) ?? 0;
                        final pct = total > 0 ? (val / total * 100) : 0;
                        final touched = _touchedPieIndex == i;
                        return PieChartSectionData(
                          color: colors[i % colors.length],
                          value: val > 0 ? val : 0.001,
                          title: touched ? '${pct.toStringAsFixed(0)}%' : '',
                          titleStyle: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: theme.colorScheme.onPrimary,
                          ),
                          radius: touched ? 62 : 54,
                          titlePositionPercentageOffset: 0.55,
                        );
                      }).toList(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 4,
                  child: ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: categories.length.clamp(0, 6),
                    separatorBuilder: (_, __) => const SizedBox(height: 6),
                    itemBuilder: (_, i) {
                      final cat = categories[i];
                      final val = double.tryParse(cat['total'].toString()) ?? 0;
                      final pct = total > 0 ? (val / total * 100).round() : 0;
                      return Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: colors[i % colors.length],
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  CategoryHelper.displayAnalyticsCategory(
                                    cat['category']?.toString() ?? '',
                                  ),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  '$pct% · ${_formatCurrency(val)}',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Top products ranked bars ─────────────────────────────────────
  Widget _buildTopProducts(Map<String, dynamic> data, ThemeData theme, Color primary) {
    final products = (data['top_products'] as List<dynamic>?) ?? [];
    if (products.isEmpty) return _emptyCard(t('top_products_by_revenue'), theme);

    final maxRevenue = products.fold<double>(
      0,
      (m, e) {
        final v = double.tryParse(e['revenue'].toString()) ?? 0;
        return v > m ? v : m;
      },
    );

    return _chartCard(
      title: t('top_products_by_revenue'),
      theme: theme,
      child: Column(
        children: products.asMap().entries.map((entry) {
          final i = entry.key;
          final product = entry.value;
          final name = product['name']?.toString() ?? '';
          final revenue = double.tryParse(product['revenue'].toString()) ?? 0;
          final fraction = maxRevenue > 0 ? revenue / maxRevenue : 0.0;
          final rankColors = [
            const Color(0xFFFFD700),
            const Color(0xFFC0C0C0),
            const Color(0xFFCD7F32),
          ];

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: i < 3
                        ? rankColors[i].withValues(alpha: 0.2)
                        : theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${i + 1}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: i < 3 ? rankColors[i] : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              name,
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            _formatCurrency(revenue),
                            style: theme.textTheme.labelMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: primary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: fraction,
                          minHeight: 6,
                          backgroundColor: primary.withValues(alpha: 0.1),
                          valueColor: AlwaysStoppedAnimation(
                            primary.withValues(alpha: 0.85),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── Traffic comparison ─────────────────────────────────────────
  Widget _buildTrafficCard(
    Map<String, dynamic> data,
    ThemeData theme,
    Color primary,
    bool isWide,
  ) {
    final metrics = [
      (
        t('store_visits'),
        (data['store_visits_today'] as num?)?.toInt() ?? 0,
        (data['store_visits_month'] as num?)?.toInt() ?? 0,
        const Color(0xFF14B8A6),
        Icons.storefront_outlined,
      ),
      (
        t('product_views'),
        (data['product_views_today'] as num?)?.toInt() ?? 0,
        (data['product_views_month'] as num?)?.toInt() ?? 0,
        const Color(0xFF3B82F6),
        Icons.visibility_outlined,
      ),
    ];

    return _chartCard(
      title: t('this_month_views'),
      theme: theme,
      child: isWide
          ? Row(
              children: metrics
                  .map((m) => Expanded(child: _trafficMetric(m, theme)))
                  .toList(),
            )
          : Column(
              children: metrics
                  .map((m) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _trafficMetric(m, theme),
                      ))
                  .toList(),
            ),
    );
  }

  Widget _trafficMetric(
    (String label, int today, int month, Color color, IconData icon) m,
    ThemeData theme,
  ) {
    final maxVal = [m.$2, m.$3].reduce((a, b) => a > b ? a : b).clamp(1, 999999);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: m.$4.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: m.$4.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(m.$5, size: 18, color: m.$4),
              const SizedBox(width: 8),
              Text(
                m.$1,
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _trafficBar(t('today'), m.$2, maxVal, m.$4, theme),
          const SizedBox(height: 10),
          _trafficBar(_trafficMonthLabel(), m.$3, maxVal, m.$4.withValues(alpha: 0.55), theme),
        ],
      ),
    );
  }

  Widget _trafficBar(String label, int value, int maxVal, Color color, ThemeData theme) {
    return Row(
      children: [
        SizedBox(
          width: 72,
          child: Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: value / maxVal,
              minHeight: 8,
              backgroundColor: color.withValues(alpha: 0.12),
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 36,
          child: Text(
            '$value',
            textAlign: TextAlign.end,
            style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }

  // ── Revenue vs expenses ──────────────────────────────────────────
  Widget _buildRevenueVsExpenses(Map<String, dynamic> data, ThemeData theme, Color primary) {
    final revenue = (data['monthly_revenue'] as List<dynamic>?) ?? [];
    final expenses = (data['monthly_expenses'] as List<dynamic>?) ?? [];
    if (revenue.isEmpty && expenses.isEmpty) {
      return _emptyCard(t('revenue_vs_expenses'), theme);
    }

    final months = <String>{};
    for (final r in revenue) months.add(r['month']?.toString() ?? '');
    for (final e in expenses) months.add(e['month']?.toString() ?? '');
    final sortedMonths = months.where((m) => m.isNotEmpty).toList()..sort();
    if (sortedMonths.length > 6) {
      sortedMonths.removeRange(0, sortedMonths.length - 6);
    }

    final revenueMap = <String, double>{};
    for (final r in revenue) {
      revenueMap[r['month']?.toString() ?? ''] = _amountInDisplayCurrency(
        r['revenue'],
        sourceCurrency: _storeCurrency,
      );
    }
    final expenseMap = <String, double>{};
    for (final e in expenses) {
      expenseMap[e['month']?.toString() ?? ''] =
          double.tryParse(e['expenses'].toString()) ?? 0;
    }

    final barGroups = <BarChartGroupData>[];
    for (int i = 0; i < sortedMonths.length; i++) {
      final m = sortedMonths[i];
      barGroups.add(
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: revenueMap[m] ?? 0,
              color: primary,
              width: 10,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
            ),
            BarChartRodData(
              toY: expenseMap[m] ?? 0,
              color: theme.colorScheme.error.withValues(alpha: 0.75),
              width: 10,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
            ),
          ],
          barsSpace: 4,
        ),
      );
    }

    final maxY = barGroups.fold<double>(0, (m, g) {
      for (final rod in g.barRods) {
        if (rod.toY > m) m = rod.toY;
      }
      return m;
    });

    return _chartCard(
      title: t('revenue_vs_expenses'),
      theme: theme,
      legend: Row(
        children: [
          _legendDot(primary, t('revenue')),
          const SizedBox(width: 16),
          _legendDot(theme.colorScheme.error.withValues(alpha: 0.75), t('expenses')),
        ],
      ),
      child: SizedBox(
        height: 220,
        child: BarChart(
          BarChartData(
            alignment: BarChartAlignment.spaceAround,
            maxY: maxY * 1.15,
            groupsSpace: 12,
            barTouchData: BarTouchData(
              touchTooltipData: BarTouchTooltipData(
                getTooltipColor: (_) => theme.colorScheme.inverseSurface,
                getTooltipItem: (group, _, rod, rodIdx) {
                  final m = sortedMonths[group.x];
                  final label = rodIdx == 0 ? t('revenue') : t('expenses');
                  return BarTooltipItem(
                    '$m\n$label: ${_formatDisplayAmount(rod.toY)}',
                    TextStyle(
                      color: theme.colorScheme.onInverseSurface,
                      fontSize: 11,
                    ),
                  );
                },
              ),
            ),
            titlesData: FlTitlesData(
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 44,
                  getTitlesWidget: (v, _) => Text(
                    _shortNum(v),
                    style: TextStyle(
                      fontSize: 10,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  getTitlesWidget: (v, _) {
                    final idx = v.toInt();
                    if (idx < 0 || idx >= sortedMonths.length) {
                      return const SizedBox.shrink();
                    }
                    final m = sortedMonths[idx];
                    return Text(
                      m.length >= 7 ? m.substring(5) : m,
                      style: TextStyle(
                        fontSize: 10,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    );
                  },
                ),
              ),
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            ),
            borderData: FlBorderData(show: false),
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              getDrawingHorizontalLine: (v) => FlLine(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.06),
                strokeWidth: 1,
              ),
            ),
            barGroups: barGroups,
          ),
        ),
      ),
    );
  }

  // ── Expenses breakdown ───────────────────────────────────────────
  Widget _buildExpensesChart(Map<String, dynamic> data, ThemeData theme, Color primary) {
    final expenses = (data['expense_categories'] as List<dynamic>?) ?? [];
    if (expenses.isEmpty) return _emptyCard(t('expenses_by_category'), theme);

    double expenseDisplayTotal(Map<String, dynamic> entry) {
      final cat = entry['category']?.toString() ?? '';
      return _amountInDisplayCurrency(
        entry['total'],
        sourceCurrency: _expenseSourceCurrency(cat),
      );
    }

    final maxVal = expenses.fold<double>(
      0,
      (m, e) {
        final v = expenseDisplayTotal(Map<String, dynamic>.from(e as Map));
        return v > m ? v : m;
      },
    );

    final errorColor = theme.colorScheme.error;

    return _chartCard(
      title: t('expenses_by_category'),
      theme: theme,
      child: SizedBox(
        height: 220,
        child: BarChart(
          BarChartData(
            alignment: BarChartAlignment.spaceEvenly,
            maxY: maxVal * 1.2,
            barTouchData: BarTouchData(
              touchTooltipData: BarTouchTooltipData(
                getTooltipColor: (_) => theme.colorScheme.inverseSurface,
                getTooltipItem: (group, _, rod, __) {
                  final cat = CategoryHelper.displayAnalyticsCategory(
                    expenses[group.x]['category']?.toString() ?? '',
                  );
                  return BarTooltipItem(
                    '$cat\n${_formatDisplayAmount(rod.toY)}',
                    TextStyle(
                      color: theme.colorScheme.onInverseSurface,
                      fontSize: 11,
                    ),
                  );
                },
              ),
            ),
            titlesData: FlTitlesData(
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 44,
                  getTitlesWidget: (v, _) => Text(
                    _shortNum(v),
                    style: TextStyle(
                      fontSize: 10,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 36,
                  getTitlesWidget: (v, _) {
                    final idx = v.toInt();
                    if (idx < 0 || idx >= expenses.length) return const SizedBox.shrink();
                    final cat = CategoryHelper.displayAnalyticsCategory(
                      expenses[idx]['category']?.toString() ?? '',
                    );
                    return Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: SizedBox(
                        width: 56,
                        child: Text(
                          cat,
                          maxLines: 2,
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 9,
                            height: 1.15,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            ),
            borderData: FlBorderData(show: false),
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              getDrawingHorizontalLine: (v) => FlLine(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.06),
                strokeWidth: 1,
              ),
            ),
            barGroups: expenses.asMap().entries.map((entry) {
              final row = Map<String, dynamic>.from(entry.value as Map);
              final val = expenseDisplayTotal(row);
              return BarChartGroupData(
                x: entry.key,
                barRods: [
                  BarChartRodData(
                    toY: val,
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        errorColor.withValues(alpha: 0.5),
                        errorColor.withValues(alpha: 0.9),
                      ],
                    ),
                    width: 22,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                  ),
                ],
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  // ── Shared widgets ───────────────────────────────────────────────
  Widget _chartCard({
    required String title,
    required ThemeData theme,
    required Widget child,
    String? subtitle,
    Widget? legend,
  }) {
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: theme.dividerColor.withValues(
            alpha: theme.brightness == Brightness.dark ? 0.5 : 0.35,
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(width: 8),
                  Text(
                    '· $subtitle',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
            if (legend != null) ...[const SizedBox(height: 12), legend],
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }

  Widget _emptyCard(String title, ThemeData theme) {
    return _chartCard(
      title: title,
      theme: theme,
      child: SizedBox(
        height: 100,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.bar_chart_rounded, size: 32, color: theme.colorScheme.outline),
              const SizedBox(height: 8),
              Text(
                t('no_data_available'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 11)),
      ],
    );
  }

  List<Color> _palette(ThemeData theme, Color primary) {
    return [
      primary,
      theme.colorScheme.tertiary,
      const Color(0xFF14B8A6),
      const Color(0xFFF59E0B),
      const Color(0xFF8B5CF6),
      const Color(0xFFEC4899),
      const Color(0xFF64748B),
    ];
  }

  String get _displayCurrency {
    final fromSettings = _currencySettings['display_currency']?.toString().trim();
    if (fromSettings != null && fromSettings.isNotEmpty) return fromSettings;
    final fromData = _data?['display_currency']?.toString().trim();
    if (fromData != null && fromData.isNotEmpty) return fromData;
    return _storeCurrency;
  }

  String _expenseSourceCurrency(String category) {
    return _usdExpenseCategories.contains(category.toLowerCase())
        ? 'USD'
        : _storeCurrency;
  }

  double _amountInDisplayCurrency(
    dynamic value, {
    String sourceCurrency = _storeCurrency,
  }) {
    final amount = double.tryParse(value.toString()) ?? 0;
    final target = _displayCurrency;
    if (sourceCurrency.toLowerCase() == target.toLowerCase()) return amount;
    final converted = CurrencyService.convertPrice(
      amount,
      sourceCurrency,
      target,
      _currencySettings['exchange_rates'],
    );
    return converted ?? amount;
  }

  String _formatDisplayAmount(dynamic value) {
    final amount = double.tryParse(value.toString()) ?? 0;
    return CurrencyService.formatPrice(amount, _displayCurrency);
  }

  String _formatCurrency(
    dynamic value, {
    String sourceCurrency = _storeCurrency,
  }) {
    final displayAmount = _amountInDisplayCurrency(
      value,
      sourceCurrency: sourceCurrency,
    );
    return CurrencyService.formatPrice(displayAmount, _displayCurrency);
  }

  String _shortNum(double v) {
    final symbol = CurrencyService.currencySymbol(_displayCurrency);
    String compact;
    if (v >= 1000000) {
      compact = '${(v / 1000000).toStringAsFixed(1)}M';
    } else if (v >= 1000) {
      compact = '${(v / 1000).toStringAsFixed(0)}K';
    } else {
      compact = v.toStringAsFixed(v == v.roundToDouble() ? 0 : 1);
    }
    return symbol.isEmpty ? compact : '$compact $symbol';
  }

  double _getInterval(List<double> values) {
    if (values.isEmpty) return 1;
    final max = values.reduce((a, b) => a > b ? a : b);
    if (max <= 0) return 1;
    if (max <= 10) return 2;
    if (max <= 100) return 20;
    if (max <= 1000) return 200;
    return (max / 5).ceilToDouble();
  }

  String _formatTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return t('just_now');
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    return '${dt.day}/${dt.month}';
  }
}

class _KpiData {
  final IconData icon;
  final String label;
  final String value;
  final String? subtitle;
  final Color color;

  const _KpiData({
    required this.icon,
    required this.label,
    required this.value,
    this.subtitle,
    required this.color,
  });
}
