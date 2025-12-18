import 'dart:async';
import 'dart:math' show cos, sqrt, asin;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import '../theme/patient_theme.dart';

class LiveTrackingScreen extends StatefulWidget {
  final int? initialSteps;

  const LiveTrackingScreen({super.key, this.initialSteps});

  @override
  State<LiveTrackingScreen> createState() => _LiveTrackingScreenState();
}

class _LiveTrackingScreenState extends State<LiveTrackingScreen> {
  final MapController _mapController = MapController();
  StreamSubscription<Position>? _positionStream;
  
  List<LatLng> _pathPoints = [];
  LatLng? _currentPosition;
  double _totalDistance = 0.0; // in meters
  int _currentSteps = 0;
  bool _isTracking = false;
  bool _isLoadingLocation = true;

  @override
  void initState() {
    super.initState();
    _currentSteps = widget.initialSteps ?? 0;
    _initializeLocation();
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _initializeLocation() async {
    setState(() {
      _isLoadingLocation = true;
    });

    try {
      // Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          _showLocationServiceDialog();
        }
        setState(() {
          _isLoadingLocation = false;
        });
        return;
      }

      // Check location permission
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Location permission denied'),
                backgroundColor: Colors.red,
              ),
            );
          }
          setState(() {
            _isLoadingLocation = false;
          });
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          _showPermissionDeniedDialog();
        }
        setState(() {
          _isLoadingLocation = false;
        });
        return;
      }

      // Get current position
      Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10,
        ),
      );

      setState(() {
        _currentPosition = LatLng(position.latitude, position.longitude);
        _pathPoints.add(_currentPosition!);
        _isLoadingLocation = false;
      });

      // Move map to current position after frame is built
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _currentPosition != null) {
          _mapController.move(_currentPosition!, 16);
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error getting location: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      setState(() {
        _isLoadingLocation = false;
      });
    }
  }

  void _startTracking() {
    if (_currentPosition == null) return;

    setState(() {
      _isTracking = true;
    });

    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10, // Update every 10 meters
    );

    _positionStream = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen((Position position) {
      final newPoint = LatLng(position.latitude, position.longitude);

      if (_pathPoints.isNotEmpty) {
        // Calculate distance from last point
        final lastPoint = _pathPoints.last;
        final distance = _calculateDistance(lastPoint, newPoint);
        
        setState(() {
          _totalDistance += distance;
          _pathPoints.add(newPoint);
          _currentPosition = newPoint;
        });

        // Move map to follow user
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _mapController.move(newPoint, _mapController.camera.zoom);
          }
        });
      } else {
        setState(() {
          _pathPoints.add(newPoint);
          _currentPosition = newPoint;
        });
      }
    });
  }

  void _stopTracking() {
    _positionStream?.cancel();
    setState(() {
      _isTracking = false;
    });
  }

  void _resetTracking() {
    _stopTracking();
    setState(() {
      _pathPoints.clear();
      _totalDistance = 0.0;
      if (_currentPosition != null) {
        _pathPoints.add(_currentPosition!);
      }
    });
  }

  // Haversine formula to calculate distance between two points
  double _calculateDistance(LatLng point1, LatLng point2) {
    const p = 0.017453292519943295; // Math.PI / 180
    final a = 0.5 -
        cos((point2.latitude - point1.latitude) * p) / 2 +
        cos(point1.latitude * p) *
            cos(point2.latitude * p) *
            (1 - cos((point2.longitude - point1.longitude) * p)) /
            2;

    return 12742000 * asin(sqrt(a)); // 2 * R * 1000; R = 6371 km
  }

  void _showLocationServiceDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Location Services Disabled'),
        content: const Text(
          'Please enable location services to use live tracking.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            child: const Text('OK'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(context).pop();
              await Geolocator.openLocationSettings();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  void _showPermissionDeniedDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Permission Required'),
        content: const Text(
          'Location permission is permanently denied. Please enable it in app settings.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(context).pop();
              await Geolocator.openAppSettings();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: PatientTheme.buildAppBar(
        title: 'Live Tracking',
        backgroundColor: PatientTheme.primaryColor,
      ),
      body: _isLoadingLocation
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Getting your location...'),
                ],
              ),
            )
          : _currentPosition == null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.location_off,
                        size: 64,
                        color: Colors.grey,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Unable to get location',
                        style: TextStyle(fontSize: 18),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        onPressed: _initializeLocation,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retry'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: PatientTheme.primaryColor,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                )
              : Stack(
                  children: [
                    // Map
                    FlutterMap(
                      mapController: _mapController,
                      options: MapOptions(
                        initialCenter: _currentPosition!,
                        initialZoom: 16,
                        minZoom: 10,
                        maxZoom: 18,
                      ),
                      children: [
                        TileLayer(
                          urlTemplate:
                              'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          userAgentPackageName: 'com.example.vital_app',
                        ),
                        // Path polyline
                        if (_pathPoints.length > 1)
                          PolylineLayer(
                            polylines: [
                              Polyline(
                                points: _pathPoints,
                                strokeWidth: 4.0,
                                color: PatientTheme.primaryColor,
                              ),
                            ],
                          ),
                        // Current position marker
                        if (_currentPosition != null)
                          MarkerLayer(
                            markers: [
                              Marker(
                                point: _currentPosition!,
                                width: 40,
                                height: 40,
                                alignment: Alignment.center,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.blue,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.white,
                                      width: 3,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.3),
                                        blurRadius: 6,
                                        spreadRadius: 2,
                                      ),
                                    ],
                                  ),
                                  child: const Icon(
                                    Icons.navigation,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),

                    // Stats overlay at the top
                    Positioned(
                      top: 16,
                      left: 16,
                      right: 16,
                      child: Card(
                        elevation: 4,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            PatientTheme.borderRadiusMedium,
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              _buildStatItem(
                                icon: Icons.directions_walk,
                                label: 'Steps',
                                value: _currentSteps.toString(),
                                color: Colors.blue,
                              ),
                              Container(
                                height: 40,
                                width: 1,
                                color: Colors.grey[300],
                              ),
                              _buildStatItem(
                                icon: Icons.straighten,
                                label: 'Distance',
                                value: '${_totalDistance.toStringAsFixed(0)}m',
                                color: Colors.green,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    // Control buttons at the bottom
                    Positioned(
                      bottom: 24,
                      left: 16,
                      right: 16,
                      child: Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _isTracking ? _stopTracking : _startTracking,
                              icon: Icon(
                                _isTracking ? Icons.stop : Icons.play_arrow,
                              ),
                              label: Text(_isTracking ? 'Stop' : 'Start'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _isTracking
                                    ? Colors.red
                                    : PatientTheme.primaryColor,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(
                                    PatientTheme.borderRadiusSmall,
                                  ),
                                ),
                                elevation: 4,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton.icon(
                            onPressed: _pathPoints.length > 1 ? _resetTracking : null,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Reset'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.grey[700],
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                vertical: 16,
                                horizontal: 20,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                  PatientTheme.borderRadiusSmall,
                                ),
                              ),
                              elevation: 4,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Center map button
                    Positioned(
                      bottom: 100,
                      right: 16,
                      child: FloatingActionButton(
                        mini: true,
                        backgroundColor: Colors.white,
                        onPressed: () {
                          if (_currentPosition != null) {
                            _mapController.move(
                              _currentPosition!,
                              _mapController.camera.zoom,
                            );
                          }
                        },
                        child: const Icon(
                          Icons.my_location,
                          color: PatientTheme.primaryColor,
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildStatItem({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 28),
        const SizedBox(height: 4),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.grey[800],
          ),
        ),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }
}
