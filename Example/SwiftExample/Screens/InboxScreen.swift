import SwiftUI
import SuprSend
import Combine

@MainActor
final class InboxViewModel: ObservableObject {
    @Published var notifications: [IRemoteNotification] = []
    @Published var apiStatus: APIResponseStatus = .initial
    @Published var hasMore: Bool = false
    @Published var badge: Int = 0
    @Published var activeStoreId: String
    @Published var storeBadges: [String: Int] = [:]

    let stores: [IStore] = [
        IStore(storeId: "all", label: "All"),
        IStore(storeId: "unread", label: "Unread", query: IStoreQuery(read: false)),
        IStore(storeId: "archived", label: "Archived", query: IStoreQuery(archived: true)),
        IStore(storeId: "transactional", label: "Transactional", query: IStoreQuery(categories: ["transactional"])),
        IStore(storeId: "custom", label: "Custom", query: IStoreQuery(tags: ["name"])),
    ]

    private var feed: Feed
    private var cancellables: Set<AnyCancellable> = []

    init() {
        self.activeStoreId = stores.first?.storeId ?? ""
        feed = SuprSend.shared.feeds.initialize(options: Self.makeOptions(stores: stores))
        bindFeed()
        Task { await initialFetch() }
    }

    deinit {
        SuprSend.shared.feeds.removeAll()
    }

    private static func makeOptions(stores: [IStore]) -> IFeedOptions {
        IFeedOptions(tenantId: nil, pageSize: 10, stores: stores, host: nil)
    }

    private func bindFeed() {
        feed.initializeSocketConnection()

        feed.emitter
            .receive(on: RunLoop.main)
            .sink { [weak self] event in
                guard let self else { return }
                if case .storeUpdate(let data) = event {
                    self.apply(data: data)
                }
            }
            .store(in: &cancellables)
    }

    func reconnectAndRefresh() {
        cancellables.removeAll()
        SuprSend.shared.feeds.removeAll()
        feed = SuprSend.shared.feeds.initialize(options: Self.makeOptions(stores: stores))
        bindFeed()
        Task { await initialFetch() }
    }

    func changeStore(_ storeId: String) {
        guard storeId != activeStoreId else { return }
        activeStoreId = storeId
        Task { _ = await feed.changeActiveStore(storeId: storeId) }
    }

    private func apply(data: IFeedData) {
        notifications = data.notifications
        apiStatus = data.apiStatus
        hasMore = data.pageInfo.hasMore
        badge = Int(data.meta["badge"] ?? "") ?? 0
        storeBadges = stores.reduce(into: [:]) { acc, store in
            acc[store.storeId] = Int(data.meta[store.storeId] ?? "") ?? 0
        }
    }

    func initialFetch() async {
        _ = await feed.fetch()
    }

    func refresh() async {
        _ = await feed.fetch()
    }

    func loadMore() async {
        guard hasMore, apiStatus != .fetchingMore else { return }
        _ = await feed.fetchNextPage()
    }

    func onItemTap(_ item: IRemoteNotification) {
        Task {
            if item.read_on == nil {
                _ = await feed.markAsRead(notificationId: item.n_id)
            }
            _ = await feed.markAsInteracted(notificationId: item.n_id)
        }
    }

    func markAsRead(_ item: IRemoteNotification) {
        Task { _ = await feed.markAsRead(notificationId: item.n_id) }
    }

    func markAsUnread(_ item: IRemoteNotification) {
        Task { _ = await feed.markAsUnread(notificationId: item.n_id) }
    }

    func archive(_ item: IRemoteNotification) {
        Task { _ = await feed.markAsArchived(notificationId: item.n_id) }
    }

    func markAllAsRead() {
        Task { _ = await feed.markAllAsRead() }
    }

    func resetBadge() {
        Task { _ = await feed.resetBadgeCount() }
    }
}

struct InboxScreen: View {
    @EnvironmentObject private var viewModel: InboxViewModel

    private var isInitialLoading: Bool {
        viewModel.apiStatus == .loading && viewModel.notifications.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            headerRow
            storeTabs

            if isInitialLoading {
                Spacer()
                ProgressView()
                Spacer()
            } else if viewModel.notifications.isEmpty {
                Spacer()
                VStack(spacing: 4) {
                    Text("No notifications yet")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.primary)
                    Text("New messages will appear here.")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                .padding(24)
                Spacer()
            } else {
                listContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.secondarySystemBackground))
    }

    private var headerRow: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Text("Inbox")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.primary)
                Spacer()
            }

            Button {
                viewModel.markAllAsRead()
            } label: {
                Text("Mark all as read")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(.systemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color(.systemGray4), lineWidth: 1)
                    )
            }
            .disabled(viewModel.notifications.isEmpty)
            .opacity(viewModel.notifications.isEmpty ? 0.5 : 1)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var storeTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(viewModel.stores, id: \.storeId) { store in
                    let isActive = viewModel.activeStoreId == store.storeId
                    let count = viewModel.storeBadges[store.storeId] ?? 0
                    Button {
                        viewModel.changeStore(store.storeId)
                    } label: {
                        HStack(spacing: 6) {
                            Text(store.label)
                                .font(.system(size: 13, weight: .semibold))
                            if count > 0 {
                                Text("\(count)")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(isActive ? Color(red: 0.145, green: 0.388, blue: 0.922) : .white)
                                    .padding(.horizontal, 5)
                                    .frame(minWidth: 18, minHeight: 16)
                                    .background(isActive ? Color.white : Color(red: 0.145, green: 0.388, blue: 0.922))
                                    .clipShape(Capsule())
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .foregroundColor(isActive ? .white : .primary)
                        .background(
                            isActive
                                ? Color(red: 0.145, green: 0.388, blue: 0.922)
                                : Color(.systemBackground)
                        )
                        .clipShape(Capsule())
                        .overlay(
                            Capsule().stroke(Color(.systemGray4), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(Color(.secondarySystemBackground))
    }

    private var listContent: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(viewModel.notifications, id: \.n_id) { item in
                    NotificationCard(
                        item: item,
                        onTap: { viewModel.onItemTap(item) },
                        onMarkRead: { viewModel.markAsRead(item) },
                        onMarkUnread: { viewModel.markAsUnread(item) },
                        onArchive: { viewModel.archive(item) }
                    )
                    .onAppear {
                        if item.n_id == viewModel.notifications.last?.n_id {
                            Task { await viewModel.loadMore() }
                        }
                    }
                }

                footer
            }
            .padding(16)
        }
        .refreshable {
            await viewModel.refresh()
        }
    }

    @ViewBuilder
    private var footer: some View {
        if viewModel.apiStatus == .fetchingMore {
            ProgressView().padding(.vertical, 16)
        } else if viewModel.hasMore {
            Button {
                Task { await viewModel.loadMore() }
            } label: {
                Text("Load older notifications")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color(.systemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(.systemGray4), lineWidth: 1)
                    )
            }
            .padding(.vertical, 8)
        } else if !viewModel.notifications.isEmpty {
            Text("You're all caught up")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .padding(.vertical, 16)
        }
    }
}

private struct NotificationCard: View {
    let item: IRemoteNotification
    let onTap: () -> Void
    let onMarkRead: () -> Void
    let onMarkUnread: () -> Void
    let onArchive: () -> Void

    private var isUnread: Bool { item.read_on == nil }
    private var hasHeader: Bool {
        let h = item.message.header ?? ""
        return !h.isEmpty
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 8) {
                    if isUnread {
                        Circle()
                            .fill(Color(red: 0.145, green: 0.388, blue: 0.922))
                            .frame(width: 8, height: 8)
                            .padding(.top, 6)
                    }
                    Text(hasHeader ? (item.message.header ?? "") : item.message.text)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(formatRelative(from: item.created_on))
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Menu {
                        if isUnread {
                            Button("Mark as read", action: onMarkRead)
                        } else {
                            Button("Mark as unread", action: onMarkUnread)
                        }
                        Button("Archive", role: .destructive, action: onArchive)
                    } label: {
                        Text("⋯")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .contentShape(Rectangle())
                    }
                    .menuStyle(.borderlessButton)
                }

                if hasHeader {
                    Text(item.message.text)
                        .font(.system(size: 13))
                        .foregroundColor(Color(red: 0.27, green: 0.27, blue: 0.27))
                        .lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let subtext = item.message.subtext?.text, !subtext.isEmpty {
                    Text(subtext)
                        .font(.system(size: 12))
                        .foregroundColor(Color(red: 0.4, green: 0.4, blue: 0.4))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isUnread ? Color(red: 0.965, green: 0.976, blue: 1.0) : Color(.systemBackground))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(
                        isUnread ? Color(red: 0.812, green: 0.863, blue: 1.0) : Color(.systemGray5),
                        lineWidth: 1
                    )
            )
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }
}

private func formatRelative(from timestamp: TimeInterval) -> String {
    let seconds = timestamp > 1_000_000_000_000 ? timestamp / 1000 : timestamp
    let date = Date(timeIntervalSince1970: seconds)
    let diff = max(1, Int(Date().timeIntervalSince(date)))
    if diff < 60 { return "\(diff)s ago" }
    let m = diff / 60
    if m < 60 { return "\(m)m ago" }
    let h = m / 60
    if h < 24 { return "\(h)h ago" }
    let d = h / 24
    if d < 7 { return "\(d)d ago" }
    let f = DateFormatter()
    f.dateStyle = .short
    return f.string(from: date)
}
