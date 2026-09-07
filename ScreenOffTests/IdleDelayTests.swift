import Foundation
import Testing

@Suite("IdleDelay 档位")
struct IdleDelayTests {
    @Test("档位严格递增、无重复，且默认值在档位内")
    func optionsAreOrdered() {
        #expect(IdleDelay.options == IdleDelay.options.sorted())
        #expect(Set(IdleDelay.options).count == IdleDelay.options.count)
        #expect(IdleDelay.options.contains(IdleDelay.defaultSeconds))
    }

    @Test("旧偏好里的秒级档位与非法值回落到默认值")
    func legacySecondsFallBackToDefault() {
        for legacy in [0, 5, 30, -1, 99_999] {
            #expect(IdleDelay.seconds(at: IdleDelay.index(of: legacy)) == IdleDelay.defaultSeconds)
        }
    }

    @Test("索引越界时夹紧到首尾档位")
    func indexIsClamped() {
        #expect(IdleDelay.seconds(at: -1) == IdleDelay.options.first)
        #expect(IdleDelay.seconds(at: IdleDelay.maximumIndex + 10) == IdleDelay.options.last)
    }

    @Test("精确档位往返一致")
    func roundTrip() {
        for (index, seconds) in IdleDelay.options.enumerated() {
            #expect(IdleDelay.index(of: seconds) == index)
            #expect(IdleDelay.seconds(at: index) == seconds)
        }
    }

    @Test("标题按分钟与小时格式化")
    func titles() {
        #expect(IdleDelay.title(60) == "1 分钟")
        #expect(IdleDelay.title(2700) == "45 分钟")
        #expect(IdleDelay.title(3600) == "1 小时")
        #expect(IdleDelay.title(5400) == "1.5 小时")
        #expect(IdleDelay.title(14400) == "4 小时")
    }
}
