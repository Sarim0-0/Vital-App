import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/prescription_service.dart';
import 'package:intl/intl.dart';

class GeneratePrescriptionScreen extends StatefulWidget {
  final String requestId;
  final Map<String, dynamic> requestData;

  const GeneratePrescriptionScreen({
    super.key,
    required this.requestId,
    required this.requestData,
  });

  @override
  State<GeneratePrescriptionScreen> createState() => _GeneratePrescriptionScreenState();
}

class _GeneratePrescriptionScreenState extends State<GeneratePrescriptionScreen> {
  final _prescriptionService = PrescriptionService();
  final _formKey = GlobalKey<FormState>();

  // Recommended Foods
  final List<String> _recommendedFoods = [];
  final _foodController = TextEditingController();

  // Recommended Exercises
  final List<String> _recommendedExercises = [];
  final _exerciseController = TextEditingController();

  // Medicines
  final List<Map<String, dynamic>> _medicines = [];
  final _medicineNameController = TextEditingController();
  final _medicineDurationController = TextEditingController();
  final _medicineTimesPerDayController = TextEditingController();

  // Appointments
  final List<Map<String, dynamic>> _appointments = [];
  final _appointmentTitleController = TextEditingController();
  DateTime? _selectedAppointmentDate;

  bool _isLoading = false;

  @override
  void dispose() {
    _foodController.dispose();
    _exerciseController.dispose();
    _medicineNameController.dispose();
    _medicineDurationController.dispose();
    _medicineTimesPerDayController.dispose();
    _appointmentTitleController.dispose();
    super.dispose();
  }

  void _addFood() {
    final food = _foodController.text.trim();
    if (food.isNotEmpty && !_recommendedFoods.contains(food)) {
      setState(() {
        _recommendedFoods.add(food);
        _foodController.clear();
      });
    }
  }

  void _removeFood(int index) {
    setState(() {
      _recommendedFoods.removeAt(index);
    });
  }

  void _addExercise() {
    final exercise = _exerciseController.text.trim();
    if (exercise.isNotEmpty && !_recommendedExercises.contains(exercise)) {
      setState(() {
        _recommendedExercises.add(exercise);
        _exerciseController.clear();
      });
    }
  }

  void _removeExercise(int index) {
    setState(() {
      _recommendedExercises.removeAt(index);
    });
  }

  void _addMedicine() {
    final name = _medicineNameController.text.trim();
    final duration = _medicineDurationController.text.trim();
    final timesPerDay = _medicineTimesPerDayController.text.trim();

    if (name.isEmpty || duration.isEmpty || timesPerDay.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please fill all medicine fields'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final durationInt = int.tryParse(duration);
    final timesInt = int.tryParse(timesPerDay);

    if (durationInt == null || timesInt == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Duration and times per day must be numbers'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _medicines.add({
        'name': name,
        'duration': durationInt,
        'timesPerDay': timesInt,
      });
      _medicineNameController.clear();
      _medicineDurationController.clear();
      _medicineTimesPerDayController.clear();
    });
  }

  void _removeMedicine(int index) {
    setState(() {
      _medicines.removeAt(index);
    });
  }

  Future<void> _selectAppointmentDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() {
        _selectedAppointmentDate = picked;
      });
    }
  }

  void _addAppointment() {
    final title = _appointmentTitleController.text.trim();
    if (title.isEmpty || _selectedAppointmentDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter appointment title and select date'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _appointments.add({
        'title': title,
        'date': _selectedAppointmentDate!,
      });
      _appointmentTitleController.clear();
      _selectedAppointmentDate = null;
    });
  }

  void _removeAppointment(int index) {
    setState(() {
      _appointments.removeAt(index);
    });
  }

  Future<void> _generatePrescription() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // Convert appointments dates to Timestamps for Firestore
      final appointmentsForFirestore = _appointments.map((appt) {
        return {
          'title': appt['title'],
          'date': Timestamp.fromDate(appt['date'] as DateTime),
        };
      }).toList();

      await _prescriptionService.createPrescription(
        requestId: widget.requestId,
        patientId: widget.requestData['patientId'] as String,
        patientName: widget.requestData['patientName'] as String,
        patientEmail: widget.requestData['patientEmail'] as String,
        clinicianId: widget.requestData['clinicianId'] as String,
        clinicianName: widget.requestData['clinicianName'] as String,
        recommendedFoods: _recommendedFoods,
        recommendedExercises: _recommendedExercises,
        medicines: _medicines,
        appointments: appointmentsForFirestore,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Prescription generated successfully!'),
          backgroundColor: Colors.green,
        ),
      );

      Navigator.of(context).pop(true); // Return true to indicate success
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error generating prescription: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final requestData = widget.requestData;
    final infoType = requestData['infoType'] as String? ?? 'basic';
    final patientName = requestData['patientName'] as String? ?? 'Unknown';
    final patientEmail = requestData['patientEmail'] as String? ?? '';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Generate Prescription'),
        backgroundColor: Colors.blue,
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Patient Info Section
              Card(
                color: Colors.blue.withValues(alpha: 0.1),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Patient Information',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text('Name: $patientName'),
                      Text('Email: $patientEmail'),
                      Text('Info Type: ${infoType.toUpperCase()}'),
                      if (infoType == 'extensive') ...[
                        const SizedBox(height: 8),
                        const Divider(),
                        const SizedBox(height: 8),
                        if (requestData['chronicConditions'] != null) ...[
                          const Text(
                            'Chronic Conditions:',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          ...(requestData['chronicConditions'] as List)
                              .map((condition) => Text('• $condition')),
                          const SizedBox(height: 8),
                        ],
                        if (requestData['allergies'] != null) ...[
                          const Text(
                            'Allergies:',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          ...(requestData['allergies'] as List)
                              .map((allergy) => Text('• $allergy')),
                          const SizedBox(height: 8),
                        ],
                        if (requestData['medications'] != null) ...[
                          const Text(
                            'Current Medications:',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          ...(requestData['medications'] as List)
                              .map((med) => Text('• $med')),
                        ],
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Recommended Foods Section
              _buildSectionHeader('Recommended Foods', Icons.restaurant),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _foodController,
                      decoration: const InputDecoration(
                        labelText: 'Food item',
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _addFood(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.add_circle),
                    color: Colors.green,
                    onPressed: _addFood,
                  ),
                ],
              ),
              if (_recommendedFoods.isNotEmpty) ...[
                const SizedBox(height: 8),
                ...List.generate(
                  _recommendedFoods.length,
                  (index) => Card(
                    margin: const EdgeInsets.only(bottom: 4),
                    child: ListTile(
                      title: Text(_recommendedFoods[index]),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => _removeFood(index),
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 24),

              // Recommended Exercises Section
              _buildSectionHeader('Recommended Exercises', Icons.fitness_center),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _exerciseController,
                      decoration: const InputDecoration(
                        labelText: 'Exercise type',
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _addExercise(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.add_circle),
                    color: Colors.green,
                    onPressed: _addExercise,
                  ),
                ],
              ),
              if (_recommendedExercises.isNotEmpty) ...[
                const SizedBox(height: 8),
                ...List.generate(
                  _recommendedExercises.length,
                  (index) => Card(
                    margin: const EdgeInsets.only(bottom: 4),
                    child: ListTile(
                      title: Text(_recommendedExercises[index]),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => _removeExercise(index),
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 24),

              // Medicines Section
              _buildSectionHeader('Medicines', Icons.medication),
              const SizedBox(height: 8),
              TextField(
                controller: _medicineNameController,
                decoration: const InputDecoration(
                  labelText: 'Medicine Name',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _medicineDurationController,
                      decoration: const InputDecoration(
                        labelText: 'Duration (days)',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _medicineTimesPerDayController,
                      decoration: const InputDecoration(
                        labelText: 'Times per day',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.add_circle),
                    color: Colors.green,
                    onPressed: _addMedicine,
                  ),
                ],
              ),
              if (_medicines.isNotEmpty) ...[
                const SizedBox(height: 8),
                ...List.generate(
                  _medicines.length,
                  (index) => Card(
                    margin: const EdgeInsets.only(bottom: 4),
                    child: ListTile(
                      title: Text(_medicines[index]['name']),
                      subtitle: Text(
                        '${_medicines[index]['duration']} days, ${_medicines[index]['timesPerDay']} times/day',
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => _removeMedicine(index),
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 24),

              // Appointments Section
              _buildSectionHeader('Appointments', Icons.calendar_today),
              const SizedBox(height: 8),
              TextField(
                controller: _appointmentTitleController,
                decoration: const InputDecoration(
                  labelText: 'Appointment Title',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              InkWell(
                onTap: _selectAppointmentDate,
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Appointment Date',
                    border: OutlineInputBorder(),
                    suffixIcon: Icon(Icons.calendar_today),
                  ),
                  child: Text(
                    _selectedAppointmentDate == null
                        ? 'Select date'
                        : DateFormat('MMM dd, yyyy').format(_selectedAppointmentDate!),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              ElevatedButton.icon(
                onPressed: _addAppointment,
                icon: const Icon(Icons.add),
                label: const Text('Add Appointment'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
              ),
              if (_appointments.isNotEmpty) ...[
                const SizedBox(height: 8),
                ...List.generate(
                  _appointments.length,
                  (index) => Card(
                    margin: const EdgeInsets.only(bottom: 4),
                    child: ListTile(
                      title: Text(_appointments[index]['title']),
                      subtitle: Text(
                        DateFormat('MMM dd, yyyy')
                            .format(_appointments[index]['date'] as DateTime),
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => _removeAppointment(index),
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 32),

              // Generate Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _generatePrescription,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text(
                          'Generate Prescription',
                          style: TextStyle(fontSize: 16),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: Colors.blue),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

