import Cocoa
import SwiftUI
import Combine

// MARK: - Localization Helper

func localize(zh: String, en: String) -> String {
    if let lang = Locale.preferredLanguages.first, lang.hasPrefix("zh") {
        return zh
    }
    return en
}

// MARK: - Models

struct DeveloperCategory: Identifiable {
    enum CategoryType: String, CaseIterable, Identifiable {
        case simulators = "Simulators"
        case derivedData = "DerivedData"
        case deviceSupport = "Device Support"
        case archives = "Archives"
        case previews = "SwiftUI Previews"
        case caches = "Caches"
        
        var id: String { self.rawValue }
    }
    
    let id: CategoryType
    
    var name: String {
        switch id {
        case .simulators: return localize(zh: "模拟器", en: "Simulators")
        case .derivedData: return localize(zh: "DerivedData 编译缓存", en: "DerivedData")
        case .deviceSupport: return localize(zh: "Device Support 真机支持", en: "Device Support")
        case .archives: return localize(zh: "Archives 打包归档", en: "Archives")
        case .previews: return localize(zh: "SwiftUI Previews 预览缓存", en: "SwiftUI Previews")
        case .caches: return localize(zh: "Caches 系统缓存", en: "Caches")
        }
    }
    
    var size: Int64
    var itemsCount: Int
    var systemIcon: String {
        switch id {
        case .simulators: return "phone.ipad.and.iphone"
        case .derivedData: return "folder.badge.gearshape"
        case .deviceSupport: return "cpu"
        case .archives: return "archivebox"
        case .previews: return "eye.square"
        case .caches: return "trash"
        }
    }
    
    var description: String {
        switch id {
        case .simulators: return localize(zh: "模拟器中安装应用的数据及沙盒，清理后可自动重建。", en: "Sandbox and application data installed in simulators. Auto-rebuilt upon running.")
        case .derivedData: return localize(zh: "项目的编译缓存和索引，删除后下次编译速度会稍慢，但完全安全。", en: "Project build caches and indexes. Safe to delete; rebuilds on next compilation.")
        case .deviceSupport: return localize(zh: "真机调试的设备支持文件，旧版本的 iOS 真机调试文件可以安全清理。", en: "Device symbols for on-device debugging. Old OS versions are safe to clean.")
        case .archives: return localize(zh: "打包的归档历史（.xcarchive），包含发布包和调试符号，如已发布可清理旧归档。", en: "Bundled build archives (.xcarchive) with debug symbols. Clean old builds if published.")
        case .previews: return localize(zh: "SwiftUI 实时预览缓存，可安全删除，预览时会自动重新生成。", en: "SwiftUI canvas preview cache. Safe to delete; rebuilds automatically when previewing.")
        case .caches: return localize(zh: "Xcode 自身的运行缓存，可以安全清理以释放空间。", en: "Xcode local operational caches. Clean safely to release disk space.")
        }
    }
}

struct CleanableItem: Identifiable, Hashable {
    enum ItemType: Hashable {
        case derivedData
        case archive
        case deviceSupport
        case simulator(udid: String, runtime: String, model: String, isAvailable: Bool)
        case preview
        case cache
    }
    
    let id: String // Path or UUID
    let name: String
    let path: String
    let size: Int64
    let modificationDate: Date
    let type: ItemType
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: CleanableItem, rhs: CleanableItem) -> Bool {
        return lhs.id == rhs.id
    }
}

// MARK: - Scanner Helper

class XcodeScanner {
    static let shared = XcodeScanner()
    
    private init() {}
    
    func getDirectorySize(url: URL) -> Int64 {
        var size: Int64 = 0
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
            options: [.skipsHiddenFiles],
            errorHandler: nil
        ) else { return 0 }
        
        for case let fileURL as URL in enumerator {
            do {
                let resourceValues = try fileURL.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
                if let isDirectory = resourceValues.isDirectory, !isDirectory {
                    if let fileSize = resourceValues.fileSize {
                        size += Int64(fileSize)
                    }
                }
            } catch {
                continue
            }
        }
        return size
    }
    
    func getSimctlStatus() -> [String: Bool] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["simctl", "list", "devices", "-j"]
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        do {
            try process.run()
            let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let devices = json["devices"] as? [String: [[String: Any]]] {
                var result: [String: Bool] = [:]
                for (_, deviceList) in devices {
                    for dev in deviceList {
                        if let udid = dev["udid"] as? String,
                           let isAvailable = dev["isAvailable"] as? Bool {
                            result[udid] = isAvailable
                        }
                    }
                }
                return result
            }
        } catch {
            // ignore
        }
        return [:]
    }
    
    func deleteSimulator(udid: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["simctl", "delete", udid]
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
    
    func deleteUnavailableSimulators() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["simctl", "delete", "unavailable"]
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}

// MARK: - Main Controller

class CleanerController: ObservableObject {
    @Published var categories: [DeveloperCategory] = []
    @Published var items: [CleanableItem] = []
    @Published var selectedCategoryId: DeveloperCategory.CategoryType? = .simulators
    @Published var isScanning = false
    @Published var isDeleting = false
    @Published var scanStatusText = ""
    @Published var scanProgress: Double = 0.0
    @Published var isPermissionDenied = false
    
    // 多选
    @Published var selectedItemIds = Set<String>()
    
    // 筛选条件
    @Published var searchText = ""
    @Published var timeFilter: TimeFilter = .all
    @Published var sizeFilter: SizeFilter = .all
    
    // 排序
    @Published var sortBy: SortOption = .sizeDescending
    
    // 模拟器筛选
    @Published var simTypeFilter = Set<String>()
    @Published var simRuntimeFilter = Set<String>()
    @Published var simModelFilter = Set<String>()
    @Published var simAvailabilityFilter: AvailabilityFilter = .all
    
    enum TimeFilter: String, CaseIterable, Identifiable {
        case all = "all"
        case over30Days = "30days"
        case over90Days = "90days"
        
        var id: String { self.rawValue }
        
        var displayName: String {
            switch self {
            case .all: return localize(zh: "所有时间", en: "All Time")
            case .over30Days: return localize(zh: "超过 30 天未修改", en: "> 30 Days Idle")
            case .over90Days: return localize(zh: "超过 90 天未修改", en: "> 90 Days Idle")
            }
        }
    }
    
    enum SizeFilter: String, CaseIterable, Identifiable {
        case all = "all"
        case over100M = "100M"
        case over500M = "500M"
        case over1G = "1G"
        case over5G = "5G"
        
        var id: String { self.rawValue }
        
        var displayName: String {
            switch self {
            case .all: return localize(zh: "所有大小", en: "All Sizes")
            case .over100M: return "> 100 MB"
            case .over500M: return "> 500 MB"
            case .over1G: return "> 1 GB"
            case .over5G: return "> 5 GB"
            }
        }
    }
    
    enum AvailabilityFilter: String, CaseIterable, Identifiable {
        case all = "all"
        case onlyAvailable = "available"
        case onlyUnavailable = "unavailable"
        
        var id: String { self.rawValue }
        
        var displayName: String {
            switch self {
            case .all: return localize(zh: "所有可用性", en: "All Availability")
            case .onlyAvailable: return localize(zh: "仅正常可用", en: "Only Available")
            case .onlyUnavailable: return localize(zh: "仅不可用 (建议清理)", en: "Only Unavailable (Recommended)")
            }
        }
    }
    
    enum SortOption: String, CaseIterable, Identifiable {
        case sizeDescending = "sizeDesc"
        case sizeAscending = "sizeAsc"
        case dateDescending = "dateDesc"
        case dateAscending = "dateAsc"
        
        var id: String { self.rawValue }
        
        var displayName: String {
            switch self {
            case .sizeDescending: return localize(zh: "大小 (从大到小)", en: "Size (Descending)")
            case .sizeAscending: return localize(zh: "大小 (从小到大)", en: "Size (Ascending)")
            case .dateDescending: return localize(zh: "最近修改 (最新优先)", en: "Date (Newest First)")
            case .dateAscending: return localize(zh: "最近修改 (最旧优先)", en: "Date (Oldest First)")
            }
        }
    }
    
    private var allScannedItems: [CleanableItem] = []
    
    init() {
        resetCategories()
    }
    
    func resetCategories() {
        categories = DeveloperCategory.CategoryType.allCases.map {
            DeveloperCategory(id: $0, size: 0, itemsCount: 0)
        }
    }
    
    // 筛选与排序引擎
    var filteredItems: [CleanableItem] {
        guard let activeCategory = selectedCategoryId else { return [] }
        
        var result = allScannedItems.filter { item in
            switch (activeCategory, item.type) {
            case (.simulators, .simulator): return true
            case (.derivedData, .derivedData): return true
            case (.deviceSupport, .deviceSupport): return true
            case (.archives, .archive): return true
            case (.previews, .preview): return true
            case (.caches, .cache): return true
            default: return false
            }
        }
        
        if !searchText.isEmpty {
            result = result.filter { $0.name.localizedCaseInsensitiveContains(searchText) || $0.path.localizedCaseInsensitiveContains(searchText) }
        }
        
        let now = Date()
        result = result.filter { item in
            switch timeFilter {
            case .all:
                return true
            case .over30Days:
                let diff = now.timeIntervalSince(item.modificationDate)
                return diff > 30 * 24 * 3600
            case .over90Days:
                let diff = now.timeIntervalSince(item.modificationDate)
                return diff > 90 * 24 * 3600
            }
        }
        
        result = result.filter { item in
            switch sizeFilter {
            case .all:
                return true
            case .over100M:
                return item.size > 100 * 1024 * 1024
            case .over500M:
                return item.size > 500 * 1024 * 1024
            case .over1G:
                return item.size > 1 * 1024 * 1024 * 1024
            case .over5G:
                return item.size > 5 * 1024 * 1024 * 1024
            }
        }
        
        if activeCategory == .simulators {
            result = result.filter { item in
                guard case let .simulator(_, runtime, model, isAvailable) = item.type else { return false }
                
                if !simModelFilter.isEmpty {
                    var modelMatched = false
                    for filterModel in simModelFilter {
                        if model.localizedCaseInsensitiveContains(filterModel) {
                            modelMatched = true
                            break
                        }
                    }
                    if !modelMatched { return false }
                }
                
                if !simRuntimeFilter.isEmpty {
                    if !simRuntimeFilter.contains(runtime) { return false }
                }
                
                switch simAvailabilityFilter {
                case .all:
                    break
                case .onlyAvailable:
                    if !isAvailable { return false }
                case .onlyUnavailable:
                    if isAvailable { return false }
                }
                
                return true
            }
        }
        
        switch sortBy {
        case .sizeDescending:
            result.sort { $0.size > $1.size }
        case .sizeAscending:
            result.sort { $0.size < $1.size }
        case .dateDescending:
            result.sort { $0.modificationDate > $1.modificationDate }
        case .dateAscending:
            result.sort { $0.modificationDate < $1.modificationDate }
        }
        
        return result
    }
    
    var allUniqueSimModels: [String] {
        let models = allScannedItems.compactMap { item -> String? in
            if case let .simulator(_, _, model, _) = item.type {
                if model.contains("iPhone") { return "iPhone" }
                if model.contains("iPad") { return "iPad" }
                if model.contains("Watch") { return "Apple Watch" }
                if model.contains("TV") { return "Apple TV" }
                if model.contains("Vision") { return "Apple Vision" }
                return model
            }
            return nil
        }
        return Array(Set(models)).sorted()
    }
    
    var allUniqueSimRuntimes: [String] {
        let runtimes = allScannedItems.compactMap { item -> String? in
            if case let .simulator(_, runtime, _, _) = item.type {
                return runtime
            }
            return nil
        }
        return Array(Set(runtimes)).sorted()
    }
    
    func startScan() {
        guard !isScanning else { return }
        isScanning = true
        scanProgress = 0.0
        scanStatusText = localize(zh: "正在扫描 Xcode 缓存目录...", en: "Scanning Xcode developer directories...")
        selectedItemIds.removeAll()
        allScannedItems.removeAll()
        isPermissionDenied = false
        
        let fileManager = FileManager.default
        let home = NSHomeDirectory()
        
        let derivedDataPath = "\(home)/Library/Developer/Xcode/DerivedData"
        let archivesPath = "\(home)/Library/Developer/Xcode/Archives"
        let deviceSupportPath = "\(home)/Library/Developer/Xcode/iOS DeviceSupport"
        let simulatorsPath = "\(home)/Library/Developer/CoreSimulator/Devices"
        let previewsPath = "\(home)/Library/Developer/Xcode/UserData/Previews"
        let cachesPath = "\(home)/Library/Caches/com.apple.dt.Xcode"
        
        Task.detached(priority: .userInitiated) {
            var scanned: [CleanableItem] = []
            var permissionDenied = false
            
            func safeContents(of path: String) -> [URL] {
                do {
                    return try fileManager.contentsOfDirectory(at: URL(fileURLWithPath: path), includingPropertiesForKeys: [.contentModificationDateKey], options: .skipsHiddenFiles)
                } catch {
                    let nsError = error as NSError
                    if nsError.domain == NSCocoaErrorDomain && (nsError.code == 257 || nsError.code == 513) {
                        permissionDenied = true
                    }
                    return []
                }
            }
            
            // 1. DerivedData
            let statusDD = localize(zh: "正在计算 DerivedData 编译缓存...", en: "Calculating DerivedData build caches...")
            await MainActor.run {
                self.scanStatusText = statusDD
                self.scanProgress = 0.1
            }
            let ddUrls = safeContents(of: derivedDataPath)
            for url in ddUrls {
                let size = XcodeScanner.shared.getDirectorySize(url: url)
                let attrs = try? fileManager.attributesOfItem(atPath: url.path)
                let modDate = attrs?[.modificationDate] as? Date ?? Date()
                scanned.append(CleanableItem(
                    id: url.path,
                    name: url.lastPathComponent,
                    path: url.path,
                    size: size,
                    modificationDate: modDate,
                    type: .derivedData
                ))
            }
            
            // 2. Archives
            let statusArch = localize(zh: "正在扫描 Archives 归档包...", en: "Scanning Archives build backups...")
            await MainActor.run {
                self.scanStatusText = statusArch
                self.scanProgress = 0.3
            }
            let dateFolders = safeContents(of: archivesPath)
            for folder in dateFolders {
                let archives = safeContents(of: folder.path)
                for archive in archives {
                    if archive.pathExtension == "xcarchive" {
                        let size = XcodeScanner.shared.getDirectorySize(url: archive)
                        let attrs = try? fileManager.attributesOfItem(atPath: archive.path)
                        let modDate = attrs?[.modificationDate] as? Date ?? Date()
                        scanned.append(CleanableItem(
                            id: archive.path,
                            name: archive.lastPathComponent,
                            path: archive.path,
                            size: size,
                            modificationDate: modDate,
                            type: .archive
                        ))
                    }
                }
            }
            
            // 3. DeviceSupport
            let statusDev = localize(zh: "正在扫描 DeviceSupport 真机调试包...", en: "Scanning iOS DeviceSupport symbols...")
            await MainActor.run {
                self.scanStatusText = statusDev
                self.scanProgress = 0.5
            }
            let dsUrls = safeContents(of: deviceSupportPath)
            for url in dsUrls {
                let size = XcodeScanner.shared.getDirectorySize(url: url)
                let attrs = try? fileManager.attributesOfItem(atPath: url.path)
                let modDate = attrs?[.modificationDate] as? Date ?? Date()
                scanned.append(CleanableItem(
                    id: url.path,
                    name: url.lastPathComponent,
                    path: url.path,
                    size: size,
                    modificationDate: modDate,
                    type: .deviceSupport
                ))
            }
            
            // 4. Previews
            let statusPr = localize(zh: "正在扫描 SwiftUI 实时预览缓存...", en: "Scanning SwiftUI canvas preview caches...")
            await MainActor.run {
                self.scanStatusText = statusPr
                self.scanProgress = 0.6
            }
            let prUrls = safeContents(of: previewsPath)
            for url in prUrls {
                let size = XcodeScanner.shared.getDirectorySize(url: url)
                let attrs = try? fileManager.attributesOfItem(atPath: url.path)
                let modDate = attrs?[.modificationDate] as? Date ?? Date()
                scanned.append(CleanableItem(
                    id: url.path,
                    name: url.lastPathComponent,
                    path: url.path,
                    size: size,
                    modificationDate: modDate,
                    type: .preview
                ))
            }
            
            // 5. Caches
            let statusCch = localize(zh: "正在扫描 Caches 运行缓存...", en: "Scanning Xcode local caches...")
            await MainActor.run {
                self.scanStatusText = statusCch
                self.scanProgress = 0.7
            }
            let cchUrls = safeContents(of: cachesPath)
            for url in cchUrls {
                let size = XcodeScanner.shared.getDirectorySize(url: url)
                let attrs = try? fileManager.attributesOfItem(atPath: url.path)
                let modDate = attrs?[.modificationDate] as? Date ?? Date()
                scanned.append(CleanableItem(
                    id: url.path,
                    name: url.lastPathComponent,
                    path: url.path,
                    size: size,
                    modificationDate: modDate,
                    type: .cache
                ))
            }
            
            // 6. Simulators
            let statusSimPrep = localize(zh: "正在解析模拟器元数据并拉取 simctl 可用状态...", en: "Parsing simulator plist and fetching simctl availability...")
            await MainActor.run {
                self.scanStatusText = statusSimPrep
                self.scanProgress = 0.8
            }
            let simctlStatus = XcodeScanner.shared.getSimctlStatus()
            
            let simUrls = safeContents(of: simulatorsPath)
            let totalSims = simUrls.count
            for (index, url) in simUrls.enumerated() {
                let udid = url.lastPathComponent
                if udid.contains("-") && udid.count >= 32 {
                    let plistPath = url.appendingPathComponent("device.plist").path
                    if fileManager.fileExists(atPath: plistPath) {
                        let plistURL = URL(fileURLWithPath: plistPath)
                        var name = "未知模拟器"
                        var runtime = "未知系统"
                        if let plistData = try? Data(contentsOf: plistURL),
                           let plist = try? PropertyListSerialization.propertyList(from: plistData, options: [], format: nil) as? [String: Any] {
                            name = plist["name"] as? String ?? name
                            if let rawRuntime = plist["runtime"] as? String {
                                var r = rawRuntime.replacingOccurrences(of: "com.apple.CoreSimulator.SimRuntime.", with: "")
                                r = r.replacingOccurrences(of: "iOS-", with: "iOS ")
                                r = r.replacingOccurrences(of: "watchOS-", with: "watchOS ")
                                r = r.replacingOccurrences(of: "tvOS-", with: "tvOS ")
                                r = r.replacingOccurrences(of: "xrOS-", with: "visionOS ")
                                runtime = r.replacingOccurrences(of: "-", with: ".")
                            }
                        }
                        
                        let tempName = name
                        let tempRuntime = runtime
                        let statusTextFormat = localize(
                            zh: "正在计算模拟器大小 (\(index + 1)/\(totalSims)): \(tempName)...",
                            en: "Calculating Simulator Size (\(index + 1)/\(totalSims)): \(tempName)..."
                        )
                        
                        await MainActor.run {
                            self.scanStatusText = statusTextFormat
                            self.scanProgress = 0.8 + (Double(index + 1) / Double(totalSims)) * 0.19
                        }
                        
                        let size = XcodeScanner.shared.getDirectorySize(url: url)
                        let attrs = try? fileManager.attributesOfItem(atPath: url.path)
                        let modDate = attrs?[.modificationDate] as? Date ?? Date()
                        
                        let isAvailable = simctlStatus[udid] ?? true
                        
                        scanned.append(CleanableItem(
                            id: udid,
                            name: tempName,
                            path: url.path,
                            size: size,
                            modificationDate: modDate,
                            type: .simulator(udid: udid, runtime: tempRuntime, model: tempName, isAvailable: isAvailable)
                        ))
                    }
                }
            }
            
            let finalScanned = scanned
            let finalPermission = permissionDenied
            let finishText = localize(zh: "扫描完成！", en: "Scan Completed!")
            await MainActor.run {
                self.allScannedItems = finalScanned
                self.isPermissionDenied = finalPermission
                self.updateCategoryTotals()
                self.isScanning = false
                self.scanProgress = 1.0
                self.scanStatusText = finishText
            }
        }
    }
    
    private func updateCategoryTotals() {
        categories = categories.map { category in
            let catItems = allScannedItems.filter { item in
                switch (category.id, item.type) {
                case (.simulators, .simulator): return true
                case (.derivedData, .derivedData): return true
                case (.deviceSupport, .deviceSupport): return true
                case (.archives, .archive): return true
                case (.previews, .preview): return true
                case (.caches, .cache): return true
                default: return false
                }
            }
            let totalSize = catItems.reduce(0) { $0 + $1.size }
            return DeveloperCategory(id: category.id, size: totalSize, itemsCount: catItems.count)
        }
    }
    
    func cleanUnavailableSimulators() {
        guard !isDeleting else { return }
        isDeleting = true
        scanStatusText = localize(zh: "正在一键清理已失效/不可用的模拟器...", en: "Cleaning up all unavailable simulators...")
        
        Task.detached(priority: .userInitiated) {
            let _ = XcodeScanner.shared.deleteUnavailableSimulators()
            await MainActor.run {
                self.isDeleting = false
                self.startScan()
            }
        }
    }
    
    func deleteSelectedItems() {
        guard !isDeleting && !selectedItemIds.isEmpty else { return }
        isDeleting = true
        scanStatusText = localize(zh: "正在删除选中项目，这需要一些时间...", en: "Deleting selected items, please wait...")
        
        let idsToDelete = selectedItemIds
        let fileManager = FileManager.default
        
        Task.detached(priority: .userInitiated) {
            for id in idsToDelete {
                if let item = self.allScannedItems.first(where: { $0.id == id }) {
                    switch item.type {
                    case .simulator(let udid, _, _, _):
                        let success = XcodeScanner.shared.deleteSimulator(udid: udid)
                        if !success {
                            try? fileManager.removeItem(atPath: item.path)
                        }
                    default:
                        try? fileManager.removeItem(atPath: item.path)
                    }
                }
            }
            
            await MainActor.run {
                self.isDeleting = false
                self.selectedItemIds.removeAll()
                self.startScan()
            }
        }
    }
    
    func deleteSingleItem(_ item: CleanableItem) {
        guard !isDeleting else { return }
        isDeleting = true
        
        let statusStr = localize(zh: "正在删除 \(item.name)...", en: "Deleting \(item.name)...")
        scanStatusText = statusStr
        let fileManager = FileManager.default
        
        Task.detached(priority: .userInitiated) {
            switch item.type {
            case .simulator(let udid, _, _, _):
                let success = XcodeScanner.shared.deleteSimulator(udid: udid)
                if !success {
                    try? fileManager.removeItem(atPath: item.path)
                }
            default:
                try? fileManager.removeItem(atPath: item.path)
            }
            
            await MainActor.run {
                self.isDeleting = false
                self.startScan()
            }
        }
    }
    
    static func formatSize(_ bytes: Int64) -> String {
        if bytes == 0 { return "0 B" }
        let units = ["B", "KB", "MB", "GB", "TB"]
        var index = 0
        var doubleValue = Double(bytes)
        while doubleValue >= 1024 && index < units.count - 1 {
            doubleValue /= 1024
            index += 1
        }
        return String(format: "%.1f %@", doubleValue, units[index])
    }
}

// MARK: - Views

struct SidebarView: View {
    @ObservedObject var controller: CleanerController
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Xcode Cleaner")
                .font(.title2)
                .bold()
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, 10)
                .foregroundColor(.primary)
            
            List(selection: $controller.selectedCategoryId) {
                Section(header: Text(localize(zh: "缓存类别", en: "Developer Categories"))) {
                    ForEach(controller.categories) { category in
                        NavigationLink(value: category.id) {
                            HStack {
                                Image(systemName: category.systemIcon)
                                    .foregroundColor(.accentColor)
                                    .frame(width: 24, height: 24)
                                    .font(.system(size: 14, weight: .semibold))
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(category.name)
                                        .font(.body)
                                        .fontWeight(.medium)
                                    Text(localize(zh: "\(category.itemsCount) 个项目", en: "\(category.itemsCount) items"))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                Text(CleanerController.formatSize(category.size))
                                    .font(.caption)
                                    .bold()
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(
                                        Capsule()
                                            .fill(category.size > 1 * 1024 * 1024 * 1024 ? Color.red.opacity(0.15) : Color.gray.opacity(0.15))
                                    )
                                    .foregroundColor(category.size > 1 * 1024 * 1024 * 1024 ? .red : .secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .listStyle(SidebarListStyle())
            
            Spacer()
            
            Button(action: {
                controller.startScan()
            }) {
                HStack {
                    if controller.isScanning {
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 16, height: 16)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                    Text(controller.isScanning ? localize(zh: "正在扫描...", en: "Scanning...") : localize(zh: "重新扫描", en: "Rescan"))
                        .bold()
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .disabled(controller.isScanning || controller.isDeleting)
            .padding(16)
        }
        .frame(minWidth: 240, idealWidth: 260)
    }
}

struct TopFilterView: View {
    @ObservedObject var controller: CleanerController
    @State private var showSimFilterPopover = false
    
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 16) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField(localize(zh: "搜索名称或路径...", en: "Search name or path..."), text: $controller.searchText)
                        .textFieldStyle(PlainTextFieldStyle())
                    if !controller.searchText.isEmpty {
                        Button(action: { controller.searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.controlBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.2), lineWidth: 1))
                .frame(maxWidth: 300)
                
                Picker("", selection: $controller.timeFilter) {
                    ForEach(CleanerController.TimeFilter.allCases) { filter in
                        Text(filter.displayName).tag(filter)
                    }
                }
                .frame(width: 160)
                
                Picker("", selection: $controller.sizeFilter) {
                    ForEach(CleanerController.SizeFilter.allCases) { filter in
                        Text(filter.displayName).tag(filter)
                    }
                }
                .frame(width: 120)
                
                if controller.selectedCategoryId == .simulators {
                    Button(action: { showSimFilterPopover.toggle() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "slider.horizontal.3")
                            Text(localize(zh: "型号与系统筛选", en: "Models & OS"))
                            if !controller.simModelFilter.isEmpty || !controller.simRuntimeFilter.isEmpty || controller.simAvailabilityFilter != .all {
                                Circle()
                                    .fill(Color.accentColor)
                                    .frame(width: 6, height: 6)
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                    .popover(isPresented: $showSimFilterPopover, arrowEdge: .bottom) {
                        SimulatorFilterPopover(controller: controller)
                    }
                }
                
                Spacer()
                
                Picker(localize(zh: "排序:", en: "Sort:"), selection: $controller.sortBy) {
                    ForEach(CleanerController.SortOption.allCases) { opt in
                        Text(opt.displayName).tag(opt)
                    }
                }
                .frame(width: 220)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            
            Divider()
        }
    }
}

struct SimulatorFilterPopover: View {
    @ObservedObject var controller: CleanerController
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(localize(zh: "设备型号:", en: "Device Model:"))
                        .font(.headline)
                    
                    if controller.allUniqueSimModels.isEmpty {
                        Text(localize(zh: "无可用型号", en: "No available models")).foregroundColor(.secondary).font(.caption)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 90, maximum: 160), spacing: 8)], alignment: .leading, spacing: 8) {
                            ForEach(controller.allUniqueSimModels, id: \.self) { model in
                                FilterTag(
                                    text: model,
                                    isSelected: controller.simModelFilter.contains(model),
                                    action: {
                                        if controller.simModelFilter.contains(model) {
                                            controller.simModelFilter.remove(model)
                                        } else {
                                            controller.simModelFilter.insert(model)
                                        }
                                    }
                                )
                            }
                        }
                    }
                }
                
                Divider()
                
                VStack(alignment: .leading, spacing: 8) {
                    Text(localize(zh: "系统版本:", en: "OS Version:"))
                        .font(.headline)
                    
                    if controller.allUniqueSimRuntimes.isEmpty {
                        Text(localize(zh: "无可用系统", en: "No available OS")).foregroundColor(.secondary).font(.caption)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 90, maximum: 160), spacing: 8)], alignment: .leading, spacing: 8) {
                            ForEach(controller.allUniqueSimRuntimes, id: \.self) { runtime in
                                FilterTag(
                                    text: runtime,
                                    isSelected: controller.simRuntimeFilter.contains(runtime),
                                    action: {
                                        if controller.simRuntimeFilter.contains(runtime) {
                                            controller.simRuntimeFilter.remove(runtime)
                                        } else {
                                            controller.simRuntimeFilter.insert(runtime)
                                        }
                                    }
                                )
                            }
                        }
                    }
                }
                
                Divider()
                
                VStack(alignment: .leading, spacing: 8) {
                    Text(localize(zh: "可用性状态:", en: "Availability Status:"))
                        .font(.headline)
                    
                    Picker("", selection: $controller.simAvailabilityFilter) {
                        ForEach(CleanerController.AvailabilityFilter.allCases) { filter in
                            Text(filter.displayName).tag(filter)
                        }
                    }
                    .pickerStyle(RadioGroupPickerStyle())
                }
                
                Divider()
                
                Button(localize(zh: "重置所有筛选项", en: "Reset All Filters")) {
                    controller.simModelFilter.removeAll()
                    controller.simRuntimeFilter.removeAll()
                    controller.simAvailabilityFilter = .all
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(16)
            .frame(width: 380)
        }
        .frame(maxHeight: 450)
    }
}

struct FilterTag: View {
    let text: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.caption)
                .fontWeight(.medium)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isSelected ? Color.accentColor : Color.gray.opacity(0.15))
                )
                .foregroundColor(isSelected ? .white : .primary)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct DetailListView: View {
    @ObservedObject var controller: CleanerController
    @State private var itemToDelete: CleanableItem? = nil
    @State private var showDeleteConfirmAlert = false
    
    var body: some View {
        VStack(spacing: 0) {
            if controller.isPermissionDenied {
                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.shield.fill")
                        .foregroundColor(.red)
                        .font(.title3)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(localize(
                            zh: "权限不足：需要完全磁盘访问权限 (Full Disk Access Required)",
                            en: "Permission Denied: Full Disk Access Required"
                        ))
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                        
                        Text(localize(
                            zh: "由于 macOS 系统的安全隐私限制，独立的桌面应用需要获得授权才能扫描 ~/Library 下的 Xcode 缓存。请在系统设置中为 XcodeCleaner 勾选‘完全磁盘访问权限’，然后重新扫描。",
                            en: "Due to macOS security restrictions, independent apps need Full Disk Access to scan Xcode cache directories. Please enable 'Full Disk Access' for XcodeCleaner in System Settings and click Rescan."
                        ))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                            NSWorkspace.shared.open(url)
                        }
                    }) {
                        Text(localize(zh: "去系统设置授权", en: "Grant Permission"))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.red.opacity(0.08)))
                .padding(.horizontal, 16)
                .padding(.top, 10)
            }

            if let activeCategory = controller.selectedCategoryId,
               let category = controller.categories.first(where: { $0.id == activeCategory }) {
                HStack(spacing: 12) {
                    Image(systemName: "info.circle")
                        .foregroundColor(.accentColor)
                        .font(.title3)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(category.description)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    if activeCategory == .simulators {
                        Button(action: {
                            controller.cleanUnavailableSimulators()
                        }) {
                            HStack {
                                Image(systemName: "bolt.fill")
                                Text(localize(zh: "清理不可用设备", en: "Clean Unavailable"))
                            }
                        }
                        .buttonStyle(.bordered)
                        .tint(.orange)
                        .help(localize(zh: "自动清理所有由于 Xcode 更新导致不可用的模拟器。", en: "Remove all outdated and unavailable simulator profiles automatically."))
                    }
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.08)))
                .padding(.horizontal, 16)
                .padding(.top, 10)
            }
            
            HStack {
                Button(action: {
                    let visibleIds = controller.filteredItems.map { $0.id }
                    let allSelected = visibleIds.allSatisfy { controller.selectedItemIds.contains($0) }
                    if allSelected {
                        visibleIds.forEach { controller.selectedItemIds.remove($0) }
                    } else {
                        visibleIds.forEach { controller.selectedItemIds.insert($0) }
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: isAllVisibleItemsSelected ? "checkmark.square.fill" : "square")
                            .foregroundColor(isAllVisibleItemsSelected ? .accentColor : .secondary)
                        Text(localize(zh: "全选/取消全选", en: "Select / Deselect All"))
                    }
                }
                .buttonStyle(PlainButtonStyle())
                .font(.subheadline)
                
                Spacer()
                
                Text(localize(
                    zh: "共过滤出 \(controller.filteredItems.count) 项，共 \(CleanerController.formatSize(totalFilteredSize))",
                    en: "Filtered: \(controller.filteredItems.count) items, Size: \(CleanerController.formatSize(totalFilteredSize))"
                ))
                .font(.caption)
                .foregroundColor(.secondary)
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 6)
            
            if controller.filteredItems.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "tray")
                        .font(.system(size: 48))
                        .foregroundColor(.gray.opacity(0.5))
                    Text(localize(zh: "没有找到符合筛选条件的缓存项目", en: "No matching cache items found"))
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(controller.filteredItems) { item in
                        HStack(spacing: 12) {
                            Toggle("", isOn: Binding(
                                get: { controller.selectedItemIds.contains(item.id) },
                                set: { selected in
                                    if selected {
                                        controller.selectedItemIds.insert(item.id)
                                    } else {
                                        controller.selectedItemIds.remove(item.id)
                                    }
                                }
                            ))
                            .toggleStyle(CheckboxToggleStyle())
                            
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Text(item.name)
                                        .font(.body)
                                        .fontWeight(.semibold)
                                    
                                    if case let .simulator(_, runtime, _, isAvailable) = item.type {
                                        Text(runtime)
                                            .font(.system(size: 10, weight: .medium))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 1)
                                            .background(Capsule().fill(Color.gray.opacity(0.15)))
                                            .foregroundColor(.secondary)
                                        
                                        if !isAvailable {
                                            Text(localize(zh: "不可用", en: "Unavailable"))
                                                .font(.system(size: 10, weight: .bold))
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 1)
                                                .background(Capsule().fill(Color.orange.opacity(0.15)))
                                                .foregroundColor(.orange)
                                        }
                                    }
                                }
                                
                                Text(item.path)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .help(item.path)
                            }
                            
                            Spacer()
                            
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(localize(zh: "修改时间", en: "Date Modified"))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(formatDate(item.modificationDate))
                                    .font(.caption)
                                    .foregroundColor(.primary)
                            }
                            .frame(width: 140, alignment: .trailing)
                            
                            Text(CleanerController.formatSize(item.size))
                                .font(.body)
                                .fontWeight(.bold)
                                .frame(width: 90, alignment: .trailing)
                                .foregroundColor(item.size > 500 * 1024 * 1024 ? .red : .primary)
                            
                            HStack(spacing: 8) {
                                Button(action: {
                                    NSWorkspace.shared.selectFile(item.path, inFileViewerRootedAtPath: "")
                                }) {
                                    Image(systemName: "magnifyingglass")
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(PlainButtonStyle())
                                .help(localize(zh: "在 Finder 中显示", en: "Reveal in Finder"))
                                
                                Button(action: {
                                    itemToDelete = item
                                    showDeleteConfirmAlert = true
                                }) {
                                    Image(systemName: "trash")
                                        .foregroundColor(.red.opacity(0.8))
                                }
                                .buttonStyle(PlainButtonStyle())
                                .help(localize(zh: "直接删除该项目", en: "Delete this item permanently"))
                            }
                            .padding(.leading, 8)
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(controller.selectedItemIds.contains(item.id) ? Color.accentColor.opacity(0.05) : Color.clear)
                        )
                        Divider()
                    }
                }
                .listStyle(PlainListStyle())
            }
            
            if !controller.selectedItemIds.isEmpty {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text(localize(zh: "已选择 \(controller.selectedItemIds.count) 个项目，将释放 ", en: "Selected \(controller.selectedItemIds.count) items, will free up "))
                        .font(.body)
                    Text(CleanerController.formatSize(totalSelectedSize))
                        .font(.body)
                        .bold()
                        .foregroundColor(.red)
                    
                    Spacer()
                    
                    Button(action: {
                        itemToDelete = nil
                        showDeleteConfirmAlert = true
                    }) {
                        HStack {
                            Image(systemName: "trash.fill")
                            Text(localize(zh: "删除所选项目", en: "Delete Selected"))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
                .padding(16)
                .background(Color(NSColor.windowBackgroundColor))
                .border(Color.gray.opacity(0.15), width: 1)
            }
        }
        .alert(isPresented: $showDeleteConfirmAlert) {
            if let item = itemToDelete {
                return Alert(
                    title: Text(localize(zh: "确认删除单个项目", en: "Confirm Deletion")),
                    message: Text(localize(zh: "您确定要永久删除 \(item.name) 吗？此操作无法撤销。", en: "Are you sure you want to permanently delete \(item.name)? This action cannot be undone.")),
                    primaryButton: .destructive(Text(localize(zh: "确认删除", en: "Delete"))) {
                        controller.deleteSingleItem(item)
                    },
                    secondaryButton: .cancel(Text(localize(zh: "取消", en: "Cancel")))
                )
            } else {
                return Alert(
                    title: Text(localize(zh: "确认批量删除项目", en: "Confirm Bulk Deletion")),
                    message: Text(localize(
                        zh: "您确定要永久删除选中的 \(controller.selectedItemIds.count) 个项目吗？共将释放 \(CleanerController.formatSize(totalSelectedSize))。此操作无法撤销。",
                        en: "Are you sure you want to permanently delete the selected \(controller.selectedItemIds.count) items? This will free up \(CleanerController.formatSize(totalSelectedSize)). This action cannot be undone."
                    )),
                    primaryButton: .destructive(Text(localize(zh: "确认批量删除", en: "Delete All"))) {
                        controller.deleteSelectedItems()
                    },
                    secondaryButton: .cancel(Text(localize(zh: "取消", en: "Cancel")))
                )
            }
        }
    }
    
    private var isAllVisibleItemsSelected: Bool {
        let visibleIds = controller.filteredItems.map { $0.id }
        if visibleIds.isEmpty { return false }
        return visibleIds.allSatisfy { controller.selectedItemIds.contains($0) }
    }
    
    private var totalFilteredSize: Int64 {
        controller.filteredItems.reduce(0) { $0 + $1.size }
    }
    
    private var totalSelectedSize: Int64 {
        controller.selectedItemIds.reduce(0) { total, id in
            if let item = controller.filteredItems.first(where: { $0.id == id }) {
                return total + item.size
            }
            return total
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }
}

// MARK: - App Main Layout

struct ContentView: View {
    @StateObject private var controller = CleanerController()
    
    var body: some View {
        NavigationSplitView {
            SidebarView(controller: controller)
        } detail: {
            VStack(spacing: 0) {
                TopFilterView(controller: controller)
                
                DetailListView(controller: controller)
                
                if controller.isScanning || controller.isDeleting {
                    VStack(spacing: 8) {
                        HStack {
                            Text(controller.scanStatusText)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(String(format: "%.0f%%", controller.scanProgress * 100))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        ProgressView(value: controller.scanProgress)
                            .progressViewStyle(LinearProgressViewStyle())
                    }
                    .padding(12)
                    .background(Color(NSColor.controlBackgroundColor))
                }
            }
        }
        .frame(minWidth: 1000, minHeight: 650)
        .onAppear {
            controller.startScan()
        }
    }
}

// MARK: - App Bootstrapping

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let contentView = ContentView()

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.center()
        window.title = localize(zh: "Xcode 磁盘空间清理工具", en: "Xcode Cleaner")
        window.contentView = NSHostingView(rootView: contentView)
        window.makeKeyAndOrderFront(nil)
        
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
