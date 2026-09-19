import Foundation

// launchd 按 Mach service 需求拉起本进程；没有客户端时由 launchd 决定何时回收。
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
