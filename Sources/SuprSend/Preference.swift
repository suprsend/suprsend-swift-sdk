//
//  Preference.swift
//  SuprSend
//
//  Created by Ram Suthar on 05/09/24.
//

import Combine
import Foundation

/// A class representing preferences.
/// This class provides methods for getting and updating user's preferences data.
public class Preferences {
    
    /// A struct representing arguments for getting preferences.
    /// The `tenantId` parameter is used to specify the tenant ID when making API requests. If not provided, it defaults to `nil`.
    /// The `showOptOutChannels` parameter controls whether to show opt-out channels in the response. It defaults to `true`.
    public struct Args {
        /// The tenant ID to use when making API requests. Defaults to `nil`.
        public let tenantId: String?

        /// Whether to show opt-out channels in the response. Defaults to `true`.
        public let showOptOutChannels: Bool
    }

    /// A struct representing arguments for getting categories.
    public struct CategoryArgs {
        /// The tenant ID to use when making API requests. Defaults to `nil`.
        public let tenantId: String?

        /// Whether to show opt-out channels in the response. Defaults to `true`.
        public let showOptOutChannels: Bool

        /// The maximum number of categories to return. Defaults to `nil`.
        public let limit: Int?

        /// The offset at which to start returning categories. Defaults to `nil`.
        public let offset: Int?
    }

    private let config: SuprSend
    private var preferenceData: PreferenceData?
    private var preferenceArgs: Args?

    struct UpdateCategoryParams {
        let category: String
        let body: RequestPayload
        let subCategory: Category
        let args: Args?
    }

    private let debouncedUpdateCategoryPreferences = PassthroughSubject<
        UpdateCategoryParams, Never
    >()
    private let debouncedUpdateChannelPreferences = PassthroughSubject<ChannelRequestPayload, Never>()
    private var cancellables = Set<AnyCancellable>()

    /// The current preference data.
    var data: PreferenceData? {
        get {
            preferenceData
        }
        set {
            preferenceData = newValue
        }
    }

    init(config: SuprSend) {
        self.config = config

        debouncedUpdateCategoryPreferences
            .throttle(for: 0.5, scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] params in
                Task { [weak self] in
                    await self?._updateCategoryPreferences(
                        category: params.category,
                        body: params.body,
                        subCategory: params.subCategory,
                        args: params.args
                    )
                }
            }
            .store(in: &cancellables)

        debouncedUpdateChannelPreferences
            .throttle(for: 0.5, scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] body in
                Task { [weak self] in
                    await self?._updateChannelPreferences(body: body)
                }
            }
            .store(in: &cancellables)
    }

    /// Returns a URL for making API requests.
    /// - Parameters:
    ///   - path: The path to append to the base URL. Defaults to `nil`.
    ///   - qp: Query parameters to include in the request. Defaults to an empty dictionary.
    func getUrlpath(path: String, qp: [String: Any?]? = nil) -> URL {
        let urlPath = "v2/subscriber/\(config.distinctID?.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String())/\(path)"
        let queryParams = qp?.compactMap({ item in
            if let value = item.value {
                URLQueryItem(name: item.key, value: String(describing: value))
            } else {
                nil
            }
        })

        var urlComponents = URLComponents(string: urlPath)!
        if let queryParams {
//            urlComponents.queryItems = queryParams
        }
        return urlComponents.url!
    }

    /// Used to get user's whole preferences data.
    /// - Parameters:
    ///   - args: Arguments for the request. Defaults to `nil`.
    public func getPreferences(args: Args? = nil) async -> PreferenceAPIResponse {

        let queryParams: [String: Any?] = [
            "tenant_id": args?.tenantId,
            "show_opt_out_channels": "\(args?.showOptOutChannels ?? true)",
        ]
        preferenceArgs = args

        let path = getUrlpath(path: "full_preference", qp: queryParams)

        let response: PreferenceAPIResponse = await config.client().request(
            reqData: .init(
                path: path.absoluteString,
                payload: nil,
                type: .get
            )
        )

        if response.error == nil {
            self.data = response.body
        }

        return response
    }

    /// Used to get categories.
    /// - Parameters:
    ///   - args: Arguments for the request. Defaults to `nil`.
    public func getCategories(args: CategoryArgs? = nil) async -> APIResponse {
        let queryParams: [String: Any?] = [
            "tenant_id": args?.tenantId,
            "show_opt_out_channels": "\(args?.showOptOutChannels ?? true)",
            "limit": args?.limit,
            "offset": args?.offset,
        ]

        let path = getUrlpath(path: "category", qp: queryParams)

        return await config.client().request(
            reqData: .init(path: path.absoluteString, payload: nil, type: .get))
    }

    /// Used to get a category.
    /// - Parameters:
    ///   - category: The ID of the category to retrieve. Defaults to `nil`.
    ///   - args: Arguments for the request. Defaults to an empty dictionary.
    public func getCategory(category: String, args: Args? = nil) async -> APIResponse {
        let questionParams: [String: Any?] = [
            "tenant_id": args?.tenantId,
            "show_opt_out_channels": "\(args?.showOptOutChannels ?? true)",
        ]

        let path = getUrlpath(path: "category/\(category)", qp: questionParams)
        return await config.client().request(
            reqData: .init(path: path.absoluteString, payload: nil, type: .get))
    }

    /// Used to get overall channel preferences.
    public func getOverallChannelPreferences() async -> APIResponse {
        let path = getUrlpath(path: "channel_preference")
        return await config.client().request(
            reqData: .init(path: path.absoluteString, payload: nil, type: .get))
    }

    private func _updateCategoryPreferences(
        category: String,
        body: RequestPayload,
        subCategory: Category,
        args: Args? = nil
    ) async -> PreferenceAPIResponse {
        let queryParams: [String: Any?] = [
            "tenant_id": args?.tenantId,
            "show_opt_out_channels": "\(args?.showOptOutChannels ?? true)",
        ]

        let path = getUrlpath(path: "category/\(category)", qp: queryParams)

        let response: PreferenceAPIResponse = await config.client().request(
            reqData: .init(
                path: path.absoluteString,
                payload: .init(body),
                type: .patch
            )
        )

        if response.error != nil {
            config.emitter.emit(event: .preferencesError, data: response)
        } else {
            //            subCategory = response.body
            let response = await getPreferences(args: preferenceArgs)
            config.emitter.emit(event: .preferencesUpdated, data: response)
        }

        return response
    }

    private func _updateChannelPreferences(body: ChannelRequestPayload) async -> PreferenceAPIResponse {
        let path = getUrlpath(path: "channel_preference")

        let response: PreferenceAPIResponse = await config.client().request(
            reqData: .init(
                path: path.absoluteString,
                payload: .init(body),
                type: .patch
            )
        )
        if response.error != nil {
            config.emitter.emit(event: .preferencesError, data: response)
        } else {
            let response = await getPreferences(args: preferenceArgs)
            config.emitter.emit(event: .preferencesUpdated, data: response)
        }
        return response
    }

    /// Used to update user's category level preference.
    /// - Parameters:
    ///   - category: The ID of the category to update. Defaults to `nil`.
    ///   - preference: The new preference value. Defaults to `nil`.
    ///   - args: Arguments for the request. Defaults to an empty dictionary.
    public func updateCategoryPreference(
        category: String,
        preference: PreferenceOptions,
        args: Args? = nil
    ) -> PreferenceAPIResponse {

        guard let data else {
            return .error(
                .init(
                    type: .validation,
                    message: "Call getPreferences method before performing action"))
        }

        guard let sections = data.sections else {
            return .error(.init(type: .validation, message: "Sections doesn't exist"))
        }

        var categoryData: Category? = nil
        var dataUpdated = false

        // optimistic update in local store
        for section in sections {
            var abort = false
            if section.subcategories == nil {
                continue
            }

            for subcategory in section.subcategories! {
                if subcategory.category == category {
                    categoryData = subcategory
                    if subcategory.isEditable {
                        if subcategory.preference != preference {
                            subcategory.preference = preference
                            dataUpdated = true
                            abort = true
                            break
                        } else {
                            // Category is already set status
                        }
                    } else {
                        return .error(
                            .init(type: .validation, message: "Category preference is not editable")
                        )
                    }
                }
            }
            if abort {
                break
            }
        }

        guard let categoryData else {
            return .error(.init(type: .validation, message: "Category not found"))
        }

        if !dataUpdated {
            return .success(statusCode: nil, body: data)
        }

        var optOutChannels: [String] = []
        categoryData.channels?.forEach({ channel in
            if channel.preference == .optOut {
                optOutChannels.append(channel.channel)
            }
        })

        let showOptOutChannels = preferenceArgs?.showOptOutChannels ?? true

        let channels = showOptOutChannels && preference == .optIn ? nil : optOutChannels

        let requestPayload: RequestPayload = .init(
            preference: categoryData.preference,
            optOutChannels: channels
        )

        debouncedUpdateCategoryPreferences.send(
            .init(
                category: category,
                body: requestPayload,
                subCategory: categoryData,
                args: args
            )
        )

        return .success(body: data)
    }

    /// Used to update a channel preference in a category.
    /// - Parameters:
    ///   - channel: The ID of the channel to update. Defaults to `nil`.
    ///   - preference: The new preference value. Defaults to `nil`.
    ///   - category: The ID of the category that contains the channel. Defaults to `nil`.
    ///   - args: Arguments for the request. Defaults to an empty dictionary.
    public func updateChannelPreferenceInCategory(
        channel: String,
        preference: PreferenceOptions,
        category: String,
        args: Args? = nil
    ) async -> PreferenceAPIResponse {
        guard let data else {
            return .error(
                .init(
                    type: .validation,
                    message: "Call getPreferences method before performing action"))
        }

        guard let sections = data.sections else {
            return .error(.init(type: .validation, message: "Sections doesn't exist"))
        }

        var categoryData: Category? = nil
        var selectedChannelData: CategoryChannel? = nil
        var dataUpdated = false

        // optimistic update in local store
        for section in sections {
            var abort = false
            guard let subcategories = section.subcategories else {
                continue
            }

            for subcategory in subcategories {
                if subcategory.category == category {
                    categoryData = subcategory
                    guard let channels = subcategory.channels else {
                        continue
                    }

                    for channelData in channels {
                        if channelData.channel == channel {
                            selectedChannelData = channelData
                            if channelData.isEditable {
                                if channelData.preference != preference {
                                    channelData.preference = preference
                                    if preference == .optIn {
                                        subcategory.preference = .optIn
                                    }
                                    dataUpdated = true
                                    abort = true
                                    break
                                } else {
                                    // Channel is already set
                                }
                            } else {
                                return .error(
                                    .init(
                                        type: .validation,
                                        message: "Channel preference is not editable"))
                            }
                        }
                    }
                }
                if abort {
                    break
                }
            }
            if abort {
                break
            }
        }

        guard let categoryData else {
            return .error(.init(type: .validation, message: "Category not found"))
        }

        guard selectedChannelData != nil else {
            return .error(.init(type: .validation, message: "Category's channel not found"))
        }

        if !dataUpdated {
            return .success(body: data)
        }

        var optOutChannels: [String] = []
        categoryData.channels?.forEach { channel in
            if channel.preference == .optOut {
                optOutChannels.append(channel.channel)
            }
        }

        let showOptOutChannels = args?.showOptOutChannels ?? true

        let categoryPreference: PreferenceOptions =
            showOptOutChannels && categoryData.preference == .optOut && preference == .optIn
            ? .optIn : categoryData.preference

        let requestPayload = RequestPayload(
            preference: categoryPreference, optOutChannels: optOutChannels)
        
        debouncedUpdateCategoryPreferences.send(
            .init(
                category: category,
                body: requestPayload,
                subCategory: categoryData,
                args: args
            )
        )

        return .success(body: data)
    }

    /// Used to update overall channel preferences.
    /// - Parameters:
    ///   - channel: The ID of the channel to update. Defaults to `nil`.
    ///   - preference: The new preference value. Defaults to `nil`.
    public func updateOverallChannelPreference(
        channel: String, preference: ChannelLevelPreferenceOptions
    ) -> PreferenceAPIResponse {

        guard let data else {
            return .error(
                .init(
                    type: .validation,
                    message: "Call getPreferences method before performing this action."))
        }

        guard let channelPreferences = data.channelPreferences else {
            return .error(.init(type: .validation, message: "Channel preferences does not exist."))
        }

        var channelData: ChannelPreference? = nil
        var dataUpdated = false
        let preferenceRestricted = preference == .required

        for channelItem in channelPreferences {
            if channelItem.channel == channel {
                channelData = channelItem
                if channelItem.isRestricted != preferenceRestricted {
                    channelItem.isRestricted = preferenceRestricted
                    dataUpdated = true
                    break
                }
            }
        }

        guard let channelData else {
            return .error(.init(type: .validation, message: "Channel data not found."))
        }

        if !dataUpdated {
            return .success(body: data)
        }
        
        let requestPayload = ChannelRequestPayload(channelPreferences: [channelData])
        
        debouncedUpdateChannelPreferences.send(requestPayload)

        return .success(body: data)
    }
}
