import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/food_data_service.dart';
import '../services/cloudinary_service.dart'; // Changed from image_storage_service
import '../services/prescription_service.dart';
import '../theme/patient_theme.dart';

class FoodTrackingScreen extends StatefulWidget {
  const FoodTrackingScreen({super.key});

  @override
  State<FoodTrackingScreen> createState() => _FoodTrackingScreenState();
}

class _FoodTrackingScreenState extends State<FoodTrackingScreen> {
  final _foodDataService = FoodDataService();
  final _prescriptionService = PrescriptionService();
  final _cloudinaryService = CloudinaryService(); // Changed
  final _imagePicker = ImagePicker();

  bool _isLoading = true;
  bool _isUploadingImage = false;

  // Food data
  double _totalCalories = 0.0;
  List<Map<String, dynamic>> _foods = [];

  // Recommended foods from prescriptions
  List<String> _recommendedFoods = [];

  // Controllers for adding new food
  final _foodNameController = TextEditingController();
  final _quantityController = TextEditingController();
  String _selectedQuantityType = 'serving';
  File? _selectedImage;
  final List<String> _quantityTypes = [
    'serving',
    'cup',
    'gram (g)',
    'ounce (oz)',
    'piece',
  ];

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
          _totalCalories =
              (foodData['totalCalories'] as num?)?.toDouble() ?? 0.0;
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
      final snapshot = await _prescriptionService
          .getPrescriptionsForPatient(user.uid)
          .first;
      final Set<String> allRecommendedFoods = {};

      for (var doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final recommendedFoods = List<String>.from(
          data['recommendedFoods'] ?? [],
        );
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
        const SnackBar(content: Text('Please enter food name')),
      );
      return;
    }

    if (quantity.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter quantity')),
      );
      return;
    }

    setState(() {
      _isUploadingImage = true;
    });

    try {
      String? imageUrl;

      // Upload image to Cloudinary if selected
      if (_selectedImage != null) {
        final user = _prescriptionService.currentUser;
        if (user != null) {
          imageUrl = await _cloudinaryService.uploadFoodImage(
            imageFile: _selectedImage!,
            userId: user.uid,
          );

          if (imageUrl == null) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Failed to upload image')),
              );
            }
            setState(() {
              _isUploadingImage = false;
            });
            return;
          }
        }
      }

      // Add food to list
      setState(() {
        _foods.add({
          'name': foodName,
          'quantity': '$quantity $_selectedQuantityType',
          'imageUrl': imageUrl,
        });
        _isUploadingImage = false;
      });

      // Save to Firestore
      await _saveFoodData();

      // Clear form
      _foodNameController.clear();
      _quantityController.clear();
      _selectedImage = null;
      _selectedQuantityType = 'serving';

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Food added successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error adding food: $e')),
        );
      }
      setState(() {
        _isUploadingImage = false;
      });
    }
  }

  Future<void> _removeFood(int index) async {
    final food = _foods[index];
    
    // Delete image from Cloudinary if exists
    if (food['imageUrl'] != null && food['imageUrl'].toString().isNotEmpty) {
      await _cloudinaryService.deleteFoodImage(food['imageUrl']);
    }

    setState(() {
      _foods.removeAt(index);
    });

    await _saveFoodData();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Food removed')),
      );
    }
  }

  Future<void> _saveFoodData() async {
    try {
      final totalCalories =
          double.tryParse(_totalCaloriesController.text.trim()) ?? 0.0;

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

  // Image capture methods
  Future<void> _captureImage(StateSetter setDialogState) async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );

      if (image != null) {
        setDialogState(() {
          _selectedImage = File(image.path);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error capturing image: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _pickImageFromGallery(StateSetter setDialogState) async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );

      if (image != null) {
        setDialogState(() {
          _selectedImage = File(image.path);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error picking image: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _discardImage(StateSetter setDialogState) {
    setDialogState(() {
      _selectedImage = null;
    });
  }

  // Show food details dialog with full-size image
  void _showFoodDetailsDialog(Map<String, dynamic> food) {
    final String? imageUrl = food['imageUrl']?.toString();
    final String foodName = food['name']?.toString() ?? 'Unknown Food';
    final String quantity = food['quantity']?.toString() ?? 'N/A';

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(PatientTheme.borderRadiusMedium),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Image section
              if (imageUrl != null && imageUrl.isNotEmpty)
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(PatientTheme.borderRadiusMedium),
                  ),
                  child: Image.network(
                    _cloudinaryService.getOptimizedUrl(imageUrl, width: 600, height: 400),
                    height: 300,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return Container(
                        height: 300,
                        color: Colors.grey[200],
                        child: Center(
                          child: CircularProgressIndicator(
                            value: loadingProgress.expectedTotalBytes != null
                                ? loadingProgress.cumulativeBytesLoaded / 
                                  loadingProgress.expectedTotalBytes!
                                : null,
                          ),
                        ),
                      );
                    },
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        height: 300,
                        color: Colors.grey[200],
                        child: const Center(
                          child: Icon(Icons.broken_image, size: 64, color: Colors.grey),
                        ),
                      );
                    },
                  ),
                ),
              
              // Details section
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.restaurant, color: PatientTheme.primaryColor),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            foodName,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Icon(Icons.scale, color: PatientTheme.primaryColor, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'Quantity: $quantity',
                          style: const TextStyle(
                            fontSize: 16,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: PatientTheme.primaryColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(PatientTheme.borderRadiusSmall),
                          ),
                        ),
                        child: const Text('Close'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAddFoodDialog() {
    return StatefulBuilder(
      builder: (dialogContext, setDialogState) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(PatientTheme.borderRadiusMedium),
          ),
          title: const Text('Add Food'),
          contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
          content: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(dialogContext).size.height * 0.7,
              maxWidth: MediaQuery.of(dialogContext).size.width * 0.85,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                TextField(
                  controller: _foodNameController,
                  decoration: InputDecoration(
                    labelText: 'Food Name',
                    prefixIcon: const Icon(Icons.restaurant),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(
                        PatientTheme.borderRadiusSmall,
                      ),
                    ),
                    filled: true,
                    fillColor: Colors.grey[50],
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: _quantityController,
                        decoration: InputDecoration(
                          labelText: 'Quantity',
                          prefixIcon: const Icon(Icons.scale),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(
                              PatientTheme.borderRadiusSmall,
                            ),
                          ),
                          filled: true,
                          fillColor: Colors.grey[50],
                        ),
                        keyboardType: TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        isExpanded: true,
                        value: _selectedQuantityType,
                        decoration: InputDecoration(
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(
                              PatientTheme.borderRadiusSmall,
                            ),
                          ),
                          filled: true,
                          fillColor: Colors.grey[50],
                        ),
                        items: _quantityTypes.map((type) {
                          return DropdownMenuItem(
                            value: type,
                            child: Text(type, overflow: TextOverflow.ellipsis),
                          );
                        }).toList(),
                        onChanged: (value) {
                          setDialogState(() {
                            _selectedQuantityType = value ?? 'serving';
                          });
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Image capture section
                if (_selectedImage == null) ...[
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey[300]!),
                      borderRadius: BorderRadius.circular(
                        PatientTheme.borderRadiusSmall,
                      ),
                    ),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Icon(
                          Icons.camera_alt,
                          size: 48,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Add a photo (optional)',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            OutlinedButton.icon(
                              onPressed: () => _captureImage(setDialogState),
                              icon: const Icon(Icons.camera_alt, size: 20),
                              label: const Text('Camera'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.orange[700],
                              ),
                            ),
                            OutlinedButton.icon(
                              onPressed: () => _pickImageFromGallery(setDialogState),
                              icon: const Icon(Icons.photo_library, size: 20),
                              label: const Text('Gallery'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.orange[700],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.orange[300]!),
                      borderRadius: BorderRadius.circular(
                        PatientTheme.borderRadiusSmall,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.only(
                            topLeft: Radius.circular(
                              PatientTheme.borderRadiusSmall,
                            ),
                            topRight: Radius.circular(
                              PatientTheme.borderRadiusSmall,
                            ),
                          ),
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final maxWidth = constraints.maxWidth > 0 
                                  ? constraints.maxWidth 
                                  : MediaQuery.of(dialogContext).size.width * 0.75;
                              final imageHeight = maxWidth * 0.64; // 16:10 aspect ratio
                              return SizedBox(
                                height: imageHeight.clamp(150, 200),
                                width: maxWidth,
                                child: Image.file(
                                  _selectedImage!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) {
                                    return Container(
                                      color: Colors.grey[200],
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.error_outline,
                                            size: 40,
                                            color: Colors.grey[400],
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            'Error loading image',
                                            style: TextStyle(
                                              color: Colors.grey[600],
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                              );
                            },
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 8,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              Flexible(
                                child: TextButton.icon(
                                  onPressed: () => _captureImage(setDialogState),
                                  icon: const Icon(Icons.camera_alt, size: 16),
                                  label: const Text('Retake'),
                                  style: TextButton.styleFrom(
                                    foregroundColor: Colors.orange[700],
                                  ),
                                ),
                              ),
                              Flexible(
                                child: TextButton.icon(
                                  onPressed: () => _discardImage(setDialogState),
                                  icon: const Icon(Icons.delete, size: 16),
                                  label: const Text('Remove'),
                                  style: TextButton.styleFrom(
                                    foregroundColor: Colors.red[400],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                if (mounted) {
                  setState(() {
                    _foodNameController.clear();
                    _quantityController.clear();
                    _selectedQuantityType = 'serving';
                    _selectedImage = null;
                  });
                }
              },
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: _isUploadingImage
                  ? null
                  : () {
                      Navigator.of(dialogContext).pop();
                      _addFood();
                    },
              style: FilledButton.styleFrom(
                backgroundColor: Colors.orange[700],
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(
                    PatientTheme.borderRadiusSmall,
                  ),
                ),
              ),
              child: _isUploadingImage
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Text('Add'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildFoodList() {
    if (_foods.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(20.0),
          child: Text(
            'No food items added yet.\nTap the + button to add food.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, color: Colors.grey),
          ),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _foods.length,
      itemBuilder: (context, index) {
        final food = _foods[index];
        final imageUrl = food['imageUrl'];

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: ListTile(
            onTap: () => _showFoodDetailsDialog(food),
            leading: imageUrl != null && imageUrl.toString().isNotEmpty
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      // Use optimized thumbnail URL
                      _cloudinaryService.getOptimizedUrl(
                        imageUrl,
                        width: 60,
                        height: 60,
                      ),
                      width: 60,
                      height: 60,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          width: 60,
                          height: 60,
                          color: Colors.grey[300],
                          child: const Icon(Icons.fastfood),
                        );
                      },
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return Container(
                          width: 60,
                          height: 60,
                          color: Colors.grey[300],
                          child: Center(
                            child: CircularProgressIndicator(
                              value: loadingProgress.expectedTotalBytes != null
                                  ? loadingProgress.cumulativeBytesLoaded /
                                      loadingProgress.expectedTotalBytes!
                                  : null,
                            ),
                          ),
                        );
                      },
                    ),
                  )
                : Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.fastfood),
                  ),
            title: Text(
              food['name'] ?? '',
              style: const TextStyle(fontWeight: FontWeight.bold),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(food['quantity'] ?? ''),
            trailing: IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              onPressed: () => _removeFood(index),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: PatientTheme.surfaceColor,
        appBar: PatientTheme.buildAppBar(
          title: 'Food Tracking',
          backgroundColor: Colors.orange[700]!,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: PatientTheme.surfaceColor,
      appBar: PatientTheme.buildAppBar(
        title: 'Food Tracking',
        backgroundColor: Colors.orange[700]!,
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
        color: Colors.orange[700],
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),
              // Total Calories Card
              PatientTheme.buildCard(
                margin: const EdgeInsets.symmetric(horizontal: 20),
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.orange[100],
                            borderRadius: BorderRadius.circular(
                              PatientTheme.borderRadiusSmall,
                            ),
                          ),
                          child: Icon(
                            Icons.local_fire_department,
                            color: Colors.orange[700],
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Text(
                          'Total Calories Eaten',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: _totalCaloriesController,
                      decoration: InputDecoration(
                        labelText: 'Total Calories (kcal)',
                        prefixIcon: const Icon(Icons.local_fire_department),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                            PatientTheme.borderRadiusSmall,
                          ),
                        ),
                        filled: true,
                        fillColor: Colors.grey[50],
                      ),
                      keyboardType: TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _saveFoodData,
                        icon: const Icon(Icons.save),
                        label: const Text('Save Calories'),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.orange[700],
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              PatientTheme.borderRadiusSmall,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),
              // Recommended Foods Section
              if (_recommendedFoods.isNotEmpty) ...[
                PatientTheme.buildCard(
                  margin: const EdgeInsets.symmetric(horizontal: 20),
                  padding: const EdgeInsets.all(20),
                  gradientColors: [
                    PatientTheme.primaryColor.withValues(alpha: 0.1),
                    PatientTheme.primaryColor.withValues(alpha: 0.05),
                  ],
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: PatientTheme.primaryColor.withValues(
                                alpha: 0.15,
                              ),
                              borderRadius: BorderRadius.circular(
                                PatientTheme.borderRadiusSmall,
                              ),
                            ),
                            child: const Icon(
                              Icons.check_circle,
                              color: PatientTheme.primaryColor,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Text(
                            'Recommended Foods',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: PatientTheme.primaryColor,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _recommendedFoods.map((food) {
                          return Chip(
                            label: Text(food),
                            backgroundColor: PatientTheme.primaryColor
                                .withValues(alpha: 0.15),
                            avatar: const Icon(
                              Icons.restaurant,
                              size: 18,
                              color: PatientTheme.primaryColor,
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
              ],

              // Foods List
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Foods Eaten',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey[800],
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: () {
                        showDialog(
                          context: context,
                          builder: (context) => _buildAddFoodDialog(),
                        );
                      },
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Add Food'),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.orange[700],
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            PatientTheme.borderRadiusSmall,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              if (_foods.isEmpty)
                PatientTheme.buildCard(
                  margin: const EdgeInsets.symmetric(horizontal: 20),
                  padding: const EdgeInsets.all(40),
                  child: Column(
                    children: [
                      Icon(
                        Icons.restaurant_outlined,
                        size: 64,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No foods added yet.\nTap "Add Food" to get started!',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey[600], fontSize: 16),
                      ),
                    ],
                  ),
                )
              else
                ...List.generate(_foods.length, (index) {
                  final food = _foods[index];
                  final hasImage = food['imageUrl'] != null;
                  
                  return PatientTheme.buildCard(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 6,
                    ),
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        // Image or icon
                        Container(
                          width: 60,
                          height: 60,
                          decoration: BoxDecoration(
                            color: Colors.orange[100],
                            borderRadius: BorderRadius.circular(
                              PatientTheme.borderRadiusSmall,
                            ),
                          ),
                          child: hasImage
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(
                                    PatientTheme.borderRadiusSmall,
                                  ),
                                  child: Image.network(
                                    food['imageUrl'],
                                    width: 60,
                                    height: 60,
                                    fit: BoxFit.cover,
                                    loadingBuilder: (context, child, loadingProgress) {
                                      if (loadingProgress == null) return child;
                                      
                                      double? progressValue;
                                      if (loadingProgress.expectedTotalBytes != null &&
                                          loadingProgress.expectedTotalBytes! > 0) {
                                        final value = loadingProgress.cumulativeBytesLoaded /
                                            loadingProgress.expectedTotalBytes!;
                                        if (value.isFinite) {
                                          progressValue = value;
                                        }
                                      }
                                      
                                      return Center(
                                        child: CircularProgressIndicator(
                                          value: progressValue,
                                          strokeWidth: 2,
                                          color: Colors.orange[700],
                                        ),
                                      );
                                    },
                                    errorBuilder: (context, error, stackTrace) {
                                      return Icon(
                                        Icons.restaurant,
                                        color: Colors.orange[700],
                                        size: 24,
                                      );
                                    },
                                  ),
                                )
                              : Center(
                                  child: Icon(
                                    Icons.restaurant,
                                    color: Colors.orange[700],
                                    size: 24,
                                  ),
                                ),
                        ),
                        const SizedBox(width: 16),
                        // Food details
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                food['name'] as String,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${food['quantity']} ${food['quantityType']}',
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Delete button
                        IconButton(
                          icon: Icon(
                            Icons.delete_outline,
                            color: Colors.red[300],
                          ),
                          onPressed: () => _removeFood(index),
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
