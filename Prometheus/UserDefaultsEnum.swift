//
//  UserDefaultsEnum.swift
//  Prometheus
//
//  Created by PAN Weiheng on 2020/8/2.
//  Copyright © 2020 PAN Weiheng. Please refer to LICENSE for license information.
//

import Foundation

/// For raw Enums only.
/// Enums are not property list types and hence cannot be stored directly using UserDefaults.
@propertyWrapper
struct UserDefaultEnum<T: RawRepresentable> {
    let key: String
    let defaultValue: T
    
    init(key: String, defaultValue: T) {
        self.key = key
        self.defaultValue = defaultValue
    }
    
    var wrappedValue: T {
        get {
            guard let rawValue = UserDefaults.standard.object(forKey: key) as? T.RawValue else {
                return defaultValue
            }
            guard let value = T(rawValue: rawValue) else {
                #if DEBUG
                print("Cannot initialize enum type \(type(of: defaultValue)) with rawValue \(rawValue).")
                #endif
                return defaultValue
            }
            return value
        }
        set {
            let rawValue = newValue.rawValue
            UserDefaults.standard.set(rawValue, forKey: key)
        }
    }
}
