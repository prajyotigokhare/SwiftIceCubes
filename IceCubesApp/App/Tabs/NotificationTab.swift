import AppAccount
import DesignSystem
import Env
import Models
import Network
import Notifications
import SwiftUI
import Timeline

struct NotificationsTab: View {
  @Environment(\.isSecondaryColumn) private var isSecondaryColumn: Bool
  @Environment(\.scenePhase) private var scenePhase

  @EnvironmentObject private var theme: Theme
  @Environment(Client.self) private var client
  @Environment(StreamWatcher.self) private var watcher
  @Environment(AppAccountsManager.self) private var appAccount
  @EnvironmentObject private var currentAccount: CurrentAccount
  @EnvironmentObject private var userPreferences: UserPreferences
  @EnvironmentObject private var pushNotificationsService: PushNotificationsService
  @State private var routerPath = RouterPath()
  @Binding var popToRootTab: Tab

  let lockedType: Models.Notification.NotificationType?

  var body: some View {
    NavigationStack(path: $routerPath.path) {
      NotificationsListView(lockedType: lockedType)
        .withAppRouter()
        .withSheetDestinations(sheetDestinations: $routerPath.presentedSheet)
        .toolbar {
          if !isSecondaryColumn {
            statusEditorToolbarItem(routerPath: routerPath,
                                    visibility: userPreferences.postVisibility)
            if UIDevice.current.userInterfaceIdiom != .pad {
              ToolbarItem(placement: .navigationBarLeading) {
                AppAccountsSelectorView(routerPath: routerPath)
              }
            }
          }
          if UIDevice.current.userInterfaceIdiom == .pad {
            if (!isSecondaryColumn && !userPreferences.showiPadSecondaryColumn) || isSecondaryColumn {
              SecondaryColumnToolbarItem()
            }
          }
        }
        .toolbarBackground(theme.primaryBackgroundColor.opacity(0.50), for: .navigationBar)
        .id(client.id)
    }
    .onAppear {
      routerPath.client = client
      if isSecondaryColumn {
        clearNotifications()
      }
    }
    .withSafariRouter()
    .environment(routerPath)
    .onChange(of: $popToRootTab.wrappedValue) { oldValue, newValue in
      if newValue == .notifications {
        routerPath.path = []
      }
    }
    .onChange(of: pushNotificationsService.handledNotification) { oldValue, newValue in
      if let newValue, let type = newValue.notification.supportedType {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
          switch type {
          case .follow, .follow_request:
            routerPath.navigate(to: .accountDetailWithAccount(account: newValue.notification.account))
          default:
            if let status = newValue.notification.status {
              routerPath.navigate(to: .statusDetailWithStatus(status: status))
            }
          }
        }
      }
    }
    .onChange(of: scenePhase) { oldValue, newValue in
      switch newValue {
      case .active:
        clearNotifications()
      default:
        break
      }
    }
    .onChange(of: client.id) {
      routerPath.path = []
    }
  }

  private func clearNotifications() {
    if isSecondaryColumn {
      if let token = appAccount.currentAccount.oauthToken {
        userPreferences.setNotification(count: 0, token: token)
      }
      watcher.unreadNotificationsCount = 0
    }
  }
}
