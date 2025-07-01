//
//  PreferenceModel.swift
//  SuprSendExample-iOS
//
//  Created by Ram Suthar on 01/10/24.
//

import Foundation
import SuprSend
import Combine

struct PreferenceSection {
    let name: String?
    let description: String?
    
    let subcategories: [SuprSend.Category]?
    let channels: [SuprSend.ChannelPreference]?
}

class PreferenceViewModel: ObservableObject {
    @Published var isLoading: Bool
    private var preferenceData: PreferenceData? {
        didSet {
            sections = (preferenceData?.sections?.map({ section in
                PreferenceSection(
                    name: section.name,
                    description: section.description,
                    subcategories: section.subcategories,
                    channels: nil
                )
            }) ?? []) + (preferenceData?.channelPreferences.map({ channels in
                [PreferenceSection(
                    name: "What notifications to allow for channel?",
                    description: nil,
                    subcategories: nil,
                    channels: channels
                )]
            }) ?? [])
        }
    }
    @Published var sections: [PreferenceSection] = []
    
    init() {
        isLoading = true
        fetchAll()
        
        SuprSend.shared.emitter.on(.preferencesUpdated) { data in
            DispatchQueue.main.async {
                self.preferenceData = data?.body
            }
        }
    }
}

extension PreferenceViewModel {
    
    func fetchAll() {
        isLoading = true
        Task {
            let result = await SuprSend.shared.preferences.getPreferences()
            DispatchQueue.main.async {
                self.preferenceData = result.body
                self.isLoading = false
            }
        }
    }
}
