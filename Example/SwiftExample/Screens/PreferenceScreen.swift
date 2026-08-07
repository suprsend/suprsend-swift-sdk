import SwiftUI
import SuprSend
import Combine

@MainActor
final class PreferenceViewModel: ObservableObject {
    @Published var preferenceData: SuprSend.PreferenceData?
    @Published var loading: Bool = true

    private let tenant: String? = nil
    private let tags: PreferenceTags? = .dictionary(["exists": true])

    func load() {
        Task { @MainActor in
            loading = true
            let response = await SuprSend.shared.user.preferences.getPreferences(
                args: .init(tenantId: tenant, locale: "fr")
            )
            if let body = response.body {
                preferenceData = body
            } else if let message = response.error?.message {
                print("[Preferences] load error: \(message)")
            }
            loading = false

            SuprSend.shared.emitter.on(.preferencesUpdated) { [weak self] resp in
                Task { @MainActor in
                    if let body = resp?.body {
                        self?.preferenceData = body
                    }
                }
            }
            SuprSend.shared.emitter.on(.preferencesError) { resp in
                print("[Preferences] update error: \(resp?.error?.message ?? "unknown")")
            }
        }
    }

    func updateCategory(_ category: SuprSend.Category, optIn: Bool) {
        let resp = SuprSend.shared.user.preferences.updateCategoryPreference(
            category: category.category,
            preference: optIn ? .optIn : .optOut,
            args: .init(tenantId: tenant)
        )
        if let body = resp.body { preferenceData = body }
    }

    func updateChannelInCategory(_ channel: SuprSend.CategoryChannel, in category: SuprSend.Category) {
        guard channel.isEditable else { return }
        let next: PreferenceOptions = channel.preference == .optIn ? .optOut : .optIn
        Task { @MainActor in
            let resp = await SuprSend.shared.user.preferences.updateChannelPreferenceInCategory(
                channel: channel.channel,
                preference: next,
                category: category.category,
                args: .init(tenantId: tenant)
            )
            if let body = resp.body { preferenceData = body }
        }
    }

    func updateOverallChannel(_ channel: SuprSend.ChannelPreference, restricted: Bool) {
        let resp = SuprSend.shared.user.preferences.updateOverallChannelPreference(
            channel: channel.channel,
            preference: restricted ? .required : .all
        )
        if let body = resp.body { preferenceData = body }
    }
}

struct PreferenceScreen: View {
    @StateObject private var viewModel = PreferenceViewModel()

    var body: some View {
        Group {
            if viewModel.loading {
                VStack { ProgressView() }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let data = viewModel.preferenceData {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Notification Preferences")
                            .font(.system(size: 20, weight: .bold))
                            .padding(.bottom, 16)

                        if let sections = data.sections {
                            ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                                SectionView(section: section, viewModel: viewModel)
                            }
                        }

                        ChannelLevelPreferencesView(data: data, viewModel: viewModel)
                    }
                    .padding(16)
                }
            } else {
                Text("Failed to load preferences.")
                    .foregroundColor(.secondary)
            }
        }
        .onAppear { viewModel.load() }
    }
}

private struct SectionView: View {
    let section: SuprSend.Section
    @ObservedObject var viewModel: PreferenceViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let name = section.name {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(Color(red: 0.24, green: 0.24, blue: 0.24))
                    if let desc = section.description {
                        Text(desc)
                            .font(.system(size: 13))
                            .foregroundColor(Color(red: 0.42, green: 0.45, blue: 0.50))
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(red: 0.98, green: 0.98, blue: 0.98))
                .cornerRadius(6)
                .padding(.bottom, 12)
            }

            if let subcategories = section.subcategories {
                ForEach(Array(subcategories.enumerated()), id: \.offset) { _, subcategory in
                    SubcategoryRow(subcategory: subcategory, viewModel: viewModel)
                }
            }
        }
        .padding(.bottom, 24)
    }
}

private struct SubcategoryRow: View {
    @ObservedObject var viewModel: PreferenceViewModel
    let subcategory: SuprSend.Category

    init(subcategory: SuprSend.Category, viewModel: PreferenceViewModel) {
        self.subcategory = subcategory
        self.viewModel = viewModel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(subcategory.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Color(red: 0.24, green: 0.24, blue: 0.24))
                    if let desc = subcategory.description {
                        Text(desc)
                            .font(.system(size: 13))
                            .foregroundColor(Color(red: 0.42, green: 0.45, blue: 0.50))
                    }
                }
                .padding(.trailing, 12)
                Spacer()
                Toggle(
                    "",
                    isOn: Binding(
                        get: { subcategory.preference == .optIn },
                        set: { viewModel.updateCategory(subcategory, optIn: $0) }
                    )
                )
                .labelsHidden()
                .disabled(!subcategory.isEditable)
            }

            if let channels = subcategory.channels {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(channels.enumerated()), id: \.offset) { _, channel in
                            ChannelCheckbox(channel: channel) {
                                viewModel.updateChannelInCategory(channel, in: subcategory)
                            }
                        }
                    }
                }
                .padding(.top, 12)
            }
        }
        .padding(.top, 18)
        .padding(.bottom, 12)
        .overlay(Divider(), alignment: .bottom)
    }
}

private struct ChannelCheckbox: View {
    let channel: SuprSend.CategoryChannel
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Circle()
                    .fill(circleColor)
                    .frame(width: 20, height: 20)
                    .overlay(Circle().stroke(Color(red: 0.63, green: 0.62, blue: 0.62), lineWidth: 0.5))
                Text(channel.channel)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color(red: 0.42, green: 0.45, blue: 0.50))
            }
            .padding(.leading, 4)
            .padding(.trailing, 16)
            .padding(.vertical, 4)
            .overlay(
                RoundedRectangle(cornerRadius: 30)
                    .stroke(Color(red: 0.71, green: 0.71, blue: 0.71), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .opacity(channel.isEditable ? 1 : 0.6)
        .disabled(!channel.isEditable)
    }

    private var circleColor: Color {
        let selected = channel.preference == .optIn
        if selected {
            return channel.isEditable
                ? Color(red: 0.14, green: 0.39, blue: 0.92)
                : Color(red: 0.74, green: 0.81, blue: 0.97)
        }
        return channel.isEditable ? Color(.systemBackground) : Color(red: 0.82, green: 0.81, blue: 0.81)
    }
}

private struct ChannelLevelPreferencesView: View {
    let data: SuprSend.PreferenceData
    @ObservedObject var viewModel: PreferenceViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What notifications to allow for channel?")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(Color(red: 0.24, green: 0.24, blue: 0.24))
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(red: 0.98, green: 0.98, blue: 0.98))
                .cornerRadius(6)

            if let channels = data.channelPreferences {
                ForEach(Array(channels.enumerated()), id: \.offset) { _, channel in
                    ChannelLevelItem(channel: channel, viewModel: viewModel)
                }
            } else {
                Text("No Data").foregroundColor(.secondary)
            }
        }
    }
}

private struct ChannelLevelItem: View {
    let channel: SuprSend.ChannelPreference
    @ObservedObject var viewModel: PreferenceViewModel
    @State private var expanded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: { expanded.toggle() }) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(channel.channel)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(Color(red: 0.24, green: 0.24, blue: 0.24))
                    Text(channel.isRestricted ? "Allow required notifications only" : "Allow all notifications")
                        .font(.system(size: 13))
                        .foregroundColor(Color(red: 0.42, green: 0.45, blue: 0.50))
                }
            }
            .buttonStyle(.plain)

            if expanded {
                VStack(alignment: .leading, spacing: 12) {
                    Text("\(channel.channel) Preferences")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(Color(red: 0.24, green: 0.24, blue: 0.24))
                        .padding(.bottom, 8)
                        .overlay(Divider(), alignment: .bottom)

                    RadioRow(
                        selected: !channel.isRestricted,
                        title: "All",
                        help: "Allow All Notifications, except the ones that I have turned off"
                    ) { viewModel.updateOverallChannel(channel, restricted: false) }

                    RadioRow(
                        selected: channel.isRestricted,
                        title: "Required",
                        help: "Allow only important notifications related to account and security settings"
                    ) { viewModel.updateOverallChannel(channel, restricted: true) }
                }
                .padding(.top, 12)
                .padding(.leading, 8)
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .stroke(Color(red: 0.85, green: 0.85, blue: 0.85), lineWidth: 1)
        )
    }
}

private struct RadioRow: View {
    let selected: Bool
    let title: String
    let help: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .stroke(Color(red: 0.63, green: 0.62, blue: 0.62), lineWidth: 1)
                        .frame(width: 18, height: 18)
                    if selected {
                        Circle()
                            .fill(Color(red: 0.14, green: 0.39, blue: 0.92))
                            .frame(width: 10, height: 10)
                    }
                }
                .padding(.top, 2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 14)).foregroundColor(Color(red: 0.24, green: 0.24, blue: 0.24))
                    Text(help).font(.system(size: 13)).foregroundColor(Color(red: 0.42, green: 0.45, blue: 0.50))
                }
            }
        }
        .buttonStyle(.plain)
    }
}

