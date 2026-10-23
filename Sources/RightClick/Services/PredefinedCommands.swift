import Foundation

struct PredefinedCommand {
    let title: String
    let command: String
}

/// 「执行预设命令」的数据源：增删改都只改这里
/// 注意：这是 MVP 的示例集合，等确认实际常用命令后替换
enum PredefinedCommands {
    static let all: [PredefinedCommand] = [
        PredefinedCommand(title: "git status", command: "git status"),
        PredefinedCommand(title: "查看目录内容 (ls -la)", command: "ls -la"),
        PredefinedCommand(title: "查看当前路径 (pwd)", command: "pwd")
    ]
}
