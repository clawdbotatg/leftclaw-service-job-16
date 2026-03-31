"use client";

import { useState } from "react";
import { AddressInput } from "@scaffold-ui/components";
import { formatEther, parseEther } from "viem";
import { useAccount } from "wagmi";
import { useScaffoldReadContract, useScaffoldWriteContract } from "~~/hooks/scaffold-eth";

const ACTION_TYPES = ["BuybackWETH", "BuybackUSDC", "Burn", "Stake", "RebalanceWETH", "RebalanceUSDC"] as const;

export const EmergencyPanel = () => {
  const { address: connectedAddress } = useAccount();
  const [tokenAddress, setTokenAddress] = useState("");
  const [emergencyActionType, setEmergencyActionType] = useState(0);
  const [emergencyAmount, setEmergencyAmount] = useState("");
  const [isTriggeringEmergency, setIsTriggeringEmergency] = useState(false);
  const [isExecutingEmergency, setIsExecutingEmergency] = useState(false);
  const [isDeactivating, setIsDeactivating] = useState(false);

  const { data: owner } = useScaffoldReadContract({
    contractName: "TreasuryManagerV2",
    functionName: "owner",
  });

  const { data: operator } = useScaffoldReadContract({
    contractName: "TreasuryManagerV2",
    functionName: "operator",
  });

  const isOwner = connectedAddress && owner && connectedAddress.toLowerCase() === owner.toLowerCase();
  const isOperator = connectedAddress && operator && connectedAddress.toLowerCase() === operator.toLowerCase();
  const canTrigger = isOwner || isOperator;

  const { data: emergencyState } = useScaffoldReadContract({
    contractName: "TreasuryManagerV2",
    functionName: "emergencyStates",
    args: [tokenAddress || "0x0000000000000000000000000000000000000000"],
  });

  const { data: emergencyAllowance } = useScaffoldReadContract({
    contractName: "TreasuryManagerV2",
    functionName: "getEmergencyAllowance",
    args: [tokenAddress || "0x0000000000000000000000000000000000000000"],
  });

  const { data: snapshotBalance } = useScaffoldReadContract({
    contractName: "TreasuryManagerV2",
    functionName: "emergencyTriggerSnapshotBalance",
    args: [tokenAddress || "0x0000000000000000000000000000000000000000"],
  });

  const { writeContractAsync: triggerEmergencyTx } = useScaffoldWriteContract("TreasuryManagerV2");
  const { writeContractAsync: executeEmergencyActionTx } = useScaffoldWriteContract("TreasuryManagerV2");
  const { writeContractAsync: deactivateEmergencyTx } = useScaffoldWriteContract("TreasuryManagerV2");

  const isEmergencyActive = emergencyState?.[1];
  const triggerTimestamp = emergencyState?.[0];

  const handleTriggerEmergency = async () => {
    if (!tokenAddress) return;
    setIsTriggeringEmergency(true);
    try {
      await triggerEmergencyTx({
        functionName: "triggerEmergency",
        args: [tokenAddress],
      });
    } catch (e) {
      console.error("Trigger emergency failed:", e);
    } finally {
      setIsTriggeringEmergency(false);
    }
  };

  const handleExecuteEmergency = async () => {
    if (!tokenAddress || !emergencyAmount) return;
    setIsExecutingEmergency(true);
    try {
      await executeEmergencyActionTx({
        functionName: "executeEmergencyAction",
        args: [tokenAddress, emergencyActionType, parseEther(emergencyAmount)],
      });
      setEmergencyAmount("");
    } catch (e) {
      console.error("Emergency action failed:", e);
    } finally {
      setIsExecutingEmergency(false);
    }
  };

  const handleDeactivate = async () => {
    if (!tokenAddress) return;
    setIsDeactivating(true);
    try {
      await deactivateEmergencyTx({
        functionName: "deactivateEmergency",
        args: [tokenAddress],
      });
    } catch (e) {
      console.error("Deactivate emergency failed:", e);
    } finally {
      setIsDeactivating(false);
    }
  };

  const getElapsedDays = () => {
    if (!triggerTimestamp || triggerTimestamp === 0n) return 0;
    const now = BigInt(Math.floor(Date.now() / 1000));
    const elapsed = now - triggerTimestamp;
    return Number(elapsed) / 86400;
  };

  const getVestingProgress = () => {
    const days = getElapsedDays();
    return Math.min(days / 5, 1) * 100;
  };

  return (
    <div className="space-y-6">
      {/* Token Selection */}
      <div className="bg-base-100 rounded-xl p-6 shadow">
        <h2 className="text-xl font-bold mb-4">🚨 90-Day Emergency Mode</h2>
        <p className="text-sm text-base-content/60 mb-4">
          Emergency mode bypasses ROI checks, market cap checks, and TWAP circuit breaker. Limited to 20% of snapshot
          balance vested over 5 days.
        </p>

        <div>
          <label className="label">
            <span className="label-text">Token Address</span>
          </label>
          <AddressInput value={tokenAddress} onChange={setTokenAddress} placeholder="0x..." />
        </div>
      </div>

      {/* Emergency Status */}
      {tokenAddress && (
        <div className={`bg-base-100 rounded-xl p-6 shadow ${isEmergencyActive ? "border-2 border-error" : ""}`}>
          <h3 className="text-lg font-bold mb-3">Emergency Status</h3>

          {isEmergencyActive ? (
            <div className="space-y-3">
              <div className="flex items-center gap-2">
                <span className="badge badge-error animate-pulse">ACTIVE</span>
                <span className="text-sm text-base-content/70">{getElapsedDays().toFixed(1)} days elapsed</span>
              </div>

              {/* Vesting Progress */}
              <div>
                <div className="flex justify-between text-sm mb-1">
                  <span>Vesting Progress (5 day unlock)</span>
                  <span>{getVestingProgress().toFixed(1)}%</span>
                </div>
                <progress className="progress progress-error w-full" value={getVestingProgress()} max="100" />
              </div>

              <div className="grid grid-cols-2 gap-4 mt-2">
                <div>
                  <p className="text-sm text-base-content/60">Snapshot Balance</p>
                  <p className="font-semibold">{snapshotBalance ? formatEther(snapshotBalance) : "0"} tokens</p>
                </div>
                <div>
                  <p className="text-sm text-base-content/60">Current Allowance</p>
                  <p className="font-semibold">{emergencyAllowance ? formatEther(emergencyAllowance) : "0"} tokens</p>
                </div>
              </div>
            </div>
          ) : (
            <p className="text-base-content/60">Emergency mode is not active for this token</p>
          )}
        </div>
      )}

      {/* Actions */}
      {tokenAddress && canTrigger && (
        <div className="bg-base-100 rounded-xl p-6 shadow">
          <h3 className="text-lg font-bold mb-4">Emergency Actions</h3>

          {!isEmergencyActive ? (
            <button className="btn btn-error w-full" onClick={handleTriggerEmergency} disabled={isTriggeringEmergency}>
              {isTriggeringEmergency && <span className="loading loading-spinner loading-sm mr-2" />}
              {isTriggeringEmergency ? "Triggering..." : "🚨 Trigger Emergency Mode"}
            </button>
          ) : (
            <div className="space-y-4">
              {isOperator && (
                <>
                  <div>
                    <label className="label">
                      <span className="label-text">Action Type</span>
                    </label>
                    <select
                      className="select select-bordered w-full"
                      value={emergencyActionType}
                      onChange={e => setEmergencyActionType(Number(e.target.value))}
                    >
                      {ACTION_TYPES.map((name, idx) => (
                        <option key={name} value={idx}>
                          {name}
                        </option>
                      ))}
                    </select>
                  </div>

                  <div>
                    <label className="label">
                      <span className="label-text">Amount</span>
                    </label>
                    <input
                      type="text"
                      className="input input-bordered w-full"
                      value={emergencyAmount}
                      onChange={e => setEmergencyAmount(e.target.value)}
                      placeholder="0.0"
                    />
                    {emergencyAllowance && (
                      <p className="text-sm text-base-content/50 mt-1">Max: {formatEther(emergencyAllowance)} tokens</p>
                    )}
                  </div>

                  <button
                    className="btn btn-warning w-full"
                    onClick={handleExecuteEmergency}
                    disabled={isExecutingEmergency || !emergencyAmount}
                  >
                    {isExecutingEmergency && <span className="loading loading-spinner loading-sm mr-2" />}
                    {isExecutingEmergency ? "Executing..." : "Execute Emergency Action"}
                  </button>
                </>
              )}

              {isOwner && (
                <button
                  className="btn btn-outline btn-error w-full mt-2"
                  onClick={handleDeactivate}
                  disabled={isDeactivating}
                >
                  {isDeactivating && <span className="loading loading-spinner loading-sm mr-2" />}
                  {isDeactivating ? "Deactivating..." : "Deactivate Emergency"}
                </button>
              )}
            </div>
          )}
        </div>
      )}
    </div>
  );
};
