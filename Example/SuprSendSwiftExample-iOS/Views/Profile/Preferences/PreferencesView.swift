//
//  PreferencesView.swift
//  SuprSendExample-iOS
//
//  Created by Ram Suthar on 01/10/24.
//

import SwiftUI
import SuprSend

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
                        List($viewModel.categories, id: \.category) { $category in
                            CategoryView(category: category)
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
    
    @State var isOn: Bool = false
    var category: SuprSend.Category
    
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
                ToggleView(category: category.category, channel: item)
            }
        }
        .headerProminence(.increased)
        .onAppear() {
            isOn = category.preference == .optIn
        }
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
