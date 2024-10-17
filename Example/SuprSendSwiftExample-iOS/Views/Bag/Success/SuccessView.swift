//
//  SuccessView.swift
//  ECommerceAppSwiftUI
//
//  Created by Ayush Gupta on 12/12/19.
//  Copyright © 2019 Ayush Gupta. All rights reserved.
//

import SwiftUI
import SuprSendSwift

struct SuccessView: View {
    
    @AppStorage("email")
    var storeageEmail: String = ""
    
    
    var body: some View {
        NavigationView {
            VStack(alignment: .center) {
                Image("success")
                    .resizable()
                    .frame(width: 180, height: 180)
                    .aspectRatio(contentMode: .fit)
                Text("Success!")
                    .font(.largeTitle)
                    .padding(.vertical, 10)
                Text("Your order will be delivered soon. Thank you for choosing our app.")
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }
        }
        .navigationBarTitle(Text(""), displayMode: .inline)
        .navigationBarHidden(true)
        .navigationBarBackButtonHidden(true)
        .onAppear {
            onAppear()
        }
    }
    
    private func onAppear() {
        if(AppConstants.cartList.count == 0){
            return
        }
        
        let total = Float(AppConstants.cartList.reduce(0, { $0 + ($1.price - ($1.price * $1.discount)/100)}))
        
        let firstProduct = AppConstants.cartList[0]
        
        CommonAnalyticsHandler.track(eventName: "order_success_screen_viewed")
        
        Task {
        
            await SuprSend.shared.user.increment(
                properties: [
                    "order_count" : 1,
                    "amount" :total
                ]
            )
            
    //        SuprSend.shared.purchaseMade (
    //            properties: [
    //                "email" : "\(storeageEmail)",
    //                "product_id":"\(firstProduct.id)",
    //                "product_name":"\(firstProduct.name)",
    //                "amount":"\(total)"
    //            ]
    //        )
            
            await SuprSend.shared.user.setOnce(
                properties: [
                    "first_ordered_at" : "\(Date().formatDate())",
                    "first_ordered_amount" : total,
                    "first_ordered_product_name" : firstProduct.name
                ]
            )
        }
        
        AppConstants.cartList = []
    }
}

struct SuccessView_Previews: PreviewProvider {
    static var previews: some View {
        SuccessView()
    }
}
