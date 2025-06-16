import React, { useState } from 'react';

interface Friend {
    id: string;
    name: string;
}

const FriendList: React.FC = () => {
    const [friends, setFriends] = useState<Friend[]>([]);

    const addFriend = (name: string) => {
        const newFriend: Friend = { id: Date.now().toString(), name };
        setFriends([...friends, newFriend]);
    };

    const removeFriend = (id: string) => {
        setFriends(friends.filter(friend => friend.id !== id));
    };

    return (
        <div>
            <h2>Friends List</h2>
            <ul>
                {friends.map(friend => (
                    <li key={friend.id}>
                        {friend.name}
                        <button onClick={() => removeFriend(friend.id)}>Remove</button>
                    </li>
                ))}
            </ul>
            <button onClick={() => addFriend(prompt('Enter friend name') || '')}>Add Friend</button>
        </div>
    );
};

export default FriendList;