export interface User {
    id: string;
    username: string;
    password: string;
    email: string;
}

export class UserService {
    private users: User[] = [];

    registerUser(username: string, password: string, email: string): User {
        const newUser: User = {
            id: this.generateId(),
            username,
            password,
            email,
        };
        this.users.push(newUser);
        return newUser;
    }

    loginUser(username: string, password: string): User | null {
        const user = this.users.find(user => user.username === username && user.password === password);
        return user || null;
    }

    getUserProfile(userId: string): User | undefined {
        return this.users.find(user => user.id === userId);
    }

    private generateId(): string {
        return Math.random().toString(36).substr(2, 9);
    }
}