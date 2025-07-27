// Modern Web3 Integration with Wagmi and RainbowKit
// This showcases advanced Web3 development patterns used in Meme Battle Arena

import { useAccount, useWriteContract, useReadContract } from 'wagmi';
import { parseUnits, formatUnits } from 'viem';
import { toast } from '@/hooks/use-toast';

// Contract configuration with ABI
export const CONTRACT_CONFIG = {
  address: '0x51Fe2C3Fba638f79BBFb5dc74640b7449Bb77722' as const,
  abi: [
    {
      name: 'makeBattle',
      type: 'function',
      stateMutability: 'payable',
      inputs: [
        { name: 'tokenA', type: 'address' },
        { name: 'tokenB', type: 'address' },
        { name: 'duration', type: 'uint256' }
      ]
    },
    {
      name: 'makeStake',
      type: 'function',
      stateMutability: 'payable',
      inputs: [
        { name: 'battleId', type: 'uint256' },
        { name: 'token', type: 'address' },
        { name: 'amount', type: 'uint256' },
        { name: 'usdValue', type: 'uint256' }
      ]
    },
    {
      name: 'takeReward',
      type: 'function',
      stateMutability: 'nonpayable',
      inputs: [{ name: 'battleId', type: 'uint256' }]
    }
  ] as const
};

// Multi-token decimal configuration
export const TOKEN_DECIMALS: Record<string, number> = {
  '0xba2ae424d960c26247dd6c32edc70b295c744c43': 8,  // DOGE
  '0x2859e4544c4bb03966803b044a93563bd2d0dd4d': 18, // SHIB
  '0x25d887ce7a35172c62febfd67a1856f20faebd00': 18, // PEPE
  '0xfb5b838b6cfeedc2873ab27866079ac55363d37e': 9,  // FLOKI
  '0xa041544fe2be56cce31ebb69102b965e06aace80': 5,  // BONK
};

// Advanced staking hook with comprehensive error handling
export function useStaking() {
  const { address } = useAccount();
  
  const { writeContract, isPending, error } = useWriteContract({
    mutation: {
      onSuccess: (hash) => {
        toast({
          title: "Stake Successful!",
          description: `Transaction hash: ${hash}`,
          variant: "default"
        });
      },
      onError: (error) => {
        console.error('Staking failed:', error);
        
        // User-friendly error messages
        if (error.message.includes('User rejected')) {
          toast({
            title: "Transaction Cancelled",
            description: "You cancelled the transaction in your wallet.",
            variant: "destructive"
          });
        } else if (error.message.includes('insufficient funds')) {
          toast({
            title: "Insufficient Balance",
            description: "You don't have enough tokens or BNB for fees.",
            variant: "destructive"
          });
        } else {
          toast({
            title: "Staking Failed",
            description: "Please check your wallet and try again.",
            variant: "destructive"
          });
        }
      }
    }
  });

  const stakeTokens = async (
    battleId: number,
    tokenAddress: string,
    amount: string
  ) => {
    if (!address) throw new Error('Wallet not connected');
    
    // Get token decimals for proper conversion
    const decimals = getTokenDecimals(tokenAddress);
    
    // Convert amount to Wei with correct decimals
    const amountWei = parseUnits(amount, decimals);
    
    // Calculate USD value using live pricing
    const tokenPrice = await fetchTokenPrice(tokenAddress);
    const usdValue = parseUnits((parseFloat(amount) * tokenPrice).toFixed(6), 18);
    
    // Execute staking transaction
    writeContract({
      ...CONTRACT_CONFIG,
      functionName: 'makeStake',
      args: [BigInt(battleId), tokenAddress, amountWei, usdValue],
      value: parseUnits('0.001', 18) // 0.001 BNB staking fee
    });
  };

  return { stakeTokens, isPending, error };
}

// Battle creation hook
export function useCreateBattle() {
  const { writeContract, isPending } = useWriteContract({
    mutation: {
      onSuccess: () => {
        toast({
          title: "Battle Created!",
          description: "Your battle has been created successfully.",
        });
      }
    }
  });

  const createBattle = (tokenA: string, tokenB: string, duration: number) => {
    writeContract({
      ...CONTRACT_CONFIG,
      functionName: 'makeBattle',
      args: [tokenA, tokenB, BigInt(duration)],
      value: parseUnits('0.01', 18) // 0.01 BNB battle creation fee
    });
  };

  return { createBattle, isPending };
}

// Real-time battle data fetching
export function useBattleData(battleId: number) {
  const { data: battleInfo } = useReadContract({
    ...CONTRACT_CONFIG,
    functionName: 'getBattleInfo',
    args: [BigInt(battleId)],
    query: {
      enabled: !!battleId,
      refetchInterval: 30000, // Refresh every 30 seconds
    }
  });

  const { data: battleStats } = useReadContract({
    ...CONTRACT_CONFIG,
    functionName: 'getBattleStats',
    args: [BigInt(battleId)],
    query: {
      enabled: !!battleId,
      refetchInterval: 30000,
    }
  });

  return {
    battleInfo,
    battleStats,
    isLoading: !battleInfo || !battleStats
  };
}

// Token price fetching with fallback system
export async function fetchTokenPrice(tokenAddress: string): Promise<number> {
  const coinGeckoId = TOKEN_PRICE_SOURCES[tokenAddress.toLowerCase()];
  
  if (coinGeckoId) {
    try {
      const response = await fetch(
        `https://api.coingecko.com/api/v3/simple/price?ids=${coinGeckoId}&vs_currencies=usd`,
        { 
          headers: { 
            'Accept': 'application/json',
            'X-Cg-Demo-Api-Key': process.env.VITE_COINGECKO_API_KEY || ''
          }
        }
      );
      
      if (!response.ok) throw new Error('API request failed');
      
      const data = await response.json();
      return data[coinGeckoId]?.usd || FALLBACK_PRICES[tokenAddress.toLowerCase()] || 0;
    } catch (error) {
      console.warn('CoinGecko API failed, using fallback price');
    }
  }
  
  return FALLBACK_PRICES[tokenAddress.toLowerCase()] || 0;
}

// Token utility functions
export function getTokenDecimals(tokenAddress: string): number {
  const normalizedAddress = tokenAddress.toLowerCase();
  return TOKEN_DECIMALS[normalizedAddress] || 18;
}

export function formatTokenAmount(amount: bigint, decimals: number): string {
  const formatted = formatUnits(amount, decimals);
  const num = parseFloat(formatted);
  
  if (num >= 1000000) {
    return (num / 1000000).toFixed(1) + 'M';
  } else if (num >= 1000) {
    return (num / 1000).toFixed(1) + 'K';
  } else if (num >= 1) {
    return num.toFixed(2);
  } else {
    return num.toFixed(6);
  }
}

// RPC management for reliability
const RPC_ENDPOINTS = [
  'https://rpc.ankr.com/bsc/[PREMIUM_KEY]',
  'https://bsc-dataseed.binance.org/',
  'https://bsc-dataseed1.binance.org/'
];

class RPCManager {
  private currentIndex = 0;
  
  async makeRequest<T>(requestFn: () => Promise<T>): Promise<T> {
    for (let attempt = 0; attempt < RPC_ENDPOINTS.length; attempt++) {
      try {
        return await requestFn();
      } catch (error) {
        console.warn(`RPC endpoint ${this.currentIndex} failed, switching...`);
        this.switchEndpoint();
        
        if (attempt === RPC_ENDPOINTS.length - 1) {
          throw error;
        }
      }
    }
    throw new Error('All RPC endpoints failed');
  }
  
  private switchEndpoint() {
    this.currentIndex = (this.currentIndex + 1) % RPC_ENDPOINTS.length;
  }
}

// Price source mapping for CoinGecko API
const TOKEN_PRICE_SOURCES: Record<string, string> = {
  '0xba2ae424d960c26247dd6c32edc70b295c744c43': 'binance-peg-dogecoin',
  '0x2859e4544c4bb03966803b044a93563bd2d0dd4d': 'shiba-inu',
  '0x25d887ce7a35172c62febfd67a1856f20faebd00': 'pepe',
  '0xfb5b838b6cfeedc2873ab27866079ac55363d37e': 'floki',
  '0xa041544fe2be56cce31ebb69102b965e06aace80': 'bonk'
};

// Fallback prices for 100% uptime
const FALLBACK_PRICES: Record<string, number> = {
  '0xba2ae424d960c26247dd6c32edc70b295c744c43': 0.23706,
  '0x2859e4544c4bb03966803b044a93563bd2d0dd4d': 0.00001404,
  '0x25d887ce7a35172c62febfd67a1856f20faebd00': 0.00001259,
  '0xfb5b838b6cfeedc2873ab27866079ac55363d37e': 0.000095,
  '0xa041544fe2be56cce31ebb69102b965e06aace80': 0.00003457
};