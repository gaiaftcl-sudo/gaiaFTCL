import Foundation
import Virtualization

@MainActor
final class VirtualMachineController: ObservableObject {
    @Published var statusLine: String = "Stopped"
    @Published var lastError: String?

    private var machine: VZVirtualMachine?

    var isRunning: Bool {
        machine?.state == .running
    }

    /// Start Linux VM with Ubuntu-style cloud kernel + initrd + writable root disk (ARM64).
    /// Optional `sharedGaiaRootURL`: read-only virtiofs tag **`gaiaos`** → guest `mount -t virtiofs gaiaos /opt/gaiaos`.
    func start(
        kernelURL: URL,
        initialRamdiskURL: URL,
        rootDiskURL: URL,
        sharedGaiaRootURL: URL? = nil,
        cpuCount: Int = 4,
        memorySizeBytes: UInt64 = 8 * 1024 * 1024 * 1024
    ) async {
        lastError = nil
        statusLine = "Configuring…"
        do {
            let boot = VZLinuxBootLoader(kernelURL: kernelURL)
            boot.initialRamdiskURL = initialRamdiskURL
            boot.commandLine = Self.defaultKernelCommandLine

            let diskAttachment = try VZDiskImageStorageDeviceAttachment(url: rootDiskURL, readOnly: false)
            let disk = VZVirtioBlockDeviceConfiguration(attachment: diskAttachment)

            let network = VZVirtioNetworkDeviceConfiguration()
            network.attachment = VZNATNetworkDeviceAttachment()

            let entropy = VZVirtioEntropyDeviceConfiguration()

            let config = VZVirtualMachineConfiguration()
            config.bootLoader = boot
            config.cpuCount = cpuCount
            config.memorySize = memorySizeBytes
            config.storageDevices = [disk]
            config.networkDevices = [network]
            config.entropyDevices = [entropy]

            if let gaia = sharedGaiaRootURL {
                let shared = VZSharedDirectory(url: gaia, readOnly: true)
                let singleShare = VZSingleDirectoryShare(directory: shared)
                let fs = VZVirtioFileSystemDeviceConfiguration(tag: Self.virtioFsTag)
                fs.share = singleShare
                config.directorySharingDevices = [fs]
            } else {
                config.directorySharingDevices = []
            }

            try config.validate()

            let vm = VZVirtualMachine(configuration: config)
            machine = vm

            statusLine = "Starting VM…"
            try await vm.start()
            statusLine = "VM running"
        } catch {
            lastError = error.localizedDescription
            statusLine = "Failed"
            machine = nil
        }
    }

    func stop() async {
        guard let vm = machine else {
            statusLine = "Stopped"
            return
        }
        statusLine = "Stopping…"
        do {
            try await vm.stop()
        } catch {
            lastError = error.localizedDescription
        }
        machine = nil
        statusLine = "Stopped"
    }

    /// Matches typical Ubuntu cloud image: first virtio block is root.
    private static let defaultKernelCommandLine =
        "console=hvc0 root=/dev/vda1 rw systemd.unified_cgroup_hierarchy=0 quiet splash"

    /// Must match `deploy/mac_cell_mount/fusion_sidecar_guest/` (`mount-gaiaos-virtiofs.sh`, fstab).
    static let virtioFsTag = "gaiaos"
}
