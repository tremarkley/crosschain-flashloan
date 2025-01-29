// Import contract artifacts
import { abi as tokenAbi } from '../../out/CrosschainFlashLoanToken.sol/CrosschainFlashLoanToken.json'
import { bytecode as rawBytecode } from '../../out/CrosschainFlashLoanToken.sol/CrosschainFlashLoanToken.json'

export const TOKEN_ABI = tokenAbi
export const TOKEN_BYTECODE = `0x${rawBytecode.object.replace(/^0x/, '')}` as `0x${string}` 