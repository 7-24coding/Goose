import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SplitTunnelingScreen extends StatefulWidget {
  const SplitTunnelingScreen({super.key});

  @override
  State<SplitTunnelingScreen> createState() => _SplitTunnelingScreenState();
}

class _SplitTunnelingScreenState extends State<SplitTunnelingScreen> {
  static const platform = MethodChannel('com.goose.vpn/control');
  List<Map<String, String>> _installedApps = [];
  Set<String> _excludedApps = {};
  bool _isLoading = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final List<String> savedExcluded = prefs.getStringList('excluded_apps') ?? [
        "com.farsitel.bazaar",
        "ir.mservices.myket",
        "cab.snapp.passenger",
        "ir.snapp.passenger",
        "ir.snapp.food",
        "ir.divar",
        "ir.tapsi.passenger",
        "ir.resana.rubika",
        "ir.rubika",
        "ir.eitaa.messenger",
        "ir.sproject.bale",
        "mobi.smartcup.splus",
        "ir.medu.shad",
        "com.aparat.filimo",
        "ir.namava.android",
        "com.aparat",
        "org.neshan.maps",
        "ir.maps.balad",
        "ir.mtn.myirancell",
        "ir.mci.myhamrah",
        "com.digikala.tarh",
        "com.torob.android"
      ]; // Default hardcoded list
      
      setState(() {
        _excludedApps = savedExcluded.toSet();
      });

      final List<dynamic> apps = await platform.invokeMethod('getInstalledApps');
      
      if (mounted) {
        setState(() {
          _installedApps = apps.map((app) => Map<String, String>.from(app)).toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load apps: $e')),
        );
      }
    }
  }

  Future<void> _saveExcludedApps() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('excluded_apps', _excludedApps.toList());
  }

  void _toggleApp(String packageName) {
    setState(() {
      if (_excludedApps.contains(packageName)) {
        _excludedApps.remove(packageName);
      } else {
        _excludedApps.add(packageName);
      }
    });
    _saveExcludedApps();
  }

  @override
  Widget build(BuildContext context) {
    final filteredApps = _installedApps.where((app) {
      final appName = app['appName']?.toLowerCase() ?? '';
      return appName.contains(_searchQuery.toLowerCase());
    }).toList();

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: const Text('Split Tunneling'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Search apps...',
                hintStyle: const TextStyle(color: Colors.white54),
                prefixIcon: const Icon(Icons.search, color: Colors.white54),
                filled: true,
                fillColor: const Color(0xFF1E293B),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                });
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Text(
              "Checked apps will bypass the VPN and connect directly to the internet.",
              style: TextStyle(color: Colors.cyanAccent.withOpacity(0.8), fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Colors.cyanAccent))
                : ListView.builder(
                    itemCount: filteredApps.length,
                    itemBuilder: (context, index) {
                      final app = filteredApps[index];
                      final packageName = app['packageName'] ?? '';
                      final appName = app['appName'] ?? packageName;
                      final isExcluded = _excludedApps.contains(packageName);

                      return CheckboxListTile(
                        title: Text(appName, style: const TextStyle(color: Colors.white)),
                        subtitle: Text(packageName, style: const TextStyle(color: Colors.white54, fontSize: 11)),
                        value: isExcluded,
                        activeColor: Colors.cyanAccent,
                        checkColor: Colors.black,
                        onChanged: (bool? value) {
                          _toggleApp(packageName);
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
