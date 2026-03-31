"use client";

import type { NextPage } from "next";
import { useAccount } from "wagmi";
import { RainbowKitCustomConnectButton } from "~~/components/scaffold-eth";
import { TreasuryDashboard } from "~~/components/treasury/TreasuryDashboard";

const Home: NextPage = () => {
  const { isConnected } = useAccount();

  return (
    <div className="flex flex-col items-center flex-grow pt-10">
      <div className="px-5 w-full max-w-6xl">
        <h1 className="text-center mb-2">
          <span className="block text-4xl font-bold">TreasuryManager V2</span>
          <span className="block text-lg text-base-content/70 mt-1">Market Cap Treasury Management</span>
        </h1>

        {!isConnected ? (
          <div className="flex flex-col items-center gap-4 mt-12">
            <p className="text-base-content/60 text-lg">Connect your wallet to manage the treasury</p>
            <RainbowKitCustomConnectButton />
          </div>
        ) : (
          <TreasuryDashboard />
        )}
      </div>
    </div>
  );
};

export default Home;
