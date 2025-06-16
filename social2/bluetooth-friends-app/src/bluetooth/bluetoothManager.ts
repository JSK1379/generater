class BluetoothManager {
    constructor() {
        this.devices = [];
        this.connectedDevice = null;
    }

    scanForDevices() {
        // 假設這裡有藍牙掃描的邏輯
        console.log("Scanning for devices...");
        // 模擬找到的設備
        this.devices = ["Device1", "Device2", "Device3"];
        console.log("Devices found:", this.devices);
    }

    connectToDevice(device) {
        if (this.devices.includes(device)) {
            this.connectedDevice = device;
            console.log(`Connected to ${device}`);
        } else {
            console.log(`Device ${device} not found`);
        }
    }

    disconnectDevice() {
        if (this.connectedDevice) {
            console.log(`Disconnected from ${this.connectedDevice}`);
            this.connectedDevice = null;
        } else {
            console.log("No device is currently connected");
        }
    }
}

export default BluetoothManager;