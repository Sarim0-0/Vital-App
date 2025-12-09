import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/health_service.dart';
import '../services/health_data_service.dart';

class HealthMetricsScreen extends StatefulWidget {
  const HealthMetricsScreen({super.key});

  @override
  State<HealthMetricsScreen> createState() => _HealthMetricsScreenState();
}

class _HealthMetricsScreenState extends State<HealthMetricsScreen> {
  final _healthService = HealthService();
  final _healthDataService = HealthDataService();
  
  bool _isHealthConnectInstalled = false;
  bool _hasPermissions = false;
  bool _isLoading = true;
  bool _isSyncing = false;
  bool _isSaving = false;
  
  // Health data
  int? _steps;
  double? _caloriesBurned;
  double? _hoursSlept;
  double? _heartRate;
  
  // Manual entry controllers
  final _stepsController = TextEditingController();
  final _caloriesController = TextEditingController();
  final _sleepController = TextEditingController();
  final _heartRateController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _initializeHealthConnect();
  }

  @override
  void dispose() {
    _stepsController.dispose();
    _caloriesController.dispose();
    _sleepController.dispose();
    _heartRateController.dispose();
    super.dispose();
  }

  Future<void> _initializeHealthConnect() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Check if Health Connect is installed
      final isInstalled = await _healthService.isHealthConnectInstalled();
      
      if (!isInstalled) {
        setState(() {
          _isHealthConnectInstalled = false;
          _isLoading = false;
        });
        return;
      }

      // Check permissions
      final hasPerms = await _healthService.hasPermissions();
      
      setState(() {
        _isHealthConnectInstalled = true;
        _hasPermissions = hasPerms ?? false;
        _isLoading = false;
      });

      if (_hasPermissions) {
        await _loadHealthData();
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error initializing Health Connect: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _requestPermissions() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final granted = await _healthService.requestPermissions();
      
      setState(() {
        _hasPermissions = granted;
        _isLoading = false;
      });

      if (granted) {
        await _loadHealthData();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Health Connect permissions were denied'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error requesting permissions: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _loadHealthData() async {
    setState(() {
      _isSyncing = true;
    });

    try {
      // First, try to get data from Health Connect
      final healthData = await _healthService.getTodayHealthData();
      
      // Then, try to get data from Firestore
      final firestoreData = await _healthDataService.getTodayHealthData();
      
      // Merge data: prefer Firestore (app's stored data) when Health Connect returns 0 or null
      setState(() {
        final hcSteps = healthData['steps'];
        final fsSteps = firestoreData?['steps'];
        // Use Health Connect if it has a value > 0, otherwise use Firestore, otherwise use Health Connect (even if 0)
        _steps = (hcSteps != null && hcSteps > 0) ? hcSteps : (fsSteps ?? hcSteps);
        
        final hcCalories = healthData['caloriesBurned'];
        final fsCalories = firestoreData?['caloriesBurned'];
        _caloriesBurned = (hcCalories != null && hcCalories > 0) ? hcCalories : (fsCalories ?? hcCalories);
        
        final hcSleep = healthData['hoursSlept'];
        final fsSleep = firestoreData?['hoursSlept'];
        _hoursSlept = (hcSleep != null && hcSleep > 0) ? hcSleep : (fsSleep ?? hcSleep);
        
        final hcHeartRate = healthData['heartRate'];
        final fsHeartRate = firestoreData?['heartRate'];
        _heartRate = (hcHeartRate != null && hcHeartRate > 0) ? hcHeartRate : (fsHeartRate ?? hcHeartRate);
        
        // Update text controllers for manual entry
        _stepsController.text = _steps?.toString() ?? '';
        _caloriesController.text = _caloriesBurned?.toStringAsFixed(1) ?? '';
        _sleepController.text = _hoursSlept?.toStringAsFixed(1) ?? '';
        _heartRateController.text = _heartRate?.toStringAsFixed(0) ?? '';
      });

      // Store in Firestore (even if null values)
      await _healthDataService.storeDailyHealthData(
        steps: _steps,
        caloriesBurned: _caloriesBurned,
        hoursSlept: _hoursSlept,
        heartRate: _heartRate,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading health data: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        _isSyncing = false;
      });
    }
  }

  Future<void> _saveManualEntry() async {
    setState(() {
      _isSaving = true;
    });

    try {
      final steps = _stepsController.text.trim().isEmpty
          ? null
          : int.tryParse(_stepsController.text.trim());
      final calories = _caloriesController.text.trim().isEmpty
          ? null
          : double.tryParse(_caloriesController.text.trim());
      final sleep = _sleepController.text.trim().isEmpty
          ? null
          : double.tryParse(_sleepController.text.trim());
      final heartRate = _heartRateController.text.trim().isEmpty
          ? null
          : double.tryParse(_heartRateController.text.trim());

      // Update local state
      setState(() {
        _steps = steps;
        _caloriesBurned = calories;
        _hoursSlept = sleep;
        _heartRate = heartRate;
      });

      // Write to Health Connect if available
      if (_isHealthConnectInstalled && _hasPermissions) {
        if (steps != null && calories != null && sleep != null && heartRate != null) {
          await _healthService.writeManualHealthData(
            steps: steps,
            calories: calories,
            hoursSlept: sleep,
            heartRate: heartRate,
          );
        }
      }

      // Store in Firestore
      await _healthDataService.storeDailyHealthData(
        steps: steps,
        caloriesBurned: calories,
        hoursSlept: sleep,
        heartRate: heartRate,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Health data saved successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving health data: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        _isSaving = false;
      });
    }
  }

  Widget _buildMetricCard({
    required String title,
    required String icon,
    required String? value,
    required String unit,
    required Color color,
  }) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(
                  icon,
                  style: const TextStyle(fontSize: 24),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value != null ? '$value $unit' : 'No data',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: value != null ? Colors.black : Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildManualEntrySection() {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Manual Entry',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _stepsController,
              decoration: const InputDecoration(
                labelText: 'Steps',
                prefixIcon: Icon(Icons.directions_walk),
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _caloriesController,
              decoration: const InputDecoration(
                labelText: 'Calories Burned',
                prefixIcon: Icon(Icons.local_fire_department),
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _sleepController,
              decoration: const InputDecoration(
                labelText: 'Hours Slept',
                prefixIcon: Icon(Icons.bedtime),
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _heartRateController,
              decoration: const InputDecoration(
                labelText: 'Heart Rate (BPM)',
                prefixIcon: Icon(Icons.favorite),
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _saveManualEntry,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _isSaving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Text(
                        'Save Manual Entry',
                        style: TextStyle(fontSize: 16),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Health Metrics'),
          backgroundColor: Colors.green,
        ),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (!_isHealthConnectInstalled) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Health Metrics'),
          backgroundColor: Colors.green,
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.health_and_safety,
                  size: 64,
                  color: Colors.orange,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Health Connect Not Found',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Health Connect app is not installed on your device. Please install it from the Play Store to sync health data automatically.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 16,
                    ),
                  ),
                  child: const Text('Go Back'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (!_hasPermissions) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Health Metrics'),
          backgroundColor: Colors.green,
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.lock,
                  size: 64,
                  color: Colors.orange,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Permissions Required',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Please grant Health Connect permissions to sync your health data automatically.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _requestPermissions,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 16,
                    ),
                  ),
                  child: const Text('Grant Permissions'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Health Metrics'),
        backgroundColor: Colors.green,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isSyncing ? null : _loadHealthData,
            tooltip: 'Sync from Health Connect',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadHealthData,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_isSyncing)
                const LinearProgressIndicator(
                  backgroundColor: Colors.green,
                ),
              const SizedBox(height: 16),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Today\'s Metrics',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              _buildMetricCard(
                title: 'Steps',
                icon: '👣',
                value: _steps?.toString(),
                unit: 'steps',
                color: Colors.blue,
              ),
              _buildMetricCard(
                title: 'Calories Burned',
                icon: '🔥',
                value: _caloriesBurned?.toStringAsFixed(1),
                unit: 'kcal',
                color: Colors.orange,
              ),
              _buildMetricCard(
                title: 'Hours Slept',
                icon: '😴',
                value: _hoursSlept?.toStringAsFixed(1),
                unit: 'hours',
                color: Colors.purple,
              ),
              _buildMetricCard(
                title: 'Heart Rate',
                icon: '❤️',
                value: _heartRate?.toStringAsFixed(0),
                unit: 'BPM',
                color: Colors.red,
              ),
              const SizedBox(height: 16),
              _buildManualEntrySection(),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

