import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'split_tunneling.dart' as split_tunneling;

class SettingsScreen extends StatefulWidget {
  final bool highlightFields;
  const SettingsScreen({super.key, this.highlightFields = false});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> with SingleTickerProviderStateMixin {
  final TextEditingController _tunnelKeyController = TextEditingController();
  final List<TextEditingController> _scriptKeyControllers = [TextEditingController()];
  double _coalesceValue = 500;
  bool _redirectToTelegram = false;
  bool _firstRedirectDone = false;
  final TextEditingController _telegramChannelController = TextEditingController();
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    if (widget.highlightFields) {
      _pulseController.repeat(reverse: true);
    }
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _tunnelKeyController.text = prefs.getString('tunnel_key') ?? '';
      List<String>? scriptKeys = prefs.getStringList('script_keys');
      if (scriptKeys != null && scriptKeys.isNotEmpty) {
        _scriptKeyControllers.clear();
        for (var key in scriptKeys) {
          _scriptKeyControllers.add(TextEditingController(text: key));
        }
      }
      _coalesceValue = prefs.getDouble('coalesce_value') ?? 500;
      _redirectToTelegram = prefs.getBool('redirect_to_telegram') ?? false;
      _firstRedirectDone = prefs.getBool('first_redirect_done') ?? false;
      final String channelVal = prefs.getString('telegram_channel_username') ?? '';
      _telegramChannelController.text = channelVal.isEmpty ? '@Tel7_24Coding' : channelVal;
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    
    List<String> validScriptKeys = _scriptKeyControllers
        .map((c) => c.text.trim())
        .where((text) => text.isNotEmpty)
        .toList();
        
    final oldScriptKeys = prefs.getStringList('script_keys') ?? [];
    bool keysChanged = false;
    if (oldScriptKeys.length != validScriptKeys.length) {
      keysChanged = true;
    } else {
      for (int i = 0; i < oldScriptKeys.length; i++) {
        if (oldScriptKeys[i] != validScriptKeys[i]) {
          keysChanged = true;
          break;
        }
      }
    }

    if (keysChanged) {
      await prefs.setInt('accumulated_daily_requests', 0);
    }
    
    await prefs.setString('tunnel_key', _tunnelKeyController.text.trim());
    await prefs.setStringList('script_keys', validScriptKeys);
    await prefs.setDouble('coalesce_value', _coalesceValue);
    await prefs.setBool('redirect_to_telegram', _redirectToTelegram);
    await prefs.setString('telegram_channel_username', _telegramChannelController.text.trim());
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Configuration saved!')),
      );
      Navigator.pop(context, true);
    }
  }

  void _addScriptKey() {
    setState(() {
      _scriptKeyControllers.add(TextEditingController());
    });
  }

  void _removeScriptKey(int index) {
    setState(() {
      if (_scriptKeyControllers.length > 1) {
        _scriptKeyControllers.removeAt(index);
      }
    });
  }

  @override
  void dispose() {
    _tunnelKeyController.dispose();
    _telegramChannelController.dispose();
    for (var controller in _scriptKeyControllers) {
      controller.dispose();
    }
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: const Text('VPN Configuration'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader("SECURITY", Icons.security),
            const SizedBox(height: 15),
            _buildTextField(
              controller: _tunnelKeyController,
              label: "Tunnel Key (64 hex characters)",
              icon: Icons.key,
              isObscure: true,
              pulse: true,
            ),
            const SizedBox(height: 30),
            
            _buildSectionHeader("GOOGLE APPS SCRIPT", Icons.cloud_circle),
            const SizedBox(height: 10),
            const Text(
              "Add multiple script keys to load balance and share the daily 20k request quota across multiple Google accounts.",
              style: TextStyle(color: Colors.white54, fontSize: 13),
            ),
            const SizedBox(height: 15),
            
            ...List.generate(_scriptKeyControllers.length, (index) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 15),
                child: Row(
                  children: [
                    Expanded(
                      child: _buildTextField(
                        controller: _scriptKeyControllers[index],
                        label: "Deployment ID ${index + 1}",
                        icon: Icons.link,
                        pulse: true,
                      ),
                    ),
                    if (_scriptKeyControllers.length > 1) ...[
                      const SizedBox(width: 10),
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline, color: Colors.redAccent),
                        onPressed: () => _removeScriptKey(index),
                      ),
                    ]
                  ],
                ),
              );
            }),
            
            OutlinedButton.icon(
              onPressed: _addScriptKey,
              icon: const Icon(Icons.add, color: Colors.cyanAccent),
              label: const Text("Add Another Script Key", style: TextStyle(color: Colors.cyanAccent)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.cyanAccent),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            
            const SizedBox(height: 40),
            _buildSectionHeader("QUOTA OPTIMIZATION", Icons.speed),
            const SizedBox(height: 15),
            const Text(
              "Request Coalescing (Buffer Time)",
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
            const SizedBox(height: 5),
            Text(
              "Higher values save Google quotas but increase latency. \nCurrent: ${_coalesceValue.toInt()} ms",
              style: const TextStyle(color: Colors.white54, fontSize: 13),
            ),
            Slider(
              value: _coalesceValue,
              min: 0,
              max: 2000,
              divisions: 20,
              activeColor: Colors.cyanAccent,
              inactiveColor: Colors.white12,
              onChanged: (value) {
                setState(() {
                  _coalesceValue = value;
                });
              },
            ),
            

            
            const SizedBox(height: 40),
            _buildSectionHeader("ADVANCED", Icons.tune),
            const SizedBox(height: 15),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.call_split, color: Colors.white70),
              title: const Text("Split Tunneling", style: TextStyle(color: Colors.white, fontSize: 16)),
              subtitle: const Text("Select which apps bypass the VPN", style: TextStyle(color: Colors.white54, fontSize: 13)),
              trailing: const Icon(Icons.chevron_right, color: Colors.white54),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const split_tunneling.SplitTunnelingScreen()),
                );
              },
            ),
            
            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton(
                onPressed: _saveSettings,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.cyan,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Text("SAVE CONFIGURATION", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: Colors.cyanAccent, size: 20),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            color: Colors.cyanAccent,
            fontSize: 14,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.5,
          ),
        ),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool isObscure = false,
    bool pulse = false,
  }) {
    if (pulse && widget.highlightFields) {
      return AnimatedBuilder(
        animation: _pulseController,
        builder: (context, child) {
          final color = Color.lerp(Colors.white10, Colors.cyanAccent, _pulseController.value)!;
          final glowWidth = _pulseController.value * 4.0;
          return Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.cyanAccent.withOpacity(_pulseController.value * 0.25),
                  blurRadius: 8 + glowWidth,
                  spreadRadius: glowWidth / 2,
                )
              ],
            ),
            child: TextField(
              controller: controller,
              obscureText: isObscure,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: label,
                labelStyle: const TextStyle(color: Colors.white54),
                prefixIcon: Icon(icon, color: Colors.white54),
                filled: true,
                fillColor: const Color(0xFF1E293B),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: color, width: 1.5),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: color, width: 1.5),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: Colors.cyanAccent, width: 2),
                ),
              ),
            ),
          );
        },
      );
    }

    return TextField(
      controller: controller,
      obscureText: isObscure,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white54),
        prefixIcon: Icon(icon, color: Colors.white54),
        filled: true,
        fillColor: Colors.white.withOpacity(0.05),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Colors.cyanAccent, width: 1),
        ),
      ),
    );
  }
}
