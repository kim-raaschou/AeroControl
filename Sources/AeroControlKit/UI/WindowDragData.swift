import SwiftUI
import Foundation

public struct WindowDragData: Codable, Transferable {
    public let windowId: Int
    public let appName: String

    public init(windowId: Int, appName: String) {
        self.windowId = windowId
        self.appName = appName
    }

    public static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .json)
    }
}
