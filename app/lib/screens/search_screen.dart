import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/drug.dart';
import '../providers/cabinet_provider.dart';
import '../services/api_service.dart';
import '../services/bottle_scanner_service.dart';
import 'drug_detail_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _controller = TextEditingController();
  final BottleScannerService _scannerService = BottleScannerService();
  Timer? _debounce;
  List<Drug> _allCatalogDrugs = [];
  List<Drug> _filteredDrugs = [];
  bool _isLoading = true;
  bool _isLiveSearching = false;
  bool _isScanningBottle = false;
  String? _liveSearchNote;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _fetchCatalog();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _fetchCatalog() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final provider = context.read<CabinetProvider>();
      final api = ApiService(baseUrl: provider.serverUrl);
      final drugs = await api.getDrugs(limit: 100);
      if (!mounted) return;
      setState(() {
        _allCatalogDrugs = drugs;
        _filteredDrugs = drugs;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Could not reach server at ${context.read<CabinetProvider>().serverUrl}. Ensure backend is running.';
        _isLoading = false;
      });
    }
  }

  void _onSearchChanged(String rawQuery) {
    _debounce?.cancel();
    final query = rawQuery.trim();

    if (query.isEmpty) {
      setState(() {
        _filteredDrugs = _allCatalogDrugs;
        _isLiveSearching = false;
        _liveSearchNote = null;
      });
      return;
    }

    final q = query.toLowerCase();
    final localMatches = _allCatalogDrugs.where((d) {
      final b = d.brandName?.toLowerCase() ?? '';
      final g = d.genericName.toLowerCase();
      final r = d.rxcui.toLowerCase();
      return b.contains(q) || g.contains(q) || r.contains(q);
    }).toList();

    setState(() {
      _filteredDrugs = localMatches;
      _liveSearchNote = null;
    });

    // If no local match and user typed at least 3 chars, auto-search official FDA/RxNorm databases after a short pause
    if (localMatches.isEmpty && query.length >= 3) {
      _debounce = Timer(const Duration(milliseconds: 700), () {
        _searchLiveFederalDatabases(query);
      });
    }
  }

  Future<void> _searchLiveFederalDatabases(String query) async {
    final trimmed = query.trim();
    if (trimmed.length < 3 || _isLiveSearching) return;

    setState(() {
      _isLiveSearching = true;
      _liveSearchNote = null;
    });

    try {
      final provider = context.read<CabinetProvider>();
      final api = ApiService(baseUrl: provider.serverUrl);
      final results = await api.getDrugs(query: trimmed, limit: 25);

      if (!mounted) return;
      if (results.isNotEmpty) {
        // Merge newly discovered canonical drug(s) into local catalog list without duplicates
        final updatedCatalog = List<Drug>.from(_allCatalogDrugs);
        for (final d in results) {
          if (!updatedCatalog.any((existing) => existing.rxcui == d.rxcui)) {
            updatedCatalog.add(d);
          }
        }
        updatedCatalog.sort((a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));

        setState(() {
          _allCatalogDrugs = updatedCatalog;
          _filteredDrugs = results;
          _isLiveSearching = false;
          _liveSearchNote = 'Verified via official FDA, RxNorm & CMS databases.';
        });
      } else {
        setState(() {
          _isLiveSearching = false;
          _liveSearchNote = 'No official FDA medication matched "$trimmed". Check spelling and try the brand or generic name.';
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLiveSearching = false;
        _liveSearchNote = 'Could not reach official databases right now. Please try again.';
      });
    }
  }

  Future<void> _scanPillBottle() async {
    if (_isScanningBottle) return;
    setState(() => _isScanningBottle = true);

    try {
      final result = await _scannerService.scanBottleAndDeletePhoto(_allCatalogDrugs);
      if (!mounted) return;

      if (result == null) {
        // User canceled camera
        setState(() => _isScanningBottle = false);
        return;
      }

      if (result.matchedCatalogDrug != null) {
        final drug = result.matchedCatalogDrug!;
        _controller.text = drug.displayName;
        setState(() {
          _filteredDrugs = [drug];
          _isScanningBottle = false;
          _liveSearchNote = 'Photo immediately deleted. Matched "${drug.displayName}" from label.';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Photo deleted — found ${drug.displayName}')),
        );
      } else if (result.queryTerm != null && result.queryTerm!.isNotEmpty) {
        final term = result.queryTerm!;
        _controller.text = term;
        setState(() {
          _isScanningBottle = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Photo deleted — searching official FDA database for "$term"')),
        );
        await _searchLiveFederalDatabases(term);
      } else {
        setState(() {
          _isScanningBottle = false;
          _liveSearchNote = 'Photo immediately deleted. Could not read a medication name — try holding the bottle closer or typing the name above.';
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isScanningBottle = false;
        _liveSearchNote = 'Could not open camera. Please check camera permission or type the medication name.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cabinetProvider = context.watch<CabinetProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Medication to Cabinet'),
        elevation: 0,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              controller: _controller,
              onChanged: _onSearchChanged,
              onSubmitted: _searchLiveFederalDatabases,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Type any U.S. brand or generic medicine...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _controller.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        tooltip: 'Clear search',
                        onPressed: () {
                          _controller.clear();
                          _onSearchChanged('');
                        },
                      )
                    : null,
                filled: true,
                fillColor: Theme.of(context).brightness == Brightness.dark
                    ? Colors.grey.shade900
                    : Colors.grey.shade100,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          if (BottleScannerService.isSupported)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton.tonalIcon(
                  onPressed: _isScanningBottle ? null : _scanPillBottle,
                  icon: _isScanningBottle
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.camera_alt_outlined),
                  label: Text(
                    _isScanningBottle
                        ? 'Reading label & deleting photo...'
                        : 'Scan Pill Bottle (Photo Auto-Deleted)',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
          if (_liveSearchNote != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  Icon(Icons.verified_outlined, size: 16, color: Colors.teal.shade700),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _liveSearchNote!,
                      style: TextStyle(fontSize: 13, color: Colors.teal.shade800),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: _buildBody(cabinetProvider),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(CabinetProvider cabinet) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off, size: 48, color: Colors.grey.shade400),
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade700),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _fetchCatalog,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry Connection'),
              ),
            ],
          ),
        ),
      );
    }

    if (_isLiveSearching) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                'Searching official FDA, RxNorm & CMS databases...',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Text(
                'Cross-referencing generic approvals, active NDCs, and pharmacy pricing.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
      );
    }

    if (_filteredDrugs.isEmpty) {
      final query = _controller.text.trim();
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.medication_outlined, size: 52, color: Colors.grey.shade400),
              const SizedBox(height: 12),
              Text(
                'No local match for "$query".',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (query.length >= 3) ...[
                const SizedBox(height: 14),
                SizedBox(
                  height: 48,
                  child: FilledButton.icon(
                    onPressed: () => _searchLiveFederalDatabases(query),
                    icon: const Icon(Icons.travel_explore),
                    label: Text('Search Official FDA Databases for "$query"'),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      itemCount: _filteredDrugs.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final drug = _filteredDrugs[index];
        final watched = cabinet.isWatched(drug.rxcui);

        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => DrugDetailScreen(drug: drug)),
            );
          },
          title: Text(
            drug.displayName,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
          ),
          subtitle: Text(
            '${drug.subtitle}  •  Tap to view details',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 13.5),
          ),
          trailing: watched
              ? Chip(
                  label: const Text('In Cabinet', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  backgroundColor: Colors.teal.shade50,
                  side: BorderSide(color: Colors.teal.shade300),
                )
              : FilledButton.tonalIcon(
                  onPressed: () async {
                    await cabinet.addDrug(drug);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('${drug.displayName} added to your cabinet'),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Watch'),
                ),
        );
      },
    );
  }
}
