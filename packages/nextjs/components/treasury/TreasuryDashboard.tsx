"use client";

import { useState } from "react";
import { ActionPanel } from "./ActionPanel";
import { AdminPanel } from "./AdminPanel";
import { EmergencyPanel } from "./EmergencyPanel";
import { TokenPanel } from "./TokenPanel";
import { Address } from "@scaffold-ui/components";
import { useAccount } from "wagmi";
import { useScaffoldReadContract } from "~~/hooks/scaffold-eth";

export const TreasuryDashboard = () => {
  const { address: connectedAddress } = useAccount();
  const [activeTab, setActiveTab] = useState<"overview" | "actions" | "emergency" | "admin">("overview");

  const { data: owner } = useScaffoldReadContract({
    contractName: "TreasuryManagerV2",
    functionName: "owner",
  });

  const { data: operator } = useScaffoldReadContract({
    contractName: "TreasuryManagerV2",
    functionName: "operator",
  });

  const { data: managedTokenCount } = useScaffoldReadContract({
    contractName: "TreasuryManagerV2",
    functionName: "getManagedTokenCount",
  });

  const isOwner = connectedAddress && owner && connectedAddress.toLowerCase() === owner.toLowerCase();
  const isOperator = connectedAddress && operator && connectedAddress.toLowerCase() === operator.toLowerCase();

  return (
    <div className="mt-8">
      {/* Contract Info */}
      <div className="bg-base-100 rounded-xl p-6 mb-6 shadow">
        <h2 className="text-xl font-bold mb-4">Contract Info</h2>
        <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
          <div>
            <p className="text-sm text-base-content/60 mb-1">Owner</p>
            {owner && <Address address={owner} />}
          </div>
          <div>
            <p className="text-sm text-base-content/60 mb-1">Operator</p>
            {operator && <Address address={operator} />}
          </div>
          <div>
            <p className="text-sm text-base-content/60 mb-1">Managed Tokens</p>
            <p className="text-lg font-semibold">{managedTokenCount?.toString() || "0"}</p>
          </div>
        </div>
        <div className="mt-3">
          {isOwner && <span className="badge badge-success mr-2">You are Owner</span>}
          {isOperator && <span className="badge badge-info mr-2">You are Operator</span>}
          {!isOwner && !isOperator && <span className="badge badge-warning">Read-only (not owner or operator)</span>}
        </div>
      </div>

      {/* Tabs */}
      <div className="tabs tabs-boxed mb-6 bg-base-100">
        <button
          className={`tab ${activeTab === "overview" ? "tab-active" : ""}`}
          onClick={() => setActiveTab("overview")}
        >
          Overview
        </button>
        <button
          className={`tab ${activeTab === "actions" ? "tab-active" : ""}`}
          onClick={() => setActiveTab("actions")}
        >
          Actions
        </button>
        <button
          className={`tab ${activeTab === "emergency" ? "tab-active" : ""}`}
          onClick={() => setActiveTab("emergency")}
        >
          Emergency
        </button>
        {isOwner && (
          <button className={`tab ${activeTab === "admin" ? "tab-active" : ""}`} onClick={() => setActiveTab("admin")}>
            Admin
          </button>
        )}
      </div>

      {/* Tab Content */}
      {activeTab === "overview" && <TokenPanel />}
      {activeTab === "actions" && <ActionPanel />}
      {activeTab === "emergency" && <EmergencyPanel />}
      {activeTab === "admin" && isOwner && <AdminPanel />}
    </div>
  );
};
