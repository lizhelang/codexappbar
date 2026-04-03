import Darwin
import Foundation

@main
enum CodexBarCLI {
    static func main() async {
        let runner = CodexBarCLICommandRunner()
        let exitCode = await runner.run(arguments: Array(CommandLine.arguments.dropFirst()))
        Darwin.exit(Int32(exitCode))
    }
}
