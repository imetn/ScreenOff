import Foundation

// launchd 按 Mach service 需求拉起本进程；最后一个客户端断开时本进程主动退出，
// 这样 App 升级后下一次连接拿到的一定是新 bundle 里的可执行文件。
let service = LidWakeHelperService()
let delegate = LidWakeListenerDelegate(service: service)

// 用 GCD 信号源而不是 signal handler：处理器里不能安全调用 IOKit。
signal(SIGTERM, SIG_IGN)
let termination = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
termination.setEventHandler { service.restoreAndExit() }
termination.resume()

let listener = NSXPCListener(machServiceName: LidWakeHelper.label)
listener.delegate = delegate
listener.resume()

RunLoop.main.run()
