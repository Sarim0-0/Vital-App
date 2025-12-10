import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/daily_tracking_service.dart';

class MedicationChecklistScreen extends StatefulWidget {
  const MedicationChecklistScreen({super.key});

  @override
  State<MedicationChecklistScreen> createState() =>
      _MedicationChecklistScreenState();
}

class _MedicationChecklistScreenState extends State<MedicationChecklistScreen> {
  final _dailyTrackingService = DailyTrackingService();
  bool _isLoading = true;
  Map<String, dynamic>? _dailyTracking;
  DateTime _selectedDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
    });

    try {
      // Check and mark missed medications for past dates
      await _dailyTrackingService.checkAndMarkMissed(_selectedDate);

      // Load daily tracking for selected date
      final tracking = await _dailyTrackingService.getDailyTracking(_selectedDate);

      if (mounted) {
        setState(() {
          _dailyTracking = tracking;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading medications: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _toggleMedication({
    required String medicineName,
    required int timeIndex,
    required String currentStatus,
  }) async {
    try {
      // Can only check medications for today
      final now = DateTime.now();
      final dateOnly = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
      final todayOnly = DateTime(now.year, now.month, now.day);

      if (dateOnly.isBefore(todayOnly)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cannot modify past medications'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 1),
          ),
        );
        return;
      }

      if (currentStatus == 'checked') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Medication already taken'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 1),
          ),
        );
        return;
      }

      // Toggle status: not_taken -> checked
      await _dailyTrackingService.updateMedicationStatus(
        date: _selectedDate,
        medicineName: medicineName,
        timeIndex: timeIndex,
        status: 'checked',
      );

      // Reload data
      await _loadData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✓ Medication marked as taken!'),
            backgroundColor: Colors.teal,
            duration: Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
      });
      await _loadData();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Medication Checklist'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_today),
            onPressed: _selectDate,
            tooltip: 'Select Date',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Selected Date Card
                    Card(
                      margin: const EdgeInsets.all(16),
                      color: Colors.indigo.withValues(alpha: 0.1),
                      child: InkWell(
                        onTap: _selectDate,
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              const Icon(Icons.calendar_today, color: Colors.indigo),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Selected Date',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      DateFormat('MMM dd, yyyy').format(_selectedDate),
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.indigo,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              if (_selectedDate.day == DateTime.now().day &&
                                  _selectedDate.month == DateTime.now().month &&
                                  _selectedDate.year == DateTime.now().year)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.teal,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Text(
                                    'TODAY',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                              const SizedBox(width: 8),
                              const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
                            ],
                          ),
                        ),
                      ),
                    ),

                    // Medications Section
                    if (_dailyTracking == null ||
                        (_dailyTracking!['medications'] as Map).isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(32),
                        child: Center(
                          child: Text(
                            'No medications for this date.',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
                      )
                    else
                      ...(_dailyTracking!['medications'] as Map<String, dynamic>)
                          .entries
                          .map((medicineEntry) {
                        final medicineName = medicineEntry.key;
                        final timeSlots = medicineEntry.value as Map<String, dynamic>;

                        // Parse time slots and determine status
                        final List<Map<String, dynamic>> parsedSlots = [];
                        timeSlots.forEach((key, value) {
                          // Extract time index from key (e.g., "panadol_1" -> 1)
                          final match = RegExp(r'_(\d+)$').firstMatch(key);
                          if (match != null) {
                            final timeIndex = int.parse(match.group(1)!);
                            parsedSlots.add({
                              'timeIndex': timeIndex,
                              'status': value as String,
                            });
                          }
                        });

                        // Sort by time index
                        parsedSlots.sort((a, b) =>
                            (a['timeIndex'] as int).compareTo(b['timeIndex'] as int));

                        final allChecked = parsedSlots.every(
                            (slot) => slot['status'] == 'checked');
                        final hasMissed = parsedSlots.any(
                            (slot) => slot['status'] == 'missed');

                        return Card(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          elevation: 2,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(
                              color: allChecked
                                  ? Colors.teal.withValues(alpha: 0.3)
                                  : hasMissed
                                      ? Colors.orange.withValues(alpha: 0.3)
                                      : Colors.grey.withValues(alpha: 0.2),
                              width: 1.5,
                            ),
                          ),
                          color: allChecked
                              ? Colors.teal.withValues(alpha: 0.08)
                              : hasMissed
                                  ? Colors.orange.withValues(alpha: 0.08)
                                  : Colors.grey.withValues(alpha: 0.05),
                          child: ExpansionTile(
                            leading: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: allChecked
                                    ? Colors.teal.withValues(alpha: 0.2)
                                    : hasMissed
                                        ? Colors.orange.withValues(alpha: 0.2)
                                        : Colors.grey.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                allChecked
                                    ? Icons.check_circle
                                    : hasMissed
                                        ? Icons.error_outline
                                        : Icons.radio_button_unchecked,
                                color: allChecked
                                    ? Colors.teal
                                    : hasMissed
                                        ? Colors.orange
                                        : Colors.grey,
                                size: 20,
                              ),
                            ),
                            title: Text(
                              medicineName,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            subtitle: Text(
                              '${parsedSlots.length} time${parsedSlots.length > 1 ? 's' : ''} per day',
                              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                            ),
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  children: parsedSlots.map((slot) {
                                    final timeIndex = slot['timeIndex'] as int;
                                    final status = slot['status'] as String;
                                    final isChecked = status == 'checked';
                                    final isMissed = status == 'missed';

                                    // Can only check today's medications
                                    final now = DateTime.now();
                                    final dateOnly = DateTime(
                                      _selectedDate.year,
                                      _selectedDate.month,
                                      _selectedDate.day,
                                    );
                                    final todayOnly = DateTime(
                                      now.year,
                                      now.month,
                                      now.day,
                                    );
                                    final canCheck = dateOnly.isAtSameMomentAs(todayOnly) &&
                                        !isChecked;

                                    return Container(
                                      margin: const EdgeInsets.only(bottom: 8),
                                      decoration: BoxDecoration(
                                        color: isChecked
                                            ? Colors.teal.withValues(alpha: 0.15)
                                            : isMissed
                                                ? Colors.orange.withValues(alpha: 0.15)
                                                : Colors.grey.withValues(alpha: 0.08),
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                          color: isChecked
                                              ? Colors.teal.withValues(alpha: 0.3)
                                              : isMissed
                                                  ? Colors.orange.withValues(alpha: 0.3)
                                                  : Colors.grey.withValues(alpha: 0.2),
                                        ),
                                      ),
                                      child: CheckboxListTile(
                                        value: isChecked,
                                        onChanged: canCheck
                                            ? (value) => _toggleMedication(
                                                  medicineName: medicineName,
                                                  timeIndex: timeIndex,
                                                  currentStatus: status,
                                                )
                                            : null,
                                        title: Text(
                                          'Time $timeIndex',
                                          style: const TextStyle(fontWeight: FontWeight.w500),
                                        ),
                                        subtitle: Padding(
                                          padding: const EdgeInsets.only(top: 4),
                                          child: isChecked
                                              ? Row(
                                                  children: [
                                                    Icon(Icons.check_circle,
                                                        size: 14, color: Colors.teal[700]),
                                                    const SizedBox(width: 4),
                                                    Text(
                                                      'Taken',
                                                      style: TextStyle(
                                                          color: Colors.teal[700], fontSize: 12),
                                                    ),
                                                  ],
                                                )
                                              : isMissed
                                                  ? Row(
                                                      children: [
                                                        Icon(Icons.error_outline,
                                                            size: 14, color: Colors.orange[700]),
                                                        const SizedBox(width: 4),
                                                        Text(
                                                          'Missed',
                                                          style: TextStyle(
                                                              color: Colors.orange[700],
                                                              fontSize: 12),
                                                        ),
                                                      ],
                                                    )
                                                  : Row(
                                                      children: [
                                                        Icon(Icons.schedule,
                                                            size: 14, color: Colors.grey[600]),
                                                        const SizedBox(width: 4),
                                                        Text(
                                                          'Pending',
                                                          style: TextStyle(
                                                              color: Colors.grey[600], fontSize: 12),
                                                        ),
                                                      ],
                                                    ),
                                        ),
                                        activeColor: Colors.teal,
                                        checkColor: Colors.white,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ),
                            ],
                          ),
                        );
                      }),

                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
    );
  }
}

