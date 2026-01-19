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
  const [scanProgress, setScanProgress] = useState<any>(null);

  // Check AR support on mount
  useEffect(() => {
    checkARSupport();
  }, []);

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
      // Stop scanning
      setIsLoading(true);
      try {
        const scanData = await ARNativeModule.stopObjectScan();
        setIsScanning(false);
        setScanProgress(null);
        
        const filename = `scan_${Date.now()}`;
        
        Alert.alert(
          'Scan Complete',
          `Captured ${scanData.meshCount || 0} meshes with ${scanData.vertexCount || 0} vertices`,
          [
            { text: 'Dismiss', style: 'cancel' },
            {
              text: 'Save',
              onPress: async () => {
                try {
                  const filePath = await ARNativeModule.saveOBJToFile(filename);
                  Alert.alert('Saved', `File saved to: ${filePath}`);
                } catch (error) {
                  Alert.alert('Error', 'Failed to save file');
                }
              },
            },
            {
              text: 'Share',
              onPress: async () => {
                try {
                  console.log('Starting file save...');
                  const filePath = await ARNativeModule.saveOBJToFile(filename);
                  console.log('File saved successfully:', filePath);
                  
                  // Verify file was created
                  if (!filePath) {
                    throw new Error('Failed to create file - no path returned');
                  }
                  
                  // Add a small delay to ensure file is fully flushed to disk
                  await new Promise(resolve => setTimeout(resolve, 200));
                  
                  console.log('Attempting to share file...');
                  
                  // Use React Native's cross-platform Share API
                  const shareOptions = {
                    title: '3D Object Scan',
                    message: `3D scan captured: ${filename}.obj`,
                    url: filePath, // Pass the absolute path
                  };
                  
                  const result = await Share.share(shareOptions);
                  
                  if (result.action === Share.sharedAction) {
                    console.log('File shared successfully');
                    Alert.alert('Success', 'File shared successfully');
                  } else if (result.action === Share.dismissedAction) {
                    console.log('Share dismissed by user');
                  }
                } catch (error) {
                  console.error('Error sharing file:', error);
                  Alert.alert('Error', `Failed to share file: ${error}`);
                }
              },
            },
          ]
        );
      } catch (error: any) {
        console.error('Error stopping scan:', error);
        Alert.alert('Error', 'Failed to stop scan');
      } finally {
        setIsLoading(false);
      }
    } else {
      // Start scanning
      setIsLoading(true);
      try {
        await ARNativeModule.startObjectScan();
        setIsScanning(true);
        console.log('Object scanning started');
      } catch (error: any) {
        console.error('Error starting scan:', error);
        Alert.alert(
          'Scan Error',
          error.message || 'Failed to start object scan',
          [{ text: 'OK' }]
        );
      } finally {
        setIsLoading(false);
      }
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
      
      {/* Scanning Status Overlay */}
      {isScanning && (
        <View style={styles.statusOverlay}>
          <View style={styles.statusContainer}>
            <View style={[styles.statusIndicator, styles.statusScanning]} />
            <Text style={styles.statusText}>Scanning Object...</Text>
          </View>
          {scanProgress && (
            <Text style={styles.progressText}>
              Meshes: {scanProgress.meshCount || 0} | Vertices: {scanProgress.vertexCount || 0}
            </Text>
          )}
          <Text style={styles.instructionText}>
            Move around the object slowly
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
              {isScanning ? 'Stop Scanning' : 'Start Object Scan'}
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
