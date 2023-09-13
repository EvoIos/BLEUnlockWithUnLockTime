// Resolve MAC address and device name of BLE device from SQLite database at /Library/Bluetooth introduced in Monterey.

import SQLite3
import Foundation

private var inited = false
private var db_paired: OpaquePointer?
private var db_other: OpaquePointer?

private var initedTime = false
private var db_time: OpaquePointer?

private func connect() {
    if inited { return }

    if sqlite3_open("/Library/Bluetooth/com.apple.MobileBluetooth.ledevices.paired.db", &db_paired) == SQLITE_OK {
        print("paired.db open success")
    } else {
        db_paired = nil
    }

    if sqlite3_open("/Library/Bluetooth/com.apple.MobileBluetooth.ledevices.other.db", &db_other) == SQLITE_OK {
        print("other.db open success")
    } else {
        db_other = nil
    }

    inited = true
}

private func connectTime() {
    if initedTime { return }
    
    /**
     CREATE TABLE Log (
        ID INTEGER PRIMARY  KEY     autoincrement,
        Time            INT     NOT NULL,
        LockType        INT     NOT NULL,
        PrettyTime      TEXT    NOT NULL,
        PrettyDate      TEXT    NOT NULL
     )
     */
    
    if sqlite3_open("/Users/zlc/Desktop/scripts/unlock_time/TimeLog.db", &db_time) == SQLITE_OK {
        print("time.db open success")
    } else {
        db_time = nil
    }
    
    initedTime = true
}

struct LEDeviceInfo {
    var name: String?
    var macAddr: String?
}

enum LockType: String {
    case lock
    case unlock
}

struct TimeInfo {
    var time: Int64
    var type: LockType?
    var prettyTime: String?
    var prettyDate: String?
}

private func getStringFromRow(stmt: OpaquePointer?, index: Int32) -> String? {
    if sqlite3_column_type(stmt, index) != SQLITE_TEXT { return nil }
    let s = String(cString: sqlite3_column_text(stmt, index))
    let trimmed = s.trimmingCharacters(in: .whitespaces)
    if trimmed == "" { return nil }
    return trimmed
}

private func getNumberFromRow(stmt: OpaquePointer?, index: Int32) -> Int64? {
    if sqlite3_column_type(stmt, index) != SQLITE_INTEGER { return nil }
    let n = sqlite3_column_int64(stmt, index)
    return n
}

private func getPairedDeviceFromUUID(_ uuid: String) -> LEDeviceInfo? {
    guard let db = db_paired else { return nil }
    var stmt: OpaquePointer?
    if sqlite3_prepare(db, "SELECT Name, Address, ResolvedAddress FROM PairedDevices where Uuid='\(uuid)'", -1, &stmt, nil) != SQLITE_OK {
        print("failed to prepare")
        return nil
    }
    if sqlite3_step(stmt) != SQLITE_ROW {
        return nil
    }
    let name = getStringFromRow(stmt: stmt, index: 0)
    let address = getStringFromRow(stmt: stmt, index: 1)
    let resolvedAddress = getStringFromRow(stmt: stmt, index: 2)
    var mac: String? = nil
    if let addr = resolvedAddress ?? address {
        // It's like "Public XX:XX:..." or "Random XX:XX:...", so split by space and take the second one
        let parts = addr.split(separator: " ")
        if parts.count > 1 {
            mac = String(parts[1])
        }
    }
    return LEDeviceInfo(name: name, macAddr: mac)
}

private func getOtherDeviceFromUUID(_ uuid: String) -> LEDeviceInfo? {
    guard let db = db_other else { return nil }
    var stmt: OpaquePointer?
    if sqlite3_prepare(db, "SELECT Name, Address FROM OtherDevices where Uuid='\(uuid)'", -1, &stmt, nil) != SQLITE_OK {
        print("failed to prepare")
        return nil
    }
    if sqlite3_step(stmt) != SQLITE_ROW {
        return nil
    }
    let name = getStringFromRow(stmt: stmt, index: 0)
    let address = getStringFromRow(stmt: stmt, index: 1)
    var mac: String? = nil
    if let addr = address {
        // It's like "Public XX:XX:..." or "Random XX:XX:...", so split by space and take the second one
        let parts = addr.split(separator: " ")
        if parts.count > 1 {
            mac = String(parts[1])
        }
    }
    return LEDeviceInfo(name: name, macAddr: mac)
}

private func getLockLogs(_ prettyTime:String? ) -> TimeInfo? {
    guard let db = db_time else { return nil }
    
    let date = Date()
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyyMMdd"
    let prettyDate = formatter.string(from: date)
   
    var stmt: OpaquePointer?
    if sqlite3_prepare(db, "SELECT Time, LockType, PrettyTime, PrettyDate FROM Log where PrettyTime='\(prettyTime ?? prettyDate)'", -1, &stmt, nil) != SQLITE_OK {
        print("failed to prepare")
        return nil
    }
    if sqlite3_step(stmt) != SQLITE_ROW {
        return nil
    }
    
    guard let time = getNumberFromRow(stmt: stmt, index: 0),
        let lockType = getStringFromRow(stmt: stmt, index: 1),
          let dbPrettyTime = getStringFromRow(stmt: stmt, index: 2) else {
        return nil
    }
    return TimeInfo(time: time, type: LockType(rawValue: lockType), prettyTime: dbPrettyTime)
}

private func insert(time: Int64, lockType: String, prettyTime: String, prettyDate: String) {
       let insertStatementString = "INSERT INTO Log (Time, LockType, PrettyTime, PrettyDate) VALUES (?, ?, ?, ?);"
       var insertStatement: OpaquePointer? = nil
       if sqlite3_prepare_v2(db_time, insertStatementString, -1, &insertStatement, nil) == SQLITE_OK {
           sqlite3_bind_int64(insertStatement, 1, Int64(time))
           sqlite3_bind_text(insertStatement, 2, (lockType as NSString).utf8String, -1, nil)
           sqlite3_bind_text(insertStatement, 3, (prettyTime as NSString).utf8String, -1, nil)
           sqlite3_bind_text(insertStatement, 4, (prettyDate as NSString).utf8String, -1, nil)
           
           if sqlite3_step(insertStatement) == SQLITE_DONE {
               print("Successfully inserted row.")
           } else {
               print("Could not insert row.")
           }
       } else {
           print("INSERT statement could not be prepared.")
       }
       sqlite3_finalize(insertStatement)
}

func getLEDeviceInfoFromUUID(_ uuid: String) -> LEDeviceInfo? {
    connect()
    return getPairedDeviceFromUUID(uuid) ?? getOtherDeviceFromUUID(uuid);
}

func prepareUnlockTimeDB() {
    connectTime()
}

func getUnlockTimeInfo(_ prettyTime: String? = nil) -> TimeInfo? {
    connectTime()
    return getLockLogs(prettyTime)
}

func insertUnlockTime() {
    connectTime()
    guard db_time != nil else { return }
    
    let date = Date()
    
    let time = date.timeIntervalSince1970
    print(time)
    
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyyMMdd"
    let prettyTime = formatter.string(from: date)
    
    formatter.dateFormat = "yyyyMMdd HH:mm:ss"
    let prettyDate = formatter.string(from: date)
    
    insert(time: Int64(time), lockType: LockType.unlock.rawValue, prettyTime: prettyTime, prettyDate: prettyDate)
}
