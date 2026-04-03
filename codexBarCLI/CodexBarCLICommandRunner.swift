import Foundation

protocol CodexBarCLIIO {
    func writeOut(_ text: String)
    func writeErr(_ text: String)
    func readInput(prompt: String) -> String?
    @discardableResult
    func openBrowser(url: URL) -> Bool
}

struct StandardCodexBarCLIIO: CodexBarCLIIO {
    func writeOut(_ text: String) {
        FileHandle.standardOutput.write(Data(text.utf8))
    }

    func writeErr(_ text: String) {
        FileHandle.standardError.write(Data(text.utf8))
    }

    func readInput(prompt: String) -> String? {
        self.writeOut(prompt)
        return readLine()
    }

    @discardableResult
    func openBrowser(url: URL) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = [url.absoluteString]

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}

enum CodexBarCLIError: LocalizedError {
    case unknownCommand(String)
    case missingValue(String)
    case missingInput
    case mutuallyExclusiveOptions(String, String)
    case unsupportedOption(String)

    var errorDescription: String? {
        switch self {
        case .unknownCommand(let command):
            return "Unknown command: \(command)"
        case .missingValue(let flag):
            return "Missing value for \(flag)"
        case .missingInput:
            return "Expected callback URL or code from stdin"
        case .mutuallyExclusiveOptions(let lhs, let rhs):
            return "\(lhs) and \(rhs) cannot be used together"
        case .unsupportedOption(let option):
            return "Unsupported option: \(option)"
        }
    }
}

private struct LoginStartOutput: Codable {
    let flowID: String
    let authURL: String

    enum CodingKeys: String, CodingKey {
        case flowID = "flow_id"
        case authURL = "auth_url"
    }
}

private struct AccountCommandOutput: Codable {
    let accountID: String
    let email: String
    let active: Bool
    let synchronized: Bool?

    enum CodingKeys: String, CodingKey {
        case accountID = "account_id"
        case email
        case active
        case synchronized
    }
}

struct CodexBarCLICommandRunner {
    private let flowService: OpenAIOAuthFlowService
    private let accountService: CodexBarOAuthAccountService
    private let io: any CodexBarCLIIO

    init(
        flowService: OpenAIOAuthFlowService = OpenAIOAuthFlowService(),
        accountService: CodexBarOAuthAccountService = CodexBarOAuthAccountService(),
        io: any CodexBarCLIIO = StandardCodexBarCLIIO()
    ) {
        self.flowService = flowService
        self.accountService = accountService
        self.io = io
    }

    func run(arguments: [String]) async -> Int {
        _ = try? self.flowService.cleanupExpiredFlows()

        do {
            return try await self.dispatch(arguments)
        } catch {
            self.io.writeErr("Error: \(error.localizedDescription)\n")
            return 1
        }
    }

    private func dispatch(_ arguments: [String]) async throws -> Int {
        guard let command = arguments.first else {
            self.writeUsage()
            return 64
        }

        switch command {
        case "help", "--help", "-h":
            self.writeUsage()
            return 0
        case "openai":
            return try await self.runOpenAICommand(Array(arguments.dropFirst()))
        case "accounts":
            return try await self.runAccountsCommand(Array(arguments.dropFirst()))
        default:
            throw CodexBarCLIError.unknownCommand(command)
        }
    }

    private func runOpenAICommand(_ arguments: [String]) async throws -> Int {
        guard arguments.first == "login" else {
            throw CodexBarCLIError.unknownCommand(arguments.first ?? "openai")
        }

        let remainder = Array(arguments.dropFirst())
        if remainder.first == "start" {
            return try await self.runOpenAILoginStart(Array(remainder.dropFirst()))
        }
        if remainder.first == "complete" {
            return try await self.runOpenAILoginComplete(Array(remainder.dropFirst()))
        }
        return try await self.runInteractiveOpenAILogin(remainder)
    }

    private func runInteractiveOpenAILogin(_ arguments: [String]) async throws -> Int {
        var openBrowser = true
        var activate = true

        for argument in arguments {
            switch argument {
            case "--no-open-browser":
                openBrowser = false
            case "--activate":
                activate = true
            case "--no-activate":
                activate = false
            default:
                throw CodexBarCLIError.unsupportedOption(argument)
            }
        }

        let started = try self.flowService.startFlow()
        self.io.writeOut("OpenAI OAuth URL:\n\(started.authURL)\n\n")
        self.io.writeOut("Flow ID: \(started.flowID)\n")
        self.io.writeOut("Paste the full callback URL or just the code.\n")

        if openBrowser, let url = URL(string: started.authURL), !self.io.openBrowser(url: url) {
            self.io.writeErr("Warning: failed to open browser automatically.\n")
        }

        guard let input = self.io.readInput(prompt: "Callback URL or code: "),
              input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            throw CodexBarCLIError.missingInput
        }

        let result = try await self.flowService.completeFlow(
            flowID: started.flowID,
            callbackInput: input,
            activate: activate
        )
        return self.emitAccountResult(result.account, active: result.active, synchronized: result.synchronized, json: false)
    }

    private func runOpenAILoginStart(_ arguments: [String]) async throws -> Int {
        var openBrowser = false
        var json = false

        for argument in arguments {
            switch argument {
            case "--open-browser":
                openBrowser = true
            case "--json":
                json = true
            default:
                throw CodexBarCLIError.unsupportedOption(argument)
            }
        }

        let started = try self.flowService.startFlow()
        if openBrowser, let url = URL(string: started.authURL), !self.io.openBrowser(url: url) {
            self.io.writeErr("Warning: failed to open browser automatically.\n")
        }

        if json {
            try self.writeJSON(LoginStartOutput(flowID: started.flowID, authURL: started.authURL))
        } else {
            self.io.writeOut("Flow ID: \(started.flowID)\n")
            self.io.writeOut("Authorization URL:\n\(started.authURL)\n")
        }
        return 0
    }

    private func runOpenAILoginComplete(_ arguments: [String]) async throws -> Int {
        var flowID: String?
        var callbackURL: String?
        var code: String?
        var activate = true
        var json = false

        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--flow-id":
                index += 1
                guard index < arguments.count else { throw CodexBarCLIError.missingValue("--flow-id") }
                flowID = arguments[index]
            case "--callback-url":
                index += 1
                guard index < arguments.count else { throw CodexBarCLIError.missingValue("--callback-url") }
                callbackURL = arguments[index]
            case "--code":
                index += 1
                guard index < arguments.count else { throw CodexBarCLIError.missingValue("--code") }
                code = arguments[index]
            case "--activate":
                activate = true
            case "--no-activate":
                activate = false
            case "--json":
                json = true
            default:
                throw CodexBarCLIError.unsupportedOption(argument)
            }
            index += 1
        }

        guard let flowID, flowID.isEmpty == false else {
            throw CodexBarCLIError.missingValue("--flow-id")
        }
        if callbackURL != nil && code != nil {
            throw CodexBarCLIError.mutuallyExclusiveOptions("--callback-url", "--code")
        }
        guard callbackURL != nil || code != nil else {
            throw CodexBarCLIError.missingValue("--callback-url/--code")
        }

        let result = try await self.flowService.completeFlow(
            flowID: flowID,
            callbackURL: callbackURL,
            code: code,
            activate: activate
        )
        return self.emitAccountResult(result.account, active: result.active, synchronized: result.synchronized, json: json)
    }

    private func runAccountsCommand(_ arguments: [String]) async throws -> Int {
        guard let subcommand = arguments.first else {
            throw CodexBarCLIError.unknownCommand("accounts")
        }

        switch subcommand {
        case "list":
            return try self.runAccountsList(Array(arguments.dropFirst()))
        case "activate":
            return try self.runAccountsActivate(Array(arguments.dropFirst()))
        default:
            throw CodexBarCLIError.unknownCommand("accounts \(subcommand)")
        }
    }

    private func runAccountsList(_ arguments: [String]) throws -> Int {
        var json = false

        for argument in arguments {
            switch argument {
            case "--json":
                json = true
            default:
                throw CodexBarCLIError.unsupportedOption(argument)
            }
        }

        let accounts = try self.accountService.listAccounts()
        if json {
            try self.writeJSON(accounts)
        } else if accounts.isEmpty {
            self.io.writeOut("No OpenAI OAuth accounts found.\n")
        } else {
            for account in accounts {
                let prefix = account.active ? "*" : "-"
                self.io.writeOut("\(prefix) \(account.email) (\(account.accountID))\n")
            }
        }
        return 0
    }

    private func runAccountsActivate(_ arguments: [String]) throws -> Int {
        var accountID: String?
        var json = false

        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--account-id":
                index += 1
                guard index < arguments.count else { throw CodexBarCLIError.missingValue("--account-id") }
                accountID = arguments[index]
            case "--json":
                json = true
            default:
                throw CodexBarCLIError.unsupportedOption(argument)
            }
            index += 1
        }

        guard let accountID, accountID.isEmpty == false else {
            throw CodexBarCLIError.missingValue("--account-id")
        }

        let result = try self.accountService.activateAccount(accountID: accountID)
        return self.emitAccountResult(result.account, active: result.active, synchronized: result.synchronized, json: json)
    }

    @discardableResult
    private func emitAccountResult(_ account: TokenAccount, active: Bool, synchronized: Bool, json: Bool) -> Int {
        let output = AccountCommandOutput(
            accountID: account.accountId,
            email: account.email,
            active: active,
            synchronized: synchronized
        )

        if json {
            try? self.writeJSON(output)
        } else {
            self.io.writeOut("Account: \(account.email) (\(account.accountId))\n")
            self.io.writeOut(active ? "Active: yes\n" : "Active: no\n")
            self.io.writeOut(synchronized ? "Synchronized: yes\n" : "Synchronized: no\n")
        }
        return 0
    }

    private func writeJSON<T: Encodable>(_ value: T) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        self.io.writeOut(String(decoding: data, as: UTF8.self) + "\n")
    }

    private func writeUsage() {
        self.io.writeOut(
            """
            Usage:
              codexbarctl openai login [--no-open-browser] [--activate|--no-activate]
              codexbarctl openai login start [--open-browser] [--json]
              codexbarctl openai login complete --flow-id <id> (--callback-url <url> | --code <code>) [--activate|--no-activate] [--json]
              codexbarctl accounts list [--json]
              codexbarctl accounts activate --account-id <id> [--json]

            """
        )
    }
}
