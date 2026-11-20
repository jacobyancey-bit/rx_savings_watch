import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/cabinet_provider.dart';
import '../widgets/drug_card.dart';
import 'drug_detail_screen.dart';
import 'search_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cabinet = context.watch<CabinetProvider>();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.medication_liquid_outlined, color: Colors.teal),
            SizedBox(width: 8),
            Text('Rx Savings Watch', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          IconButton(
            icon: cabinet.isSyncing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync),
            tooltip: 'Sync updates anonymously',
            onPressed: cabinet.isSyncing ? null : () => cabinet.syncCabinet(),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
          ),
        ],
      ),
      body: cabinet.isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () => cabinet.syncCabinet(),
              child: CustomScrollView(
                slivers: [
                  // Overview stats hero banner
                  SliverToBoxAdapter(
                    child: _buildHeroBanner(context, cabinet),
                  ),

                  // Sync error alert if present
                  if (cabinet.syncError != null)
                    SliverToBoxAdapter(
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.red.shade200),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.sync_problem, color: Colors.red.shade700, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Sync warning: Verify backend server is running.\n${cabinet.syncError}',
                                style: TextStyle(fontSize: 11, color: Colors.red.shade900),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  // Cabinet items header
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'My Medication Cabinet (${cabinet.cabinet.length})',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (cabinet.lastChecked != null)
                            Text(
                              'Updated: ${cabinet.lastChecked!.split('T')[0]}',
                              style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                            ),
                        ],
                      ),
                    ),
                  ),

                  // Empty State or List
                  if (cabinet.cabinet.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: _buildEmptyState(context),
                    )
                  else
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final drug = cabinet.cabinet[index];
                          return DrugCard(
                            drug: drug,
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => DrugDetailScreen(drug: drug),
                                ),
                              );
                            },
                            onRemove: () {
                              cabinet.removeDrug(drug.rxcui);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Removed ${drug.displayName}'),
                                  duration: const Duration(seconds: 2),
                                ),
                              );
                            },
                          );
                        },
                        childCount: cabinet.cabinet.length,
                      ),
                    ),
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const SearchScreen()),
          );
        },
        icon: const Icon(Icons.add),
        label: const Text('Add Medication'),
      ),
    );
  }

  Widget _buildHeroBanner(BuildContext context, CabinetProvider cabinet) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.teal.shade800, Colors.teal.shade900],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.teal.withValues(alpha: 0.2),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'GENERIC LAUNCH MONITOR',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 11,
              letterSpacing: 1.2,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStatItem('Watched', '${cabinet.cabinet.length}', Icons.medication),
              _buildStatItem('Launched', '${cabinet.genericLaunchedCount}', Icons.rocket_launch, color: Colors.greenAccent),
              _buildStatItem('Max Savings', cabinet.maxSavingsAvailable > 0 ? '~${cabinet.maxSavingsAvailable.toStringAsFixed(0)}%' : 'N/A', Icons.savings, color: Colors.amberAccent),
              _buildStatItem('Shortages', '${cabinet.shortageCount}', Icons.warning_amber, color: cabinet.shortageCount > 0 ? Colors.orangeAccent : Colors.white70),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon, {Color? color}) {
    return Column(
      children: [
        Icon(icon, size: 20, color: color ?? Colors.white),
        const SizedBox(height: 6),
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color ?? Colors.white,
          ),
        ),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: Colors.white70),
        ),
      ],
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            const Text(
              'Your Cabinet is Empty',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Add your prescriptions to watch for commercial generic launches, acquisition savings, and supply shortages.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SearchScreen()),
                );
              },
              icon: const Icon(Icons.add),
              label: const Text('Add Your First Medication'),
            ),
          ],
        ),
      ),
    );
  }
}
