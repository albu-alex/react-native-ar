//
//  ARViewManager.swift
//  ARinReactNative
//
//  View Manager for ARView
//

import Foundation

@objc(ARView)
class ARViewManager: RCTViewManager {
  
  override func view() -> UIView! {
    return ARView()
  }
  
  @objc
  override static func requiresMainQueueSetup() -> Bool {
    return true
  }
}
