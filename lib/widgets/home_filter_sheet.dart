// lib/widgets/home_filter_sheet.dart
import 'package:flutter/material.dart';
import '../lang/translations.dart';
import '../utils/tr.dart';
import 'common/price_input_field.dart';
import 'common/price_preset_chip.dart';

class FilterCategoryOption {
  final int id;
  final String label;

  const FilterCategoryOption({required this.id, required this.label});
}

class HomeFilterSheet extends StatefulWidget {
  final String locationFilterMode;
  final String? userVillage;
  final String? userCity;
  final String? userCountry;
  final String? userCityId;
  final String? userVillageId;
  final String? userCountryCode;
  final bool hasPosition;
  final double? distanceFilterKm;
  final double selectedMinPrice;
  final double selectedMaxPrice;
  final int? selectedCategoryId;
  final List<FilterCategoryOption> categories;
  final double minRating;
  final String sortBy;
  final void Function(Map<String, dynamic>) onApply;
  final VoidCallback onReset;
  final VoidCallback onRequestLocation;

  const HomeFilterSheet({
    super.key,
    required this.locationFilterMode,
    this.userVillage,
    this.userCity,
    this.userCountry,
    this.userCityId,
    this.userVillageId,
    this.userCountryCode,
    required this.hasPosition,
    this.distanceFilterKm,
    required this.selectedMinPrice,
    required this.selectedMaxPrice,
    required this.selectedCategoryId,
    required this.categories,
    required this.minRating,
    required this.sortBy,
    required this.onApply,
    required this.onReset,
    required this.onRequestLocation,
  });

  @override
  State<HomeFilterSheet> createState() => _HomeFilterSheetState();
}

class _HomeFilterSheetState extends State<HomeFilterSheet> {
  late String _locationFilterMode;
  late double? _distanceFilterKm;
  late double _selMinPrice;
  late double _selMaxPrice;
  late int? _categoryId;
  late double _rating;
  late String _sort;

  static const double _sliderMax = 100000.0;
  final List<double> _distanceOptions = [5.0, 10.0, 20.0, 50.0];
  final List<String> _sortOptions = [
    'newest',
    'price_low',
    'price_high',
    'popular',
  ];

  @override
  void initState() {
    super.initState();
    _locationFilterMode = widget.locationFilterMode;
    _distanceFilterKm = widget.distanceFilterKm;
    _selMinPrice = widget.selectedMinPrice;
    _selMaxPrice = widget.selectedMaxPrice;
    _categoryId = widget.selectedCategoryId;
    _rating = widget.minRating;
    _sort = widget.sortBy;
  }

  void _setMinPrice(double value) {
    setState(() {
      _selMinPrice = value.clamp(0.0, _sliderMax);
      if (_selMaxPrice != double.infinity && _selMinPrice > _selMaxPrice) {
        _selMaxPrice = _selMinPrice;
      }
    });
  }

  void _setMaxPrice(double value) {
    setState(() {
      if (value == double.infinity) {
        _selMaxPrice = double.infinity;
        return;
      }
      _selMaxPrice = value.clamp(0.0, _sliderMax);
      if (_selMaxPrice < _selMinPrice) {
        _selMinPrice = _selMaxPrice;
      }
    });
  }

  double _sliderToPrice(double sliderValue) {
    if (sliderValue >= _sliderMax) return double.infinity;
    return sliderValue;
  }

  double _priceToSlider(double price) {
    if (price == double.infinity) return _sliderMax;
    return price.clamp(0.0, _sliderMax);
  }

  String _formatPriceLabel(double price) {
    if (price == double.infinity) return t('unlimited');
    if (price >= 1000000) return '\$${(price / 1000000).toStringAsFixed(1)}M';
    if (price >= 1000) return '\$${(price / 1000).toStringAsFixed(1)}K';
    return '\$${price.toStringAsFixed(0)}';
  }

  @override
  Widget build(BuildContext context) {
    final village = widget.userVillage;
    final villageId = widget.userVillageId;
    final city = widget.userCity;
    final cityId = widget.userCityId;
    final country = widget.userCountry;
    final countryCode = widget.userCountryCode;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Row(
              children: [
                Text(
                  t('filters'),
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                TextButton(
                  onPressed: widget.onReset,
                  child: Text(t('reset_all')),
                ),
              ],
            ),
          ),
          const Divider(),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSectionTitle(t('location'), Icons.location_on),
                  const SizedBox(height: 8),
                  if (!widget.hasPosition)
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          widget.onRequestLocation();
                          Navigator.pop(context);
                        },
                        icon: const Icon(Icons.my_location, size: 18),
                        label: Text(t('enable_gps_location')),
                      ),
                    )
                  else
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 8,
                          children: [
                            ChoiceChip(
                              label: Text(tr('all_regions', fallback: 'All Regions')),
                              selected: _locationFilterMode == 'all',
                              onSelected: (_) =>
                                  setState(() => _locationFilterMode = 'all'),
                            ),
                            if (villageId != null || village != null)
                              ChoiceChip(
                                label: Text(
                                  village ?? villageId ?? t('nearby'),
                                ),
                                selected: _locationFilterMode == 'village',
                                onSelected: (_) => setState(
                                  () => _locationFilterMode = 'village',
                                ),
                              ),
                            if (cityId != null || city != null)
                              ChoiceChip(
                                label: Text(
                                  city != null &&
                                          city.isNotEmpty &&
                                          city.toLowerCase() != 'null'
                                      ? city
                                      : (cityId ?? t('nearby')),
                                ),
                                selected: _locationFilterMode == 'city',
                                onSelected: (_) => setState(
                                  () => _locationFilterMode = 'city',
                                ),
                              ),
                            if (countryCode != null || country != null)
                              ChoiceChip(
                                label: Text(
                                  country != null && country.isNotEmpty
                                      ? country
                                      : (countryCode?.toUpperCase() ??
                                            t('unknown_country')),
                                ),
                                selected: _locationFilterMode == 'country',
                                onSelected: (_) => setState(
                                  () => _locationFilterMode = 'country',
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (village != null ||
                            villageId != null ||
                            city != null ||
                            cityId != null ||
                            country != null ||
                            countryCode != null)
                          Text(
                            '${t('location')}: ${[village ?? villageId, city ?? cityId, country ?? countryCode?.toUpperCase()].where((e) => e != null).join(', ')}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurface.withOpacity(0.5),
                            ),
                          ),
                      ],
                    ),
                  const SizedBox(height: 20),
                  _buildSectionTitle(t('radius'), Icons.straighten),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        label: Text(t('all')),
                        selected: _distanceFilterKm == null,
                        onSelected: (_) =>
                            setState(() => _distanceFilterKm = null),
                      ),
                      ..._distanceOptions.map((km) {
                        return ChoiceChip(
                          label: Text('${km.round()} km'),
                          selected: _distanceFilterKm == km,
                          onSelected: (_) =>
                              setState(() => _distanceFilterKm = km),
                        );
                      }),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _buildSectionTitle(t('price_range'), Icons.attach_money),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: PriceInputField(
                          label: t('min'),
                          value: _selMinPrice == double.infinity
                              ? ''
                              : _selMinPrice.toStringAsFixed(0),
                          onChanged: (val) {
                            final parsed = double.tryParse(val) ?? 0;
                            _setMinPrice(parsed);
                          },
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          '—',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      Expanded(
                        child: PriceInputField(
                          label: t('max'),
                          value: _selMaxPrice == double.infinity
                              ? ''
                              : _selMaxPrice.toStringAsFixed(0),
                          hint: t('unlimited'),
                          onChanged: (val) {
                            if (val.isEmpty) {
                              _setMaxPrice(double.infinity);
                              return;
                            }
                            final parsed = double.tryParse(val);
                            if (parsed == null) return;
                            if (parsed <= 0 || parsed >= _sliderMax) {
                              _setMaxPrice(double.infinity);
                            } else {
                              _setMaxPrice(parsed);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _formatPriceLabel(_selMinPrice),
                        style: const TextStyle(fontSize: 12),
                      ),
                      Text(
                        _formatPriceLabel(_selMaxPrice),
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                  RangeSlider(
                    values: RangeValues(
                      _priceToSlider(
                        _selMinPrice,
                      ).clamp(0.0, _priceToSlider(_selMaxPrice)),
                      _priceToSlider(
                        _selMaxPrice,
                      ).clamp(_priceToSlider(_selMinPrice), _sliderMax),
                    ),
                    min: 0,
                    max: _sliderMax,
                    divisions: 1000,
                    labels: RangeLabels(
                      _formatPriceLabel(_selMinPrice),
                      _formatPriceLabel(_selMaxPrice),
                    ),
                    onChanged: (values) {
                      setState(() {
                        _selMinPrice = values.start;
                        _selMaxPrice = _sliderToPrice(values.end);
                        if (_selMaxPrice != double.infinity &&
                            _selMinPrice > _selMaxPrice) {
                          _selMaxPrice = _selMinPrice;
                        }
                      });
                    },
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      PricePresetChip(
                        label: '< \$100',
                        onTap: () {
                          _setMinPrice(0);
                          _setMaxPrice(100);
                        },
                        isActive: _selMinPrice == 0 && _selMaxPrice == 100,
                      ),
                      PricePresetChip(
                        label: '\$100 - \$500',
                        onTap: () {
                          _setMinPrice(100);
                          _setMaxPrice(500);
                        },
                        isActive: _selMinPrice == 100 && _selMaxPrice == 500,
                      ),
                      PricePresetChip(
                        label: '\$500 - \$2K',
                        onTap: () {
                          _setMinPrice(500);
                          _setMaxPrice(2000);
                        },
                        isActive: _selMinPrice == 500 && _selMaxPrice == 2000,
                      ),
                      PricePresetChip(
                        label: '\$2K - \$10K',
                        onTap: () {
                          _setMinPrice(2000);
                          _setMaxPrice(10000);
                        },
                        isActive: _selMinPrice == 2000 && _selMaxPrice == 10000,
                      ),
                      PricePresetChip(
                        label: '> \$10K',
                        onTap: () {
                          _setMinPrice(10000);
                          _setMaxPrice(double.infinity);
                        },
                        isActive:
                            _selMinPrice == 10000 &&
                            _selMaxPrice == double.infinity,
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _buildSectionTitle(t('category'), Icons.category),
                  const SizedBox(height: 8),
                  if (widget.categories.isEmpty)
                    Text(
                      t('no_categories'),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    )
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ChoiceChip(
                          label: Text(t('all')),
                          selected: _categoryId == null,
                          onSelected: (_) => setState(() => _categoryId = null),
                        ),
                        ...widget.categories.map((cat) {
                          return ChoiceChip(
                            label: Text(cat.label),
                            selected: _categoryId == cat.id,
                            onSelected: (_) =>
                                setState(() => _categoryId = cat.id),
                          );
                        }),
                      ],
                    ),
                  const SizedBox(height: 20),
                  _buildSectionTitle(t('sort_by'), Icons.sort),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _sortOptions.map((opt) {
                      final labels = {
                        'newest': tr('newest', fallback: 'Newest'),
                        'price_low': tr(
                          'price_low_high',
                          fallback: 'Price: Low to High',
                        ),
                        'price_high': tr(
                          'price_high_low',
                          fallback: 'Price: High to Low',
                        ),
                        'popular': tr('most_popular', fallback: 'Most Popular'),
                      };
                      return ChoiceChip(
                        label: Text(labels[opt] ?? opt),
                        selected: _sort == opt,
                        onSelected: (_) => setState(() => _sort = opt),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),
                  _buildSectionTitle(t('minimum_rating'), Icons.star),
                  const SizedBox(height: 8),
                  Row(
                    children: List.generate(5, (index) {
                      final starValue = index + 1;
                      return IconButton(
                        icon: Icon(
                          starValue <= _rating ? Icons.star : Icons.star_border,
                          color: Colors.amber,
                        ),
                        onPressed: () =>
                            setState(() => _rating = starValue.toDouble()),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      );
                    }),
                  ),
                  if (_rating > 0)
                    TextButton(
                      onPressed: () => setState(() => _rating = 0),
                      child: Text(t('clear_rating_filter')),
                    ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  widget.onApply({
                    'locationFilterMode': _locationFilterMode,
                    'distanceFilterKm': _distanceFilterKm,
                    'minPrice': _selMinPrice,
                    'maxPrice': _selMaxPrice,
                    'categoryId': _categoryId,
                    'minRating': _rating,
                    'sortBy': _sort,
                  });
                },
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  t('apply_filters'),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}
