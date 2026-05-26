import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'settings.dart';

void main() {
  runApp(const GooseVpnApp());
}

class GooseVpnApp extends StatelessWidget {
  const GooseVpnApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Goose',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.cyanAccent,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const VpnHomeScreen(),
    );
  }
}

class VpnHomeScreen extends StatefulWidget {
  const VpnHomeScreen({super.key});

  @override
  State<VpnHomeScreen> createState() => _VpnHomeScreenState();
}

class _VpnHomeScreenState extends State<VpnHomeScreen> with SingleTickerProviderStateMixin {
  static const platform = MethodChannel('com.goose.vpn/control');
  String vpnState = 'stopped';
  late AnimationController _pulseController;

  String _downloadText = "0.0 B";
  String _uploadText = "0.0 B";
  String _quotaText = "0 / 20,000";
  double _quotaProgress = 0.0;
  Timer? _statsTimer;

  String selectedMode = "VPN";
  String _pingText = "--";
  bool _hasRedirectedThisSession = false;
  int _accumulatedDailyRequests = 0;
  int _lastDailyCount = 0;
  int _uniqueScriptsCount = 1;
  List<dynamic> _endpoints = [];

  bool get isConnected => vpnState == 'connected';
  
  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    
    _loadSavedMode();
    _loadDailyQuota();
    _checkVpnStatus();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _statsTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadDailyQuota() async {
    final prefs = await SharedPreferences.getInstance();
    final todayStr = DateTime.now().toIso8601String().substring(0, 10);
    final lastResetDate = prefs.getString('last_usage_reset_date') ?? '';
    if (lastResetDate != todayStr) {
      await prefs.setString('last_usage_reset_date', todayStr);
      await prefs.setInt('accumulated_daily_requests', 0);
      setState(() {
        _accumulatedDailyRequests = 0;
      });
    } else {
      setState(() {
        _accumulatedDailyRequests = prefs.getInt('accumulated_daily_requests') ?? 0;
      });
    }
  }

  Future<void> _loadSavedMode() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> scriptKeys = prefs.getStringList('script_keys') ?? [];
    final uniqueKeysCount = scriptKeys.map((k) => k.trim()).where((k) => k.isNotEmpty).toSet().length;
    setState(() {
      selectedMode = prefs.getString('selected_mode') ?? 'VPN';
      _uniqueScriptsCount = uniqueKeysCount > 0 ? uniqueKeysCount : 1;
    });
  }

  Future<void> _saveSelectedMode(String mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selected_mode', mode);
  }

  Future<void> _checkVpnStatus() async {
    try {
      final String? statsJson = await platform.invokeMethod('getStats');
      if (statsJson != null) {
        final Map<String, dynamic> data = jsonDecode(statsJson);
        final String status = data['status'] ?? 'stopped';
        final int dailyCount = data['daily_count'] ?? 0;
        setState(() {
          vpnState = status;
          _lastDailyCount = dailyCount;
        });
        if (status != 'stopped' && !status.startsWith('failed')) {
          _fetchStats();
          _startStatsTimer();
        }
      }
    } catch (e) {
      debugPrint("Failed to check VPN status: $e");
    }
  }

  void _startStatsTimer() {
    _statsTimer?.cancel();
    _statsTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _fetchStats();
    });
  }

  void _stopStatsTimer() {
    _statsTimer?.cancel();
    _statsTimer = null;
  }

  void _resetStats() {
    _downloadText = "0.0 B";
    _uploadText = "0.0 B";
    final int totalQuotaLimit = _uniqueScriptsCount * 20000;
    _quotaText = "$_accumulatedDailyRequests / ${totalQuotaLimit.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')}";
    _quotaProgress = (_accumulatedDailyRequests / totalQuotaLimit.toDouble()).clamp(0.0, 1.0);
    _pingText = "--";
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return "0.0 B";
    if (bytes < 1024) return "$bytes B";
    double kb = bytes / 1024;
    if (kb < 1024) return "${kb.toStringAsFixed(1)} KB";
    double mb = kb / 1024;
    if (mb < 1024) return "${mb.toStringAsFixed(1)} MB";
    double gb = mb / 1024;
    return "${gb.toStringAsFixed(1)} GB";
  }

  Future<void> _fetchStats() async {
    if (vpnState == 'stopped' || vpnState.startsWith('failed')) return;
    try {
      final String? statsJson = await platform.invokeMethod('getStats');
      if (statsJson != null) {
        final Map<String, dynamic> data = jsonDecode(statsJson);
        final String status = data['status'] ?? 'stopped';
        final int bytesIn = data['bytes_in'] ?? 0;
        final int bytesOut = data['bytes_out'] ?? 0;
        final int dailyCount = data['daily_count'] ?? 0;
        final int scriptCount = data['script_count'] ?? 0;
        final int pingVal = data['ping'] ?? -1;
        final List<dynamic> endpointsData = data['endpoints'] ?? [];

        if (mounted) {
          final int delta = dailyCount - _lastDailyCount;
          if (delta > 0) {
            _accumulatedDailyRequests += delta;
            _lastDailyCount = dailyCount;
          } else if (dailyCount < _lastDailyCount) {
            // Backend daily count reset
            _lastDailyCount = dailyCount;
          }

          // If the server-reported script quota is less than our accumulated UI quota,
          // it means the script quota was reset (e.g., 24 hours passed).
          // We only check for > 0 to avoid resetting during the first second of connection before the first response.
          if (scriptCount > 0 && scriptCount < _accumulatedDailyRequests) {
            _accumulatedDailyRequests = scriptCount;
          }

          final int displayQuota = scriptCount > _accumulatedDailyRequests ? scriptCount : _accumulatedDailyRequests;
          
          if (displayQuota != _accumulatedDailyRequests || delta > 0) {
            _accumulatedDailyRequests = displayQuota;
            final prefs = await SharedPreferences.getInstance();
            await prefs.setInt('accumulated_daily_requests', _accumulatedDailyRequests);
          }

          setState(() {
            vpnState = status;
            _endpoints = endpointsData.cast<Map<String, dynamic>>();
            _downloadText = _formatBytes(bytesIn);
            _uploadText = _formatBytes(bytesOut);
            
            final int totalQuotaLimit = _uniqueScriptsCount * 20000;
            _quotaText = "$displayQuota / ${totalQuotaLimit.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')}";
            _quotaProgress = (displayQuota / totalQuotaLimit.toDouble()).clamp(0.0, 1.0);
            
            if (pingVal < 0) {
              _pingText = "--";
            } else {
              _pingText = "$pingVal ms";
            }
          });

          if (status == 'connected') {
            final prefs = await SharedPreferences.getInstance();
            final bool firstRedirectDone = prefs.getBool('first_redirect_done') ?? false;
            if (!firstRedirectDone) {
              await prefs.setBool('first_redirect_done', true);
              _hasRedirectedThisSession = true;
              final String channelVal = prefs.getString('telegram_channel_username') ?? '';
              final String channel = channelVal.isEmpty ? 'Tel7_24Coding' : channelVal;
              try {
                final cleanChannel = channel.replaceAll('@', '').trim();
                await platform.invokeMethod('openTelegramChannel', {
                  'username': cleanChannel,
                });
              } catch (e) {
                debugPrint("Failed to perform first-time Telegram redirect: $e");
              }
            } else if (!_hasRedirectedThisSession) {
              _hasRedirectedThisSession = true;
              _handleTelegramRedirect();
            }
          }

          if (status == 'stopped' || status.startsWith('failed')) {
            _stopStatsTimer();
          }
        }
      }
    } catch (e) {
      debugPrint("Failed to fetch stats: $e");
    }
  }

  Future<void> _handleTelegramRedirect() async {
    final prefs = await SharedPreferences.getInstance();
    final bool redirect = prefs.getBool('redirect_to_telegram') ?? false;
    final String channelVal = prefs.getString('telegram_channel_username') ?? '';
    final String channel = channelVal.isEmpty ? 'Tel7_24Coding' : channelVal;
    
    if (redirect && channel.isNotEmpty) {
      final int lastRedirect = prefs.getInt('last_telegram_redirect_time') ?? 0;
      final int now = DateTime.now().millisecondsSinceEpoch;
      
      // Cooldown of 24 hours (24 * 60 * 60 * 1000 = 86400000 ms)
      if (now - lastRedirect > 86400000) {
        try {
          final cleanChannel = channel.replaceAll('@', '').trim();
          await platform.invokeMethod('openTelegramChannel', {
            'username': cleanChannel,
          });
          await prefs.setInt('last_telegram_redirect_time', now);
        } catch (e) {
          debugPrint("Failed to redirect to Telegram: $e");
        }
      }
    }
  }

  void _openSettingsWithHighlight() {
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => const SettingsScreen(highlightFields: true),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          const begin = Offset(1.0, 0.0);
          const end = Offset.zero;
          const curve = Curves.easeInOut;
          var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
          var offsetAnimation = animation.drive(tween);
          return SlideTransition(
            position: offsetAnimation,
            child: child,
          );
        },
      ),
    ).then((_) {
      _loadSavedMode();
      _loadDailyQuota();
    });
  }

  void _toggleConnection() async {
    final prefs = await SharedPreferences.getInstance();
    final tunnelKey = prefs.getString('tunnel_key') ?? '';
    final scriptKeys = prefs.getStringList('script_keys') ?? [];
    final excludedApps = prefs.getStringList('excluded_apps');

    if (tunnelKey.isEmpty || scriptKeys.isEmpty) {
      _openSettingsWithHighlight();
      return;
    }

    try {
      if (vpnState != 'stopped') {
        await platform.invokeMethod('stopVpn');
        _stopStatsTimer();
        setState(() {
          vpnState = 'stopped';
          _resetStats();
        });
      } else {
        // Construct the config to pass to native side
        final scriptKeysJson = '[' + scriptKeys.map((e) => '"$e"').join(',') + ']';
        String configJson = '{"tunnel_key": "$tunnelKey", "script_keys": $scriptKeysJson}'; 
        if (excludedApps != null) {
          final excludedAppsJson = '[' + excludedApps.map((e) => '"$e"').join(',') + ']';
          configJson = '{"tunnel_key": "$tunnelKey", "script_keys": $scriptKeysJson, "excluded_apps": $excludedAppsJson}';
        }

        
        setState(() {
          vpnState = 'checking_internet';
          _hasRedirectedThisSession = false;
          _lastDailyCount = 0;
        });
        
        await platform.invokeMethod('startVpn', {
          'config': configJson,
          'mode': selectedMode,
        });
        _startStatsTimer();
      }
    } on PlatformException catch (e) {
      debugPrint("Failed to toggle VPN: '${e.message}'.");
      setState(() {
        vpnState = 'failed: ${e.message}';
      });
    }
  }

  Future<void> _openTelegramProxy() async {
    try {
      await platform.invokeMethod('openTelegramProxy');
    } on PlatformException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message ?? 'Could not open Telegram'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Background Animated Gradients
          Positioned(
            top: -100,
            left: -100,
            child: Container(
              width: 300,
              height: 300,
              decoration: const BoxDecoration(
                color: Colors.cyanAccent,
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned(
            bottom: -50,
            right: -50,
            child: Container(
              width: 250,
              height: 250,
              decoration: const BoxDecoration(
                color: Colors.deepPurpleAccent,
                shape: BoxShape.circle,
              ),
            ),
          ),
          // Blur layer for glassmorphism background
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 80, sigmaY: 80),
            child: Container(color: Colors.black.withOpacity(0.1)),
          ),
          
          SafeArea(
            child: Column(
              children: [
                _buildHeader(),
                const Spacer(),
                const Text(
                  "Goose",
                  style: TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 3.0,
                    color: Colors.white,
                    shadows: [
                      Shadow(
                        color: Colors.black38,
                        offset: Offset(0, 4),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 25),
                _buildConnectButton(),
                _buildStatusDescription(),
                _buildModeSelector(),
                _buildTelegramButton(),
                const Spacer(),
                _buildStatsCard(),
                const SizedBox(height: 30),
              ],
            ),
          ),
        ],
      ),
    );
  }



  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Align(
        alignment: Alignment.centerRight,
        child: IconButton(
          icon: const Icon(Icons.settings, color: Colors.white70),
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const SettingsScreen()),
            ).then((_) {
              _loadSavedMode();
              _loadDailyQuota();
            });
          },
        ),
      ),
    );
  }

  Widget _buildConnectButton() {
    final bool isConnecting = vpnState == 'checking_internet' || vpnState == 'checking_relay';
    final bool isConnectedState = vpnState == 'connected';
    final bool isFailedState = vpnState.startsWith('failed');

    Color startColor;
    Color endColor;
    IconData icon;
    String buttonText;
    Color shadowColor;

    if (isConnectedState) {
      startColor = Colors.tealAccent;
      endColor = Colors.cyan;
      icon = Icons.shield_rounded;
      buttonText = "CONNECTED";
      shadowColor = Colors.cyanAccent;
    } else if (isConnecting) {
      startColor = Colors.cyan.shade800;
      endColor = Colors.blue.shade900;
      icon = Icons.hourglass_top_rounded;
      buttonText = "CONNECTING...";
      shadowColor = Colors.blueAccent;
    } else if (isFailedState) {
      startColor = Colors.redAccent.shade400;
      endColor = Colors.red.shade900;
      icon = Icons.error_outline_rounded;
      buttonText = "FAILED";
      shadowColor = Colors.redAccent;
    } else {
      startColor = Colors.grey.shade800;
      endColor = Colors.grey.shade700;
      icon = Icons.shield_outlined;
      buttonText = "TAP TO CONNECT";
      shadowColor = Colors.black;
    }

    return GestureDetector(
      onTap: _toggleConnection,
      child: AnimatedBuilder(
        animation: _pulseController,
        builder: (context, child) {
          double scale = isConnectedState || isConnecting ? 1.0 : 1.0 + (_pulseController.value * 0.05);
          return Transform.scale(
            scale: scale,
            child: Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [startColor, endColor],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: shadowColor.withOpacity(0.5),
                    blurRadius: 30,
                    spreadRadius: isConnectedState || isConnecting ? 10 : 2,
                  ),
                ],
              ),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (isConnecting)
                      const SizedBox(
                        width: 50,
                        height: 50,
                        child: CircularProgressIndicator(
                          color: Colors.cyanAccent,
                          strokeWidth: 4,
                        ),
                      )
                    else
                      Icon(
                        icon,
                        size: 60,
                        color: isConnectedState || isFailedState ? Colors.white : Colors.grey.shade400,
                      ),
                    const SizedBox(height: 10),
                    Text(
                      buttonText,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isConnectedState || isFailedState ? Colors.white : Colors.grey.shade400,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
      ),
    );
  }

  Widget _buildStatusDescription() {
    String description = "";
    Color textColor = Colors.white70;

    if (vpnState == 'checking_internet') {
      description = "Checking internet connection...";
      textColor = Colors.cyanAccent;
    } else if (vpnState == 'checking_relay') {
      description = "Securing tunnel connection...";
      textColor = Colors.cyanAccent;
    } else if (vpnState == 'connected') {
      description = selectedMode == 'Proxy' 
          ? "Local SOCKS5 proxy running on 127.0.0.1:1080"
          : "VPN tunnel established";
      textColor = Colors.greenAccent;
    } else if (vpnState.startsWith('failed')) {
      final errorReason = vpnState.replaceFirst('failed: ', '');
      description = "Error: $errorReason";
      textColor = Colors.redAccent;
    } else {
      description = "Disconnected";
      textColor = Colors.white54;
    }

    return Padding(
      padding: const EdgeInsets.only(top: 15, left: 20, right: 20),
      child: Text(
        description,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: textColor,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildModeSelector() {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: isConnected ? 0.6 : 1.0,
      child: AbsorbPointer(
        absorbing: isConnected,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 20),
          child: SegmentedButton<String>(
            segments: const <ButtonSegment<String>>[
              ButtonSegment<String>(
                value: 'VPN',
                label: Text('VPN Mode (Tunnel)'),
                icon: Icon(Icons.vpn_lock_rounded),
              ),
              ButtonSegment<String>(
                value: 'Proxy',
                label: Text('Proxy Mode'),
                icon: Icon(Icons.settings_input_component_rounded),
              ),
            ],
            selected: <String>{selectedMode},
            onSelectionChanged: (Set<String> newSelection) {
              setState(() {
                selectedMode = newSelection.first;
              });
              _saveSelectedMode(newSelection.first);
            },
            style: ButtonStyle(
              visualDensity: VisualDensity.comfortable,
              backgroundColor: MaterialStateProperty.resolveWith<Color>(
                (Set<MaterialState> states) {
                  if (states.contains(MaterialState.selected)) {
                    return Colors.cyanAccent.withOpacity(0.2);
                  }
                  return Colors.white.withOpacity(0.05);
                },
              ),
              foregroundColor: MaterialStateProperty.all(Colors.white),
              side: MaterialStateProperty.all(
                BorderSide(color: Colors.white.withOpacity(0.1), width: 1.5),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTelegramButton() {
    return AnimatedSize(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      child: (selectedMode == 'Proxy' && isConnected)
          ? Container(
              margin: const EdgeInsets.only(bottom: 20),
              padding: const EdgeInsets.symmetric(horizontal: 20),
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _openTelegramProxy,
                icon: Transform.rotate(
                  angle: -0.2,
                  child: const Icon(Icons.near_me_rounded, size: 24, color: Colors.white),
                ),
                label: const Text(
                  "Connect to Telegram Proxy",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF24A1DE), // Telegram blue
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 4,
                  shadowColor: const Color(0xFF24A1DE).withOpacity(0.4),
                ),
              ),
            )
          : const SizedBox.shrink(),
    );
  }

  Widget _buildStatsCard() {
    return Column(
      children: [
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 20),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: Colors.white.withOpacity(0.1),
              width: 1.5,
            ),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Expanded(child: _buildStatItem("DOWNLOAD", _downloadText, Icons.arrow_downward, Colors.greenAccent)),
                  Expanded(
                    child: GestureDetector(
                      onTap: () async {
                        if (vpnState == 'connected') {
                          setState(() {
                            _pingText = "Testing...";
                          });
                          try {
                            await platform.invokeMethod('triggerPing');
                          } catch (e) {
                            debugPrint("Failed to trigger ping: $e");
                          }
                        }
                      },
                      child: _buildStatItem("LATENCY", _pingText, Icons.bolt_rounded, Colors.cyanAccent),
                    ),
                  ),
                  Expanded(child: _buildStatItem("UPLOAD", _uploadText, Icons.arrow_upward, Colors.orangeAccent)),
                ],
              ),
              const Divider(color: Colors.white24, height: 30),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    "Daily Requests (Quota)",
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                  Text(
                    _quotaText,
                    style: TextStyle(
                      color: Colors.cyanAccent.shade100, 
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              LinearProgressIndicator(
                value: _quotaProgress,
                backgroundColor: Colors.white12,
                valueColor: const AlwaysStoppedAnimation<Color>(Colors.cyanAccent),
                borderRadius: BorderRadius.circular(10),
                minHeight: 8,
              ),
            ],
          ),
        ),
        if (isConnected && _endpoints.isNotEmpty) ...[
          const SizedBox(height: 15),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 20),
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.02),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withOpacity(0.05)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.hub_outlined, color: Colors.cyanAccent, size: 16),
                    SizedBox(width: 8),
                    Text("Live Script Balance", style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 10),
                ..._endpoints.map((ep) {
                  final url = ep['url'] as String? ?? 'unknown';
                  // Extract short ID (like the Go backend shortScriptKey)
                  String shortId = url;
                  final parts = url.split('/');
                  for (int i = 0; i < parts.length - 1; i++) {
                    if (parts[i] == 's') {
                      final id = parts[i + 1];
                      if (id.length > 14) {
                        shortId = "${id.substring(0, 6)}...${id.substring(id.length - 6)}";
                      } else {
                        shortId = id;
                      }
                      break;
                    }
                  }
                  
                  final daily = ep['daily_count'] as int? ?? 0;
                  final isBlacklisted = ep['IsBlacklisted'] as bool? ?? false;
                  
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(
                              isBlacklisted ? Icons.error_outline : Icons.circle, 
                              color: isBlacklisted ? Colors.redAccent : Colors.greenAccent, 
                              size: 8
                            ),
                            const SizedBox(width: 8),
                            Text(shortId, style: TextStyle(color: isBlacklisted ? Colors.white38 : Colors.white70, fontSize: 12)),
                          ],
                        ),
                        Text("$daily reqs", style: TextStyle(color: isBlacklisted ? Colors.white38 : Colors.cyanAccent.shade100, fontSize: 12)),
                      ],
                    ),
                  );
                }).toList(),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon, Color color) {
    return Column(
      children: [
        Icon(icon, color: color, size: 28),
        const SizedBox(height: 8),
        Text(
          value, 
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.white54)),
      ],
    );
  }
}



