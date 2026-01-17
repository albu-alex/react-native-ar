import React, { useEffect, useState, useCallback } from 'react';
import {
  View,
  Text,
  StyleSheet,
  TouchableOpacity,
  Alert,
  ActivityIndicator,
  Platform,
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
  const [isSessionActive, setIsSessionActive] = useState(false);
  const [isLoading, setIsLoading] = useState(false);

  // Check AR support on mount
  useEffect(() => {
    checkARSupport();
  }, []);

  // Handle session lifecycle with screen focus
  useFocusEffect(
    useCallback(() => {
      // Start session when screen gains focus (if supported)
      if (isSupported && !isSessionActive) {
        handleStartSession();
      }

      // Cleanup: stop session when screen loses focus
      return () => {
        if (isSessionActive) {
          handleStopSession();
        }
      };
    }, [isSupported, isSessionActive])
  );

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

  const handleStartSession = async () => {
    if (isSessionActive) return;

    setIsLoading(true);
    try {
      await ARNativeModule.startSession();
      setIsSessionActive(true);
      console.log('AR Session started successfully');
    } catch (error: any) {
      console.error('Error starting AR session:', error);
      Alert.alert(
        'AR Session Error',
        error.message || 'Failed to start AR session',
        [{ text: 'OK' }]
      );
    } finally {
      setIsLoading(false);
    }
  };

  const handleStopSession = async () => {
    if (!isSessionActive) return;

    try {
      await ARNativeModule.stopSession();
      setIsSessionActive(false);
      console.log('AR Session stopped');
    } catch (error) {
      console.error('Error stopping AR session:', error);
    }
  };

  const toggleSession = () => {
    if (isSessionActive) {
      handleStopSession();
    } else {
      handleStartSession();
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
      
      {/* Status Overlay */}
      <View style={styles.statusOverlay}>
        <View style={styles.statusContainer}>
          <View
            style={[
              styles.statusIndicator,
              isSessionActive ? styles.statusActive : styles.statusInactive,
            ]}
          />
          <Text style={styles.statusText}>
            {isSessionActive ? 'AR Active' : 'AR Inactive'}
          </Text>
        </View>
        <Text style={styles.platformText}>
          {Platform.OS === 'ios' ? 'ARKit' : 'ARCore'}
        </Text>
      </View>

      {/* Controls */}
      <View style={styles.controls}>
        <TouchableOpacity
          style={[
            styles.controlButton,
            isSessionActive ? styles.stopButton : styles.startButton,
          ]}
          onPress={toggleSession}
          disabled={isLoading}
        >
          {isLoading ? (
            <ActivityIndicator color="#fff" />
          ) : (
            <Text style={styles.controlButtonText}>
              {isSessionActive ? 'Stop Session' : 'Start Session'}
            </Text>
          )}
        </TouchableOpacity>

        <TouchableOpacity
          style={styles.backButton}
          onPress={() => navigation.goBack()}
        >
          <Text style={styles.backButtonText}>Back to Home</Text>
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
    backgroundColor: 'rgba(0, 0, 0, 0.7)',
    borderRadius: 10,
    padding: 15,
  },
  statusContainer: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  statusIndicator: {
    width: 12,
    height: 12,
    borderRadius: 6,
    marginRight: 8,
  },
  statusActive: {
    backgroundColor: '#4CAF50',
  },
  statusInactive: {
    backgroundColor: '#999',
  },
  statusText: {
    fontSize: 16,
    color: '#fff',
    fontWeight: '600',
  },
  platformText: {
    fontSize: 12,
    color: '#999',
    marginTop: 5,
  },
  controls: {
    position: 'absolute',
    bottom: 0,
    left: 0,
    right: 0,
    padding: 20,
    paddingBottom: 40,
    backgroundColor: 'rgba(0, 0, 0, 0.7)',
  },
  controlButton: {
    paddingVertical: 15,
    paddingHorizontal: 40,
    borderRadius: 10,
    alignItems: 'center',
    marginBottom: 15,
  },
  startButton: {
    backgroundColor: '#4CAF50',
  },
  stopButton: {
    backgroundColor: '#f44336',
  },
  controlButtonText: {
    color: '#fff',
    fontSize: 18,
    fontWeight: '600',
  },
  backButton: {
    paddingVertical: 15,
    paddingHorizontal: 40,
    borderRadius: 10,
    alignItems: 'center',
    backgroundColor: '#333',
  },
  backButtonText: {
    color: '#fff',
    fontSize: 16,
    fontWeight: '500',
  },
});
