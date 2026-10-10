import SwiftUI
import Foundation

public enum OverviewDragPayload: Codable, Transferable {
    case window(id: Int)
    case workspace(name: String)

    public static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .json)
    }
}
