# Bluetooth Friends App

Bluetooth Friends App is a mobile application designed to help users connect with friends via Bluetooth. The app allows users to discover nearby friends, manage their friend list, and communicate seamlessly.

## Features

- **Bluetooth Connection**: Scan for nearby devices and connect with friends using Bluetooth technology.
- **Friend Management**: Add and remove friends from your list easily.
- **User Authentication**: Register and log in to manage your profile and friend list.

## Project Structure

```
bluetooth-friends-app
├── src
│   ├── app.ts                # Entry point of the application
│   ├── bluetooth
│   │   └── bluetoothManager.ts # Manages Bluetooth connections
│   ├── components
│   │   └── FriendList.ts      # Displays the list of friends
│   ├── services
│   │   └── userService.ts      # Manages user data
│   └── types
│       └── index.ts            # Defines User and Friend interfaces
├── package.json                # npm configuration file
├── tsconfig.json               # TypeScript configuration file
└── README.md                   # Project documentation
```

## Installation

1. Clone the repository:
   ```
   git clone https://github.com/yourusername/bluetooth-friends-app.git
   ```
2. Navigate to the project directory:
   ```
   cd bluetooth-friends-app
   ```
3. Install the dependencies:
   ```
   npm install
   ```

## Usage

1. Start the application:
   ```
   npm start
   ```
2. Follow the on-screen instructions to register or log in.
3. Use the Bluetooth functionality to connect with friends nearby.

## Contributing

Contributions are welcome! Please open an issue or submit a pull request for any enhancements or bug fixes.

## License

This project is licensed under the MIT License. See the LICENSE file for details.