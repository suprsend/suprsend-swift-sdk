//
//  DecideView.swift
//  ECommerceAppSwiftUI
//
//  Created by Niks on 05/11/21.
//
//

import SwiftUI

struct DecideView: View {
    
    @ObservedObject var decideViewModel: DecideViewModel
    
    @AppStorage("isLoggedIn")
    var isLoggedIn: Bool = false

    var body: some View {
        if(isLoggedIn) {
            TabBarView(viewModel: TabBarViewModel(selectedTab: decideViewModel.selectedTab))
        } else {
            LoginView()
        }
    }
}
