// =============================================================================
// Widget Data Manager - App Group Shared Storage Access
// =============================================================================

import Foundation

// MARK: - Widget Data Manager

/// Manages reading and writing widget data through App Group shared storage
public final class WidgetDataManager: @unchecked Sendable {
    
    // MARK: - Constants
    
    public static let appGroupIdentifier = "group.com.jsayram.lifewrapped"
    private static let widgetDataKey = "widgetData"
    
    // MARK: - Shared Instance
    
    public static let shared = WidgetDataManager()
    
    // MARK: - Properties
    
    private let userDefaults: UserDefaults?
    
    // MARK: - Initialization
    
    /// Initialize with optional UserDefaults
    /// - Parameters:
    ///   - userDefaults: Custom UserDefaults to use. If nil and `disableAppGroup` is false, App Group will be used.
    ///   - disableAppGroup: If true, skips App Group lookup entirely (for testing unavailable scenarios)
    public init(userDefaults: UserDefaults? = nil, disableAppGroup: Bool = false) {
        // If disableAppGroup is true, explicitly set userDefaults to nil
        if disableAppGroup {
            print("⚠️ [WidgetDataManager] App Group disabled for testing")
            self.userDefaults = nil
            return
        }
        
        // If userDefaults provided explicitly (for testing), use it
        if let providedDefaults = userDefaults {
            print("✅ [WidgetDataManager] Using provided UserDefaults")
            self.userDefaults = providedDefaults
            return
        }
        
        // Check if App Group container exists before trying to create UserDefaults
        // This prevents CFPrefs warnings when the container is not available
        if FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Self.appGroupIdentifier) != nil,
           let appGroupDefaults = UserDefaults(suiteName: Self.appGroupIdentifier) {
            print("✅ [WidgetDataManager] Using App Group UserDefaults")
            self.userDefaults = appGroupDefaults
        } else {
            print("⚠️ [WidgetDataManager] App Group not available")
            self.userDefaults = nil
        }
    }
    
    // MARK: - Public Methods
    
    /// Reads the current widget data from App Group storage
    /// - Returns: The stored widget data, or empty data if none exists
    public func readWidgetData() -> WidgetData {
        guard let userDefaults = userDefaults else {
            return .empty
        }
        
        guard let data = userDefaults.data(forKey: Self.widgetDataKey) else {
            return .empty
        }
        
        do {
            let decoder = JSONDecoder()
            return try decoder.decode(WidgetData.self, from: data)
        } catch {
            return .empty
        }
    }
    
    /// Writes widget data to App Group storage
    /// - Parameter widgetData: The data to store
    /// - Returns: Whether the write was successful
    @discardableResult
    public func writeWidgetData(_ widgetData: WidgetData) -> Bool {
        guard let userDefaults = userDefaults else {
            return false
        }
        
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(widgetData)
            userDefaults.set(data, forKey: Self.widgetDataKey)
            return userDefaults.synchronize()
        } catch {
            return false
        }
    }
    
    /// Updates widget data with new values
    /// - Parameter update: Closure that modifies the widget data
    /// - Returns: Whether the update was successful
    @discardableResult
    public func updateWidgetData(_ update: (inout WidgetData) -> Void) -> Bool {
        var data = readWidgetData()
        update(&data)
        return writeWidgetData(data)
    }
    
    /// Clears all widget data
    @discardableResult
    public func clearWidgetData() -> Bool {
        guard let userDefaults = userDefaults else {
            return false
        }
        
        userDefaults.removeObject(forKey: Self.widgetDataKey)
        return userDefaults.synchronize()
    }
    
    /// Checks if the App Group is available
    public var isAppGroupAvailable: Bool {
        userDefaults != nil
    }
    
    /// Returns the age of the stored data
    public var dataAge: TimeInterval? {
        let data = readWidgetData()
        return Date().timeIntervalSince(data.lastUpdated)
    }
    
    /// Checks if data is stale (older than specified interval)
    /// - Parameter maxAge: Maximum age in seconds before data is considered stale
    /// - Returns: Whether the data is stale
    public func isDataStale(maxAge: TimeInterval = 3600) -> Bool {
        guard let age = dataAge else { return true }
        return age > maxAge
    }
}
