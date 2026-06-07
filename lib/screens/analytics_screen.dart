// lib/screens/analytics_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import '../services/analytics_service.dart';
import '../lang/translations.dart';

class AnalyticsScreen extends ConsumerStatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  ConsumerState<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends ConsumerState<AnalyticsScreen>
    with SingleTickerProviderStateMixin {
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _error;
  DateTime? _lastUpdated;
  int _selectedDays = 7;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
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
      appBar: AppBar(
        title: Text(t('analytics')),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: t('retry'),
            onPressed: _loading ? null : _loadData,
          ),
          if (_lastUpdated != null)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: Chip(
                  avatar: const Icon(Icons.schedule, size: 16),
                  label: Text(
                    '${t('last_updated')}: ${_formatTime(_lastUpdated!)}',
                    style: theme.textTheme.labelSmall,
                  ),
                ),
              ),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.error_outline, size: 48, color: Colors.grey.shade400),
                      const SizedBox(height: 12),
                      Text(_error!, style: theme.textTheme.bodyMedium),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: _loadData,
                        child: Text(t('retry')),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    Material(
                      color: theme.colorScheme.surface,
                      elevation: 1,
                      child: TabBar(
                        controller: _tabController,
                        isScrollable: !isWide,
                        labelColor: primary,
                        unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
                        indicatorColor: primary,
                        tabs: [
                          Tab(
                            text: t('overview') ?? 'Overview',
                            icon: const Icon(Icons.dashboard_outlined),
                          ),
                          Tab(
                            text: t('sales') ?? 'Sales',
                            icon: const Icon(Icons.show_chart_outlined),
                          ),
                          Tab(
                            text: t('finance') ?? 'Finance',
                            icon: const Icon(Icons.account_balance_outlined),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: _buildPeriodSelector(theme, primary),
                    ),
                    Expanded(
                      child: TabBarView(
                        controller: _tabController,
                        children: [
                          _buildOverviewTab(theme, primary, isWide),
                          _buildSalesTab(theme, primary, isWide),
                          _buildFinanceTab(theme, primary, isWide),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildOverviewTab(ThemeData theme, Color primary, bool isWide) {
    final data = _data!;
    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.all(isWide ? 24 : 16),
        children: [
          _buildTopCards(data, theme, primary, isWide),
          const SizedBox(height: 16),
          _buildVisitsCard(data, theme, primary),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildSalesTab(ThemeData theme, Color primary, bool isWide) {
    final data = _data!;
    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.all(isWide ? 24 : 16),
        children: [
          if (isWide)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _buildRevenueChart(data, theme, primary)),
                const SizedBox(width: 16),
                Expanded(child: _buildOrdersChart(data, theme, primary)),
              ],
            )
          else ...[
            _buildRevenueChart(data, theme, primary),
            const SizedBox(height: 16),
            _buildOrdersChart(data, theme, primary),
          ],
          const SizedBox(height: 16),
          _buildCategorySalesChart(data, theme, primary),
          const SizedBox(height: 16),
          _buildTopProductsChart(data, theme, primary),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildFinanceTab(ThemeData theme, Color primary, bool isWide) {
    final data = _data!;
    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.all(isWide ? 24 : 16),
        children: [
          _buildRevenueVsExpensesChart(data, theme, primary),
          const SizedBox(height: 16),
          _buildExpensesChart(data, theme, primary),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ==================== TOP CARDS ====================
  Widget _buildTopCards(
    Map<String, dynamic> data,
    ThemeData theme,
    Color primary,
    bool isWide,
  ) {
    return GridView.count(
      crossAxisCount: isWide ? 3 : 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: isWide ? 1.8 : 1.6,
      children: [
        _statCard(
          icon: Icons.attach_money,
          label: t('today_revenue'),
          value: _formatCurrency(data['today_revenue'] ?? 0),
          color: primary,
          theme: theme,
        ),
        _statCard(
          icon: Icons.shopping_bag_outlined,
          label: t('today_orders'),
          value: '${data['today_orders'] ?? 0}',
          color: Colors.orange.shade600,
          theme: theme,
        ),
        _statCard(
          icon: Icons.warning_amber_rounded,
          label: t('low_stock'),
          value: '${data['low_stock_count'] ?? 0}',
          color: Colors.red.shade600,
          theme: theme,
        ),
        _statCard(
          icon: Icons.account_balance_wallet_outlined,
          label: t('outstanding_credits'),
          value: _formatCurrency(data['outstanding_credits'] ?? 0),
          color: Colors.purple.shade600,
          theme: theme,
        ),
        _statCard(
          icon: Icons.storefront_outlined,
          label: t('store_visits_today'),
          value: '${data['store_visits_today'] ?? 0}',
          color: Colors.teal.shade600,
          theme: theme,
        ),
        _statCard(
          icon: Icons.visibility_outlined,
          label: t('product_views_today'),
          value: '${data['product_views_today'] ?? 0}',
          color: Colors.indigo.shade600,
          theme: theme,
        ),
      ],
    );
  }

  Widget _buildVisitsCard(Map<String, dynamic> data, ThemeData theme, Color primary) {
    return Card(
      elevation: 1,
      shadowColor: Colors.black12,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              t('this_month_views'),
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _miniStat(
                    Icons.storefront,
                    t('store_visits'),
                    '${data['store_visits_month'] ?? 0}',
                    Colors.teal,
                    theme,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _miniStat(
                    Icons.visibility,
                    t('product_views'),
                    '${data['product_views_month'] ?? 0}',
                    Colors.indigo,
                    theme,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _miniStat(IconData icon, String label, String value, Color color, ThemeData theme) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 20, color: color),
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            Text(label, style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey)),
          ],
        ),
      ],
    );
  }

  Widget _statCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    required ThemeData theme,
  }) {
    return Card(
      elevation: 0,
      color: color.withOpacity(0.08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: color.withOpacity(0.15)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 20, color: color),
            ),
            const Spacer(),
            Text(
              value,
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  // ==================== PERIOD SELECTOR ====================
  Widget _buildPeriodSelector(ThemeData theme, Color primary) {
    return Row(
      children: [
        Text(t('period'), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
        const Spacer(),
        _periodButton(7, '7d', primary, theme),
        const SizedBox(width: 8),
        _periodButton(30, '30d', primary, theme),
        const SizedBox(width: 8),
        _periodButton(90, '90d', primary, theme),
      ],
    );
  }

  Widget _periodButton(int days, String label, Color primary, ThemeData theme) {
    final selected = _selectedDays == days;
    return InkWell(
      onTap: () {
        if (_selectedDays != days) {
          setState(() => _selectedDays = days);
          _loadData();
        }
      },
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? primary : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? primary : Colors.grey.shade300),
        ),
        child: Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: selected ? Colors.white : Colors.grey.shade700,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  // ==================== REVENUE LINE CHART ====================
  Widget _buildRevenueChart(Map<String, dynamic> data, ThemeData theme, Color primary) {
    final series = (data['revenue_series'] as List<dynamic>?) ?? [];
    if (series.isEmpty) return _emptyChart(t('revenue'), theme);

    final spots = <FlSpot>[];
    for (int i = 0; i < series.length; i++) {
      spots.add(FlSpot(i.toDouble(), (double.tryParse(series[i]['revenue'].toString()) ?? 0)));
    }

    return _chartCard(
      title: t('revenue'),
      theme: theme,
      child: SizedBox(
        height: 200,
        child: LineChart(
          LineChartData(
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              horizontalInterval: _getInterval(spots.map((s) => s.y).toList()),
              getDrawingHorizontalLine: (v) => FlLine(color: Colors.grey.shade200, strokeWidth: 1),
            ),
            titlesData: FlTitlesData(
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 50,
                  getTitlesWidget: (v, meta) => Text(
                    _shortNum(v),
                    style: const TextStyle(fontSize: 10, color: Colors.grey),
                  ),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  interval: (series.length / 5).ceilToDouble().clamp(1, 30),
                  getTitlesWidget: (v, meta) {
                    final idx = v.toInt();
                    if (idx < 0 || idx >= series.length) return const SizedBox.shrink();
                    final day = series[idx]['day']?.toString() ?? '';
                    return Text(
                      day.length >= 10 ? day.substring(5, 10) : day,
                      style: const TextStyle(fontSize: 9, color: Colors.grey),
                    );
                  },
                ),
              ),
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            ),
            borderData: FlBorderData(show: false),
            lineBarsData: [
              LineChartBarData(
                spots: spots,
                isCurved: true,
                color: primary,
                barWidth: 2.5,
                dotData: const FlDotData(show: false),
                belowBarData: BarAreaData(
                  show: true,
                  color: primary.withOpacity(0.1),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ==================== ORDERS LINE CHART ====================
  Widget _buildOrdersChart(Map<String, dynamic> data, ThemeData theme, Color primary) {
    final series = (data['revenue_series'] as List<dynamic>?) ?? [];
    if (series.isEmpty) return _emptyChart(t('orders'), theme);

    final spots = <FlSpot>[];
    for (int i = 0; i < series.length; i++) {
      spots.add(FlSpot(i.toDouble(), (int.tryParse(series[i]['order_count'].toString()) ?? 0).toDouble()));
    }

    return _chartCard(
      title: t('order_count'),
      theme: theme,
      child: SizedBox(
        height: 200,
        child: LineChart(
          LineChartData(
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              horizontalInterval: _getInterval(spots.map((s) => s.y).toList()),
              getDrawingHorizontalLine: (v) => FlLine(color: Colors.grey.shade200, strokeWidth: 1),
            ),
            titlesData: FlTitlesData(
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 40,
                  getTitlesWidget: (v, meta) => Text(
                    v.toInt().toString(),
                    style: const TextStyle(fontSize: 10, color: Colors.grey),
                  ),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  interval: (series.length / 5).ceilToDouble().clamp(1, 30),
                  getTitlesWidget: (v, meta) {
                    final idx = v.toInt();
                    if (idx < 0 || idx >= series.length) return const SizedBox.shrink();
                    final day = series[idx]['day']?.toString() ?? '';
                    return Text(
                      day.length >= 10 ? day.substring(5, 10) : day,
                      style: const TextStyle(fontSize: 9, color: Colors.grey),
                    );
                  },
                ),
              ),
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            ),
            borderData: FlBorderData(show: false),
            lineBarsData: [
              LineChartBarData(
                spots: spots,
                isCurved: true,
                color: Colors.orange.shade600,
                barWidth: 2.5,
                dotData: const FlDotData(show: false),
                belowBarData: BarAreaData(
                  show: true,
                  color: Colors.orange.shade600.withOpacity(0.1),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ==================== PIE CHART: Sales by Category ====================
  Widget _buildCategorySalesChart(Map<String, dynamic> data, ThemeData theme, Color primary) {
    final categories = (data['category_sales'] as List<dynamic>?) ?? [];
    if (categories.isEmpty) return _emptyChart(t('sales_by_category'), theme);

    final total = categories.fold<double>(
      0,
      (sum, e) => sum + (double.tryParse(e['total'].toString()) ?? 0),
    );

    final colors = [
      primary,
      Colors.orange.shade500,
      Colors.green.shade500,
      Colors.purple.shade500,
      Colors.teal.shade500,
      Colors.red.shade400,
      Colors.amber.shade600,
      Colors.indigo.shade400,
      Colors.pink.shade400,
      Colors.cyan.shade500,
    ];

    return _chartCard(
      title: t('sales_by_category'),
      theme: theme,
      child: SizedBox(
        height: 220,
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: PieChart(
                PieChartData(
                  sectionsSpace: 2,
                  centerSpaceRadius: 36,
                  sections: categories.asMap().entries.map((entry) {
                    final i = entry.key;
                    final cat = entry.value;
                    final val = double.tryParse(cat['total'].toString()) ?? 0;
                    final pct = total > 0 ? (val / total * 100) : 0;
                    return PieChartSectionData(
                      color: colors[i % colors.length],
                      value: val,
                      title: '${pct.toStringAsFixed(0)}%',
                      titleStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                      radius: 50,
                    );
                  }).toList(),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: categories.asMap().entries.take(6).map((entry) {
                  final i = entry.key;
                  final cat = entry.value;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: colors[i % colors.length],
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            cat['category']?.toString() ?? '',
                            style: const TextStyle(fontSize: 11),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== HORIZONTAL BAR: Top 10 Products ====================
  Widget _buildTopProductsChart(Map<String, dynamic> data, ThemeData theme, Color primary) {
    final products = (data['top_products'] as List<dynamic>?) ?? [];
    if (products.isEmpty) return _emptyChart(t('top_products_by_revenue'), theme);

    final maxRevenue = products.fold<double>(
      0,
      (max, e) => (double.tryParse(e['revenue'].toString()) ?? 0) > max
          ? (double.tryParse(e['revenue'].toString()) ?? 0)
          : max,
    );

    return _chartCard(
      title: t('top_products_by_revenue'),
      theme: theme,
      child: Column(
        children: products.asMap().entries.map((entry) {
          final product = entry.value;
          final name = product['name']?.toString() ?? '';
          final revenue = double.tryParse(product['revenue'].toString()) ?? 0;
          final fraction = maxRevenue > 0 ? revenue / maxRevenue : 0.0;

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                SizedBox(
                  width: 80,
                  child: Text(
                    name.length > 12 ? '${name.substring(0, 12)}..' : name,
                    style: theme.textTheme.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return Stack(
                        children: [
                          Container(
                            height: 20,
                            decoration: BoxDecoration(
                              color: primary.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          Container(
                            height: 20,
                            width: constraints.maxWidth * fraction,
                            decoration: BoxDecoration(
                              color: primary.withOpacity(0.8),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 50,
                  child: Text(
                    _formatCurrency(revenue),
                    style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                    textAlign: TextAlign.end,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  // ==================== BAR CHART: Expenses by Category ====================
  Widget _buildExpensesChart(Map<String, dynamic> data, ThemeData theme, Color primary) {
    final expenses = (data['expense_categories'] as List<dynamic>?) ?? [];
    if (expenses.isEmpty) return _emptyChart(t('expenses_by_category'), theme);

    final maxVal = expenses.fold<double>(
      0,
      (max, e) => (double.tryParse(e['total'].toString()) ?? 0) > max
          ? (double.tryParse(e['total'].toString()) ?? 0)
          : max,
    );

    return _chartCard(
      title: t('expenses_by_category'),
      theme: theme,
      child: SizedBox(
        height: 200,
        child: BarChart(
          BarChartData(
            alignment: BarChartAlignment.spaceEvenly,
            maxY: maxVal * 1.15,
            barTouchData: BarTouchData(
              touchTooltipData: BarTouchTooltipData(
                getTooltipItem: (group, groupIdx, rod, rodIdx) {
                  final cat = expenses[group.x.toInt()]['category'] ?? '';
                  return BarTooltipItem(
                    '$cat\n${_formatCurrency(rod.toY)}',
                    const TextStyle(color: Colors.white, fontSize: 11),
                  );
                },
              ),
            ),
            titlesData: FlTitlesData(
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 50,
                  getTitlesWidget: (v, meta) => Text(
                    _shortNum(v),
                    style: const TextStyle(fontSize: 10, color: Colors.grey),
                  ),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  getTitlesWidget: (v, meta) {
                    final idx = v.toInt();
                    if (idx < 0 || idx >= expenses.length) return const SizedBox.shrink();
                    final cat = expenses[idx]['category']?.toString() ?? '';
                    return Text(
                      cat.length > 8 ? '${cat.substring(0, 8)}..' : cat,
                      style: const TextStyle(fontSize: 9, color: Colors.grey),
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
              getDrawingHorizontalLine: (v) => FlLine(color: Colors.grey.shade200, strokeWidth: 1),
            ),
            barGroups: expenses.asMap().entries.map((entry) {
              final i = entry.key;
              final expense = entry.value;
              final val = double.tryParse(expense['total'].toString()) ?? 0;
              return BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: val,
                    color: Colors.red.shade400,
                    width: 18,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(4),
                      topRight: Radius.circular(4),
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  // ==================== COMBO: Revenue vs Expenses ====================
  Widget _buildRevenueVsExpensesChart(Map<String, dynamic> data, ThemeData theme, Color primary) {
    final revenue = (data['monthly_revenue'] as List<dynamic>?) ?? [];
    final expenses = (data['monthly_expenses'] as List<dynamic>?) ?? [];
    if (revenue.isEmpty && expenses.isEmpty) {
      return _emptyChart(t('revenue_vs_expenses'), theme);
    }

    final months = <String>{};
    for (final r in revenue) months.add(r['month']?.toString() ?? '');
    for (final e in expenses) months.add(e['month']?.toString() ?? '');
    final sortedMonths = months.toList()..sort();

    final revenueMap = <String, double>{};
    for (final r in revenue) {
      revenueMap[r['month']?.toString() ?? ''] = double.tryParse(r['revenue'].toString()) ?? 0;
    }
    final expenseMap = <String, double>{};
    for (final e in expenses) {
      expenseMap[e['month']?.toString() ?? ''] = double.tryParse(e['expenses'].toString()) ?? 0;
    }

    final revenueSpots = <FlSpot>[];
    final expenseBars = <BarChartGroupData>[];
    for (int i = 0; i < sortedMonths.length; i++) {
      final m = sortedMonths[i];
      revenueSpots.add(FlSpot(i.toDouble(), revenueMap[m] ?? 0));
      expenseBars.add(BarChartGroupData(
        x: i,
        barRods: [
          BarChartRodData(
            toY: expenseMap[m] ?? 0,
            color: Colors.red.shade300.withOpacity(0.6),
            width: 16,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(3),
              topRight: Radius.circular(3),
            ),
          ),
        ],
      ));
    }

    final allValues = [
      ...revenueSpots.map((s) => s.y),
      ...expenseBars.map((b) => b.barRods.first.toY),
    ];
    final maxY = allValues.isEmpty ? 100.0 : allValues.reduce((a, b) => a > b ? a : b) * 1.15;

    return _chartCard(
      title: t('revenue_vs_expenses'),
      theme: theme,
      child: SizedBox(
        height: 220,
        child: Stack(
          children: [
            BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceEvenly,
                maxY: maxY,
                barTouchData: BarTouchData(enabled: false),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 50,
                      getTitlesWidget: (v, meta) => Text(
                        _shortNum(v),
                        style: const TextStyle(fontSize: 10, color: Colors.grey),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (v, meta) {
                        final idx = v.toInt();
                        if (idx < 0 || idx >= sortedMonths.length) return const SizedBox.shrink();
                        final m = sortedMonths[idx];
                        return Text(
                          m.length >= 7 ? m.substring(5, 7) : m,
                          style: const TextStyle(fontSize: 10, color: Colors.grey),
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
                  getDrawingHorizontalLine: (v) => FlLine(color: Colors.grey.shade200, strokeWidth: 1),
                ),
                barGroups: expenseBars,
              ),
            ),
            LineChart(
              LineChartData(
                maxY: maxY,
                minY: 0,
                lineTouchData: const LineTouchData(enabled: false),
                titlesData: const FlTitlesData(show: false),
                borderData: FlBorderData(show: false),
                gridData: const FlGridData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: revenueSpots,
                    isCurved: true,
                    color: primary,
                    barWidth: 2.5,
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (spot, pct, bar, idx) => FlDotCirclePainter(
                        radius: 3,
                        color: primary,
                        strokeWidth: 0,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      legend: Row(
        children: [
          Container(width: 12, height: 4, decoration: BoxDecoration(color: primary, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 4),
          Text(t('revenue'), style: const TextStyle(fontSize: 10, color: Colors.grey)),
          const SizedBox(width: 12),
          Container(width: 12, height: 8, decoration: BoxDecoration(color: Colors.red.shade300, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 4),
          Text(t('expenses'), style: const TextStyle(fontSize: 10, color: Colors.grey)),
        ],
      ),
    );
  }

  // ==================== HELPERS ====================
  Widget _chartCard({required String title, required ThemeData theme, required Widget child, Widget? legend}) {
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.35),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
            if (legend != null) ...[const SizedBox(height: 8), legend],
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }

  Widget _emptyChart(String title, ThemeData theme) {
    return _chartCard(
      title: title,
      theme: theme,
      child: SizedBox(
        height: 120,
        child: Center(
          child: Text(
            t('no_data_available'),
            style: TextStyle(color: Colors.grey.shade500),
          ),
        ),
      ),
    );
  }

  String _formatCurrency(dynamic value) {
    final v = double.tryParse(value.toString()) ?? 0;
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}K';
    return v.toStringAsFixed(0);
  }

  String _shortNum(double v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(0)}K';
    return v.toStringAsFixed(0);
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
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return t('just_now');
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    return '${dt.day}/${dt.month}';
  }
}
