import Foundation

/// A production-safe logger that only outputs in DEBUG builds.
/// Use this instead of `print()` throughout the codebase.
public enum Logger {
    
    // MARK: - Log Levels
    
    /// Log informational messages (✅, 📝, 💾, etc.)
    public static func info(_ message: @autoclosure () -> String, file: String = #file, function: String = #function) {
        #if DEBUG
        log(message(), file: file, function: function)
        #endif
    }
    
    /// Log success messages (✅)
    public static func success(_ message: @autoclosure () -> String, file: String = #file, function: String = #function) {
        #if DEBUG
        log("✅ " + message(), file: file, function: function)
        #endif
    }
    
    /// Log warning messages (⚠️)
    public static func warning(_ message: @autoclosure () -> String, file: String = #file, function: String = #function) {
        #if DEBUG
        log("⚠️ " + message(), file: file, function: function)
        #endif
    }
    
    /// Log error messages (❌)
    public static func error(_ message: @autoclosure () -> String, file: String = #file, function: String = #function) {
        #if DEBUG
        log("❌ " + message(), file: file, function: function)
        #endif
    }
    
    /// Log debug messages for development (🔍)
    public static func debug(_ message: @autoclosure () -> String, file: String = #file, function: String = #function) {
        #if DEBUG
        log("🔍 " + message(), file: file, function: function)
        #endif
    }
    
    /// Log API/network related messages (🌐)
    public static func network(_ message: @autoclosure () -> String, file: String = #file, function: String = #function) {
        #if DEBUG
        log("🌐 " + message(), file: file, function: function)
        #endif
    }
    
    /// Log audio related messages (🎧)
    public static func audio(_ message: @autoclosure () -> String, file: String = #file, function: String = #function) {
        #if DEBUG
        log("🎧 " + message(), file: file, function: function)
        #endif
    }
    
    /// Log database related messages (💾)
    public static func database(_ message: @autoclosure () -> String, file: String = #file, function: String = #function) {
        #if DEBUG
        log("💾 " + message(), file: file, function: function)
        #endif
    }
    
    /// Log AI/summarization related messages (🧠)
    public static func ai(_ message: @autoclosure () -> String, file: String = #file, function: String = #function) {
        #if DEBUG
        log("🧠 " + message(), file: file, function: function)
        #endif
    }
    
    // MARK: - Private
    
    private static func log(_ message: String, file: String, function: String) {
        let filename = (file as NSString).lastPathComponent.replacingOccurrences(of: ".swift", with: "")
        print("[\(filename)] \(message)")
    }
}
