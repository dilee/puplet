import AppKit

MainActor.assumeIsolated {
    let arguments = CommandLine.arguments

    if let index = arguments.firstIndex(of: "--dump-frames") {
        let directory = arguments.count > index + 1 ? arguments[index + 1] : "./frames"
        FrameDumper.run(into: directory)
        exit(0)
    }

    if let index = arguments.firstIndex(of: "--chat") {
        let message = arguments.count > index + 1 ? arguments[index + 1] : "hello!"
        let brain = LayeredBrain(useOnDeviceModel: true)
        let context = BrainContext(
            petName: PetSettings.shared.name,
            frontmostApp: "Terminal",
            dayPart: WorkspaceContext().dayPart
        )
        print("you: \(message)")
        Task.detached {
            let reply = await brain.reply(to: message, context: context) { partial in
                let oneLine = partial.replacingOccurrences(of: "\n", with: " ")
                fputs("\u{1B}[2K\r\(context.petName): \(oneLine)", stdout)
                fflush(stdout)
            }
            let mood = reply.mood.map { " (mood: \($0))" } ?? ""
            print("\u{1B}[2K\r\(context.petName) [\(brain.chatStatusDetail)]: \(reply.say)\(mood)")
            exit(0)
        }
        RunLoop.main.run()
    }

    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)

    let delegate = AppDelegate()
    AppDelegate.shared = delegate
    app.delegate = delegate

    app.run()
}
