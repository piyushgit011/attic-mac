import Foundation

enum SourceSort: String, CaseIterable { case files = "Most files", size = "Largest", recent = "Most recent", name = "Name" }
enum CardSort: String, CaseIterable { case size = "Size", count = "Items", name = "Name" }
enum DupeSort: String, CaseIterable { case reclaim = "Space to free", copies = "Copies", size = "File size", name = "Name" }
enum JunkSort: String, CaseIterable { case size = "Size", lastUsed = "Last touched", name = "Name" }
enum AppSort: String, CaseIterable { case memory = "Memory", processes = "Processes", name = "Name" }
