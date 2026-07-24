//
//  Gzip.swift
//  StoreGauge
//
//  Gzip (RFC 1952) decompression using Apple's Compression framework. Sales and
//  Analytics reports are returned gzip-encoded.
//

import Foundation
import Compression

enum Gzip {
    /// Decompresses gzip data. If the input isn't gzip, it's returned unchanged.
    nonisolated static func decompress(_ data: Data) -> Data {
        guard data.count > 18, data[data.startIndex] == 0x1f,
              data[data.startIndex + 1] == 0x8b, data[data.startIndex + 2] == 0x08 else {
            return data // not gzip — assume already plain
        }
        let flags = data[data.startIndex + 3]
        var idx = data.startIndex + 10
        // FEXTRA
        if flags & 0x04 != 0, idx + 2 <= data.endIndex {
            let xlen = Int(data[idx]) | (Int(data[idx + 1]) << 8)
            idx += 2 + xlen
        }
        // FNAME
        if flags & 0x08 != 0 { while idx < data.endIndex, data[idx] != 0 { idx += 1 }; idx += 1 }
        // FCOMMENT
        if flags & 0x10 != 0 { while idx < data.endIndex, data[idx] != 0 { idx += 1 }; idx += 1 }
        // FHCRC
        if flags & 0x02 != 0 { idx += 2 }
        guard idx < data.endIndex - 8 else { return data }
        let body = data.subdata(in: idx..<(data.endIndex - 8))
        return inflate(body) ?? data
    }

    /// Raw DEFLATE (RFC 1951) inflate.
    nonisolated static func inflate(_ input: Data, expectedSize: Int? = nil) -> Data? {
        let bufferSize = 1 << 16
        let dst = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { dst.deallocate() }

        var stream = compression_stream(dst_ptr: dst, dst_size: bufferSize, src_ptr: dst, src_size: 0, state: nil)
        guard compression_stream_init(&stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB) == COMPRESSION_STATUS_OK else {
            return nil
        }
        defer { compression_stream_destroy(&stream) }

        return input.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Data? in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return input.isEmpty ? Data() : nil }
            stream.src_ptr = base
            stream.src_size = input.count
            stream.dst_ptr = dst
            stream.dst_size = bufferSize

            var output = Data()
            if let expectedSize, expectedSize > 0 { output.reserveCapacity(expectedSize) }
            let flags = Int32(COMPRESSION_STREAM_FINALIZE.rawValue)
            while true {
                let status = compression_stream_process(&stream, flags)
                switch status {
                case COMPRESSION_STATUS_OK, COMPRESSION_STATUS_END:
                    let produced = bufferSize - stream.dst_size
                    if produced > 0 { output.append(dst, count: produced) }
                    stream.dst_ptr = dst
                    stream.dst_size = bufferSize
                    if status == COMPRESSION_STATUS_END { return output }
                default:
                    return nil
                }
            }
        }
    }
}
