//
//  InboxView.swift
//  SuprSendSwift
//
//  Created by Ram Suthar on 31/07/25.
//

import SwiftUI
import SuprSend

struct InboxView: View {
    
    @StateObject var theme = ThemeManager()
    @Environment(\.colorScheme) var colorScheme
    
    @ObservedObject var viewModel: InboxViewModel
    
    var body: some View {
        VStack(alignment: .leading) {
            if viewModel.isLoading {
                ProgressView()
                    .progressViewStyle(.circular)
            } else {
                List($viewModel.messages, id: \.id) { $item in
                    MessageView(message: item)
                        .onTapGesture {
                            if let url = item.url,
                               UIApplication.shared.canOpenURL(url) {
                                UIApplication.shared.open(url)
                            }
                        }
                        .overlay(alignment: .topTrailing) {
                            Menu {
                                if item.isRead {
                                    Button("Mark as unread", systemImage: "envelope.badge") {
                                        viewModel.markAsUnread(item: item)
                                    }
                                } else {
                                    Button("Mark as read", systemImage: "envelope.open") {
                                        viewModel.markAsRead(item: item)
                                    }
                                }
                                
                                Button("Archive", systemImage: "archivebox") {
                                    viewModel.archive(item: item)
                                }
                            } label: {
                                Image(systemName: "ellipsis")
                                    .frame(width: 24, height: 32)
                                    .foregroundStyle(theme.color.subtitle)
                            }
                            .padding()
                            .padding(.top, 16)
                        }
                }
                .listStyle(.plain)
                .background(theme.color.background)
                .modifier(ScrollContentBackgroundIfAvailable())
            }
        }
        .toolbar(content: {
            ToolbarItem(placement: .automatic) {
                Button("Mark all as read") {
                    viewModel.markAllAsRead()
                }
            }
        })
        .navigationBarTitle(Text("Notifications"), displayMode: .inline)
        .tint(theme.color.tint)
        .environmentObject(theme)
        .onChange(of: colorScheme) { newValue in
            theme.updateTheme(for: newValue)
        }
    }
}

struct MessageView: View {
    @EnvironmentObject var theme: ThemeManager
    let message: Message
    
    var body: some View {
        HStack(alignment: .top, spacing: 8.0) {
            Circle()
                .fill(message.isRead ? Color.clear : Color.blue)
                .frame(width: 8, height: 36)
            
            Image(systemName: "person.circle.fill")
                .resizable()
                .frame(width: 36, height: 36)
                .clipShape(.circle)
                .foregroundStyle(Color(red: 0.79, green: 0.83, blue: 0.88))
            
            VStack(alignment: .leading) {
                VStack(alignment: .leading, spacing: 4.0) {
                    HStack {
                        Text(message.header)
                            .font(theme.font.title)
                            .foregroundStyle(theme.color.title)
                        
                        Spacer()
                        
                        Text(message.time)
                            .font(theme.font.subtitle)
                            .foregroundStyle(theme.color.subtitle)
                    }
                    
                    Text(.init(message.text))
                        .font(theme.font.subtitle)
                        .foregroundStyle(theme.color.subtitle)
                }
                
                HStack {
                    ForEach(message.actions, id: \.id) { item in
                        if message.actions.first?.id == item.id {
                            Button(item.name) {
                                if let url = item.url,
                                   UIApplication.shared.canOpenURL(url) {
                                    UIApplication.shared.open(url)
                                }
                            }
                            .buttonBorderShape(.roundedRectangle)
                            .buttonStyle(.borderedProminent)
                        } else {
                            Button(item.name) {
                                if let url = item.url,
                                   UIApplication.shared.canOpenURL(url) {
                                    UIApplication.shared.open(url)
                                }
                            }
                            .buttonBorderShape(.roundedRectangle)
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(message.isRead ? Color.clear : Color.blue.opacity(0.1))
        .listRowInsets(
            EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
        )
    }
}
