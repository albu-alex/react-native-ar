import { requireNativeComponent, ViewStyle } from 'react-native';

interface ARViewProps {
  style?: ViewStyle;
}

export const ARViewNative = requireNativeComponent<ARViewProps>('ARView');
