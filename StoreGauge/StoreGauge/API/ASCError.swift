//
//  ASCError.swift
//  StoreGauge
//

import Foundation

struct ASCError: LocalizedError {
    let statusCode: Int?
    let apiCode: String?
    let detail: String

    var errorDescription: String? { detail }
    var isNotFound: Bool { statusCode == 404 }
    var isAuth: Bool { statusCode == 401 || statusCode == 403 }

    static func message(_ text: String, status: Int? = nil, code: String? = nil) -> ASCError {
        ASCError(statusCode: status, apiCode: code, detail: text)
    }
}
