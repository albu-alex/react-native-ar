import React, { useEffect, useState, useCallback } from 'react';
import {
  View,
  Text,
  StyleSheet,
  TouchableOpacity,
  Alert,
  ActivityIndicator,
  Platform,
  Share,
} from 'react-native';
import { NativeStackNavigationProp } from '@react-navigation/native-stack';
import { useFocusEffect } from '@react-navigation/native';
import { ARNativeModule } from '../native/ARNativeModule';
import { ARViewNative } from '../native/ARView';
import { RootStackParamList } from '../types/navigation';

type ARScreenProps = {
  navigation: NativeStackNavigationProp<RootStackParamList, 'AR'>;
};

export const ARScreen: React.FC<ARScreenProps> = ({ navigation }) => {
  const [isSupported, setIsSupported] = useState<boolean | null>(null);
  const [isScanning, setIsScanning] = useState(false);
  const [isLoading, setIsLoading] = useState(false);
  const [imageCount, setImageCount] = useState(0);
  const [captureDirectory, setCaptureDirectory] = useState<string | null>(null);
  const [processingProgress, setProcessingProgress] = useState<{ status: string; progress: number } | null>(null);
  const [selectedQuality, setSelectedQuality] = useState<'reduced' | 'medium' | 'full' | 'raw'>('medium');
  const [pollingInterval, setPollingInterval] = useState<NodeJS.Timeout | null>(null);

  // Check AR support on mount
  useEffect(() => {
    checkARSupport();
    
    // Cleanup polling interval on unmount
    return () => {
      if (pollingInterval) {
        clearInterval(pollingInterval);
      }
    };
  }, [pollingInterval]);

  const checkARSupport = async () => {
    try {
      const supported = await ARNativeModule.isSupported();
      setIsSupported(supported);

      if (!supported) {
        Alert.alert(
          'AR Not Supported',
          `AR is not supported on this device. ${
            Platform.OS === 'android'
              ? 'ARCore may need to be installed or updated.'
              : 'This device does not support ARKit.'
          }`,
          [{ text: 'OK', onPress: () => navigation.goBack() }]
        );
      }
    } catch (error) {
      console.error('Error checking AR support:', error);
      setIsSupported(false);
      Alert.alert(
        'Error',
        'Failed to check AR support',
        [{ text: 'OK', onPress: () => navigation.goBack() }]
      );
    }
  };

  const handleStartScan = async () => {
    if (isScanning) {
      // Stop capturing images
      setIsLoading(true);
      
      // Clear polling interval
      if (pollingInterval) {
        clearInterval(pollingInterval);
        setPollingInterval(null);
      }
      
      try {
        const scanData = await ARNativeModule.stopObjectScan();
        setIsScanning(false);
        const directory = scanData.directory || captureDirectory;
        const count = scanData.imageCount || imageCount;
        
        Alert.alert(
          'Capture Complete',
          `Captured ${count} images`,
          [
            { text: 'OK', style: 'cancel' },
            {
              text: 'Process Now',
              onPress: async () => {
                // Check if photogrammetry is supported
                const isSupported = await ARNativeModule.isPhotogrammetrySupported();
                if (!isSupported) {
                  Alert.alert(
                    'Not Supported',
                    'Photogrammetry is not supported on this device. Requires Mac with 4GB+ GPU and ray tracing, or iOS device with LiDAR.',
                    [{ text: 'OK' }]
                  );
                  return;
                }
                
                // Show quality selector
                Alert.alert(
                  'Select Quality',
                  'Choose processing quality level',
                  [
                    {
                      text: 'Reduced (Fast)',
                      onPress: () => processPhotogrammetry(directory, 'reduced')
                    },
                    {
                      text: 'Medium',
                      onPress: () => processPhotogrammetry(directory, 'medium')
                    },
                    {
                      text: 'Full (Slow)',
                      onPress: () => processPhotogrammetry(directory, 'full')
                    },
                    { text: 'Cancel', style: 'cancel' }
                  ]
                );
              },
            },
            {
              text: 'Share Images',
              onPress: async () => {
                try {
                  if (!directory) {
                    Alert.alert('Error', 'No capture directory found');
                    return;
                  }
                  
                  await Share.share({
                    title: 'Photogrammetry Images',
                    message: `Captured ${count} images for 3D reconstruction`,
                    url: directory,
                  });
                } catch (error) {
                  console.error('Error sharing directory:', error);
                  Alert.alert('Error', 'Failed to share images');
                }
              },
            },
          ]
        );
      } catch (error: any) {
        console.error('Error stopping capture:', error);
        Alert.alert('Error', 'Failed to stop capture');
      } finally {
        setIsLoading(false);
      }
    } else {
      // Start capturing images
      setIsLoading(true);
      try {
        await ARNativeModule.startObjectScan();
        setIsScanning(true);
        setImageCount(0);
        console.log('Photogrammetry capture started');
        
        // Poll for image count updates
        const interval = setInterval(async () => {
          try {
            const count = await ARNativeModule.getPhotogrammetryImageCount();
            setImageCount(count);
            
            const directory = await ARNativeModule.getPhotogrammetryCaptureDirectory();
            if (directory) {
              setCaptureDirectory(directory);
            }
          } catch (error) {
            console.error('Error getting capture info:', error);
          }
        }, 500); // Poll every 500ms for smooth updates
        
        setPollingInterval(interval);
      } catch (error: any) {
        console.error('Error starting capture:', error);
        Alert.alert(
          'Capture Error',
          error.message || 'Failed to start photogrammetry capture',
          [{ text: 'OK' }]
        );
      } finally {
        setIsLoading(false);
      }
    }
  };

  const processPhotogrammetry = async (directory: string | null, quality: string) => {
    if (!directory) {
      Alert.alert('Error', 'No capture directory found');
      return;
    }
    
    // Check if we're on Android
    if (Platform.OS === 'android') {
      Alert.alert(
        'Android Limitation',
        `Captured ${imageCount} images successfully!\n\nAndroid doesn't have built-in 3D reconstruction. You can:\n\n1. Share the images and use external photogrammetry software (Metashape, RealityCapture)\n2. Use cloud services (Polycam API, Sketchfab)\n3. Process on a Mac/iOS device with this app`,
        [
          { text: 'OK' },
          {
            text: 'Share Images',
            onPress: async () => {
              try {
                await Share.share({
                  title: 'Photogrammetry Images',
                  message: `${imageCount} images ready for 3D reconstruction. Directory: ${directory}`,
                  url: directory,
                });
              } catch (error) {
                console.error('Error sharing:', error);
              }
            }
          }
        ]
      );
      return;
    }
    
    setIsLoading(true);
    setProcessingProgress({ status: 'Starting...', progress: 0 });
    
    try {
      const filename = `model_${Date.now()}`;
      const outputPath = await ARNativeModule.processPhotogrammetry(
        directory,
        filename,
        quality,
        (progressData) => {
          if (progressData && progressData[0]) {
            setProcessingProgress(progressData[0]);
          }
        }
      );
      
      setProcessingProgress(null);
      
      Alert.alert(
        'Processing Complete',
        `USDZ model generated successfully`,
        [
          { text: 'OK', style: 'cancel' },
          {
            text: 'Share Model',
            onPress: async () => {
              try {
                await Share.share({
                  title: '3D Model',
                  message: `3D model generated from ${imageCount} images`,
                  url: outputPath,
                });
              } catch (error) {
                console.error('Error sharing model:', error);
                Alert.alert('Error', 'Failed to share model');
              }
            },
          },
        ]
      );
    } catch (error: any) {
      console.error('Error processing photogrammetry:', error);
      setProcessingProgress(null);
      Alert.alert(
        'Processing Failed',
        error.message || 'Failed to process photogrammetry',
        [{ text: 'OK' }]
      );
    } finally {
      setIsLoading(false);
    }
  };

  if (isSupported === null) {
    return (
      <View style={styles.container}>
        <ActivityIndicator size="large" color="#007AFF" />
        <Text style={styles.loadingText}>Checking AR support...</Text>
      </View>
    );
  }

  if (!isSupported) {
    return (
      <View style={styles.container}>
        <Text style={styles.errorText}>AR not supported on this device</Text>
        <TouchableOpacity
          style={styles.backButton}
          onPress={() => navigation.goBack()}
        >
          <Text style={styles.backButtonText}>Go Back</Text>
        </TouchableOpacity>
      </View>
    );
  }

  return (
    <View style={styles.container}>
      {/* AR Camera View */}
      <ARViewNative style={styles.arView} />
      
      {/* Capture Status Overlay */}
      {isScanning && (
        <View style={styles.statusOverlay}>
          <View style={styles.statusContainer}>
            <View style={[styles.statusIndicator, styles.statusScanning]} />
            <Text style={styles.statusText}>Capturing Images...</Text>
          </View>
          <Text style={styles.progressText}>
            Images: {imageCount}
          </Text>
          <Text style={styles.instructionText}>
            Move slowly around the object{"\n"}
            Capture from multiple angles (50-100 images recommended)
          </Text>
        </View>
      )}
      
      {/* Processing Progress Overlay */}
      {processingProgress && (
        <View style={styles.statusOverlay}>
          <View style={styles.statusContainer}>
            <ActivityIndicator size="small" color="#00BCD4" style={{marginRight: 10}} />
            <Text style={styles.statusText}>Processing...</Text>
          </View>
          <Text style={styles.progressText}>
            {processingProgress.status}: {Math.round(processingProgress.progress * 100)}%
          </Text>
          <Text style={styles.instructionText}>
            This may take several minutes
          </Text>
        </View>
      )}

      {/* Scan Control Button */}
      <View style={styles.controls}>
        <TouchableOpacity
          style={[
            styles.scanButton,
            isScanning ? styles.stopButton : styles.startButton,
          ]}
          onPress={handleStartScan}
          disabled={isLoading}
        >
          {isLoading ? (
            <ActivityIndicator color="#fff" />
          ) : (
            <Text style={styles.scanButtonText}>
              {isScanning ? 'Stop Capture' : 'Start Photogrammetry'}
            </Text>
          )}
        </TouchableOpacity>
      </View>
    </View>
  );
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#000',
  },
  loadingText: {
    marginTop: 20,
    fontSize: 16,
    color: '#fff',
  },
  errorText: {
    fontSize: 18,
    color: '#fff',
    textAlign: 'center',
    marginBottom: 20,
  },
  arView: {
    flex: 1,
  },
  statusOverlay: {
    position: 'absolute',
    top: 60,
    left: 20,
    right: 20,
    backgroundColor: 'rgba(0, 0, 0, 0.8)',
    borderRadius: 12,
    padding: 20,
  },
  statusContainer: {
    flexDirection: 'row',
    alignItems: 'center',
    marginBottom: 8,
  },
  statusIndicator: {
    width: 12,
    height: 12,
    borderRadius: 6,
    marginRight: 10,
  },
  statusScanning: {
    backgroundColor: '#00BCD4',
  },
  statusText: {
    fontSize: 18,
    color: '#fff',
    fontWeight: '700',
  },
  progressText: {
    fontSize: 14,
    color: '#00BCD4',
    marginTop: 5,
    fontWeight: '600',
  },
  instructionText: {
    fontSize: 13,
    color: '#AAA',
    marginTop: 8,
    fontStyle: 'italic',
  },
  controls: {
    position: 'absolute',
    bottom: 0,
    left: 0,
    right: 0,
    padding: 30,
    paddingBottom: 50,
    alignItems: 'center',
  },
  scanButton: {
    paddingVertical: 18,
    paddingHorizontal: 50,
    borderRadius: 30,
    alignItems: 'center',
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.3,
    shadowRadius: 8,
    elevation: 8,
  },
  startButton: {
    backgroundColor: '#00BCD4',
  },
  stopButton: {
    backgroundColor: '#FF5722',
  },
  scanButtonText: {
    color: '#fff',
    fontSize: 20,
    fontWeight: '700',
  },
});
