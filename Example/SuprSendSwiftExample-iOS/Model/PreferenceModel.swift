//
//  PreferenceModel.swift
//  SuprSendExample-iOS
//
//  Created by Ram Suthar on 01/10/24.
//

import Foundation
import SuprSend
import Combine

class PreferenceViewModel: ObservableObject {
    @Published var isLoading: Bool
    private var preferenceData: PreferenceData? {
        didSet {
            categories = preferenceData?.sections?.first?.subcategories ?? []
            channels = preferenceData?.channelPreferences ?? []
        }
    }
    @Published var categories: [SuprSend.Category] = []
    @Published var channels: [SuprSend.ChannelPreference] = []
    
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
