//
//  Push+NotificationService.swift
//  SuprSend
//
//  Created by Ram Suthar on 24/09/24.
//

#if os(iOS) || os(watchOS) || os(tvOS)
import UserNotifications
import UIKit

open class SuprSendNotificationService: UNNotificationServiceExtension {
    
    open func publicKey() -> String {
        String()
    }
    
    open func options() -> SuprSend.Options? {
        nil
    }
    
    var contentHandler: ((UNNotificationContent) -> Void)?
    var modifiedNotificationContent: UNMutableNotificationContent?
    
    public override func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        self.contentHandler = contentHandler
        modifiedNotificationContent = (request.content.mutableCopy() as? UNMutableNotificationContent)
        
        SuprSend.shared.configure(publicKey: publicKey(), options: options())
        SuprSend.shared.push.didReceive(request, withContentHandler: contentHandler)
        
        if let modifiedNotificationContent = modifiedNotificationContent {
            // Modify the notification content here...
            // 1
            guard let imageURLString =
                    modifiedNotificationContent.userInfo["image_url"] as? String else {
                contentHandler(modifiedNotificationContent)
                return
            }
            
            getMediaAttachment(for: imageURLString) { [weak self] image in
                guard let self = self, let image = image, let fileURL = self.saveImageAttachment(
                    image: image,
                    forIdentifier: "attachment.png")
                else {
                    contentHandler(modifiedNotificationContent)
                    return
                }
                
                let imageAttachment = try? UNNotificationAttachment(
                    identifier: "image",
                    url: fileURL,
                    options: nil)
                
                if let imageAttachment = imageAttachment {
                    modifiedNotificationContent.attachments = [imageAttachment]
                }
                
                contentHandler(modifiedNotificationContent)
            }
        }
    }
    
    public override func serviceExtensionTimeWillExpire() {
        // Called just before the extension will be terminated by the system.
        // Use this as an opportunity to deliver your "best attempt" at modified content, otherwise the original push payload will be used.
        if let contentHandler = contentHandler, let bestAttemptContent =  modifiedNotificationContent {
            contentHandler(bestAttemptContent)
        }
        
    }
}

extension SuprSendNotificationService {
    
    private func saveImageAttachment(image: UIImage, forIdentifier identifier: String
    ) -> URL? {
        let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
        let directoryPath = tempDirectory.appendingPathComponent(
            ProcessInfo.processInfo.globallyUniqueString,
            isDirectory: true)
        
        do {
            try FileManager.default.createDirectory(
                at: directoryPath,
                withIntermediateDirectories: true,
                attributes: nil)
            
            let fileURL = directoryPath.appendingPathComponent(identifier)
            
            guard let imageData = image.pngData() else {
                return nil
            }
            
            try imageData.write(to: fileURL)
            return fileURL
        } catch {
            return nil
        }
    }
    
    private func getMediaAttachment(for urlString: String, completion: @escaping (UIImage?) -> Void
    ) {
        // 1
        guard let url = URL(string: urlString) else {
            completion(nil)
            return
        }
        
        let task = URLSession.shared.dataTask(with: url) { data, response, error in
            if error != nil {
                completion(nil)
                return
            }
            
            guard let data = data else {
                completion(nil)
                return
            }
            
            guard let image = UIImage(data: data) else {
                completion(nil)
                return
            }
            completion(image)
        }
        task.resume()
    }
    
}
#endif
