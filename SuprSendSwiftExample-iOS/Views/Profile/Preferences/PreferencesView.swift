//
//  PreferencesView.swift
//  SuprSendSwiftExample-iOS
//
//  Created by Ram Suthar on 01/10/24.
//

import SwiftUI
import SuprSendSwift

struct PreferencesView: View {
    
    @StateObject var viewModel = PreferenceViewModel()
    @State private var selectedTab = "Category"
    var colors = ["Category", "Channel"]
    
    @State private var selection = Set<String>()
    
    var body: some View {
        NavigationView {
            
            VStack(alignment: .leading) {
                if viewModel.isLoading {
                    Text("loading...")
                } else {
                    if selectedTab == "Category" {
                        List($viewModel.categories, id: \.category) { category in
                            CategoryView(category: category.wrappedValue)
                        }
                    } else {
                        List($viewModel.channels, id: \.channel) { item in
                            Section(header: Text(item.wrappedValue.channel)) {
                                RadioView(channel: item.wrappedValue)
                            }
                            .headerProminence(.increased)
                        }
                    }
                }
            }
            .navigationBarTitle(Text("Notification Preferences"), displayMode: .inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("Preferences", selection: $selectedTab) {
                        ForEach(colors, id: \.self) {
                            Text($0)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationBarHidden(false)
            .navigationBarBackButtonHidden(true)
        }
    }
}

struct CategoryView: View {
    
    @State var isOn: Bool
    var category: SuprSendSwift.Category
    
    init(category: SuprSendSwift.Category) {
        isOn = category.preference == .optIn
        self.category = category
    }
    
    var body: some View {
        Section(header: Toggle(category.name, isOn: $isOn)
            .onChange(
                of: isOn,
                perform: { value in
                    print("Toggle value: \(value)")
                    _ = SuprSend.shared.preferences.updateCategoryPreference(category: category.category, preference: value ? .optIn : .optOut)
                })
                .disabled(!category.isEditable)
        ) {
            ForEach(category.channels ?? [], id: \.channel) { item in
                ToggleView(channel: item, category: category.category)
            }
        }
        .headerProminence(.increased)
    }
}

struct RadioView: View {
    var channel: ChannelPreference
    @State var selection: ChannelLevelPreferenceOptions
    
    init(channel: ChannelPreference) {
        self.channel = channel
        self.selection = channel.isRestricted ? .required : .all
    }
    
    var body: some View {
        Picker(selection: $selection, label: Text(channel.channel)) {
            Text("All").tag(ChannelLevelPreferenceOptions.all)
            Text("Required").tag(ChannelLevelPreferenceOptions.required)
        }.pickerStyle(.automatic)
            .onChange(of: selection) { value in
                _ = SuprSend.shared.preferences.updateOverallChannelPreference(
                    channel: channel.channel,
                    preference: selection
                )
            }
    }
}

struct ToggleView: View {
    let category: String
    let channel: CategoryChannel
    @State var isOn: Bool
    
    init(channel: CategoryChannel, category: String) {
        self.channel = channel
        self.category = category
        self.isOn = channel.preference == .optIn
    }
    
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
            .disabled(!channel.isEditable)
    }
}
