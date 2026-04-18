import ArgumentParser
import GaiaFTCLCore

struct MeshCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mesh",
        abstract: "Mesh operations",
        subcommands: [
            Cells.self,
            Franklin.self,
            Nats.self,
            Mooring.self
        ]
    )

    struct Cells: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "cells", abstract: "List mesh cells")
        mutating func run() async throws { print("CALORIE\n{\"cells\": []}") }
    }

    struct Franklin: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "franklin", abstract: "Franklin guardian cell", subcommands: [Status.self])
        struct Status: AsyncParsableCommand { mutating func run() async throws { print("CALORIE\n{\"franklin_status\": \"active\"}") } }
    }

    struct Nats: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "nats", abstract: "NATS operations", subcommands: [Tail.self, Pub.self])
        struct Tail: AsyncParsableCommand {
            @Argument(help: "Subject") var subject: String
            mutating func run() async throws { print("CALORIE\n{\"tailing\": \"\(subject)\"}") }
        }
        struct Pub: AsyncParsableCommand {
            @Argument(help: "Subject") var subject: String
            @Argument(help: "Payload") var payload: String
            mutating func run() async throws { print("CALORIE\n{\"published\": \"\(subject)\"}") }
        }
    }

    struct Mooring: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "mooring", abstract: "Mooring operations", subcommands: [Heartbeat.self, Status.self])
        struct Heartbeat: AsyncParsableCommand { mutating func run() async throws { print("CALORIE\n{\"heartbeat\": \"sent\"}") } }
        struct Status: AsyncParsableCommand { mutating func run() async throws { print("CALORIE\n{\"mooring_status\": \"MEASURED\"}") } }
    }
}
