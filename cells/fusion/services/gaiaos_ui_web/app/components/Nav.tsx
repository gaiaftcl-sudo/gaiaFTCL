"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { WalletConnect } from "./WalletConnect";

const tabs = [
  { href: "/", label: "Dashboard" },
  { href: "/games", label: "Games" },
  { href: "/atmosphere", label: "Atmosphere" },
  { href: "/ocean", label: "Ocean" },
  { href: "/biosphere", label: "Biosphere" },
  { href: "/molecular", label: "Molecular" },
  { href: "/astro", label: "Astro" },
  { href: "/entropy/aviation", label: "Entropy" },
  { href: "/atc/turbulence", label: "Turbulence" },
  { href: "/closure-proof", label: "Closure Proof" },
  { href: "/closure-game", label: "Closure Game" },
  { href: "/domain-tubes", label: "Domain Tubes" },
  { href: "/sovereign-mesh", label: "Sovereign mesh" },
  { href: "/moor", label: "Type I moor" },
];

export function Nav() {
  const path = usePathname();
  return (
    <div className="border-b border-zinc-800 bg-black/70 backdrop-blur">
      <div className="mx-auto flex max-w-6xl items-center gap-3 px-4 py-3">
        <div className="text-sm font-semibold text-white">GaiaOS Multi-Substrate Digital Twin</div>
        <div className="ml-auto flex flex-wrap items-center gap-3">
          <WalletConnect />
          <div className="flex flex-wrap gap-2">
            {tabs.map((t) => {
              const active = path === t.href;
              return (
                <Link
                  key={t.href}
                  href={t.href}
                  className={[
                    "rounded-md px-3 py-1 text-xs font-medium",
                    active ? "bg-emerald-600 text-black" : "bg-zinc-900 text-zinc-200 hover:bg-zinc-800",
                  ].join(" ")}
                >
                  {t.label}
                </Link>
              );
            })}
          </div>
        </div>
      </div>
    </div>
  );
}


