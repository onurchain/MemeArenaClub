# Technical Architecture - Meme Battle Arena

## Smart Contract Design

### Core Contract Architecture
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract MemeBattleArenaV9 is ERC721, ReentrancyGuard, Ownable {
    // Battle structure optimized for gas efficiency
    struct Battle {
        address tokenA;
        address tokenB;
        uint256 endTime;
        bool finalized;
        uint256 totalStakedA;
        uint256 totalStakedB;
        uint256 totalValueA;    // USD value in wei
        uint256 totalValueB;    // USD value in wei
        address creator;
    }
    
    // Mapping for efficient battle and stake tracking
    mapping(uint256 => Battle) public battles;
    mapping(uint256 => mapping(address => mapping(address => uint256))) public userStakes;
    
    // Events for comprehensive logging
    event BattleCreated(uint256 indexed battleId, address tokenA, address tokenB);
    event StakePlaced(uint256 indexed battleId, address user, address token, uint256 amount);
    event BattleFinalized(uint256 indexed battleId, address winningToken);
    event RewardsClaimed(uint256 indexed battleId, address user, uint256 amount);
}
```

### Key Security Features

#### 1. Reentrancy Protection
```solidity
function makeStake(uint256 battleId, address token, uint256 amount, uint256 usdValue) 
    external payable nonReentrant {
    // Protected against reentrancy attacks
    require(msg.value >= STAKING_FEE, "Insufficient fee");
    // Safe external calls after state updates
}
```

#### 2. Trustless Architecture
- **No Emergency Withdrawals:** Contract has no admin withdrawal functions
- **No Pause Mechanism:** Funds cannot be frozen by administrators
- **Automatic Finalization:** Winner determination is purely mathematical
- **Transparent Logic:** All calculations verifiable on-chain

#### 3. Gas Optimization
```solidity
// Packed structs for efficient storage
struct Battle {
    address tokenA;      // 20 bytes
    address tokenB;      // 20 bytes  
    uint256 endTime;     // 32 bytes
    bool finalized;      // 1 byte (packed)
    // Additional fields...
}

// Batch operations to reduce gas costs
function batchClaimRewards(uint256[] calldata battleIds) external {
    for (uint256 i = 0; i < battleIds.length; i++) {
        _claimBattleReward(battleIds[i]);
    }
}
```

## Frontend Web3 Integration

### Modern Wagmi Hooks Implementation
```typescript
// Advanced staking hook with comprehensive error handling
export function useStaking() {
  const { address } = useAccount();
  const { data: balance } = useBalance({ address });
  
  const { writeContract, isPending, error } = useWriteContract({
    mutation: {
      onSuccess: (hash) => {
        toast.success('Stake transaction sent!');
        queryClient.invalidateQueries({ queryKey: ['battles'] });
      },
      onError: (error) => {
        console.error('Staking failed:', error);
        toast.error('Staking failed. Please try again.');
      }
    }
  });

  const stakeTokens = useCallback(async (
    battleId: number,
    tokenAddress: string,
    amount: string,
    decimals: number
  ) => {
    if (!address) throw new Error('Wallet not connected');
    
    // Convert amount to Wei with proper decimal handling
    const amountWei = parseUnits(amount, decimals);
    
    // Calculate USD value using live pricing
    const tokenPrice = await fetchTokenPrice(tokenAddress);
    const usdValue = parseUnits((parseFloat(amount) * tokenPrice).toFixed(6), 18);
    
    writeContract({
      address: CONTRACT_ADDRESS,
      abi: CONTRACT_ABI,
      functionName: 'makeStake',
      args: [battleId, tokenAddress, amountWei, usdValue],
      value: parseUnits('0.001', 18) // 0.001 BNB staking fee
    });
  }, [writeContract, address]);

  return { stakeTokens, isPending, error };
}
```

### Multi-Token Decimal System
```typescript
// Centralized token configuration for 15+ meme tokens
export const TOKEN_DECIMALS: Record<string, number> = {
  '0xba2ae424d960c26247dd6c32edc70b295c744c43': 8,  // DOGE
  '0x2859e4544c4bb03966803b044a93563bd2d0dd4d': 18, // SHIB
  '0x25d887ce7a35172c62febfd67a1856f20faebd00': 18, // PEPE
  '0xfb5b838b6cfeedc2873ab27866079ac55363d37e': 9,  // FLOKI
  '0xa041544fe2be56cce31ebb69102b965e06aace80': 5,  // BONK
  // ... additional tokens
};

// Dynamic decimal handling for different token types
export function getTokenDecimals(tokenAddress: string): number {
  const normalizedAddress = tokenAddress.toLowerCase();
  return TOKEN_DECIMALS[normalizedAddress] || 18;
}

// Safe BigInt conversion with scientific notation support
export function convertToBigInt(amount: string, decimals: number): bigint {
  try {
    // Handle scientific notation (e.g., "5.5222e+22")
    const normalizedAmount = parseFloat(amount).toFixed(decimals);
    return parseUnits(normalizedAmount, decimals);
  } catch (error) {
    throw new Error(`Failed to convert amount: ${amount}`);
  }
}
```

### Real-Time Price Integration
```typescript
// Live token pricing with fallback system
export async function fetchTokenPrice(tokenAddress: string): Promise<number> {
  const coinGeckoId = TOKEN_PRICE_SOURCES[tokenAddress.toLowerCase()];
  
  if (coinGeckoId) {
    try {
      const response = await fetch(
        `https://api.coingecko.com/api/v3/simple/price?ids=${coinGeckoId}&vs_currencies=usd`
      );
      const data = await response.json();
      return data[coinGeckoId]?.usd || FALLBACK_PRICES[tokenAddress.toLowerCase()] || 0;
    } catch (error) {
      console.warn('CoinGecko API failed, using fallback price');
    }
  }
  
  return FALLBACK_PRICES[tokenAddress.toLowerCase()] || 0;
}

// Comprehensive fallback pricing for all supported tokens
const FALLBACK_PRICES: Record<string, number> = {
  '0xba2ae424d960c26247dd6c32edc70b295c744c43': 0.23706,   // DOGE
  '0x2859e4544c4bb03966803b044a93563bd2d0dd4d': 0.00001404, // SHIB
  '0x25d887ce7a35172c62febfd67a1856f20faebd00': 0.00001259, // PEPE
  // ... additional fallback prices
};
```

## Database Schema Design

### Drizzle ORM with Type Safety
```typescript
// Type-safe database schema
export const battles = pgTable('battles', {
  id: serial('id').primaryKey(),
  contract_battle_id: integer('contract_battle_id').notNull().unique(),
  token_a: varchar('token_a', { length: 42 }).notNull(),
  token_b: varchar('token_b', { length: 42 }).notNull(),
  creator_address: varchar('creator_address', { length: 42 }).notNull(),
  end_time: timestamp('end_time').notNull(),
  created_at: timestamp('created_at').defaultNow().notNull(),
  finalized: boolean('finalized').default(false),
});

export const stakes = pgTable('stakes', {
  id: serial('id').primaryKey(),
  battle_id: integer('battle_id').references(() => battles.id),
  user_address: varchar('user_address', { length: 42 }).notNull(),
  token_address: varchar('token_address', { length: 42 }).notNull(),
  amount: varchar('amount', { length: 100 }).notNull(), // Store as string for BigInt
  usd_value: decimal('usd_value', { precision: 20, scale: 6 }),
  transaction_hash: varchar('transaction_hash', { length: 66 }),
  created_at: timestamp('created_at').defaultNow().notNull(),
});

// Type inference for compile-time safety
export type Battle = typeof battles.$inferSelect;
export type NewBattle = typeof battles.$inferInsert;
export type Stake = typeof stakes.$inferSelect;
export type NewStake = typeof stakes.$inferInsert;
```

## Performance Optimizations

### RPC Management System
```typescript
// Multi-RPC failover for reliability
const RPC_ENDPOINTS = [
  'https://rpc.ankr.com/bsc/[API_KEY]',
  'https://bsc-dataseed.binance.org/',
  'https://bsc-dataseed1.binance.org/',
  // ... additional endpoints
];

class RPCManager {
  private currentRPCIndex = 0;
  private errorCounts = new Map<string, number>();
  
  async makeRequest<T>(request: () => Promise<T>): Promise<T> {
    for (let attempt = 0; attempt < RPC_ENDPOINTS.length; attempt++) {
      try {
        return await request();
      } catch (error) {
        await this.switchToNextRPC();
        if (attempt === RPC_ENDPOINTS.length - 1) throw error;
      }
    }
    throw new Error('All RPC endpoints failed');
  }
  
  private async switchToNextRPC() {
    this.currentRPCIndex = (this.currentRPCIndex + 1) % RPC_ENDPOINTS.length;
    await new Promise(resolve => setTimeout(resolve, 100)); // Brief delay
  }
}
```

### Caching Strategy
```typescript
// Intelligent query caching with TanStack Query
export function useBattles() {
  return useQuery({
    queryKey: ['battles'],
    queryFn: fetchAllBattles,
    staleTime: 30000,        // 30 seconds
    cacheTime: 300000,       // 5 minutes
    refetchOnWindowFocus: true,
    refetchInterval: 60000,  // Refresh every minute
  });
}

// Battle-specific caching with dependencies
export function useBattleDetail(battleId: number) {
  return useQuery({
    queryKey: ['battle', battleId],
    queryFn: () => fetchBattleDetail(battleId),
    enabled: !!battleId,
    staleTime: 15000,        // 15 seconds for active battles
  });
}
```

## Security Implementation

### Input Validation & Sanitization
```typescript
// Zod schemas for type-safe validation
const CreateBattleSchema = z.object({
  tokenA: z.string().regex(/^0x[a-fA-F0-9]{40}$/, 'Invalid token address'),
  tokenB: z.string().regex(/^0x[a-fA-F0-9]{40}$/, 'Invalid token address'),
  duration: z.number().min(300).max(15552000), // 5 minutes to 6 months
});

const StakeSchema = z.object({
  battleId: z.number().positive(),
  tokenAddress: z.string().regex(/^0x[a-fA-F0-9]{40}$/),
  amount: z.string().regex(/^\d+(\.\d+)?$/, 'Invalid amount'),
});

// Runtime validation with error handling
export function validateCreateBattle(data: unknown) {
  try {
    return CreateBattleSchema.parse(data);
  } catch (error) {
    if (error instanceof z.ZodError) {
      throw new Error(`Validation failed: ${error.errors[0].message}`);
    }
    throw error;
  }
}
```

### Error Boundary Implementation
```typescript
// Comprehensive error handling
class Web3ErrorBoundary extends Component<Props, State> {
  constructor(props: Props) {
    super(props);
    this.state = { hasError: false, error: null };
  }
  
  static getDerivedStateFromError(error: Error): State {
    return { hasError: true, error };
  }
  
  componentDidCatch(error: Error, errorInfo: ErrorInfo) {
    // Log to monitoring service
    console.error('Web3 Error:', error, errorInfo);
    
    // Handle specific Web3 errors
    if (error.message.includes('User rejected')) {
      toast.error('Transaction cancelled by user');
    } else if (error.message.includes('insufficient funds')) {
      toast.error('Insufficient balance for transaction');
    } else {
      toast.error('An unexpected error occurred');
    }
  }
  
  render() {
    if (this.state.hasError) {
      return <ErrorFallback error={this.state.error} />;
    }
    return this.props.children;
  }
}
```

## Deployment Architecture

### Production Configuration
```typescript
// Environment-specific configuration
const PRODUCTION_CONFIG = {
  contract: {
    address: '0x51Fe2C3Fba638f79BBFb5dc74640b7449Bb77722',
    network: 'bsc-mainnet',
    confirmations: 3,
  },
  rpc: {
    primary: 'https://rpc.ankr.com/bsc/[PREMIUM_KEY]',
    fallbacks: ['https://bsc-dataseed.binance.org/'],
    timeout: 30000,
  },
  database: {
    url: process.env.DATABASE_URL,
    ssl: true,
    maxConnections: 20,
  },
  performance: {
    enableCompression: true,
    cacheHeaders: '1h',
    bundleAnalyzer: false,
  }
};
```

This technical architecture demonstrates advanced Web3 development skills including smart contract security, modern React patterns, type-safe database operations, and production-ready deployment strategies.