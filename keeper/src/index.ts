import {
  createWalletClient,
  http,
  parseAbi,
  publicActions,
  type Hex,
} from 'viem'
import { privateKeyToAccount } from 'viem/accounts'
import { base } from 'viem/chains'

const client = createWalletClient({
  account: privateKeyToAccount(Bun.env.DEPLOYER_KEY as Hex),
  transport: http(Bun.env.BASE_RPC_URL),
  chain: base,
}).extend(publicActions)

const contract = {
  address: '0x271f0FA3852c9bB8940426A74cb987a354ED2553' as const,
  abi: parseAbi([
    'function rebalance() public',
    'function getLeverageRatio() public view returns (uint256)',
  ]),
}

const leverageRatio = await client.readContract({
  ...contract,
  functionName: 'getLeverageRatio',
})

if (leverageRatio < 1.9e18 || leverageRatio > 2.1e18) {
  await client.writeContract({
    ...contract,
    functionName: 'rebalance',
  })

  console.log('Rebalanced')
} else {
  console.log('Leverage ratio is within acceptable range')
}
