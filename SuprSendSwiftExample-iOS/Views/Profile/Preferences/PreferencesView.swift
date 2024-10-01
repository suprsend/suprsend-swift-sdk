//
//  PreferencesView.swift
//  SuprSendSwiftExample-iOS
//
//  Created by Ram Suthar on 01/10/24.
//

import SwiftUI
import SuprSendSwift

struct PreferencesView: View {
    
    @StateObject var preferenceViewModel = PreferenceViewModel()
    @State private var favoriteColor = "Category"
    var colors = ["Category", "Channel"]

    var section: SuprSendSwift.Section? {
        self.preferenceViewModel.preferenceData?.sections?.first
    }
    
    var channels: [ChannelPreference] {
        self.preferenceViewModel.preferenceData?.channelPreferences ?? []
    }
    
    func name(at index: Int) -> String {
        section?.subcategories?[index].name ?? ""
    }
    
    func channels(at index: Int) -> [CategoryChannel] {
        section?.subcategories?[index].channels ?? []
    }
    
    var range: Range<Int> {
        0..<(section?.subcategories?.count ?? 0)
    }
    
    var channelRange: Range<Int> {
        0..<channels.count
    }
    
    func channelName(at index: Int) -> String {
        channels[index].channel
    }
    
    var body: some View {
        NavigationView {
            VStack(alignment: .leading) {
                if self.preferenceViewModel.isLoading {
                    Text("loading...")
                } else {
                    Picker("What is your favorite color?", selection: $favoriteColor) {
                        ForEach(colors, id: \.self) {
                            Text($0)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding()
                    
                    if favoriteColor == "Category" {
                        List(range) { index in
                            Section(header: Text(name(at: index))) {
                                ForEach(channels(at: index), id: \.channel) { item in
                                    Toggle(item.channel, isOn: .constant(item.preference == .optIn))
                                }
                            }
                            .headerProminence(.increased)
                        }
                    } else {
                        List(channelRange) { index in
                            Section(header: Text(channelName(at: index))) {
                                Toggle("All", isOn: .constant(!channels[index].isRestricted))
                                Toggle("Required", isOn: .constant(channels[index].isRestricted))
                            }
                            .headerProminence(.increased)
                        }
                    }
                }
                
                Spacer()
            }
            .navigationBarTitle(Text("Notification Preferences"), displayMode: .inline)
            .navigationBarHidden(false)
            .navigationBarBackButtonHidden(true)
        }
    }
}
