import OSLog

let logger = Logger()

final class Logger {
    
    private let logger = os.Logger()
    
    private var enabled: Bool = false
    
    func enableLogging() {
        enabled = true
    }
    
    func warning(_ message: String) {
        guard enabled else {
            return
        }
        logger.warning("\(message)")
    }
    
    func error(_ message: String) {
        guard enabled else {
            return
        }
        logger.error("\(message)")
    }
    
    func info(_ message: String) {
        guard enabled else {
            return
        }
        logger.info("\(message)")
    }
}
