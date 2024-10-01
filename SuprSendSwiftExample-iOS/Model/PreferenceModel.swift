//
//  PreferenceModel.swift
//  SuprSendSwiftExample-iOS
//
//  Created by Ram Suthar on 01/10/24.
//

import Foundation
import SuprSendSwift
import Combine

class PreferenceViewModel: ObservableObject {
    @Published var isLoading: Bool
    @Published var preferenceData: PreferenceData?
    
    init() {
        isLoading = true
        fetchAll()
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
