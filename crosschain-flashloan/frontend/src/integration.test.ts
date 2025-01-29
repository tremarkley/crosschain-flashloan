import { describe, it, expect } from 'vitest'
import { SuperWallet as Wallet, getSuperContract } from 'superchain-starter'
import { config } from './config'
import { TOKEN_ABI, TOKEN_BYTECODE } from './contracts'
import { setTimeout } from 'timers/promises'

// Bridge ABI - from ISuperchainTokenBridge
const BRIDGE_ABI = [{
    "inputs": [
        {"internalType": "address", "name": "_token", "type": "address"},
        {"internalType": "address", "name": "_to", "type": "address"},
        {"internalType": "uint256", "name": "_amount", "type": "uint256"},
        {"internalType": "uint256", "name": "_chainId", "type": "uint256"}
    ],
    "name": "sendERC20",
    "outputs": [{"internalType": "bytes32", "name": "msgHash_", "type": "bytes32"}],
    "stateMutability": "nonpayable",
    "type": "function"
}]

describe('CrosschainFlashLoanToken Integration Tests', () => {
    const PRIVATE_KEY = '0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80' as const
    const wallet = new Wallet(PRIVATE_KEY)
    const token = getSuperContract(
        config,
        wallet,
        TOKEN_ABI,
        TOKEN_BYTECODE,
        [wallet.getAccount().address], // Pass owner address to constructor
    )
    
    const bridge = getSuperContract(
        config,
        wallet,
        BRIDGE_ABI,
        '0x' as `0x${string}`, // Empty bytecode since it's already deployed
        [], // No constructor args needed
        undefined, // No salt needed
        '0x4200000000000000000000000000000000000028' // Pre-deployed bridge address
    )

    it('should deploy token on both chains and perform cross-chain transfer', async () => {
        // Deploy on chain 901
        await token.deploy(901)
        const isDeployed901 = await token.isDeployed(901)

        // Deploy on chain 902
        await token.deploy(902)
        const isDeployed902 = await token.isDeployed(902)

        // Verify both deployments succeeded
        expect(isDeployed901).toBe(true)
        expect(isDeployed902).toBe(true)

        // First mint some tokens on chain 901 as owner
        const amount = 1000n
        await token.sendTx(901, 'mint', [wallet.getAccount().address, amount])

        // Get initial balance on chain 902
        const initialBalance = await token.call(902, 'balanceOf', [wallet.getAccount().address])

        // Send tokens from chain 901 to 902 using the bridge
        await bridge.sendTx(901, 'sendERC20', [
            token.address,
            wallet.getAccount().address,
            amount,
            902n
        ])

        // Wait for cross-chain message to be processed
        await setTimeout(5000)

        // Check final balance on chain 902
        const finalBalance = await token.call(902, 'balanceOf', [wallet.getAccount().address])

        // Verify the balance increased by the sent amount
        expect(finalBalance - initialBalance).toBe(amount)
    }, 30000) // Increase timeout to 30 seconds for this test
}) 