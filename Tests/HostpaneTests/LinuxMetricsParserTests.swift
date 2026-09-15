import Foundation
import XCTest
@testable import HostpaneCore

final class LinuxMetricsParserTests: XCTestCase {
    func testParsesTwoSamplesForCPUAndNetworkRates() throws {
        var parser = LinuxMetricsParser()
        let first = try parser.consume(
            sample(idle: 100, totalIdleAndBusy: 200, rx: 1_000, tx: 2_000),
            at: Date(timeIntervalSince1970: 1_000)
        )
        XCTAssertEqual(first.hostname, "jp01")
        XCTAssertTrue(first.isLinux)
        XCTAssertNil(first.cpuUsage)
        XCTAssertEqual(first.memoryTotalBytes, 2_000 * 1024)
        XCTAssertEqual(first.memoryAvailableBytes, 500 * 1024)
        XCTAssertTrue(first.disks.contains { $0.mount == "/" && $0.totalBytes == 1_000_000 })
        XCTAssertNil(first.netReceiveBytesPerSecond)

        let second = try parser.consume(
            sample(idle: 140, totalIdleAndBusy: 300, rx: 3_000, tx: 6_000),
            at: Date(timeIntervalSince1970: 1_002)
        )
        let cpu = try XCTUnwrap(second.cpuUsage)
        XCTAssertEqual(cpu, 0.6, accuracy: 0.001)
        XCTAssertEqual(second.netReceiveBytesPerSecond, 1_000)
        XCTAssertEqual(second.netTransmitBytesPerSecond, 2_000)
    }

    func testSkipsLoopbackAndVirtualInterfaces() throws {
        var parser = LinuxMetricsParser()
        let text = """
        HP_BEGIN
        os=Linux
        hostname=box
        uptime_sec=10
        HP_STAT
        cpu  0 0 0 0 0 0 0 0
        HP_MEM
        MemTotal: 100 kB
        MemAvailable: 40 kB
        SwapTotal: 0 kB
        SwapFree: 0 kB
        HP_NET
        Inter-|   Receive                                                Transmit
        lo: 999 0 0 0 0 0 0 0 999 0 0 0 0 0 0 0
        docker0: 888 0 0 0 0 0 0 0 888 0 0 0 0 0 0 0
        eth0: 100 0 0 0 0 0 0 0 200 0 0 0 0 0 0 0
        HP_DISK
        Filesystem 1B-blocks Used Available Capacity Mounted on
        /dev/sda1 1000 400 600 40% /
        HP_END
        """
        _ = try parser.consume(text, at: Date(timeIntervalSince1970: 10))
        let secondText = text.replacingOccurrences(
            of: "eth0: 100 0 0 0 0 0 0 0 200 0 0 0 0 0 0 0",
            with: "eth0: 300 0 0 0 0 0 0 0 600 0 0 0 0 0 0 0"
        )
        let second = try parser.consume(secondText, at: Date(timeIntervalSince1970: 12))
        XCTAssertEqual(second.netReceiveBytesPerSecond, 100)
        XCTAssertEqual(second.netTransmitBytesPerSecond, 200)
    }

    func testPrimaryDiskPrefersLargestLocalVolume() throws {
        var parser = LinuxMetricsParser()
        let text = """
        HP_BEGIN
        os=Linux
        hostname=syno
        uptime_sec=10
        HP_STAT
        cpu  0 0 0 0 0 0 0 0
        HP_MEM
        MemTotal: 100 kB
        MemAvailable: 40 kB
        SwapTotal: 0 kB
        SwapFree: 0 kB
        HP_NET
        eth0: 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
        HP_DISK
        Filesystem Type 1B-blocks Used Available Capacity Mounted on
        /dev/md0 ext4 8000000000 2000000000 6000000000 25% /
        /dev/mapper/cachedev_1 btrfs 15000000000000 8000000000000 7000000000000 54% /volume1
        nas.example:/share nfs 9999999999999 1 9999999999998 1% /mnt/nfs
        HP_END
        """
        let metrics = try parser.consume(text, at: Date(timeIntervalSince1970: 10))
        XCTAssertEqual(metrics.primaryDisk?.mount, "/volume1")
        XCTAssertEqual(metrics.localStorageBytes, 8_000_000_000 + 15_000_000_000_000)
        XCTAssertFalse(metrics.localDisks.contains { $0.mount == "/mnt/nfs" })
    }

    private func sample(idle: UInt64, totalIdleAndBusy: UInt64, rx: UInt64, tx: UInt64) -> String {
        let busy = totalIdleAndBusy - idle
        return """
        HP_BEGIN
        os=Linux
        hostname=jp01
        uptime_sec=3600
        loadavg=0.10 0.20 0.30
        HP_STAT
        cpu  \(busy) 0 0 \(idle) 0 0 0 0
        HP_MEM
        MemTotal:       2000 kB
        MemAvailable:    500 kB
        SwapTotal:         0 kB
        SwapFree:          0 kB
        HP_NET
        Inter-|   Receive                                                Transmit
        face |bytes    packets errs drop fifo frame compressed multicast|bytes    packets errs drop fifo colls carrier compressed
        eth0: \(rx) 0 0 0 0 0 0 0 \(tx) 0 0 0 0 0 0 0
        lo: 50 0 0 0 0 0 0 0 50 0 0 0 0 0 0 0
        HP_DISK
        Filesystem     1B-blocks        Used   Available Capacity Mounted on
        /dev/sda1        1000000      400000      600000      40% /
        tmpfs               9999         100        9899       1% /run
        HP_END
        """
    }
}
