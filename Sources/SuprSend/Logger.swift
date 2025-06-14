//
//  Logger.swift
//  SuprSend
//
//  Created by Ram Suthar on 15/09/24.
//

import OSLog

/// SuprSend internal `Logger` instance
let logger = Logger()

/// SuprSend Logger
final class Logger {
    
    /// OSLog Logger instance
    private let logger = os.Logger()
    
    /// Logs enabled
    private var enabled: Bool = false
    
    /// Enable logs
    func enableLogging() {
        enabled = true
    }
    
    /// Logs a warning message
    /// - Parameter message: The message to be logged.
    func warning(_ message: String) {
        guard enabled else {
            return
        }
        logger.warning("\(message)")
    }
    
    /// Logs an error message
    /// - Parameter message: The message to be logged.
    func error(_ message: String) {
        guard enabled else {
            return
        }
        logger.error("\(message)")
    }
    
    /// Logs an info message
    /// - Parameter message: The message to be logged.
    func info(_ message: String) {
        guard enabled else {
            return
        }
        logger.info("\(message)")
    }
}
