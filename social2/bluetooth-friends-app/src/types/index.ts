export interface User {
    id: string;
    username: string;
    email: string;
    createdAt: Date;
}

export interface Friend {
    id: string;
    userId: string;
    friendId: string;
    addedAt: Date;
}