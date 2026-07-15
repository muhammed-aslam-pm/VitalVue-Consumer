import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class ActionCaptureDialog extends StatefulWidget {
  const ActionCaptureDialog({super.key});

  @override
  State<ActionCaptureDialog> createState() => _ActionCaptureDialogState();
}

class _ActionCaptureDialogState extends State<ActionCaptureDialog> {
  String? _selectedAction;
  final TextEditingController _otherController = TextEditingController();

  final List<String> _actions = [
    'Device Reconnected',
    'Network Reset',
    'Battery Replaced',
    'Band Adjusted',
    'Other Action',
  ];

  @override
  void dispose() {
    _otherController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
      child: Container(
        width: 400,
        decoration: BoxDecoration(
          color: const Color(0xFF141620),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 32,
              spreadRadius: 4,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 16, 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Action Capture',
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, color: Colors.white54, size: 20),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Colors.white10),
            
            // Body
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Action Taken',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: _actions.map((action) {
                      final isSelected = _selectedAction == action;
                      return InkWell(
                        onTap: () => setState(() => _selectedAction = action),
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: isSelected 
                                ? const Color(0xFF2C2F3D)
                                : const Color(0xFF1F222F),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: isSelected 
                                  ? const Color(0xFF1A73E8) 
                                  : Colors.transparent,
                            ),
                          ),
                          child: Text(
                            action,
                            style: TextStyle(
                              color: isSelected ? const Color(0xFF1A73E8) : Colors.white70,
                              fontSize: 13,
                              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  
                  if (_selectedAction == 'Other Action') ...[
                    const SizedBox(height: 16),
                    TextField(
                      controller: _otherController,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Describe the action...',
                        hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
                        filled: true,
                        fillColor: const Color(0xFF1F222F),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            
            const Divider(height: 1, color: Colors.white10),
            
            // Footer
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white.withValues(alpha: 0.6),
                      side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _selectedAction == null ? null : () {
                      if (_selectedAction == 'Other Action' && _otherController.text.trim().isEmpty) {
                        return; // Prevent submitting empty 'Other'
                      }
                      final result = _selectedAction == 'Other Action' 
                          ? 'Other: ${_otherController.text.trim()}' 
                          : _selectedAction;
                      Navigator.of(context).pop(result);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFBCAAA4), // the brownish color from screenshot
                      foregroundColor: const Color(0xFF3E2723),
                      disabledBackgroundColor: const Color(0xFFBCAAA4).withValues(alpha: 0.3),
                      disabledForegroundColor: Colors.black38,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    child: const Text('Confirm', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
