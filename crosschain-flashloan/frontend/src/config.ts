import { StandardSuperConfig } from 'superchain-starter'

// Configure chains for local development
export const config = new StandardSuperConfig({
    901: 'http://127.0.0.1:9545', // Local chain 1
    902: 'http://127.0.0.1:9546'  // Local chain 2
}) 