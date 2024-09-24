//
//  ProfileView.swift
//  ECommerceAppSwiftUI
//
//  Created by Ayush Gupta on 26/11/19.
//  Copyright © 2019 Ayush Gupta. All rights reserved.
//

import SwiftUI
import Combine

struct ProfileView: View {
    
    @AppStorage("email")
    var storeageEmail: String = ""
    
    @State var selection: Int? = nil
    let arrProfile = ProfileModel.all()
    
    fileprivate func NavigationBarView() -> some View {
        return HStack {
            Text("")
        }
        .frame(width: UIScreen.main.bounds.width, height: 45)
        .overlay(
            Text("More")
                .font(.custom(Constants.AppFont.semiBoldFont, size: 15))
                .padding(.horizontal, 10)
            , alignment: .center)
    }
    
    var body: some View {
        NavigationView {
            VStack(alignment: .leading) {
                NavigationBarView()
                HStack {
                    Image("banner2")
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 80, height: 80)
                        .clipShape(Circle())
                        .padding(.leading, 15)
                    VStack(alignment: .leading) {
                        Text(storeageEmail)
                            .font(.headline)
                            .bold()
                        Text("")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }.padding(.horizontal, 5)
                    Spacer()
                }.padding(.vertical, 10)
                
                ScrollView(.vertical, showsIndicators: false, content: {
                    VStack(spacing: 10) {
                        ForEach(self.arrProfile, id: \.id) { profile in
                            ProfileRow(profile: profile)
                        }
                    }
                    .padding(.horizontal, 15)
                })
                
                Spacer()
            }
            .navigationBarTitle(Text(""), displayMode: .inline)
            .navigationBarHidden(true)
            .navigationBarBackButtonHidden(true)
        }
    }
}

struct ProfileView_Previews: PreviewProvider {
    static var previews: some View {
        ProfileView()
    }
}

struct ProfileRow: View {
    
    @AppStorage("isLoggedIn")
    var isLoggedIn: Bool = false
    
    let profile: ProfileModel
    
    var body: some View {
        ZStack(alignment: .leading) {
            Rectangle()
                .foregroundColor(.white)
                .cornerRadius(5)
                .shadow(color: Constants.AppColor.shadowColor, radius: 1, x: 0.8, y: 0.8)
            VStack(alignment: .leading) {
                Text(profile.title)
                    .font(.subheadline)
                    .bold()
                    .padding(.bottom, 1)
                Text(profile.subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .onTapGesture {
                Task { @MainActor in
                    CommonAnalyticsHandler.unset(key: "choices")
                    if profile.title == "Logout(unsubscribe Push)" {
                        await CommonAnalyticsHandler.reset(unsubscribePushNotification: true)
                    } else {
                        await CommonAnalyticsHandler.reset(unsubscribePushNotification: false)
                    }
                    CommonAnalyticsHandler.unSetSuperProperties(key: "user_type")
                    self.isLoggedIn.toggle()
                }
            }
            .padding(15)
            Spacer()
        }
    }
}
