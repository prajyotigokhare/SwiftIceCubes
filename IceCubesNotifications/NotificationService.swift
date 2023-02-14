import AppAccount
import CryptoKit
import Env
import KeychainSwift
import Models
import UIKit
import UserNotifications
import Intents
import Network

@MainActor
class NotificationService: UNNotificationServiceExtension {
  var contentHandler: ((UNNotificationContent) -> Void)?
  var bestAttemptContent: UNMutableNotificationContent?

  override func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
    self.contentHandler = contentHandler
    bestAttemptContent = (request.content.mutableCopy() as? UNMutableNotificationContent)

    if var bestAttemptContent {
      let privateKey = PushNotificationsService.shared.notificationsPrivateKeyAsKey
      let auth = PushNotificationsService.shared.notificationsAuthKeyAsKey

      guard let encodedPayload = bestAttemptContent.userInfo["m"] as? String,
            let payload = Data(base64Encoded: encodedPayload.URLSafeBase64ToBase64())
      else {
        contentHandler(bestAttemptContent)
        return
      }

      guard let encodedPublicKey = bestAttemptContent.userInfo["k"] as? String,
            let publicKeyData = Data(base64Encoded: encodedPublicKey.URLSafeBase64ToBase64()),
            let publicKey = try? P256.KeyAgreement.PublicKey(x963Representation: publicKeyData)
      else {
        contentHandler(bestAttemptContent)
        return
      }

      guard let encodedSalt = bestAttemptContent.userInfo["s"] as? String,
            let salt = Data(base64Encoded: encodedSalt.URLSafeBase64ToBase64())
      else {
        contentHandler(bestAttemptContent)
        return
      }

      guard let plaintextData = NotificationService.decrypt(payload: payload,
                                                            salt: salt,
                                                            auth: auth,
                                                            privateKey: privateKey,
                                                            publicKey: publicKey),
        let notification = try? JSONDecoder().decode(MastodonPushNotification.self, from: plaintextData)
      else {
        contentHandler(bestAttemptContent)
        return
      }

      bestAttemptContent.title = notification.title
      bestAttemptContent.subtitle = bestAttemptContent.userInfo["i"] as? String ?? ""
      bestAttemptContent.body = notification.body.escape()
      bestAttemptContent.userInfo["plaintext"] = plaintextData
      bestAttemptContent.sound = UNNotificationSound(named: UNNotificationSoundName(rawValue: "glass.caf"))
      

      let preferences = UserPreferences.shared
      preferences.pushNotificationsCount += 1

      bestAttemptContent.badge = .init(integerLiteral: preferences.pushNotificationsCount)
      
      if let urlString = notification.icon,
         let url = URL(string: urlString)
      {
        let temporaryDirectoryURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("notification-attachments")
        try? FileManager.default.createDirectory(at: temporaryDirectoryURL, withIntermediateDirectories: true, attributes: nil)
        let filename = url.lastPathComponent
        let fileURL = temporaryDirectoryURL.appendingPathComponent(filename)

        Task {
          if let (data, _) = try? await URLSession.shared.data(for: .init(url: url)) {
            if let image = UIImage(data: data) {
              try? image.pngData()?.write(to: fileURL)
  
              if let remoteNotification = await toRemoteNotification(localNotification: notification) {
                let intent = buildMessageIntent(remoteNotification: remoteNotification, avatarURL: fileURL)
                bestAttemptContent = try bestAttemptContent.updating(from: intent) as! UNMutableNotificationContent
                let newBody = "\(bestAttemptContent.userInfo["i"] as? String ?? "") \n\(notification.title)\n\(notification.body.escape())"
                bestAttemptContent.body = newBody
              } else {
                if let attachment = try? UNNotificationAttachment(identifier: filename, url: fileURL, options: nil) {
                  bestAttemptContent.attachments = [attachment]
                }
              }
            }
            contentHandler(bestAttemptContent)
          } else {
            contentHandler(bestAttemptContent)
          }
        }
      } else {
        contentHandler(bestAttemptContent)
      }
    }
  }
  
  private func toRemoteNotification(localNotification: MastodonPushNotification) async -> Models.Notification? {
    do {
      if let account = AppAccountsManager.shared.availableAccounts.first(where: { $0.oauthToken?.accessToken == localNotification.accessToken }) {
        let client = Client(server: account.server, oauthToken: account.oauthToken)
        let remoteNotification: Models.Notification = try await client.get(endpoint: Notifications.notification(id: String(localNotification.notificationID)))
        return remoteNotification
      }
    } catch {
      return nil
    }
    return nil
  }
  
  private func buildMessageIntent(remoteNotification: Models.Notification, avatarURL: URL) -> INSendMessageIntent {
    let handle = INPersonHandle(value: remoteNotification.account.id, type: .unknown)
    let avatar = INImage(url: avatarURL)
    let sender = INPerson(personHandle: handle,
                          nameComponents: nil,
                          displayName: remoteNotification.account.safeDisplayName,
                          image: avatar,
                          contactIdentifier: nil,
                          customIdentifier: nil)
    let intent = INSendMessageIntent(recipients: nil,
                                     outgoingMessageType: .outgoingMessageText,
                                     content: nil,
                                     speakableGroupName: nil,
                                     conversationIdentifier: remoteNotification.account.id,
                                     serviceName: nil,
                                     sender: sender,
                                     attachments: nil)
    return intent
  }
}
