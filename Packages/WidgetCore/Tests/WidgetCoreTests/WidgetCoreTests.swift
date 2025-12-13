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
        #expect(data.goalProgress == 0)
        #expect(data.lastEntryTime == nil)
        #expect(data.isStreakAtRisk == false)
        #expect(data.weeklyWords == 0)
        #expect(data.weeklyMinutes == 0)
    }
    
    @Test("Placeholder widget data has sample values")
    func placeholderWidgetData() {
        let data = WidgetData.placeholder
        
        #expect(data.streakDays == 7)
        #expect(data.todayWords == 350)
        #expect(data.todayMinutes == 5)
        #expect(data.todayEntries == 2)
        #expect(data.goalProgress == 0.7)
        #expect(data.lastEntryTime != nil)
        #expect(data.isStreakAtRisk == false)
        #expect(data.weeklyWords == 2450)
        #expect(data.weeklyMinutes == 35)
    }
    
    @Test("Widget data initializes with custom values")
    func customWidgetData() {
        let lastEntry = Date()
        let data = WidgetData(
            streakDays: 10,
            todayWords: 500,
            todayMinutes: 8,
            todayEntries: 3,
            goalProgress: 0.85,
            lastEntryTime: lastEntry,
            isStreakAtRisk: true,
            weeklyWords: 3500,
            weeklyMinutes: 50
        )
        
        #expect(data.streakDays == 10)
        #expect(data.todayWords == 500)
        #expect(data.todayMinutes == 8)
        #expect(data.todayEntries == 3)
        #expect(data.goalProgress == 0.85)
        #expect(data.lastEntryTime == lastEntry)
        #expect(data.isStreakAtRisk == true)
        #expect(data.weeklyWords == 3500)
        #expect(data.weeklyMinutes == 50)
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
        #expect(decoded.goalProgress == original.goalProgress)
    }
    
    @Test("Widget data from rollup calculates goal progress")
    func fromRollupCalculatesGoalProgress() {
        let data = WidgetData.from(
            streakDays: 5,
            todayWordCount: 250,
            todayDuration: 300, // 5 minutes
            todayEntryCount: 1,
            dailyWordGoal: 500,
            lastEntryDate: Date(),
            weeklyWordCount: 1500,
            weeklyDuration: 1800 // 30 minutes
        )
        
        #expect(data.goalProgress == 0.5)
        #expect(data.todayMinutes == 5)
        #expect(data.weeklyMinutes == 30)
    }
    
    @Test("Widget data caps goal progress at 100%")
    func goalProgressCappedAt100Percent() {
        let data = WidgetData.from(
            streakDays: 5,
            todayWordCount: 750,
            todayDuration: 600,
            todayEntryCount: 2,
            dailyWordGoal: 500,
            lastEntryDate: Date(),
            weeklyWordCount: 2000,
            weeklyDuration: 2400
        )
        
        #expect(data.goalProgress == 1.0)
    }
    
    @Test("Widget data handles zero goal gracefully")
    func zeroGoalHandled() {
        let data = WidgetData.from(
            streakDays: 1,
            todayWordCount: 100,
            todayDuration: 120,
            todayEntryCount: 1,
            dailyWordGoal: 0,
            lastEntryDate: Date(),
            weeklyWordCount: 100,
            weeklyDuration: 120
        )
        
        #expect(data.goalProgress == 0)
    }
    
    @Test("Widget data is Equatable")
    func equatableWidgetData() {
        let data1 = WidgetData(streakDays: 5, todayWords: 100)
        let data2 = WidgetData(streakDays: 5, todayWords: 100)
        let data3 = WidgetData(streakDays: 6, todayWords: 100)
        
        #expect(data1 == data2)
        #expect(data1 != data3)
    }
    
    @Test("Widget data minutes converts from seconds")
    func minutesConversion() {
        let data = WidgetData.from(
            streakDays: 1,
            todayWordCount: 100,
            todayDuration: 180, // 3 minutes
            todayEntryCount: 1,
            dailyWordGoal: 200,
            lastEntryDate: Date(),
            weeklyWordCount: 500,
            weeklyDuration: 900 // 15 minutes
        )
        
        #expect(data.todayMinutes == 3)
        #expect(data.weeklyMinutes == 15)
    }
}

// MARK: - Widget Data Manager Tests

@Suite("WidgetDataManager Tests")
struct WidgetDataManagerTests {
    
    @Test("Manager detects unavailable App Group")
    func unavailableAppGroup() {
        let manager = WidgetDataManager(userDefaults: nil)
        
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
            goalProgress: 0.84,
            lastEntryTime: Date(),
            isStreakAtRisk: false,
            weeklyWords: 2940,
            weeklyMinutes: 49
        )
        
        let writeSuccess = manager.writeWidgetData(original)
        #expect(writeSuccess == true)
        
        let read = manager.readWidgetData()
        #expect(read.streakDays == 15)
        #expect(read.todayWords == 420)
        #expect(read.todayMinutes == 7)
        #expect(read.goalProgress == 0.84)
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
                goalProgress: 0.2,
                lastEntryTime: Date(),
                isStreakAtRisk: false,
                weeklyWords: 100,
                weeklyMinutes: 2
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
        #expect(WidgetDisplayMode.overview.rawValue == "Overview")
        #expect(WidgetDisplayMode.streak.rawValue == "Streak Focus")
        #expect(WidgetDisplayMode.goals.rawValue == "Goals")
        #expect(WidgetDisplayMode.weekly.rawValue == "Weekly Stats")
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
        let mode = WidgetDisplayMode.overview
        
        await Task {
            #expect(mode.rawValue == "Overview")
        }.value
    }
    
    @Test("Overview mode properties")
    func overviewModeProperties() {
        let mode = WidgetDisplayMode.overview
        
        #expect(mode.displayName == "Overview")
        #expect(mode.description.contains("metrics"))
        #expect(mode.icon == "rectangle.grid.2x2")
    }
    
    @Test("Streak mode properties")
    func streakModeProperties() {
        let mode = WidgetDisplayMode.streak
        
        #expect(mode.displayName == "Streak Focus")
        #expect(mode.description.contains("streak"))
        #expect(mode.icon == "flame.fill")
    }
    
    @Test("Goals mode properties")
    func goalsModeProperties() {
        let mode = WidgetDisplayMode.goals
        
        #expect(mode.displayName == "Goals")
        #expect(mode.description.contains("goal"))
        #expect(mode.icon == "target")
    }
    
    @Test("Weekly mode properties")
    func weeklyModeProperties() {
        let mode = WidgetDisplayMode.weekly
        
        #expect(mode.displayName == "Weekly Stats")
        #expect(mode.description.contains("weekly"))
        #expect(mode.icon == "calendar")
    }
}
