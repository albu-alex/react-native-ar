export type RootStackParamList = {
  Home: undefined;
  AR: undefined;
};

declare global {
  namespace ReactNavigation {
    interface RootParamList extends RootStackParamList {}
  }
}
