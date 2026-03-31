"use client";

import { Address } from "@scaffold-ui/components";
import { formatEther } from "viem";
import { useScaffoldReadContract } from "~~/hooks/scaffold-eth";

const ACTION_TYPES = ["BuybackWETH", "BuybackUSDC", "Burn", "Stake", "RebalanceWETH", "RebalanceUSDC"] as const;

const TokenCard = ({ tokenAddress }: { tokenAddress: string }) => {
  const { data: marketCap } = useScaffoldReadContract({
    contractName: "TreasuryManagerV2",
    functionName: "getMarketCap",
    args: [tokenAddress],
  });

  const { data: weightedAvgCost } = useScaffoldReadContract({
    contractName: "TreasuryManagerV2",
    functionName: "getWeightedAverageCost",
    args: [tokenAddress],
  });

  const { data: tokenConfig } = useScaffoldReadContract({
    contractName: "TreasuryManagerV2",
    functionName: "tokenConfigs",
    args: [tokenAddress],
  });

  const { data: emergencyState } = useScaffoldReadContract({
    contractName: "TreasuryManagerV2",
    functionName: "emergencyStates",
    args: [tokenAddress],
  });

  const { data: emergencyAllowance } = useScaffoldReadContract({
    contractName: "TreasuryManagerV2",
    functionName: "getEmergencyAllowance",
    args: [tokenAddress],
  });

  const isEmergency = emergencyState?.[1]; // active field

  return (
    <div className="bg-base-100 rounded-xl p-6 shadow">
      <div className="flex items-center justify-between mb-4">
        <div>
          <p className="text-sm text-base-content/60 mb-1">Token</p>
          <Address address={tokenAddress} />
        </div>
        {isEmergency && <span className="badge badge-error animate-pulse">🚨 EMERGENCY</span>}
      </div>

      <div className="grid grid-cols-2 gap-4 mt-4">
        <div>
          <p className="text-sm text-base-content/60">Market Cap</p>
          <p className="text-lg font-semibold">{marketCap ? `${formatEther(marketCap)} ETH` : "—"}</p>
        </div>
        <div>
          <p className="text-sm text-base-content/60">Weighted Avg Cost</p>
          <p className="text-lg font-semibold">{weightedAvgCost ? `${formatEther(weightedAvgCost)} ETH/token` : "—"}</p>
        </div>
        <div>
          <p className="text-sm text-base-content/60">Total ETH Spent</p>
          <p className="text-lg font-semibold">{tokenConfig?.[3] ? formatEther(tokenConfig[3]) : "0"} ETH</p>
        </div>
        <div>
          <p className="text-sm text-base-content/60">Total Tokens Received</p>
          <p className="text-lg font-semibold">{tokenConfig?.[4] ? formatEther(tokenConfig[4]) : "0"}</p>
        </div>
      </div>

      {isEmergency && (
        <div className="mt-4 p-3 bg-error/10 rounded-lg">
          <p className="text-sm font-semibold text-error">Emergency Mode Active</p>
          <p className="text-sm text-base-content/70">
            Emergency Allowance: {emergencyAllowance ? formatEther(emergencyAllowance) : "0"} tokens
          </p>
        </div>
      )}

      {/* Cooldown status for each action type */}
      <div className="mt-4">
        <p className="text-sm text-base-content/60 mb-2">Action Cooldowns</p>
        <div className="flex flex-wrap gap-2">
          {ACTION_TYPES.map((actionName, idx) => (
            <CooldownBadge key={actionName} tokenAddress={tokenAddress} actionType={idx} actionName={actionName} />
          ))}
        </div>
      </div>
    </div>
  );
};

const CooldownBadge = ({
  tokenAddress,
  actionType,
  actionName,
}: {
  tokenAddress: string;
  actionType: number;
  actionName: string;
}) => {
  const { data: remaining } = useScaffoldReadContract({
    contractName: "TreasuryManagerV2",
    functionName: "getCooldownRemaining",
    args: [tokenAddress, actionType],
  });

  const cooldownActive = remaining && remaining > 0n;

  return (
    <span className={`badge badge-sm ${cooldownActive ? "badge-warning" : "badge-success"}`}>
      {actionName}: {cooldownActive ? `${Math.ceil(Number(remaining) / 3600)}h` : "Ready"}
    </span>
  );
};

export const TokenPanel = () => {
  const { data: managedTokens } = useScaffoldReadContract({
    contractName: "TreasuryManagerV2",
    functionName: "getManagedTokens",
  });

  if (!managedTokens || managedTokens.length === 0) {
    return (
      <div className="bg-base-100 rounded-xl p-8 text-center shadow">
        <p className="text-base-content/60 text-lg">No managed tokens yet</p>
        <p className="text-base-content/40 mt-2">The owner needs to add tokens via the Admin panel</p>
      </div>
    );
  }

  return (
    <div className="space-y-4">
      {managedTokens.map((tokenAddr: string) => (
        <TokenCard key={tokenAddr} tokenAddress={tokenAddr} />
      ))}
    </div>
  );
};
