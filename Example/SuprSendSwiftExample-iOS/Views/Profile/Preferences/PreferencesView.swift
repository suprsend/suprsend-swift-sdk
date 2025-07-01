//
//  PreferencesView.swift
//  SuprSendExample-iOS
//
//  Created by Ram Suthar on 01/10/24.
//

import SwiftUI
import SuprSend

// Theme Protocol
protocol ThemeProtocol {
    var tint: Color { get }
    var title: Color { get }
    var subtitle: Color { get }
    var background: Color { get }
    var rowBackground: Color { get }
}

// Light Theme
struct LightTheme: ThemeProtocol {
    let tint = Color(red: 0.18, green: 0.44, blue: 0.91)
    let title = Color(red: 0.12, green: 0.16, blue: 0.23)
    let subtitle = Color(red: 0.28, green: 0.33, blue: 0.41)
    let background = Color(red: 0.95, green: 0.96, blue: 0.97)
    let rowBackground = Color.white
}

// Dark Theme
struct DarkTheme: ThemeProtocol {
    let tint = Color(red: 0.39, green: 0.64, blue: 0.97)
    let title = Color(red: 0.8, green: 0.85, blue: 0.91)
    let subtitle = Color(red: 0.61, green: 0.66, blue: 0.72)
    let background = Color(red: 0.09, green: 0.11, blue: 0.13)
    let rowBackground = Color(red: 0.12, green: 0.14, blue: 0.17)
}

struct FontTheme {
    let sectionTitle = Font.custom("Inter SemiBold", size: 17)
    let sectionSubtitle = Font.custom("Inter", size: 15)
    let title = Font.custom("Inter Medium", size: 15)
    let subtitle = Font.custom("Inter", size: 13)
    let body = Font.custom("Inter", size: 15)
}

// Theme Manager
class ThemeManager: ObservableObject {
    @Published var color: ThemeProtocol
    var font: FontTheme
    
    init() {
        // Initialize with system preference
        let isDark = UITraitCollection.current.userInterfaceStyle == .dark
        self.color = isDark ? DarkTheme() : LightTheme()
        self.font = FontTheme()
    }
    
    func updateTheme(for colorScheme: ColorScheme) {
        color = colorScheme == .dark ? DarkTheme() : LightTheme()
    }
}

struct PreferencesView: View {
    
    @StateObject var theme = ThemeManager()
    @Environment(\.colorScheme) var colorScheme
    
    @StateObject var viewModel = PreferenceViewModel()
    
    @State private var selection = Set<String>()
    
    var body: some View {
        VStack(alignment: .leading) {
            if viewModel.isLoading {
                ProgressView()
                    .progressViewStyle(.circular)
            } else {
                List($viewModel.sections, id: \.name) { $section in
                    if let channels = section.channels {
                        Section(header: SectionHeaderView(section: section)) {
                            ForEach(
                                channels,
                                id: \.channel
                            ) { channel in
                                DisclosureGroup {
                                    RadioView(channel: channel)
                                } label: {
                                    ChannelHeaderView(channel: channel)
                                }
                            }
                        }
                        .listRowBackground(theme.color.rowBackground)
                    } else {
                        Section(header: SectionHeaderView(section: section)) {
                            ForEach(
                                section.subcategories ?? [],
                                id: \.category
                            ) { category in
                                CategoryView(category: category)
                            }
                        }
                        .listRowBackground(theme.color.rowBackground)
                    }
                }
//                .listRowBackground(theme.color.rowBackground)
                .listStyle(.insetGrouped)
                .background(theme.color.background)
                .modifier(ScrollContentBackgroundIfAvailable())
            }
        }
        .navigationBarTitle(Text("Notification Preferences"), displayMode: .inline)
        .tint(theme.color.tint)
        .environmentObject(theme)
        .onChange(of: colorScheme) { newValue in
            theme.updateTheme(for: newValue)
        }
    }
}

struct SectionHeaderView: View {
    @EnvironmentObject var theme: ThemeManager
    
    var section: PreferenceSection
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8.0) {
            if let name = section.name {
                Text(name)
                    .font(theme.font.sectionTitle)
                    .foregroundStyle(theme.color.title)
            }
            
            if let description = section.description {
                Text(description)
                    .font(theme.font.sectionSubtitle)
                    .foregroundStyle(theme.color.subtitle)
            }
        }
        .listRowInsets(EdgeInsets(top: 16, leading: 0, bottom: 16, trailing: 0))
        .textCase(.none)
    }
}

struct CategoryView: View {
    
    @State var isOn: Bool = false
    var category: SuprSend.Category
    
    var body: some View {
        
//                    Toggle(category.name, isOn: $isOn)
//            .onChange(
//                of: isOn,
//                perform: { value in
//                    print("Toggle value: \(value)")
//                    _ = SuprSend.shared.preferences.updateCategoryPreference(category: category.category, preference: value ? .optIn : .optOut)
//                })
//                .disabled(!category.isEditable)
        DisclosureGroup {
            ForEach(category.channels ?? [], id: \.channel) { item in
                ToggleView(category: category.category, channel: item)
                    .listRowInsets(
                        EdgeInsets(top: 10, leading: 0, bottom: 10, trailing: 16)
                    )
                    .listRowSeparator(.hidden)
            }
        } label: {
            CategoryHeaderView(category: category)
        }
        .onAppear() {
            isOn = category.preference == .optIn
        }
        .onChange(
            of: category.preference,
            perform: { value in
                isOn = value == .optIn
            })
    }
}

struct CategoryHeaderView: View {
    @EnvironmentObject var theme: ThemeManager
    var category: SuprSend.Category
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4.0) {
            Text(category.name)
                .font(theme.font.title)
                .foregroundStyle(theme.color.title)
            
            if let description = category.description {
                Text(description)
                    .font(theme.font.subtitle)
                    .foregroundStyle(theme.color.subtitle)
            }
        }
        .listRowInsets(
            EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)
        )
    }
}

struct ChannelHeaderView: View {
    @EnvironmentObject var theme: ThemeManager
    var channel: SuprSend.ChannelPreference
    
    var body: some View {
        HStack {
//            Image(systemName: "envelope.fill")
//                .foregroundStyle(theme.color.tint)
            
            VStack(alignment: .leading, spacing: 4.0) {
                Text(channel.channel)
                    .font(theme.font.title)
                    .foregroundStyle(theme.color.title)
                
                Text(channel.isRestricted ? "Allow required notifications" : "Allow all notifications")
                    .font(theme.font.subtitle)
                    .foregroundStyle(theme.color.subtitle)
            }
        }
        .listRowInsets(
            EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)
        )
    }
}

struct RadioView: View {
    @EnvironmentObject var theme: ThemeManager
    
    var channel: ChannelPreference
    @State var selection: ChannelLevelPreferenceOptions
    
    var options: [ChannelLevelPreferenceOptions] = [.all, .required]
    
    init(channel: ChannelPreference) {
        self.channel = channel
        self.selection = channel.isRestricted ? .required : .all
    }
    
    var body: some View {
        Text("\(channel.channel) Preferences")
            .font(theme.font.subtitle)
            .foregroundStyle(theme.color.subtitle)
        
        ForEach(options, id: \.self) { option in
            Button(action:{
                selection = option
            }) {
                HStack(alignment: .top) {
                    Image(
                        systemName: selection == option ? "largecircle.fill.circle" : "circle"
                    )
                    .renderingMode(.original)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 20, height: 20)
                    .foregroundStyle(theme.color.tint)
                    .padding(.top, 4)
                    
                    VStack(alignment: .leading) {
                        Text(option.rawValue.capitalized)
                            .font(theme.font.title)
                            .foregroundStyle(theme.color.title)
                        
                        Text(option == .all ? "Allow All Notifications, except the ones that I have turned off" : "Allow only important notifications related to account and security settings")
                            .font(theme.font.subtitle)
                            .foregroundStyle(theme.color.subtitle)
                    }
                    
                    Spacer()
                }
            }
        }
        .onChange(of: selection) { value in
            _ = SuprSend.shared.preferences.updateOverallChannelPreference(
                channel: channel.channel,
                preference: selection
            )
        }
    }
}

struct ToggleView: View {
    @EnvironmentObject var theme: ThemeManager
    
    let category: String
    let channel: CategoryChannel
    @State var isOn: Bool = false
    
    var body: some View {
        Toggle(channel.channel, isOn: $isOn)
            .onChange(
                of: isOn,
                perform: { value in
                    print("Toggle value: \(value)")
                    Task {
                        await SuprSend.shared.preferences.updateChannelPreferenceInCategory(
                            channel: channel.channel,
                            preference: value ? .optIn : .optOut,
                            category: category,
                            args: nil
                        )
                }
            })
            .foregroundStyle(theme.color.title)
            .font(theme.font.body)
            .disabled(!channel.isEditable)
            .onAppear() {
                self.isOn = channel.preference == .optIn
            }
            .onChange(
                of: channel.preference,
                perform: { value in
                    self.isOn = value == .optIn
                })
    }
}

struct ScrollContentBackgroundIfAvailable: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 16.0, *) {
            content.scrollContentBackground(.hidden)
        } else {
            content
        }
    }
}
