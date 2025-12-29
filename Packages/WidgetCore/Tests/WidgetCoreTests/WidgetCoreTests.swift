// =============================================================================
// WidgetCore Tests
// =============================================================================

import Testing
import Foundation
@testable import WidgetCore

// MARK: - Widget Data Tests

@Suite("WidgetData Tests")
struct WidgetDataTests {
    
    @Test("Empty widget data has zero values")
    func emptyWidgetData() {
        let data = WidgetData.empty
        
        #expect(data.streakDays == 0)
        #expect(data.todayWords == 0)
        #expect(data.todayMinutes == 0)
        #expect(data.todayEntries == 0)
        #expect(data.lastEntryTime == nil)
        #expect(data.isStreakAtRisk == false)
    }
    
    @Test("Placeholder widget data has sample values")
    func placeholderWidgetData() {
        let data = WidgetData.placeholder
        
        #expect(data.streakDays == 7)
        #expect(data.todayWords == 350)
        #expect(data.todayMinutes == 5)
        #expect(data.todayEntries == 2)
        #expect(data.lastEntryTime != nil)
        #expect(data.isStreakAtRisk == false)
    }
    
    @Test("Widget data initializes with custom values")
    func customWidgetData() {
        let lastEntry = Date()
        let data = WidgetData(
            streakDays: 10,
            todayWords: 500,
            todayMinutes: 8,
            todayEntries: 3,
            lastEntryTime: lastEntry,
            isStreakAtRisk: true
        )
        
        #expect(data.streakDays == 10)
        #expect(data.todayWords == 500)
        #expect(data.todayMinutes == 8)
        #expect(data.todayEntries == 3)
        #expect(data.lastEntryTime == lastEntry)
        #expect(data.isStreakAtRisk == true)
    }
    
    @Test("Widget data is Codable")
    func codableWidgetData() throws {
        let original = WidgetData.placeholder
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(WidgetData.self, from: data)
        
        #expect(decoded.streakDays == original.streakDays)
        #expect(decoded.todayWords == original.todayWords)
        #expect(decoded.todayMinutes == original.todayMinutes)
    }
    
    @Test("Widget data from factory calculates minutes")
    func fromFactoryCalculatesMinutes() {
        let data = WidgetData.from(
            streakDays: 5,
            todayWordCount: 250,
            todayDuration: 300, // 5 minutes in seconds
            todayEntryCount: 1,
            lastEntryDate: Date()
        )
        
        #expect(data.todayMinutes == 5)
        #expect(data.todayEntries == 1)
    }
    
    @Test("Widget data is Equatable")
    func equatableWidgetData() {
        // Use a fixed date to avoid sub-millisecond timing differences
        let fixedDate = Date(timeIntervalSince1970: 1700000000)
        let data1 = WidgetData(streakDays: 5, todayWords: 100, lastUpdated: fixedDate)
        let data2 = WidgetData(streakDays: 5, todayWords: 100, lastUpdated: fixedDate)
        let data3 = WidgetData(streakDays: 6, todayWords: 100, lastUpdated: fixedDate)
        
        #expect(data1 == data2)
        #expect(data1 != data3)
    }
    
    @Test("Widget data session count tracks todayEntries")
    func sessionCountTracking() {
        let data = WidgetData.from(
            streakDays: 3,
            todayWordCount: 450,
            todayDuration: 540, // 9 minutes
            todayEntryCount: 5,
            lastEntryDate: Date()
        )
        
        #expect(data.todayEntries == 5)
        #expect(data.todayMinutes == 9)
    }
}

// MARK: - Widget Data Manager Tests

@Suite("WidgetDataManager Tests")
struct WidgetDataManagerTests {
    
    @Test("Manager detects unavailable App Group")
    func unavailableAppGroup() {
        let manager = WidgetDataManager(disableAppGroup: true)
        
        #expect(manager.isAppGroupAvailable == false)
        #expect(manager.readWidgetData().streakDays == 0)
        #expect(manager.writeWidgetData(.placeholder) == false)
    }
    
    @Test("Manager reads empty data when none stored")
    func readsEmptyWhenNoneStored() {
        let testDefaults = UserDefaults(suiteName: "test.widget.empty.\(UUID())")!
        
        let manager = WidgetDataManager(userDefaults: testDefaults)
        let data = manager.readWidgetData()
        
        #expect(data.streakDays == 0)
        #expect(data.todayWords == 0)
    }
    
    @Test("Manager writes and reads widget data")
    func writesAndReadsData() {
        let testDefaults = UserDefaults(suiteName: "test.widget.readwrite.\(UUID())")!
        
        let manager = WidgetDataManager(userDefaults: testDefaults)
        
        let original = WidgetData(
            streakDays: 15,
            todayWords: 420,
            todayMinutes: 7,
            todayEntries: 2,
            lastEntryTime: Date(),
            isStreakAtRisk: false
        )
        
        let writeSuccess = manager.writeWidgetData(original)
        #expect(writeSuccess == true)
        
        let read = manager.readWidgetData()
        #expect(read.streakDays == 15)
        #expect(read.todayWords == 420)
        #expect(read.todayMinutes == 7)
        #expect(read.todayEntries == 2)
    }
    
    @Test("Manager updates widget data")
    func updatesData() {
        let testDefaults = UserDefaults(suiteName: "test.widget.update.\(UUID())")!
        
        let manager = WidgetDataManager(userDefaults: testDefaults)
        
        manager.writeWidgetData(WidgetData(streakDays: 5))
        
        manager.updateWidgetData { data in
            data = WidgetData(
                streakDays: data.streakDays + 1,
                todayWords: 100,
                todayMinutes: 2,
                todayEntries: 1,
                lastEntryTime: Date(),
                isStreakAtRisk: false
            )
        }
        
        let read = manager.readWidgetData()
        #expect(read.streakDays == 6)
        #expect(read.todayWords == 100)
    }
    
    @Test("Manager clears widget data")
    func clearsData() {
        let testDefaults = UserDefaults(suiteName: "test.widget.clear.\(UUID())")!
        
        let manager = WidgetDataManager(userDefaults: testDefaults)
        
        manager.writeWidgetData(.placeholder)
        #expect(manager.readWidgetData().streakDays == 7)
        
        manager.clearWidgetData()
        #expect(manager.readWidgetData().streakDays == 0)
    }
    
    @Test("Manager reports data staleness")
    func reportsDataStaleness() {
        let testDefaults = UserDefaults(suiteName: "test.widget.stale.\(UUID())")!
        
        let manager = WidgetDataManager(userDefaults: testDefaults)
        
        // Fresh data
        manager.writeWidgetData(.placeholder)
        #expect(manager.isDataStale(maxAge: 3600) == false)
        
        // Old data (simulate by using very short max age)
        #expect(manager.isDataStale(maxAge: 0) == true)
    }
    
    @Test("Shared instance is accessible")
    func sharedInstanceAccessible() {
        let shared = WidgetDataManager.shared
        #expect(shared != nil)
    }
    
    @Test("App group identifier is correct")
    func appGroupIdentifierCorrect() {
        #expect(WidgetDataManager.appGroupIdentifier == "group.com.jsayram.lifewrapped")
    }
}

// MARK: - Widget Display Mode Tests

@Suite("WidgetDisplayMode Tests")
struct WidgetDisplayModeTests {
    
    @Test("All display modes have correct raw values")
    func correctRawValues() {
        #expect(WidgetDisplayMode.record.rawValue == "Record")
        #expect(WidgetDisplayMode.sessions.rawValue == "Sessions")
    }
    
    @Test("Display modes have unique raw values")
    func uniqueRawValues() {
        let rawValues = WidgetDisplayMode.allCases.map { $0.rawValue }
        let uniqueValues = Set(rawValues)
        
        #expect(uniqueValues.count == rawValues.count)
    }
    
    @Test("All modes have display names")
    func allModesHaveDisplayNames() {
        for mode in WidgetDisplayMode.allCases {
            #expect(!mode.displayName.isEmpty)
        }
    }
    
    @Test("All modes have descriptions")
    func allModesHaveDescriptions() {
        for mode in WidgetDisplayMode.allCases {
            #expect(!mode.description.isEmpty)
        }
    }
    
    @Test("All modes have icons")
    func allModesHaveIcons() {
        for mode in WidgetDisplayMode.allCases {
            #expect(!mode.icon.isEmpty)
        }
    }
    
    @Test("Display modes are Codable")
    func codableDisplayMode() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        
        for mode in WidgetDisplayMode.allCases {
            let data = try encoder.encode(mode)
            let decoded = try decoder.decode(WidgetDisplayMode.self, from: data)
            #expect(decoded == mode)
        }
    }
    
    @Test("Display modes are Sendable")
    func sendableDisplayMode() async {
        let mode = WidgetDisplayMode.record
        
        await Task {
            #expect(mode.rawValue == "Record")
        }.value
    }
    
    @Test("Record mode properties")
    func recordModeProperties() {
        let mode = WidgetDisplayMode.record
        
        #expect(mode.displayName == "Record")
        #expect(mode.description.contains("record") || mode.description.contains("Quick"))
        #expect(mode.icon == "mic.fill")
    }
    
    @Test("Sessions mode properties")
    func sessionsModeProperties() {
        let mode = WidgetDisplayMode.sessions
        
        #expect(mode.displayName == "Sessions")
        #expect(mode.description.contains("session"))
        #expect(mode.icon == "waveform")
    }
}
