"use client";

import { useState } from "react";
import { AddressInput } from "@scaffold-ui/components";
import { parseEther } from "viem";
import { useScaffoldWriteContract } from "~~/hooks/scaffold-eth";

const ACTION_TYPES = ["BuybackWETH", "BuybackUSDC", "Burn", "Stake", "RebalanceWETH", "RebalanceUSDC"] as const;

export const AdminPanel = () => {
  // Add Token
  const [newTokenAddress, setNewTokenAddress] = useState("");
  const [poolAddress, setPoolAddress] = useState("");
  const [twapInterval, setTwapInterval] = useState("86400");
  const [isAddingToken, setIsAddingToken] = useState(false);

  // Set Operator
  const [newOperator, setNewOperator] = useState("");
  const [isSettingOperator, setIsSettingOperator] = useState(false);

  // Set Action Config
  const [configToken, setConfigToken] = useState("");
  const [configActionType, setConfigActionType] = useState(0);
  const [dailyCap, setDailyCap] = useState("");
  const [dailyUGas, setDailyUGas] = useState("");
  const [isSettingConfig, setIsSettingConfig] = useState(false);

  // Withdraw
  const [withdrawTokenAddr, setWithdrawTokenAddr] = useState("");
  const [withdrawTo, setWithdrawTo] = useState("");
  const [withdrawAmount, setWithdrawAmount] = useState("");
  const [isWithdrawing, setIsWithdrawing] = useState(false);

  // ETH Withdraw
  const [ethWithdrawTo, setEthWithdrawTo] = useState("");
  const [ethWithdrawAmount, setEthWithdrawAmount] = useState("");
  const [isWithdrawingETH, setIsWithdrawingETH] = useState(false);

  const { writeContractAsync: addTokenTx } = useScaffoldWriteContract("TreasuryManagerV2");
  const { writeContractAsync: setOperatorTx } = useScaffoldWriteContract("TreasuryManagerV2");
  const { writeContractAsync: setActionConfigTx } = useScaffoldWriteContract("TreasuryManagerV2");
  const { writeContractAsync: withdrawTokenTx } = useScaffoldWriteContract("TreasuryManagerV2");
  const { writeContractAsync: withdrawETHTx } = useScaffoldWriteContract("TreasuryManagerV2");

  const handleAddToken = async () => {
    if (!newTokenAddress) return;
    setIsAddingToken(true);
    try {
      await addTokenTx({
        functionName: "addToken",
        args: [newTokenAddress, poolAddress || "0x0000000000000000000000000000000000000000", Number(twapInterval)],
      });
      setNewTokenAddress("");
      setPoolAddress("");
    } catch (e) {
      console.error("Add token failed:", e);
    } finally {
      setIsAddingToken(false);
    }
  };

  const handleSetOperator = async () => {
    if (!newOperator) return;
    setIsSettingOperator(true);
    try {
      await setOperatorTx({
        functionName: "setOperator",
        args: [newOperator],
      });
      setNewOperator("");
    } catch (e) {
      console.error("Set operator failed:", e);
    } finally {
      setIsSettingOperator(false);
    }
  };

  const handleSetActionConfig = async () => {
    if (!configToken) return;
    setIsSettingConfig(true);
    try {
      await setActionConfigTx({
        functionName: "setActionConfig",
        args: [configToken, configActionType, dailyCap ? parseEther(dailyCap) : 0n, BigInt(dailyUGas || "0"), true],
      });
    } catch (e) {
      console.error("Set action config failed:", e);
    } finally {
      setIsSettingConfig(false);
    }
  };

  const handleWithdrawToken = async () => {
    if (!withdrawTokenAddr || !withdrawTo || !withdrawAmount) return;
    setIsWithdrawing(true);
    try {
      await withdrawTokenTx({
        functionName: "withdrawToken",
        args: [withdrawTokenAddr, withdrawTo, parseEther(withdrawAmount)],
      });
      setWithdrawAmount("");
    } catch (e) {
      console.error("Withdraw failed:", e);
    } finally {
      setIsWithdrawing(false);
    }
  };

  const handleWithdrawETH = async () => {
    if (!ethWithdrawTo || !ethWithdrawAmount) return;
    setIsWithdrawingETH(true);
    try {
      await withdrawETHTx({
        functionName: "withdrawETH",
        args: [ethWithdrawTo, parseEther(ethWithdrawAmount)],
      });
      setEthWithdrawAmount("");
    } catch (e) {
      console.error("ETH Withdraw failed:", e);
    } finally {
      setIsWithdrawingETH(false);
    }
  };

  return (
    <div className="space-y-6">
      {/* Set Operator */}
      <div className="bg-base-100 rounded-xl p-6 shadow">
        <h2 className="text-xl font-bold mb-4">Set Operator</h2>
        <div className="space-y-3">
          <AddressInput value={newOperator} onChange={setNewOperator} placeholder="New operator address" />
          <button
            className="btn btn-primary w-full"
            onClick={handleSetOperator}
            disabled={isSettingOperator || !newOperator}
          >
            {isSettingOperator && <span className="loading loading-spinner loading-sm mr-2" />}
            {isSettingOperator ? "Setting..." : "Set Operator"}
          </button>
        </div>
      </div>

      {/* Add Token */}
      <div className="bg-base-100 rounded-xl p-6 shadow">
        <h2 className="text-xl font-bold mb-4">Add Token</h2>
        <div className="space-y-3">
          <div>
            <label className="label">
              <span className="label-text">Token Address</span>
            </label>
            <AddressInput value={newTokenAddress} onChange={setNewTokenAddress} placeholder="0x..." />
          </div>
          <div>
            <label className="label">
              <span className="label-text">Uniswap V3 Pool (for TWAP)</span>
            </label>
            <AddressInput value={poolAddress} onChange={setPoolAddress} placeholder="0x... (optional)" />
          </div>
          <div>
            <label className="label">
              <span className="label-text">TWAP Interval (seconds)</span>
            </label>
            <input
              type="text"
              className="input input-bordered w-full"
              value={twapInterval}
              onChange={e => setTwapInterval(e.target.value)}
              placeholder="86400"
            />
          </div>
          <button
            className="btn btn-primary w-full"
            onClick={handleAddToken}
            disabled={isAddingToken || !newTokenAddress}
          >
            {isAddingToken && <span className="loading loading-spinner loading-sm mr-2" />}
            {isAddingToken ? "Adding..." : "Add Token"}
          </button>
        </div>
      </div>

      {/* Configure Action */}
      <div className="bg-base-100 rounded-xl p-6 shadow">
        <h2 className="text-xl font-bold mb-4">Configure Action</h2>
        <div className="space-y-3">
          <div>
            <label className="label">
              <span className="label-text">Token</span>
            </label>
            <AddressInput value={configToken} onChange={setConfigToken} placeholder="0x..." />
          </div>
          <div>
            <label className="label">
              <span className="label-text">Action Type</span>
            </label>
            <select
              className="select select-bordered w-full"
              value={configActionType}
              onChange={e => setConfigActionType(Number(e.target.value))}
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
              <span className="label-text">Daily Cap (tokens)</span>
            </label>
            <input
              type="text"
              className="input input-bordered w-full"
              value={dailyCap}
              onChange={e => setDailyCap(e.target.value)}
              placeholder="0.0"
            />
          </div>
          <div>
            <label className="label">
              <span className="label-text">Daily Gas Limit</span>
            </label>
            <input
              type="text"
              className="input input-bordered w-full"
              value={dailyUGas}
              onChange={e => setDailyUGas(e.target.value)}
              placeholder="0"
            />
          </div>
          <button
            className="btn btn-primary w-full"
            onClick={handleSetActionConfig}
            disabled={isSettingConfig || !configToken}
          >
            {isSettingConfig && <span className="loading loading-spinner loading-sm mr-2" />}
            {isSettingConfig ? "Configuring..." : "Set Action Config"}
          </button>
        </div>
      </div>

      {/* Withdraw Token */}
      <div className="bg-base-100 rounded-xl p-6 shadow">
        <h2 className="text-xl font-bold mb-4">Withdraw Token</h2>
        <div className="space-y-3">
          <div>
            <label className="label">
              <span className="label-text">Token</span>
            </label>
            <AddressInput value={withdrawTokenAddr} onChange={setWithdrawTokenAddr} placeholder="0x..." />
          </div>
          <div>
            <label className="label">
              <span className="label-text">To</span>
            </label>
            <AddressInput value={withdrawTo} onChange={setWithdrawTo} placeholder="0x..." />
          </div>
          <div>
            <label className="label">
              <span className="label-text">Amount</span>
            </label>
            <input
              type="text"
              className="input input-bordered w-full"
              value={withdrawAmount}
              onChange={e => setWithdrawAmount(e.target.value)}
              placeholder="0.0"
            />
          </div>
          <button
            className="btn btn-warning w-full"
            onClick={handleWithdrawToken}
            disabled={isWithdrawing || !withdrawTokenAddr || !withdrawTo || !withdrawAmount}
          >
            {isWithdrawing && <span className="loading loading-spinner loading-sm mr-2" />}
            {isWithdrawing ? "Withdrawing..." : "Withdraw Token"}
          </button>
        </div>
      </div>

      {/* Withdraw ETH */}
      <div className="bg-base-100 rounded-xl p-6 shadow">
        <h2 className="text-xl font-bold mb-4">Withdraw ETH</h2>
        <div className="space-y-3">
          <div>
            <label className="label">
              <span className="label-text">To</span>
            </label>
            <AddressInput value={ethWithdrawTo} onChange={setEthWithdrawTo} placeholder="0x..." />
          </div>
          <div>
            <label className="label">
              <span className="label-text">Amount (ETH)</span>
            </label>
            <input
              type="text"
              className="input input-bordered w-full"
              value={ethWithdrawAmount}
              onChange={e => setEthWithdrawAmount(e.target.value)}
              placeholder="0.0"
            />
          </div>
          <button
            className="btn btn-warning w-full"
            onClick={handleWithdrawETH}
            disabled={isWithdrawingETH || !ethWithdrawTo || !ethWithdrawAmount}
          >
            {isWithdrawingETH && <span className="loading loading-spinner loading-sm mr-2" />}
            {isWithdrawingETH ? "Withdrawing..." : "Withdraw ETH"}
          </button>
        </div>
      </div>
    </div>
  );
};
