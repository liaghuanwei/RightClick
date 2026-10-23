import Foundation

/// shell 拼接：一律单引号包裹，内部单引号按 '\'' 转义，杜绝路径里的 ; $() ` 造成命令注入
enum ShellCommand {
    static func quote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func line(directory: String, command: String?) -> String {
        let cd = "cd " + quote(directory)
        guard let command else { return cd }
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return cd }
        return cd + " && " + trimmed
    }
}
