import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/daily_tracking_service.dart';
import '../theme/patient_theme.dart';

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
      final tracking = await _dailyTrackingService.getDailyTracking(
        _selectedDate,
      );

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
      final dateOnly = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
      );
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
      backgroundColor: PatientTheme.surfaceColor,
      appBar: PatientTheme.buildAppBar(
        title: 'Medication Checklist',
        backgroundColor: Colors.indigo[700]!,
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
              color: Colors.indigo[700],
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 20),
                    // Selected Date Card
                    PatientTheme.buildCard(
                      margin: const EdgeInsets.symmetric(horizontal: 20),
                      padding: const EdgeInsets.all(20),
                      gradientColors: [
                        Colors.indigo[100]!.withValues(alpha: 0.5),
                        Colors.indigo[50]!.withValues(alpha: 0.3),
                      ],
                      onTap: _selectDate,
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.indigo[100],
                              borderRadius: BorderRadius.circular(
                                PatientTheme.borderRadiusSmall,
                              ),
                            ),
                            child: Icon(
                              Icons.calendar_today,
                              color: Colors.indigo[700],
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Selected Date',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  DateFormat(
                                    'MMM dd, yyyy',
                                  ).format(_selectedDate),
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.grey[800],
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
                                color: PatientTheme.primaryColor,
                                borderRadius: BorderRadius.circular(
                                  PatientTheme.borderRadiusSmall,
                                ),
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
                          Icon(
                            Icons.arrow_forward_ios,
                            size: 16,
                            color: Colors.grey[400],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),
                    // Medications Section
                    if (_dailyTracking == null ||
                        (_dailyTracking!['medications'] as Map).isEmpty)
                      PatientTheme.buildCard(
                        margin: const EdgeInsets.symmetric(horizontal: 20),
                        padding: const EdgeInsets.all(40),
                        child: Column(
                          children: [
                            Icon(
                              Icons.medication_outlined,
                              size: 64,
                              color: Colors.grey[400],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No medications for this date.',
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      ...(_dailyTracking!['medications']
                              as Map<String, dynamic>)
                          .entries
                          .map((medicineEntry) {
                            final medicineName = medicineEntry.key;
                            final timeSlots =
                                medicineEntry.value as Map<String, dynamic>;

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
                            parsedSlots.sort(
                              (a, b) => (a['timeIndex'] as int).compareTo(
                                b['timeIndex'] as int,
                              ),
                            );

                            final allChecked = parsedSlots.every(
                              (slot) => slot['status'] == 'checked',
                            );
                            final hasMissed = parsedSlots.any(
                              (slot) => slot['status'] == 'missed',
                            );

                            final cardColor = allChecked
                                ? PatientTheme.primaryColor
                                : hasMissed
                                ? Colors.orange[700]!
                                : Colors.grey[400]!;

                            return PatientTheme.buildCard(
                              margin: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 8,
                              ),
                              padding: EdgeInsets.zero,
                              gradientColors: [
                                cardColor.withValues(alpha: 0.08),
                                cardColor.withValues(alpha: 0.04),
                              ],
                              child: ExpansionTile(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(
                                    PatientTheme.borderRadiusMedium,
                                  ),
                                ),
                                leading: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: cardColor.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(
                                      PatientTheme.borderRadiusSmall,
                                    ),
                                  ),
                                  child: Icon(
                                    allChecked
                                        ? Icons.check_circle
                                        : hasMissed
                                        ? Icons.error_outline
                                        : Icons.radio_button_unchecked,
                                    color: cardColor,
                                    size: 20,
                                  ),
                                ),
                                title: Text(
                                  medicineName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  '${parsedSlots.length} time${parsedSlots.length > 1 ? 's' : ''} per day',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                ),
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Column(
                                      children: parsedSlots.map((slot) {
                                        final timeIndex =
                                            slot['timeIndex'] as int;
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
                                        final canCheck =
                                            dateOnly.isAtSameMomentAs(
                                              todayOnly,
                                            ) &&
                                            !isChecked;

                                        final slotColor = isChecked
                                            ? PatientTheme.primaryColor
                                            : isMissed
                                            ? Colors.orange[700]!
                                            : Colors.grey[400]!;

                                        return Container(
                                          margin: const EdgeInsets.only(
                                            bottom: 8,
                                          ),
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            color: slotColor.withValues(
                                              alpha: 0.1,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              PatientTheme.borderRadiusSmall,
                                            ),
                                            border: Border.all(
                                              color: slotColor.withValues(
                                                alpha: 0.3,
                                              ),
                                              width: 1.5,
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
                                            contentPadding: EdgeInsets.zero,
                                            title: Text(
                                              'Time $timeIndex',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            subtitle: Padding(
                                              padding: const EdgeInsets.only(
                                                top: 4,
                                              ),
                                              child: Row(
                                                children: [
                                                  Icon(
                                                    isChecked
                                                        ? Icons.check_circle
                                                        : isMissed
                                                        ? Icons.error_outline
                                                        : Icons.schedule,
                                                    size: 14,
                                                    color: slotColor,
                                                  ),
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    isChecked
                                                        ? 'Taken'
                                                        : isMissed
                                                        ? 'Missed'
                                                        : 'Pending',
                                                    style: TextStyle(
                                                      color: slotColor,
                                                      fontSize: 12,
                                                      fontWeight:
                                                          FontWeight.w500,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            activeColor:
                                                PatientTheme.primaryColor,
                                            checkColor: Colors.white,
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(
                                                    PatientTheme
                                                        .borderRadiusSmall,
                                                  ),
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

                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
    );
  }
}
