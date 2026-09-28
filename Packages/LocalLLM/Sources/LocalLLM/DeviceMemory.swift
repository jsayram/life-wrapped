//
//  DeviceMemory.swift
//  LocalLLM
//
//  Created by Life Wrapped on 9/26/2026.
//

import Foundation
import os

/// Memory numbers used to decide whether the Smart model can run.
public enum DeviceMemory {

    /// RAM in the device, in bytes
    public static var physicalBytes: UInt64 {
        ProcessInfo.processInfo.physicalMemory
    }

    /// How much more memory the app can use right now before iOS ends it, in bytes.
    /// nil when iOS doesn't report it (the Simulator returns 0).
    public static var availableToAppBytes: UInt64? {
        let available = os_proc_available_memory()
        return available > 0 ? UInt64(available) : nil
    }

    /// Whether this device has enough RAM for the model at all
    public static func canRun(_ modelType: LocalModelType) -> Bool {
        physicalBytes >= modelType.minimumDeviceMemoryBytes
    }

    /// Formats bytes for logs, for example "2.9 GB"
    static func describe(_ bytes: UInt64) -> String {
        String(format: "%.1f GB", Double(bytes) / 1_000_000_000)
    }
}
