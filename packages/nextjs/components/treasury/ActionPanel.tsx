"use client";

import { useState } from "react";
import { AddressInput } from "@scaffold-ui/components";
import { formatEther, parseEther } from "viem";
import { useAccount } from "wagmi";
import { useScaffoldReadContract, useScaffoldWriteContract } from "~~/hooks/scaffold-eth";

const ACTION_TYPES = ["BuybackWETH", "BuybackUSDC", "Burn", "Stake", "RebalanceWETH", "RebalanceUSDC"] as const;

export const ActionPanel = () => {
  const { address: connectedAddress } = useAccount();
  const [tokenAddress, setTokenAddress] = useState("");
  const [actionType, setActionType] = useState(0);
  const [amount, setAmount] = useState("");
  const [gasEstimate, setGasEstimate] = useState("");
  const [isExecuting, setIsExecuting] = useState(false);

  // Buyback recording
  const [buybackToken, setBuybackToken] = useState("");
  const [ethSpent, setEthSpent] = useState("");
  const [tokensReceived, setTokensReceived] = useState("");
  const [isRecording, setIsRecording] = useState(false);

  const { data: operator } = useScaffoldReadContract({
    contractName: "TreasuryManagerV2",
    functionName: "operator",
  });

  const { writeContractAsync: executeAction } = useScaffoldWriteContract("TreasuryManagerV2");
  const { writeContractAsync: recordBuyback } = useScaffoldWriteContract("TreasuryManagerV2");

  const isOperator = connectedAddress && operator && connectedAddress.toLowerCase() === operator.toLowerCase();

  const { data: remainingCap } = useScaffoldReadContract({
    contractName: "TreasuryManagerV2",
    functionName: "getRemainingDailyCap",
    args: [tokenAddress || "0x0000000000000000000000000000000000000000", actionType],
  });

  const { data: cooldownRemaining } = useScaffoldReadContract({
    contractName: "TreasuryManagerV2",
    functionName: "getCooldownRemaining",
    args: [tokenAddress || "0x0000000000000000000000000000000000000000", actionType],
  });

  const handleExecute = async () => {
    if (!tokenAddress || !amount) return;
    setIsExecuting(true);
    try {
      await executeAction({
        functionName: "executeAction",
        args: [tokenAddress, actionType, parseEther(amount), BigInt(gasEstimate || "0")],
      });
      setAmount("");
      setGasEstimate("");
    } catch (e) {
      console.error("Action failed:", e);
    } finally {
      setIsExecuting(false);
    }
  };

  const handleRecordBuyback = async () => {
    if (!buybackToken || !ethSpent || !tokensReceived) return;
    setIsRecording(true);
    try {
      await recordBuyback({
        functionName: "recordBuyback",
        args: [buybackToken, parseEther(ethSpent), parseEther(tokensReceived)],
      });
      setEthSpent("");
      setTokensReceived("");
    } catch (e) {
      console.error("Record buyback failed:", e);
    } finally {
      setIsRecording(false);
    }
  };

  if (!isOperator) {
    return (
      <div className="bg-base-100 rounded-xl p-8 text-center shadow">
        <p className="text-base-content/60 text-lg">Only the operator can execute actions</p>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      {/* Execute Action */}
      <div className="bg-base-100 rounded-xl p-6 shadow">
        <h2 className="text-xl font-bold mb-4">Execute Action</h2>

        <div className="space-y-4">
          <div>
            <label className="label">
              <span className="label-text">Token Address</span>
            </label>
            <AddressInput value={tokenAddress} onChange={setTokenAddress} placeholder="0x..." />
          </div>

          <div>
            <label className="label">
              <span className="label-text">Action Type</span>
            </label>
            <select
              className="select select-bordered w-full"
              value={actionType}
              onChange={e => setActionType(Number(e.target.value))}
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
              <span className="label-text">Amount (tokens)</span>
            </label>
            <input
              type="text"
              className="input input-bordered w-full"
              value={amount}
              onChange={e => setAmount(e.target.value)}
              placeholder="0.0"
            />
          </div>

          <div>
            <label className="label">
              <span className="label-text">Gas Estimate (optional)</span>
            </label>
            <input
              type="text"
              className="input input-bordered w-full"
              value={gasEstimate}
              onChange={e => setGasEstimate(e.target.value)}
              placeholder="0"
            />
          </div>

          {/* Status info */}
          {tokenAddress && (
            <div className="flex gap-4 text-sm text-base-content/70">
              <span>Daily Cap Remaining: {remainingCap ? formatEther(remainingCap) : "—"}</span>
              <span>
                Cooldown:{" "}
                {cooldownRemaining && cooldownRemaining > 0n
                  ? `${Math.ceil(Number(cooldownRemaining) / 60)}min`
                  : "Ready"}
              </span>
            </div>
          )}

          <button
            className="btn btn-primary w-full"
            onClick={handleExecute}
            disabled={isExecuting || !tokenAddress || !amount || (cooldownRemaining != null && cooldownRemaining > 0n)}
          >
            {isExecuting && <span className="loading loading-spinner loading-sm mr-2" />}
            {isExecuting ? "Executing..." : "Execute Action"}
          </button>
        </div>
      </div>

      {/* Record Buyback */}
      <div className="bg-base-100 rounded-xl p-6 shadow">
        <h2 className="text-xl font-bold mb-4">Record Buyback</h2>

        <div className="space-y-4">
          <div>
            <label className="label">
              <span className="label-text">Token Address</span>
            </label>
            <AddressInput value={buybackToken} onChange={setBuybackToken} placeholder="0x..." />
          </div>

          <div>
            <label className="label">
              <span className="label-text">ETH Spent</span>
            </label>
            <input
              type="text"
              className="input input-bordered w-full"
              value={ethSpent}
              onChange={e => setEthSpent(e.target.value)}
              placeholder="0.0"
            />
          </div>

          <div>
            <label className="label">
              <span className="label-text">Tokens Received</span>
            </label>
            <input
              type="text"
              className="input input-bordered w-full"
              value={tokensReceived}
              onChange={e => setTokensReceived(e.target.value)}
              placeholder="0.0"
            />
          </div>

          <button
            className="btn btn-secondary w-full"
            onClick={handleRecordBuyback}
            disabled={isRecording || !buybackToken || !ethSpent || !tokensReceived}
          >
            {isRecording && <span className="loading loading-spinner loading-sm mr-2" />}
            {isRecording ? "Recording..." : "Record Buyback"}
          </button>
        </div>
      </div>
    </div>
  );
};
