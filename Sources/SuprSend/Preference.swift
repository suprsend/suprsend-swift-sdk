//
//  Preference.swift
//  SuprSend
//
//  Created by Ram Suthar on 05/09/24.
//

import Foundation

/// A class representing preferences.
/// This class provides methods for getting and updating user's preferences data.
public class Preferences {
    
    /// A struct representing arguments for getting/updating preferences.
    ///
    /// All fields are optional. When ``showOptOutChannels`` is `nil` it is
    /// treated as `true` at the request layer — this distinguishes "caller did
    /// not specify" from "caller explicitly said `false`", which matches the
    /// web SDK's `args?.showOptOutChannels === false ? false : true` rule.
    public struct Args {
        /// The tenant ID to use when making API requests. Defaults to `nil`.
        public let tenantId: String?

        /// Whether to show opt-out channels in the response. `nil` means "not
        /// specified" — the SDK falls back to the value stored from the most
        /// recent ``Preferences/getPreferences(args:)`` call, or `true`.
        public let showOptOutChannels: Bool?

        /// Tags filter applied when fetching preferences.
        public let tags: PreferenceTags?

        /// Locale to use when fetching preference text. Defaults to `nil`.
        public let locale: String?

        public init(
            tenantId: String? = nil,
            showOptOutChannels: Bool? = nil,
            tags: PreferenceTags? = nil,
            locale: String? = nil
        ) {
            self.tenantId = tenantId
            self.showOptOutChannels = showOptOutChannels
            self.tags = tags
            self.locale = locale
        }
    }

    /// A struct representing arguments for getting categories.
    public struct CategoryArgs {
        /// The tenant ID to use when making API requests. Defaults to `nil`.
        public let tenantId: String?

        /// Whether to show opt-out channels in the response. `nil` means "not
        /// specified" — treated as `true` at the request layer.
        public let showOptOutChannels: Bool?

        /// Tags filter applied when fetching categories.
        public let tags: PreferenceTags?

        /// Locale to use when fetching category text. Defaults to `nil`.
        public let locale: String?

        /// The maximum number of categories to return. Defaults to `nil`.
        public let limit: Int?

        /// The offset at which to start returning categories. Defaults to `nil`.
        public let offset: Int?

        public init(
            tenantId: String? = nil,
            showOptOutChannels: Bool? = nil,
            tags: PreferenceTags? = nil,
            locale: String? = nil,
            limit: Int? = nil,
            offset: Int? = nil
        ) {
            self.tenantId = tenantId
            self.showOptOutChannels = showOptOutChannels
            self.tags = tags
            self.locale = locale
            self.limit = limit
            self.offset = offset
        }
    }

    private let config: SuprSendClient
    private var preferenceData: PreferenceData?
    private var preferenceArgs: Args?

    struct UpdateCategoryParams {
        let category: String
        let body: RequestPayload
        let subCategory: Category
        let args: Args?
    }

    struct UpdateChannelParams {
        let body: ChannelRequestPayload
        let args: Args?
    }

    /// Per-category debounce. Mirrors the web SDK's `debounceByType(_, 1000ms)`
    /// keyed by category — rapid toggles to the *same* category coalesce into
    /// one PATCH; toggles across *different* categories each fire their own
    /// PATCH.
    private let categoryPreferenceDebouncer = KeyedDebouncer<UpdateCategoryParams>(
        delayNanoseconds: Preferences.debounceDelayNanoseconds
    )

    /// Per-channel debounce for channel-level (`channel_preference`) updates.
    private let channelPreferenceDebouncer = KeyedDebouncer<UpdateChannelParams>(
        delayNanoseconds: Preferences.debounceDelayNanoseconds
    )

    /// Debounce window in nanoseconds. Matches the web SDK's 1000 ms.
    private static let debounceDelayNanoseconds: UInt64 = 1_000_000_000

    /// The current preference data.
    var data: PreferenceData? {
        get {
            preferenceData
        }
        set {
            preferenceData = newValue
        }
    }

    init(config: SuprSendClient) {
        self.config = config

        categoryPreferenceDebouncer.action = { [weak self] params in
            _ = await self?._updateCategoryPreferences(
                category: params.category,
                body: params.body,
                subCategory: params.subCategory,
                args: params.args
            )
        }

        channelPreferenceDebouncer.action = { [weak self] params in
            _ = await self?._updateChannelPreferences(body: params.body, args: params.args)
        }
    }

    /// Returns a URL for making API requests.
    /// - Parameters:
    ///   - path: The path to append to the base URL. Defaults to `nil`.
    ///   - qp: Query parameters to include in the request. Defaults to an empty dictionary.
    func getUrlpath(path: String, qp: [String: Any?]? = nil) -> URL {
        let urlPath = "v2/subscriber/\(config.distinctID?.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String())/\(path)/"
        let queryParams = qp?.compactMap({ item in
            if let value = item.value {
                URLQueryItem(name: item.key, value: String(describing: value))
            } else {
                nil
            }
        })

        var urlComponents = URLComponents(string: urlPath)!
        if let queryParams {
            urlComponents.queryItems = queryParams
        }
        return urlComponents.url!
    }

    /// Encodes a ``PreferenceTags`` value into the form expected on the wire.
    /// String tags are passed through as-is; dictionary tags are serialised as
    /// JSON. Mirrors the web SDK's `validateQueryParams` branch on `object`.
    private func encodeTags(_ tags: PreferenceTags?) -> String? {
        guard let tags else { return nil }
        switch tags {
        case .string(let value):
            return value
        case .dictionary(let dict):
            guard
                JSONSerialization.isValidJSONObject(dict),
                let data = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys]),
                let json = String(data: data, encoding: .utf8)
            else { return nil }
            return json
        }
    }

    /// Resolves the effective `show_opt_out_channels` query value using the
    /// web SDK priority: explicit arg → value stored from the last
    /// ``getPreferences(args:)`` call → `true`.
    private func resolveShowOptOutChannels(_ args: Args?) -> Bool {
        args?.showOptOutChannels
            ?? preferenceArgs?.showOptOutChannels
            ?? true
    }

    /// Captures the effective ``Args`` for an update call by folding the
    /// caller-supplied ``Args`` over the stored ``preferenceArgs`` (set by the
    /// last ``getPreferences(args:)`` call). This snapshot is what reaches the
    /// PATCH URL after debouncing, so the URL reflects intent at call-time
    /// rather than whatever the stored args happen to be when the debouncer
    /// fires.
    private func resolvedArgs(_ args: Args?, showOptOutChannels: Bool) -> Args {
        Args(
            tenantId: args?.tenantId ?? preferenceArgs?.tenantId,
            showOptOutChannels: showOptOutChannels,
            tags: args?.tags ?? preferenceArgs?.tags,
            locale: args?.locale ?? preferenceArgs?.locale
        )
    }

    /// Used to get user's whole preferences data.
    /// - Parameters:
    ///   - args: Arguments for the request. Defaults to `nil`.
    public func getPreferences(args: Args? = nil) async -> PreferenceAPIResponse {

        let queryParams: [String: Any?] = [
            "tenant_id": args?.tenantId,
            "show_opt_out_channels": args?.showOptOutChannels ?? true,
            "tags": encodeTags(args?.tags),
            "locale": args?.locale,
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
            "tags": encodeTags(args?.tags),
            "locale": args?.locale,
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
            "locale": args?.locale,
        ]

        let path = getUrlpath(path: "category/\(category)", qp: questionParams)
        return await config.client().request(
            reqData: .init(path: path.absoluteString, payload: nil, type: .get))
    }

    /// Used to get overall channel preferences.
    /// - Parameters:
    ///   - args: Arguments for the request. Only `tenantId` is honoured here;
    ///     other fields on ``Args`` are ignored. Defaults to `nil`.
    public func getOverallChannelPreferences(args: Args? = nil) async -> APIResponse {
        let queryParams: [String: Any?] = [
            "tenant_id": args?.tenantId
        ]
        let path = getUrlpath(path: "channel_preference", qp: queryParams)
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
            "tenant_id": args?.tenantId ?? preferenceArgs?.tenantId,
            "show_opt_out_channels": "\(resolveShowOptOutChannels(args))",
            "tags": encodeTags(args?.tags ?? preferenceArgs?.tags),
            "locale": args?.locale ?? preferenceArgs?.locale,
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

    private func _updateChannelPreferences(
        body: ChannelRequestPayload,
        args: Args? = nil
    ) async -> PreferenceAPIResponse {
        let queryParams: [String: Any?] = [
            "tenant_id": args?.tenantId ?? preferenceArgs?.tenantId
        ]
        let path = getUrlpath(path: "channel_preference", qp: queryParams)

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

        let showOptOutChannels = resolveShowOptOutChannels(args)

        let channels = showOptOutChannels && preference == .optIn ? nil : optOutChannels

        let requestPayload: RequestPayload = .init(
            preference: categoryData.preference,
            optOutChannels: channels
        )

        categoryPreferenceDebouncer.send(
            key: category,
            payload: .init(
                category: category,
                body: requestPayload,
                subCategory: categoryData,
                args: resolvedArgs(args, showOptOutChannels: showOptOutChannels)
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

        let showOptOutChannels = resolveShowOptOutChannels(args)

        let categoryPreference: PreferenceOptions =
            showOptOutChannels && categoryData.preference == .optOut && preference == .optIn
            ? .optIn : categoryData.preference

        let requestPayload = RequestPayload(
            preference: categoryPreference, optOutChannels: optOutChannels)

        categoryPreferenceDebouncer.send(
            key: category,
            payload: .init(
                category: category,
                body: requestPayload,
                subCategory: categoryData,
                args: resolvedArgs(args, showOptOutChannels: showOptOutChannels)
            )
        )

        return .success(body: data)
    }

    /// Used to update overall channel preferences.
    /// - Parameters:
    ///   - channel: The ID of the channel to update. Defaults to `nil`.
    ///   - preference: The new preference value. Defaults to `nil`.
    public func updateOverallChannelPreference(
        channel: String,
        preference: ChannelLevelPreferenceOptions,
        args: Args? = nil
    ) -> PreferenceAPIResponse {

        guard let data else {
            return .error(
                .init(
                    type: .validation,
                    message: "Call getPreferences method before performing action"))
        }

        guard let channelPreferences = data.channelPreferences else {
            return .error(.init(type: .validation, message: "Channel preferences doesn't exist"))
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
            return .error(.init(type: .validation, message: "Channel data not found"))
        }

        if !dataUpdated {
            return .success(body: data)
        }
        
        let requestPayload = ChannelRequestPayload(channelPreferences: [channelData])

        channelPreferenceDebouncer.send(
            key: channelData.channel,
            payload: .init(body: requestPayload, args: args)
        )

        return .success(body: data)
    }
}

/// A per-key debouncer that mirrors the web SDK's `debounceByType`.
///
/// Each unique `key` has its own pending task. A new `send` for the same key
/// cancels the in-flight task and starts a fresh delay so the *latest* payload
/// wins. Sends for different keys are independent and run in parallel — this
/// is the key behavioural difference vs a single `Combine.debounce` upstream,
/// which would drop earlier different-key events when rapid sends arrive
/// inside the debounce window.
final class KeyedDebouncer<Payload>: @unchecked Sendable {
    private let lock = NSLock()
    private var tasks: [String: Task<Void, Never>] = [:]
    private let delayNanoseconds: UInt64

    /// Invoked once per debounced key with the latest payload for that key.
    /// Set after construction so the closure can capture `self` weakly.
    var action: ((Payload) async -> Void)?

    init(delayNanoseconds: UInt64) {
        self.delayNanoseconds = delayNanoseconds
    }

    func send(key: String, payload: Payload) {
        let delay = delayNanoseconds

        lock.lock()
        let actionRef = action
        tasks[key]?.cancel()
        let task = Task {
            do {
                try await Task.sleep(nanoseconds: delay)
            } catch {
                return
            }
            await actionRef?(payload)
        }
        tasks[key] = task
        lock.unlock()
    }

    func cancelAll() {
        lock.lock()
        for task in tasks.values { task.cancel() }
        tasks.removeAll()
        lock.unlock()
    }

    deinit {
        cancelAll()
    }
}
