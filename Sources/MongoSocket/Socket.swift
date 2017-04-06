//
// This source file is part of the MongoKitten open source project
//
// Copyright (c) 2016 - 2017 OpenKitten and the MongoKitten project authors
// Licensed under MIT
//
// See https://github.com/OpenKitten/MongoKitten/blob/mongokitten31/LICENSE.md for license information
// See https://github.com/OpenKitten/MongoKitten/blob/mongokitten31/CONTRIBUTORS.md for the list of MongoKitten project authors
//

import Foundation
import Sockets
import libc
import TLS

public final class MongoSocket: MongoTCP {
    private let plainClient: TCPInternetSocket?
    private let sslClient: TLS.Socket?
    private var sslEnabled = false

    public init(address hostname: String, port: UInt16, options: [String: Any]) throws {
        self.sslEnabled = options["sslEnabled"] as? Bool ?? false

        if sslEnabled {
            plainClient = nil
            let address = hostname.lowercased() == "localhost" ? InternetAddress.localhost(port: port) : InternetAddress.init(hostname: hostname, port: port)

            let internetSocket = try TCPInternetSocket(address, scheme: "mongodb")
            
            sslClient = try TLS.InternetSocket(internetSocket, TLS.Context(.client))
            try sslClient?.socket.connect()
        } else {
            sslClient = nil
            let address = hostname.lowercased() == "localhost" ? InternetAddress.localhost(port: port) : InternetAddress(hostname: hostname, port: port)
            plainClient = try TCPInternetSocket(address, scheme: "mongodb")
            try plainClient?.connect()
        }
    }

    /// Sends the data to the other side of the connection
    public func send(data binary: [UInt8]) throws {
        if sslEnabled {
            try sslClient?.socket.write(binary, flushing: true)
        } else {
            try plainClient?.write(binary, flushing: true)
        }
    }

    /// Receives any available data from the socket
    public func receive(into buffer: Buffer) throws {
        let receivedBytes: Int
        
        if sslEnabled {
            guard let sslClient = sslClient else { throw MongoSocketError.clientNotInitialized }
            
            receivedBytes = libc.recv(sslClient.socket.descriptor.raw, buffer.pointer, Int(UInt16.max), 0)
        } else {
            guard let plainClient = plainClient else { throw MongoSocketError.clientNotInitialized }
            
            receivedBytes = libc.recv(plainClient.descriptor.raw, buffer.pointer, Int(UInt16.max), 0)
        }
        
        guard receivedBytes != -1 else {
            if errno == ECONNRESET {
                // closed by peer, need to close this side.
                // Since this is not an error, no need to throw unless the close
                // itself throws an error.
                _ = try self.close()
                return
            } else {
                throw SocketsError(.readFailed)
            }
        }
        
        buffer.usedCapacity = receivedBytes
    }

    /// `true` when connected, `false` otherwise
    public var isConnected: Bool {
        if sslEnabled {
            return !(sslClient?.socket.isClosed ?? false)
        } else {
            return !(plainClient?.isClosed ?? false)
        }
    }

    /// Closes the connection
    public func close() throws {
        if sslEnabled {
            guard let sslClient = sslClient else { throw MongoSocketError.clientNotInitialized }
            try sslClient.close()
        } else {
            guard let plainClient = plainClient else { throw MongoSocketError.clientNotInitialized }
            try plainClient.close()
        }
    }
}
