import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/drug.dart';
import '../providers/cabinet_provider.dart';
import '../services/api_service.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _controller = TextEditingController();
  List<Drug> _allCatalogDrugs = [];
  List<Drug> _filteredDrugs = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _fetchCatalog();
  }

  Future<void> _fetchCatalog() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final provider = context.read<CabinetProvider>();
      final api = ApiService(baseUrl: provider.serverUrl);
      final drugs = await api.getDrugs();
      setState(() {
        _allCatalogDrugs = drugs;
        _filteredDrugs = drugs;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Could not reach server at ${context.read<CabinetProvider>().serverUrl}. Ensure backend is running.';
        _isLoading = false;
      });
    }
  }

  void _filter(String query) {
    if (query.isEmpty) {
      setState(() => _filteredDrugs = _allCatalogDrugs);
      return;
    }

    final q = query.toLowerCase();
    setState(() {
      _filteredDrugs = _allCatalogDrugs.where((d) {
        final b = d.brandName?.toLowerCase() ?? '';
        final g = d.genericName.toLowerCase();
        final r = d.rxcui.toLowerCase();
        return b.contains(q) || g.contains(q) || r.contains(q);
      }).toList();
    });
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
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _controller,
              onChanged: _filter,
              decoration: InputDecoration(
                hintText: 'Search brand (e.g. Vyvanse, Eliquis, Humira)...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _controller.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _controller.clear();
                          _filter('');
                        },
                      )
                    : null,
                filled: true,
                fillColor: Colors.grey.shade100,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
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

    if (_filteredDrugs.isEmpty) {
      return Center(
        child: Text(
          'No matching medications found.',
          style: TextStyle(color: Colors.grey.shade600),
        ),
      );
    }

    return ListView.separated(
      itemCount: _filteredDrugs.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final drug = _filteredDrugs[index];
        final isAlreadyAdded = cabinet.isWatched(drug.rxcui);

        return ListTile(
          title: Text(
            drug.displayName,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          subtitle: Text(drug.subtitle),
          trailing: isAlreadyAdded
              ? const Chip(
                  avatar: Icon(Icons.check, size: 16, color: Colors.green),
                  label: Text('In Cabinet', style: TextStyle(fontSize: 11)),
                  backgroundColor: Color(0xFFE8F5E9),
                )
              : ElevatedButton.icon(
                  onPressed: () {
                    cabinet.addDrug(drug);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Added ${drug.displayName} to watched cabinet'),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  },
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Watch'),
                  style: ElevatedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
        );
      },
    );
  }
}
