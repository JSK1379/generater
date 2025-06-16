import { BluetoothManager } from './bluetooth/bluetoothManager';
import { UserService } from './services/userService';
import { FriendList } from './components/FriendList';

class App {
    private bluetoothManager: BluetoothManager;
    private userService: UserService;
    private friendList: FriendList;

    constructor() {
        this.bluetoothManager = new BluetoothManager();
        this.userService = new UserService();
        this.friendList = new FriendList();
    }

    public initialize() {
        this.setupBluetooth();
        this.setupUserService();
        this.setupFriendList();
    }

    private setupBluetooth() {
        this.bluetoothManager.scanForDevices()
            .then(devices => {
                console.log('Found devices:', devices);
            })
            .catch(error => {
                console.error('Error scanning for devices:', error);
            });
    }

    private setupUserService() {
        // Initialize user service if needed
    }

    private setupFriendList() {
        // Initialize friend list if needed
    }
}

const app = new App();
app.initialize();