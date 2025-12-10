import 'package:flutter/material.dart';
import '../services/food_data_service.dart';
import '../services/prescription_service.dart';

class FoodTrackingScreen extends StatefulWidget {
  const FoodTrackingScreen({super.key});

  @override
  State<FoodTrackingScreen> createState() => _FoodTrackingScreenState();
}

class _FoodTrackingScreenState extends State<FoodTrackingScreen> {
  final _foodDataService = FoodDataService();
  final _prescriptionService = PrescriptionService();
  
  bool _isLoading = true;
  
  // Food data
  double _totalCalories = 0.0;
  List<Map<String, dynamic>> _foods = [];
  
  // Recommended foods from prescriptions
  List<String> _recommendedFoods = [];
  
  // Controllers for adding new food
  final _foodNameController = TextEditingController();
  final _quantityController = TextEditingController();
  String _selectedQuantityType = 'serving';
  final List<String> _quantityTypes = ['serving', 'cup', 'gram (g)', 'ounce (oz)', 'piece'];
  
  // Controller for total calories
  final _totalCaloriesController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadFoodData();
    _loadRecommendedFoods();
  }

  @override
  void dispose() {
    _foodNameController.dispose();
    _quantityController.dispose();
    _totalCaloriesController.dispose();
    super.dispose();
  }

  Future<void> _loadFoodData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final foodData = await _foodDataService.getTodayFoodData();
      
      if (foodData != null) {
        setState(() {
          _totalCalories = (foodData['totalCalories'] as num?)?.toDouble() ?? 0.0;
          _foods = List<Map<String, dynamic>>.from(foodData['foods'] ?? []);
          _totalCaloriesController.text = _totalCalories.toStringAsFixed(1);
        });
      } else {
        setState(() {
          _totalCalories = 0.0;
          _foods = [];
          _totalCaloriesController.text = '';
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading food data: $e'),
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

  Future<void> _loadRecommendedFoods() async {
    final user = _prescriptionService.currentUser;
    if (user == null) return;

    try {
      final snapshot = await _prescriptionService.getPrescriptionsForPatient(user.uid).first;
      final Set<String> allRecommendedFoods = {};

      for (var doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final recommendedFoods = List<String>.from(data['recommendedFoods'] ?? []);
        allRecommendedFoods.addAll(recommendedFoods);
      }

      if (mounted) {
        setState(() {
          _recommendedFoods = allRecommendedFoods.toList()..sort();
        });
      }
    } catch (e) {
      // Silently fail - recommended foods are optional
      if (mounted) {
        setState(() {
          _recommendedFoods = [];
        });
      }
    }
  }

  Future<void> _addFood() async {
    final foodName = _foodNameController.text.trim();
    final quantity = _quantityController.text.trim();

    if (foodName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a food name'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (quantity.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a quantity'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final quantityValue = double.tryParse(quantity);
    if (quantityValue == null || quantityValue <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid quantity'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _foods.add({
        'name': foodName,
        'quantity': quantityValue,
        'quantityType': _selectedQuantityType,
      });
    });

    _foodNameController.clear();
    _quantityController.clear();
    _selectedQuantityType = 'serving';

    // Save to Firestore
    await _saveFoodData();
  }

  void _removeFood(int index) {
    setState(() {
      _foods.removeAt(index);
    });
    _saveFoodData();
  }

  Future<void> _saveFoodData() async {
    try {
      final totalCalories = double.tryParse(_totalCaloriesController.text.trim()) ?? 0.0;

      await _foodDataService.storeDailyFoodData(
        totalCalories: totalCalories,
        foods: _foods,
      );

      setState(() {
        _totalCalories = totalCalories;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Food data saved successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving food data: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildAddFoodDialog() {
    return AlertDialog(
      title: const Text('Add Food'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _foodNameController,
              decoration: const InputDecoration(
                labelText: 'Food Name',
                prefixIcon: Icon(Icons.restaurant),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _quantityController,
                    decoration: const InputDecoration(
                      labelText: 'Quantity',
                      prefixIcon: Icon(Icons.scale),
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.numberWithOptions(decimal: true),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: _selectedQuantityType,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                    ),
                    items: _quantityTypes.map((type) {
                      return DropdownMenuItem(
                        value: type,
                        child: Text(
                          type,
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() {
                        _selectedQuantityType = value ?? 'serving';
                      });
                    },
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
            _foodNameController.clear();
            _quantityController.clear();
          },
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            Navigator.of(context).pop();
            _addFood();
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
          ),
          child: const Text('Add'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Food Tracking'),
          backgroundColor: Colors.orange,
        ),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Food Tracking'),
        backgroundColor: Colors.orange,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadFoodData,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await _loadFoodData();
          await _loadRecommendedFoods();
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Total Calories Card
              Card(
                elevation: 2,
                margin: const EdgeInsets.all(16),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Total Calories Eaten',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _totalCaloriesController,
                        decoration: const InputDecoration(
                          labelText: 'Total Calories (kcal)',
                          prefixIcon: Icon(Icons.local_fire_department),
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.numberWithOptions(decimal: true),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _saveFoodData,
                          icon: const Icon(Icons.save),
                          label: const Text('Save Calories'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Recommended Foods Section
              if (_recommendedFoods.isNotEmpty) ...[
                Card(
                  color: Colors.green.withValues(alpha: 0.1),
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.check_circle, color: Colors.green),
                            const SizedBox(width: 8),
                            const Text(
                              'Recommended Foods',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.green,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _recommendedFoods.map((food) {
                            return Chip(
                              label: Text(food),
                              backgroundColor: Colors.green.withValues(alpha: 0.2),
                              avatar: const Icon(Icons.restaurant, size: 18, color: Colors.green),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Foods List
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Foods Eaten',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: () {
                        showDialog(
                          context: context,
                          builder: (context) => _buildAddFoodDialog(),
                        );
                      },
                      icon: const Icon(Icons.add),
                      label: const Text('Add Food'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),

              if (_foods.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(
                    child: Text(
                      'No foods added yet.\nTap "Add Food" to get started!',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                )
              else
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _foods.length,
                  itemBuilder: (context, index) {
                    final food = _foods[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: ListTile(
                        leading: const Icon(Icons.restaurant, color: Colors.orange),
                        title: Text(food['name'] as String),
                        subtitle: Text(
                          '${food['quantity']} ${food['quantityType']}',
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () => _removeFood(index),
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

