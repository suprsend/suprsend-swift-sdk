//
//  Logger.swift
//  SuprSend
//
//  Created by Ram Suthar on 15/09/24.
//

import OSLog

let logger = Logger()

extension Logger {
    /// Logs a warning message at the debug level.
    ///
    /// - Parameter message: The message to be logged.
    func warn(_ message: String) {
        log(level: .debug, "\(message)")
    }
}
