import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/exercise_data_service.dart';

class ExerciseTrackingScreen extends StatefulWidget {
  const ExerciseTrackingScreen({super.key});

  @override
  State<ExerciseTrackingScreen> createState() => _ExerciseTrackingScreenState();
}

class _ExerciseTrackingScreenState extends State<ExerciseTrackingScreen> {
  final _exerciseDataService = ExerciseDataService();
  
  bool _isLoading = true;
  
  // Exercise data
  List<Map<String, dynamic>> _exercises = [];
  
  // Controllers for adding new exercise
  final _exerciseTypeController = TextEditingController();
  String _exerciseMode = 'duration'; // 'duration' or 'reps'
  final _durationController = TextEditingController();
  final _repsController = TextEditingController();
  final _setsController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadExerciseData();
  }

  @override
  void dispose() {
    _exerciseTypeController.dispose();
    _durationController.dispose();
    _repsController.dispose();
    _setsController.dispose();
    super.dispose();
  }

  Future<void> _loadExerciseData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final exerciseData = await _exerciseDataService.getTodayExerciseData();
      
      if (exerciseData != null) {
        setState(() {
          _exercises = List<Map<String, dynamic>>.from(exerciseData['exercises'] ?? []);
        });
      } else {
        setState(() {
          _exercises = [];
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading exercise data: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _addExercise() async {
    final exerciseType = _exerciseTypeController.text.trim();

    if (exerciseType.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter an exercise type'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    Map<String, dynamic> exerciseData = {
      'type': exerciseType,
      'mode': _exerciseMode,
    };

    if (_exerciseMode == 'duration') {
      final duration = _durationController.text.trim();
      if (duration.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please enter duration'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
      final durationValue = int.tryParse(duration);
      if (durationValue == null || durationValue <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please enter a valid duration'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
      exerciseData['duration'] = durationValue; // in minutes
    } else {
      final reps = _repsController.text.trim();
      final sets = _setsController.text.trim();
      
      if (reps.isEmpty || sets.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please enter both reps and sets'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
      
      final repsValue = int.tryParse(reps);
      final setsValue = int.tryParse(sets);
      
      if (repsValue == null || repsValue <= 0 || setsValue == null || setsValue <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please enter valid reps and sets'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
      
      exerciseData['reps'] = repsValue;
      exerciseData['sets'] = setsValue;
    }

    setState(() {
      _exercises.add(exerciseData);
    });

    _exerciseTypeController.clear();
    _durationController.clear();
    _repsController.clear();
    _setsController.clear();
    _exerciseMode = 'duration';

    // Save to Firestore
    await _saveExerciseData();
  }

  void _removeExercise(int index) {
    setState(() {
      _exercises.removeAt(index);
    });
    _saveExerciseData();
  }

  Future<void> _saveExerciseData() async {
    try {
      await _exerciseDataService.storeDailyExerciseData(
        exercises: _exercises,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Exercise data saved successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving exercise data: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildAddExerciseDialog() {
    return StatefulBuilder(
      builder: (context, setDialogState) {
        return AlertDialog(
          title: const Text('Add Exercise'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _exerciseTypeController,
                  decoration: const InputDecoration(
                    labelText: 'Exercise Type',
                    prefixIcon: Icon(Icons.fitness_center),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: 'duration',
                      label: Text('Duration'),
                      icon: Icon(Icons.timer),
                    ),
                    ButtonSegment(
                      value: 'reps',
                      label: Text('Reps/Sets'),
                      icon: Icon(Icons.repeat),
                    ),
                  ],
                  selected: {_exerciseMode},
                  onSelectionChanged: (Set<String> newSelection) {
                    setDialogState(() {
                      _exerciseMode = newSelection.first;
                    });
                  },
                ),
                const SizedBox(height: 16),
                if (_exerciseMode == 'duration')
                  TextField(
                    controller: _durationController,
                    decoration: const InputDecoration(
                      labelText: 'Duration (minutes)',
                      prefixIcon: Icon(Icons.timer),
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  )
                else
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _repsController,
                          decoration: const InputDecoration(
                            labelText: 'Reps',
                            prefixIcon: Icon(Icons.repeat),
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _setsController,
                          decoration: const InputDecoration(
                            labelText: 'Sets',
                            prefixIcon: Icon(Icons.layers),
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _exerciseTypeController.clear();
                _durationController.clear();
                _repsController.clear();
                _setsController.clear();
              },
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                _addExercise();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
              ),
              child: const Text('Add'),
            ),
          ],
        );
      },
    );
  }

  String _formatExerciseData(Map<String, dynamic> exercise) {
    if (exercise['mode'] == 'duration') {
      return '${exercise['duration']} minutes';
    } else {
      return '${exercise['sets']} sets × ${exercise['reps']} reps';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Exercise Tracking'),
          backgroundColor: Colors.blue,
        ),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Exercise Tracking'),
        backgroundColor: Colors.blue,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadExerciseData,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadExerciseData,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Exercises List
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Exercises',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: () {
                        showDialog(
                          context: context,
                          builder: (context) => _buildAddExerciseDialog(),
                        );
                      },
                      icon: const Icon(Icons.add),
                      label: const Text('Add Exercise'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                      ),
                    ),
                  ],
                ),
              ),

              if (_exercises.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(
                    child: Text(
                      'No exercises added yet.\nTap "Add Exercise" to get started!',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                )
              else
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _exercises.length,
                  itemBuilder: (context, index) {
                    final exercise = _exercises[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: ListTile(
                        leading: const Icon(Icons.fitness_center, color: Colors.blue),
                        title: Text(exercise['type'] as String),
                        subtitle: Text(_formatExerciseData(exercise)),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () => _removeExercise(index),
                        ),
                      ),
                    );
                  },
                ),

              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

