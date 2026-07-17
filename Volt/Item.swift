//
//  Item.swift
//  Volt
//
//  Created by Dylan Ironside on 7/17/26.
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
