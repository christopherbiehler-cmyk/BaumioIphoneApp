//
//  Item.swift
//  Baumio.
//
//  Created by Christopher Biehler on 28.06.26.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
