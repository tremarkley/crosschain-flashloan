import { useState, useEffect } from 'react'
import { SuperWallet as Wallet, getSuperContract } from 'superchain-starter'
import { config } from './config'
import { TOKEN_ABI, TOKEN_BYTECODE } from './contracts'
import './App.css'

// Default Anvil private key
const PRIVATE_KEY = '0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80' as `0x${string}`

function App() {
  const [balance, setBalance] = useState<string>('0')
  const [mintAmount, setMintAmount] = useState<string>('')
  const [burnAmount, setBurnAmount] = useState<string>('')
  const [status, setStatus] = useState<string>('')

  // Initialize wallet and contract
  const wallet = new Wallet(PRIVATE_KEY)
  const contract = getSuperContract(
    config,
    wallet,
    TOKEN_ABI,
    TOKEN_BYTECODE,
    [wallet.getAccount().address], // Pass owner address to constructor
  )

  useEffect(() => {
    const loadBalance = async () => {
      try {
        if (await contract.isDeployed(901)) {
          const result = await contract.call(901, 'balanceOf', [wallet.getAccount().address])
          setBalance(result.toString())
        } else {
          setStatus('Contract not deployed')
        }
      } catch (error) {
        console.error('Error loading balance:', error)
        setStatus('Error loading balance')
      }
    }

    loadBalance()
  }, [])

  const handleMint = async () => {
    try {
      setStatus('Minting...')
      if (!await contract.isDeployed(901)) {
        await contract.deploy(901)
      }
      await contract.sendTx(901, 'mint', [wallet.getAccount().address, BigInt(mintAmount)])
      setStatus('Minted successfully')
    } catch (error) {
      console.error('Error minting:', error)
      setStatus('Error minting tokens')
    }
  }

  const handleBurn = async () => {
    try {
      setStatus('Burning...')
      await contract.sendTx(901, 'burn', [wallet.getAccount().address, BigInt(burnAmount)])
      setStatus('Burned successfully')
    } catch (error) {
      console.error('Error burning:', error)
      setStatus('Error burning tokens')
    }
  }

  return (
    <div className="container">
      <h1>XChainFlashLoan Token (CXL)</h1>
      <div className="card">
        <h2>Balance: {balance} CXL</h2>
        <div className="form-group">
          <input
            type="number"
            value={mintAmount}
            onChange={(e) => setMintAmount(e.target.value)}
            placeholder="Amount to mint"
          />
          <button onClick={handleMint}>Mint</button>
        </div>
        <div className="form-group">
          <input
            type="number"
            value={burnAmount}
            onChange={(e) => setBurnAmount(e.target.value)}
            placeholder="Amount to burn"
          />
          <button onClick={handleBurn}>Burn</button>
        </div>
        <p className="status">{status}</p>
      </div>
    </div>
  )
}

export default App
