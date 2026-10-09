import CoreData
import Combine
import CloudKit

@MainActor
final class PersistenceController: ObservableObject {
    static let shared = PersistenceController()

    let container: NSPersistentContainer
    @Published private(set) var iCloudEnabled: Bool

    var viewContext: NSManagedObjectContext { container.viewContext }

    init(inMemory: Bool = false) {
        let wantCloud = UserDefaults.standard.object(forKey: "settings.iCloudSync") as? Bool ?? false
        let useCloud = wantCloud && !inMemory

        let model = Self.makeModel()
        let builtContainer: NSPersistentContainer
        if useCloud {
            let cloud = NSPersistentCloudKitContainer(name: "Aptvios", managedObjectModel: model)
            let description = cloud.persistentStoreDescriptions.first
            description?.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
            description?.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
            description?.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
                containerIdentifier: "iCloud.com.aptvios.app"
            )
            builtContainer = cloud
        } else {
            builtContainer = NSPersistentContainer(name: "Aptvios", managedObjectModel: model)
        }
        container = builtContainer
        iCloudEnabled = useCloud

        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        }

        container.loadPersistentStores { _, error in
            if let error {
                print("Core Data load error: \(error). Falling back without CloudKit.")
            }
        }

        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        container.viewContext.automaticallyMergesChangesFromParent = true
    }

    func save() {
        let context = viewContext
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            print("Core Data save error: \(error)")
        }
    }

    // MARK: - Config

    @discardableResult
    func createConfig(
        name: String,
        url: String?,
        rawContent: String?,
        format: String,
        kind: SourceKind = .m3u,
        username: String? = nil,
        password: String? = nil,
        macAddress: String? = nil,
        outputFormat: String? = nil,
        channels: [ParsedChannel]
    ) -> SourceConfig {
        let config = SourceConfig(context: viewContext)
        config.id = UUID()
        config.name = name
        config.url = url
        config.rawContent = rawContent
        config.format = format
        config.kind = kind.rawValue
        config.username = username
        config.password = password
        config.macAddress = macAddress
        config.outputFormat = outputFormat
        config.createdAt = Date()
        config.lastRefreshed = Date()
        config.isEnabled = true

        replaceChannels(for: config, with: channels)
        save()
        return config
    }

    func replaceChannels(for config: SourceConfig, with channels: [ParsedChannel]) {
        if let existing = config.items as? Set<ChannelItem> {
            existing.forEach { viewContext.delete($0) }
        }

        for (index, parsed) in channels.enumerated() {
            let item = ChannelItem(context: viewContext)
            item.id = UUID()
            item.name = parsed.name
            item.url = parsed.url
            item.logo = parsed.logo
            item.groupTitle = parsed.groupTitle
            item.tvgId = parsed.tvgId
            item.tvgName = parsed.tvgName
            item.userAgent = parsed.userAgent
            item.referer = parsed.referer
            item.sortOrder = Int32(index)
            item.config = config
        }
        config.lastRefreshed = Date()
        config.channelCount = Int32(channels.count)
    }

    func updateChannel(
        id: UUID,
        name: String,
        url: String,
        logo: String?,
        groupTitle: String,
        tvgId: String?,
        userAgent: String?,
        referer: String?
    ) {
        let request = ChannelItem.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        guard let item = try? viewContext.fetch(request).first else { return }
        item.name = name
        item.url = url
        item.logo = logo
        item.groupTitle = groupTitle
        item.tvgId = tvgId
        item.userAgent = userAgent
        item.referer = referer
        save()
        objectWillChange.send()
    }

    func deleteChannel(id: UUID) {
        let request = ChannelItem.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        if let item = try? viewContext.fetch(request).first {
            let config = item.config
            viewContext.delete(item)
            if let config {
                config.channelCount = Int32(max(0, Int(config.channelCount) - 1))
            }
            save()
            objectWillChange.send()
        }
    }

    func addSingleChannel(
        name: String,
        url: String,
        groupTitle: String,
        logo: String?,
        to config: SourceConfig? = nil
    ) {
        let target: SourceConfig
        if let config {
            target = config
        } else {
            let request = SourceConfig.fetchRequest()
            request.predicate = NSPredicate(format: "kind == %@", SourceKind.blank.rawValue)
            request.fetchLimit = 1
            if let existing = try? viewContext.fetch(request).first {
                target = existing
            } else {
                target = createConfig(
                    name: "Manuel",
                    url: nil,
                    rawContent: nil,
                    format: "single",
                    kind: .blank,
                    channels: []
                )
            }
        }

        let item = ChannelItem(context: viewContext)
        item.id = UUID()
        item.name = name
        item.url = url
        item.logo = logo
        item.groupTitle = groupTitle
        item.sortOrder = target.channelCount
        item.config = target
        target.channelCount += 1
        target.lastRefreshed = Date()
        save()
        objectWillChange.send()
    }

    func mergeChannels(in config: SourceConfig, strategy: ChannelMergeService.Strategy) {
        let items = (config.items as? Set<ChannelItem>) ?? []
        let parsed = items.sorted { $0.sortOrder < $1.sortOrder }.map {
            ParsedChannel(
                name: $0.name ?? "Channel",
                url: $0.url ?? "",
                logo: $0.logo,
                groupTitle: $0.groupTitle ?? "Uncategorized",
                tvgId: $0.tvgId,
                tvgName: $0.tvgName,
                userAgent: $0.userAgent,
                referer: $0.referer
            )
        }
        let merged = ChannelMergeService.mergeDuplicates(parsed, strategy: strategy)
        replaceChannels(for: config, with: merged)
        save()
        objectWillChange.send()
    }

    func deleteConfig(_ config: SourceConfig) {
        viewContext.delete(config)
        save()
    }

    func allEnabledChannels() -> [PlayableChannel] {
        let request = ChannelItem.fetchRequest()
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \ChannelItem.groupTitle, ascending: true),
            NSSortDescriptor(keyPath: \ChannelItem.sortOrder, ascending: true),
            NSSortDescriptor(keyPath: \ChannelItem.name, ascending: true)
        ]
        request.predicate = NSPredicate(format: "config.isEnabled == YES")

        let items = (try? viewContext.fetch(request)) ?? []
        return items.map(PlayableChannel.init(from:))
    }

    func channelItem(id: UUID) -> ChannelItem? {
        let request = ChannelItem.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return try? viewContext.fetch(request).first
    }

    // MARK: - Favorites

    func isFavorite(url: String) -> Bool {
        let request = FavoriteChannel.fetchRequest()
        request.predicate = NSPredicate(format: "url == %@", url)
        request.fetchLimit = 1
        return ((try? viewContext.count(for: request)) ?? 0) > 0
    }

    func toggleFavorite(_ channel: PlayableChannel) {
        let request = FavoriteChannel.fetchRequest()
        request.predicate = NSPredicate(format: "url == %@", channel.url)
        if let existing = try? viewContext.fetch(request), let first = existing.first {
            viewContext.delete(first)
        } else {
            let fav = FavoriteChannel(context: viewContext)
            fav.id = UUID()
            fav.name = channel.name
            fav.url = channel.url
            fav.logo = channel.logo
            fav.groupTitle = channel.groupTitle
            fav.tvgId = channel.tvgId
            fav.createdAt = Date()
        }
        save()
        objectWillChange.send()
    }

    func favoriteChannels() -> [PlayableChannel] {
        let request = FavoriteChannel.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \FavoriteChannel.createdAt, ascending: false)]
        let items = (try? viewContext.fetch(request)) ?? []
        return items.map {
            PlayableChannel(
                id: $0.id ?? UUID(),
                name: $0.name ?? "Channel",
                url: $0.url ?? "",
                logo: $0.logo,
                groupTitle: $0.groupTitle ?? "Favorites",
                tvgId: $0.tvgId
            )
        }
    }

    // MARK: - Recently played

    func recordPlay(_ channel: PlayableChannel) {
        let request = RecentlyPlayed.fetchRequest()
        request.predicate = NSPredicate(format: "url == %@", channel.url)
        if let existing = try? viewContext.fetch(request) {
            existing.forEach { viewContext.delete($0) }
        }

        let row = RecentlyPlayed(context: viewContext)
        row.id = UUID()
        row.name = channel.name
        row.url = channel.url
        row.logo = channel.logo
        row.groupTitle = channel.groupTitle
        row.tvgId = channel.tvgId
        row.timestamp = Date()

        let allReq = RecentlyPlayed.fetchRequest()
        allReq.sortDescriptors = [NSSortDescriptor(keyPath: \RecentlyPlayed.timestamp, ascending: false)]
        if let all = try? viewContext.fetch(allReq), all.count > 50 {
            all.dropFirst(50).forEach { viewContext.delete($0) }
        }
        save()
    }

    func recentChannels() -> [PlayableChannel] {
        let request = RecentlyPlayed.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \RecentlyPlayed.timestamp, ascending: false)]
        request.fetchLimit = 30
        let items = (try? viewContext.fetch(request)) ?? []
        return items.map {
            PlayableChannel(
                id: $0.id ?? UUID(),
                name: $0.name ?? "Channel",
                url: $0.url ?? "",
                logo: $0.logo,
                groupTitle: $0.groupTitle ?? "Recent",
                tvgId: $0.tvgId
            )
        }
    }

    func activeProxy() -> ProxyConfig? {
        let request = ProxyConfig.fetchRequest()
        request.predicate = NSPredicate(format: "isEnabled == YES")
        request.fetchLimit = 1
        return try? viewContext.fetch(request).first
    }

    // MARK: - Model

    private static func makeModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()

        let config = NSEntityDescription()
        config.name = "SourceConfig"
        config.managedObjectClassName = "SourceConfig"

        let item = NSEntityDescription()
        item.name = "ChannelItem"
        item.managedObjectClassName = "ChannelItem"

        let favorite = NSEntityDescription()
        favorite.name = "FavoriteChannel"
        favorite.managedObjectClassName = "FavoriteChannel"

        let proxy = NSEntityDescription()
        proxy.name = "ProxyConfig"
        proxy.managedObjectClassName = "ProxyConfig"

        let recent = NSEntityDescription()
        recent.name = "RecentlyPlayed"
        recent.managedObjectClassName = "RecentlyPlayed"

        config.properties = [
            attr("id", .UUIDAttributeType),
            attr("name", .stringAttributeType),
            attr("url", .stringAttributeType, optional: true),
            attr("rawContent", .stringAttributeType, optional: true),
            attr("format", .stringAttributeType),
            attr("kind", .stringAttributeType, optional: true, defaultValue: "m3u"),
            attr("username", .stringAttributeType, optional: true),
            attr("password", .stringAttributeType, optional: true),
            attr("macAddress", .stringAttributeType, optional: true),
            attr("outputFormat", .stringAttributeType, optional: true),
            attr("createdAt", .dateAttributeType),
            attr("lastRefreshed", .dateAttributeType, optional: true),
            attr("isEnabled", .booleanAttributeType, defaultValue: true),
            attr("channelCount", .integer32AttributeType, defaultValue: 0)
        ]

        item.properties = [
            attr("id", .UUIDAttributeType),
            attr("name", .stringAttributeType),
            attr("url", .stringAttributeType),
            attr("logo", .stringAttributeType, optional: true),
            attr("groupTitle", .stringAttributeType, optional: true),
            attr("tvgId", .stringAttributeType, optional: true),
            attr("tvgName", .stringAttributeType, optional: true),
            attr("userAgent", .stringAttributeType, optional: true),
            attr("referer", .stringAttributeType, optional: true),
            attr("sortOrder", .integer32AttributeType, defaultValue: 0)
        ]

        favorite.properties = [
            attr("id", .UUIDAttributeType),
            attr("name", .stringAttributeType),
            attr("url", .stringAttributeType),
            attr("logo", .stringAttributeType, optional: true),
            attr("groupTitle", .stringAttributeType, optional: true),
            attr("tvgId", .stringAttributeType, optional: true),
            attr("createdAt", .dateAttributeType)
        ]

        proxy.properties = [
            attr("id", .UUIDAttributeType),
            attr("host", .stringAttributeType),
            attr("port", .integer32AttributeType),
            attr("username", .stringAttributeType, optional: true),
            attr("password", .stringAttributeType, optional: true),
            attr("type", .stringAttributeType, defaultValue: "http"),
            attr("isEnabled", .booleanAttributeType, defaultValue: false),
            attr("createdAt", .dateAttributeType)
        ]

        recent.properties = [
            attr("id", .UUIDAttributeType),
            attr("name", .stringAttributeType),
            attr("url", .stringAttributeType),
            attr("logo", .stringAttributeType, optional: true),
            attr("groupTitle", .stringAttributeType, optional: true),
            attr("tvgId", .stringAttributeType, optional: true),
            attr("timestamp", .dateAttributeType)
        ]

        let configToItems = NSRelationshipDescription()
        configToItems.name = "items"
        configToItems.destinationEntity = item
        configToItems.minCount = 0
        configToItems.maxCount = 0
        configToItems.deleteRule = .cascadeDeleteRule
        configToItems.isOptional = true

        let itemToConfig = NSRelationshipDescription()
        itemToConfig.name = "config"
        itemToConfig.destinationEntity = config
        itemToConfig.minCount = 0
        itemToConfig.maxCount = 1
        itemToConfig.deleteRule = .nullifyDeleteRule
        itemToConfig.isOptional = true

        configToItems.inverseRelationship = itemToConfig
        itemToConfig.inverseRelationship = configToItems

        config.properties.append(configToItems)
        item.properties.append(itemToConfig)

        model.entities = [config, item, favorite, proxy, recent]
        return model
    }

    private static func attr(
        _ name: String,
        _ type: NSAttributeType,
        optional: Bool = false,
        defaultValue: Any? = nil
    ) -> NSAttributeDescription {
        let a = NSAttributeDescription()
        a.name = name
        a.attributeType = type
        a.isOptional = optional
        if let defaultValue {
            a.defaultValue = defaultValue
        }
        return a
    }
}

@objc(SourceConfig)
public class SourceConfig: NSManagedObject {
    @NSManaged public var id: UUID?
    @NSManaged public var name: String?
    @NSManaged public var url: String?
    @NSManaged public var rawContent: String?
    @NSManaged public var format: String?
    @NSManaged public var kind: String?
    @NSManaged public var username: String?
    @NSManaged public var password: String?
    @NSManaged public var macAddress: String?
    @NSManaged public var outputFormat: String?
    @NSManaged public var createdAt: Date?
    @NSManaged public var lastRefreshed: Date?
    @NSManaged public var isEnabled: Bool
    @NSManaged public var channelCount: Int32
    @NSManaged public var items: NSSet?

    var sourceKind: SourceKind {
        SourceKind(rawValue: kind ?? "m3u") ?? .m3u
    }
}

extension SourceConfig {
    @nonobjc class func fetchRequest() -> NSFetchRequest<SourceConfig> {
        NSFetchRequest<SourceConfig>(entityName: "SourceConfig")
    }
}

@objc(ChannelItem)
public class ChannelItem: NSManagedObject {
    @NSManaged public var id: UUID?
    @NSManaged public var name: String?
    @NSManaged public var url: String?
    @NSManaged public var logo: String?
    @NSManaged public var groupTitle: String?
    @NSManaged public var tvgId: String?
    @NSManaged public var tvgName: String?
    @NSManaged public var userAgent: String?
    @NSManaged public var referer: String?
    @NSManaged public var sortOrder: Int32
    @NSManaged public var config: SourceConfig?
}

extension ChannelItem {
    @nonobjc class func fetchRequest() -> NSFetchRequest<ChannelItem> {
        NSFetchRequest<ChannelItem>(entityName: "ChannelItem")
    }
}

@objc(FavoriteChannel)
public class FavoriteChannel: NSManagedObject {
    @NSManaged public var id: UUID?
    @NSManaged public var name: String?
    @NSManaged public var url: String?
    @NSManaged public var logo: String?
    @NSManaged public var groupTitle: String?
    @NSManaged public var tvgId: String?
    @NSManaged public var createdAt: Date?
}

extension FavoriteChannel {
    @nonobjc class func fetchRequest() -> NSFetchRequest<FavoriteChannel> {
        NSFetchRequest<FavoriteChannel>(entityName: "FavoriteChannel")
    }
}

@objc(ProxyConfig)
public class ProxyConfig: NSManagedObject {
    @NSManaged public var id: UUID?
    @NSManaged public var host: String?
    @NSManaged public var port: Int32
    @NSManaged public var username: String?
    @NSManaged public var password: String?
    @NSManaged public var type: String?
    @NSManaged public var isEnabled: Bool
    @NSManaged public var createdAt: Date?
}

extension ProxyConfig {
    @nonobjc class func fetchRequest() -> NSFetchRequest<ProxyConfig> {
        NSFetchRequest<ProxyConfig>(entityName: "ProxyConfig")
    }
}

@objc(RecentlyPlayed)
public class RecentlyPlayed: NSManagedObject {
    @NSManaged public var id: UUID?
    @NSManaged public var name: String?
    @NSManaged public var url: String?
    @NSManaged public var logo: String?
    @NSManaged public var groupTitle: String?
    @NSManaged public var tvgId: String?
    @NSManaged public var timestamp: Date?
}

extension RecentlyPlayed {
    @nonobjc class func fetchRequest() -> NSFetchRequest<RecentlyPlayed> {
        NSFetchRequest<RecentlyPlayed>(entityName: "RecentlyPlayed")
    }
}
