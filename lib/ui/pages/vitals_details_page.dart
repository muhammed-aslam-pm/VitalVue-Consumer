import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';

import '../../db/vitals_database.dart';

class VitalsDetailsPage extends StatefulWidget {
  final String title;
  final String dbColumnName;
  final String unit;
  final Color accentColor;

  const VitalsDetailsPage({
    super.key,
    required this.title,
    required this.dbColumnName,
    required this.unit,
    required this.accentColor,
  });

  @override
  State<VitalsDetailsPage> createState() => _VitalsDetailsPageState();
}

class _VitalsDetailsPageState extends State<VitalsDetailsPage> {
  List<Map<String, dynamic>> _vitalsData = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final db = VitalsDatabase.instance;
    final data = await db.getVitalsForLast24Hours();
    
    // Filter out invalid readings (0) only for specific health metrics
    final filteredData = data.where((row) {
      final val = row[widget.dbColumnName];
      if (val == null) return false;
      
      if (['hr', 'spo2', 'bpSys', 'hrv'].contains(widget.dbColumnName)) {
        return val > 0;
      }
      if (widget.dbColumnName == 'battery') {
        return val >= 0;
      }
      return true; // allow 0 for steps, calories, stress, distance, etc.
    }).toList();

    setState(() {
      _vitalsData = filteredData;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1117),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text('${widget.title} History (24h)'),
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.blue))
          : _vitalsData.isEmpty
              ? const Center(
                  child: Text('No data recorded in the last 24 hours.',
                      style: TextStyle(color: Colors.white54)))
              : Column(
                  children: [
                    _buildChartSection(),
                    const SizedBox(height: 16),
                    Expanded(child: _buildListSection()),
                  ],
                ),
    );
  }

  Widget _buildChartSection() {
    return Container(
      height: 250,
      padding: const EdgeInsets.only(right: 24, left: 16, top: 24, bottom: 12),
      child: LineChart(
        LineChartData(
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (value) {
              return FlLine(
                color: Colors.white.withValues(alpha: 0.1),
                strokeWidth: 1,
              );
            },
          ),
          titlesData: FlTitlesData(
            show: true,
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 30,
                interval: _getBottomInterval(),
                getTitlesWidget: (value, meta) {
                  final date = DateTime.fromMillisecondsSinceEpoch(value.toInt());
                  return Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(
                      DateFormat('HH:mm').format(date),
                      style: const TextStyle(color: Colors.white54, fontSize: 10),
                    ),
                  );
                },
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: _getLeftInterval(),
                getTitlesWidget: (value, meta) {
                  return Text(
                    value.toInt().toString(),
                    style: const TextStyle(color: Colors.white54, fontSize: 10),
                    textAlign: TextAlign.left,
                  );
                },
                reservedSize: 42,
              ),
            ),
          ),
          borderData: FlBorderData(show: false),
          lineBarsData: [
            LineChartBarData(
              spots: _vitalsData.map((e) {
                final x = (e['timestamp'] as num).toDouble();
                final y = (e[widget.dbColumnName] as num).toDouble();
                return FlSpot(x, y);
              }).toList(),
              isCurved: true,
              color: widget.accentColor,
              barWidth: 3,
              isStrokeCapRound: true,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                color: widget.accentColor.withValues(alpha: 0.2),
              ),
            ),
          ],
        ),
      ),
    );
  }

  double _getBottomInterval() {
    if (_vitalsData.isEmpty) return 1;
    final min = _vitalsData.first['timestamp'] as num;
    final max = _vitalsData.last['timestamp'] as num;
    final diff = max - min;
    // rough interval: 4 labels
    return diff > 0 ? (diff / 4) : 1;
  }

  double _getLeftInterval() {
    if (_vitalsData.isEmpty) return 1;
    final minVal = _vitalsData.map((e) => (e[widget.dbColumnName] as num)).reduce((a, b) => a < b ? a : b);
    final maxVal = _vitalsData.map((e) => (e[widget.dbColumnName] as num)).reduce((a, b) => a > b ? a : b);
    final diff = maxVal - minVal;
    return diff > 10 ? (diff / 5).floorToDouble() : 5;
  }

  Widget _buildListSection() {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1A1D27),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _vitalsData.length,
        separatorBuilder: (context, index) => Divider(color: Colors.white.withValues(alpha: 0.05)),
        itemBuilder: (context, index) {
          // reverse list so newest is on top
          final data = _vitalsData[_vitalsData.length - 1 - index];
          final date = DateTime.fromMillisecondsSinceEpoch(data['timestamp']);
          final value = data[widget.dbColumnName];
          final isIngested = data['isIngested'] == 1;

          return ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: widget.accentColor.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isIngested ? Icons.cloud_done : Icons.cloud_upload,
                color: isIngested ? widget.accentColor : Colors.white54,
                size: 20,
              ),
            ),
            title: Text(
              '$value ${widget.unit}',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 16),
            ),
            subtitle: Text(
              DateFormat('MMM d, yyyy - HH:mm:ss').format(date),
              style: const TextStyle(color: Colors.white54, fontSize: 13),
            ),
            trailing: Text(
              isIngested ? 'Synced' : 'Pending',
              style: TextStyle(
                color: isIngested ? Colors.greenAccent : Colors.orangeAccent,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          );
        },
      ),
    );
  }
}
