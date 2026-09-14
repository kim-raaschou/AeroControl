import SwiftUI
import Foundation

/// What can be dragged inside the overview: a window tile (move it to another
/// workspace) or a workspace badge (merge that workspace into the drop target).
public enum OverviewDragPayload: Codable, Transferable {
    case window(id: Int)
    case workspace(name: String)

    public static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .json)
    }
}
