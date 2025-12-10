import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/medication_tracking_service.dart';

class MedicationChecklistScreen extends StatefulWidget {
  const MedicationChecklistScreen({super.key});

  @override
  State<MedicationChecklistScreen> createState() => _MedicationChecklistScreenState();
}

class _MedicationChecklistScreenState extends State<MedicationChecklistScreen> {
  final _medicationTrackingService = MedicationTrackingService();
  bool _isLoading = true;
  Map<String, dynamic>? _todayStatus;
  List<Map<String, dynamic>> _missedMedications = [];
  DateTime _selectedDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    // Load data without missed medications first for faster initial load
    _loadData(loadMissed: false);
    // Load missed medications in background
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        _loadData(loadMissed: true);
      }
    });
  }

  Future<void> _loadData({bool loadMissed = true}) async {
    if (!mounted) return;
    
    setState(() {
      _isLoading = true;
    });

    try {
      // Load today's status first (faster)
      final todayStatus = await _medicationTrackingService.getMedicationStatusForDate(_selectedDate);
      
      if (mounted) {
        setState(() {
          _todayStatus = todayStatus;
          _isLoading = false;
        });
      }

      // Load missed medications in background (slower, can be async)
      if (loadMissed && mounted) {
        try {
          final missed = await _medicationTrackingService.getMissedMedications();
          if (mounted) {
            setState(() {
              _missedMedications = missed;
            });
          }
        } catch (e) {
          // Silently fail for missed medications - not critical
          debugPrint('Warning: Failed to load missed medications: $e');
        }
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
    required String prescriptionId,
    required String medicineName,
    required int timeIndex,
    required bool isCurrentlyTaken,
  }) async {
    try {
      if (isCurrentlyTaken) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Medication already taken'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 1),
          ),
        );
        return;
      }

      // Mark as taken
      await _medicationTrackingService.markMedicationTaken(
        prescriptionId: prescriptionId,
        medicineName: medicineName,
        date: _selectedDate,
        timeIndex: timeIndex,
      );

      // Only reload status for the selected date, not everything
      final todayStatus = await _medicationTrackingService.getMedicationStatusForDate(_selectedDate);
      
      if (mounted) {
        setState(() {
          _todayStatus = todayStatus;
        });
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
      await _loadData(loadMissed: false); // Don't reload missed on date change for speed
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
            onPressed: () => _loadData(loadMissed: true),
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
                    // Selected Date Card - Fixed overflow
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

                    // Missed Medications Section - Improved colors
                    if (_missedMedications.isNotEmpty) ...[
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.warning_rounded, color: Colors.orange, size: 24),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Missed Medications (${_missedMedications.length})',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.orange,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      ..._missedMedications.take(5).map((missed) {
                        return Card(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 4,
                          ),
                          color: Colors.orange.withValues(alpha: 0.08),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(color: Colors.orange.withValues(alpha: 0.2)),
                          ),
                          child: ListTile(
                            leading: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.orange.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.medication, color: Colors.orange, size: 20),
                            ),
                            title: Text(
                              missed['medicineName'] as String,
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 4),
                                Text(
                                  'Missed on ${DateFormat('MMM dd, yyyy').format(missed['date'] as DateTime)}',
                                  style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                                ),
                                Text(
                                  'Time ${(missed['timeIndex'] as int) + 1} of ${missed['timesPerDay']}',
                                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                                ),
                              ],
                            ),
                            trailing: const Icon(Icons.error_outline, color: Colors.orange, size: 20),
                          ),
                        );
                      }),
                      if (_missedMedications.length > 5)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: Text(
                            '... and ${_missedMedications.length - 5} more missed medications',
                            style: TextStyle(color: Colors.grey[600], fontSize: 12),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      const SizedBox(height: 8),
                    ],

                    // Today's Medications - Improved header
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.indigo.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.indigo.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.medication, color: Colors.indigo, size: 20),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _selectedDate.day == DateTime.now().day &&
                                      _selectedDate.month == DateTime.now().month &&
                                      _selectedDate.year == DateTime.now().year
                                  ? "Today's Medications"
                                  : 'Medications for Selected Date',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.indigo,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),

                    if (_todayStatus == null ||
                        (_todayStatus!['medications'] as List).isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(32),
                        child: Center(
                          child: Text(
                            'No active medications for this date.',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
                      )
                    else
                      ...(_todayStatus!['medications'] as List<dynamic>).map((medication) {
                        final medicineName = medication['medicineName'] as String;
                        final timesPerDay = medication['timesPerDay'] as int;
                        final prescriptionId = medication['prescriptionId'] as String;
                        final timeSlots = medication['timeSlots'] as List<dynamic>;
                        final allTaken = medication['allTaken'] == true;
                        final hasMissed = medication['hasMissed'] == true;
                        final clinicianName = medication['clinicianName'] as String;

                        return Card(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          elevation: 2,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(
                              color: allTaken
                                  ? Colors.teal.withValues(alpha: 0.3)
                                  : hasMissed
                                      ? Colors.orange.withValues(alpha: 0.3)
                                      : Colors.grey.withValues(alpha: 0.2),
                              width: 1.5,
                            ),
                          ),
                          color: allTaken
                              ? Colors.teal.withValues(alpha: 0.08)
                              : hasMissed
                                  ? Colors.orange.withValues(alpha: 0.08)
                                  : Colors.grey.withValues(alpha: 0.05),
                          child: ExpansionTile(
                            leading: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: allTaken
                                    ? Colors.teal.withValues(alpha: 0.2)
                                    : hasMissed
                                        ? Colors.orange.withValues(alpha: 0.2)
                                        : Colors.grey.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                allTaken
                                    ? Icons.check_circle
                                    : hasMissed
                                        ? Icons.error_outline
                                        : Icons.radio_button_unchecked,
                                color: allTaken
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
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Prescribed by: $clinicianName',
                                    style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '$timesPerDay time${timesPerDay > 1 ? 's' : ''} per day',
                                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                                  ),
                                ],
                              ),
                            ),
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  children: timeSlots.asMap().entries.map((entry) {
                                    final index = entry.key;
                                    final slot = entry.value as Map<String, dynamic>;
                                    final isTaken = slot['isTaken'] == true;
                                    final isMissed = slot['isMissed'] == true;
                                    final canCheck = _selectedDate.day == DateTime.now().day &&
                                        _selectedDate.month == DateTime.now().month &&
                                        _selectedDate.year == DateTime.now().year &&
                                        !isTaken;

                                    return Container(
                                      margin: const EdgeInsets.only(bottom: 8),
                                      decoration: BoxDecoration(
                                        color: isTaken
                                            ? Colors.teal.withValues(alpha: 0.15)
                                            : isMissed
                                                ? Colors.orange.withValues(alpha: 0.15)
                                                : Colors.grey.withValues(alpha: 0.08),
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                          color: isTaken
                                              ? Colors.teal.withValues(alpha: 0.3)
                                              : isMissed
                                                  ? Colors.orange.withValues(alpha: 0.3)
                                                  : Colors.grey.withValues(alpha: 0.2),
                                        ),
                                      ),
                                      child: CheckboxListTile(
                                        value: isTaken,
                                        onChanged: canCheck
                                            ? (value) => _toggleMedication(
                                                  prescriptionId: prescriptionId,
                                                  medicineName: medicineName,
                                                  timeIndex: index,
                                                  isCurrentlyTaken: isTaken,
                                                )
                                            : null,
                                        title: Text(
                                          'Time ${index + 1} of $timesPerDay',
                                          style: const TextStyle(fontWeight: FontWeight.w500),
                                        ),
                                        subtitle: Padding(
                                          padding: const EdgeInsets.only(top: 4),
                                          child: isTaken
                                              ? Row(
                                                  children: [
                                                    Icon(Icons.check_circle, size: 14, color: Colors.teal[700]),
                                                    const SizedBox(width: 4),
                                                    Text(
                                                      'Taken',
                                                      style: TextStyle(color: Colors.teal[700], fontSize: 12),
                                                    ),
                                                  ],
                                                )
                                              : isMissed
                                                  ? Row(
                                                      children: [
                                                        Icon(Icons.error_outline, size: 14, color: Colors.orange[700]),
                                                        const SizedBox(width: 4),
                                                        Text(
                                                          'Missed',
                                                          style: TextStyle(color: Colors.orange[700], fontSize: 12),
                                                        ),
                                                      ],
                                                    )
                                                  : Row(
                                                      children: [
                                                        Icon(Icons.schedule, size: 14, color: Colors.grey[600]),
                                                        const SizedBox(width: 4),
                                                        Text(
                                                          'Pending',
                                                          style: TextStyle(color: Colors.grey[600], fontSize: 12),
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

