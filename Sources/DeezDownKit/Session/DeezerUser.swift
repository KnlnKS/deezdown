import Foundation

public struct DeezerUser: Sendable, Codable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var pictureMD5: String
    public var licenseToken: String
    public var canStreamHQ: Bool
    public var canStreamLossless: Bool
    public var country: String
    public var language: String
    public var lovedTracksID: String
    public var offerName: String?

    public var highestAvailableFormat: TrackFormat {
        if canStreamLossless { return .flac }
        if canStreamHQ { return .mp3_320 }
        return .mp3_128
    }

    public func canStream(_ format: TrackFormat) -> Bool {
        if format.requiresLossless { return canStreamLossless }
        if format == .mp3_320 { return canStreamHQ }
        return true
    }

    init(results: JSONValue) {
        let user = results["USER"]
        let options = user["OPTIONS"]
        id = user["USER_ID"].stringValue ?? "0"
        name = user["BLOG_NAME"].stringValue ?? ""
        pictureMD5 = user["USER_PICTURE"].stringValue ?? ""
        licenseToken = options["license_token"].stringValue ?? ""
        canStreamHQ = (options["web_hq"].boolValue ?? false) || (options["mobile_hq"].boolValue ?? false)
        canStreamLossless =
            (options["web_lossless"].boolValue ?? false) || (options["mobile_lossless"].boolValue ?? false)
        country = options["license_country"].stringValue ?? results["COUNTRY"].stringValue ?? ""
        language = user["SETTING"]["global"]["language"].stringValue ?? "en"
        lovedTracksID = user["LOVEDTRACKS_ID"].stringValue ?? ""
        offerName = user["OFFER_NAME"].stringValue
    }
}
