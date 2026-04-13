/*
 * Quick Vision Storage Service
 * 快速识图历史记录持久化服务
 */

import Foundation

class QuickVisionStorage {
    static let shared = QuickVisionStorage()

    private let userDefaults = UserDefaults.standard
    private let recordsKey = "quickVisionRecords"
    private let maxRecords = 100 // 最多保存100条记录

    private init() {}

    // MARK: - Save Record

    func saveRecord(_ record: QuickVisionRecord) {
        var records = loadAllRecords()

        // Add new record at the beginning
        records.insert(record, at: 0)

        // Keep only the most recent maxRecords
        if records.count > maxRecords {
            records = Array(records.prefix(maxRecords))
        }

        // Encode and save
        if let encoded = try? JSONEncoder().encode(records) {
            userDefaults.set(encoded, forKey: recordsKey)
            print("💾 [QuickVisionStorage] 保存记录成功: \(record.id), 总数: \(records.count)")
        } else {
            print("❌ [QuickVisionStorage] 保存记录失败")
        }
    }

    // MARK: - Load Records

    func loadAllRecords() -> [QuickVisionRecord] {
        guard let data = userDefaults.data(forKey: recordsKey),
              let records = try? JSONDecoder().decode([QuickVisionRecord].self, from: data) else {
            return []
        }
        return records
    }

    func loadRecords(limit: Int = 20, offset: Int = 0) -> [QuickVisionRecord] {
        let allRecords = loadAllRecords()
        let endIndex = min(offset + limit, allRecords.count)

        guard offset < allRecords.count else {
            return []
        }

        return Array(allRecords[offset..<endIndex])
    }

    // MARK: - Delete Records

    func deleteRecord(_ id: UUID) {
        var records = loadAllRecords()
        records.removeAll { $0.id == id }

        if let encoded = try? JSONEncoder().encode(records) {
            userDefaults.set(encoded, forKey: recordsKey)
            print("🗑️ [QuickVisionStorage] 删除记录成功: \(id)")
        }
    }

    func deleteAllRecords() {
        userDefaults.removeObject(forKey: recordsKey)
        print("🗑️ [QuickVisionStorage] 清空所有记录")
    }

    // MARK: - Get Record

    func getRecord(by id: UUID) -> QuickVisionRecord? {
        return loadAllRecords().first { $0.id == id }
    }

    // MARK: - Statistics

    var recordCount: Int {
        return loadAllRecords().count
    }
}
