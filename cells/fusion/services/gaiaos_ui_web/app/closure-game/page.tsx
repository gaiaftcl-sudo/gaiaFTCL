"use client";

import { useEffect, useState } from "react";
import { useWallet } from "../context/WalletContext";
import { executeMCPTool } from "../lib/mcp";

type ReportData = {
  total_receipts?: number;
  receipts_by_domain?: Record<string, number>;
  last_10_receipts?: Array<{ domain_id?: string; closure_class?: string; timestamp_utc?: string }>;
  echo_ledger_count?: number;
};

export default function ClosureGamePage() {
  const { walletAddress, isConnected } = useWallet();
  const [report, setReport] = useState<ReportData | null>(null);
  const [err, setErr] = useState<string | null>(null);
  const [claimText, setClaimText] = useState("");
  const [claimResult, setClaimResult] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const [nonce, setNonce] = useState("");
  const [submitEvidenceResult, setSubmitEvidenceResult] = useState<string | null>(null);
  const [verifyResult, setVerifyResult] = useState<{ verified: boolean; evidence_hash?: string; rendered?: string } | null>(null);
  const [receiptResult, setReceiptResult] = useState<string | null>(null);

  useEffect(() => {
    if (!isConnected || !walletAddress) return;
    let stopped = false;
    (async () => {
      try {
        setErr(null);
        const res = await executeMCPTool(walletAddress, "closure_game_report_v1", {});
        if (!stopped && res.result) setReport(res.result as ReportData);
      } catch (e: unknown) {
        if (!stopped) setErr(e instanceof Error ? e.message : String(e));
      }
    })();
    return () => { stopped = true; };
  }, [isConnected, walletAddress]);

  const handleEvaluate = async () => {
    if (!walletAddress || !claimText.trim()) return;
    setLoading(true);
    setClaimResult(null);
    try {
      const res = await executeMCPTool(walletAddress, "closure_evaluate_claim_v1", {
        domain_id: "generic",
        claim_text: claimText.trim(),
        claim_class: "TRUTH_ASSERTION",
      });
      const r = res as { result?: { rendered_text?: string } };
      setClaimResult(r.result?.rendered_text ?? JSON.stringify((res as { result?: unknown }).result));
    } catch (e: unknown) {
      setClaimResult(`Error: ${e instanceof Error ? e.message : String(e)}`);
    } finally {
      setLoading(false);
    }
  };

  const handleSubmitEvidence = async () => {
    if (!walletAddress || !nonce.trim()) return;
    setLoading(true);
    setSubmitEvidenceResult(null);
    try {
      const res = await fetch("/api/echo/nonce", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-Wallet-Address": walletAddress,
        },
        body: JSON.stringify({ nonce: nonce.trim(), agent_id: walletAddress }),
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data.error || "Submit failed");
      setSubmitEvidenceResult(data.recorded ? "Evidence recorded." : JSON.stringify(data));
    } catch (e: unknown) {
      setSubmitEvidenceResult(`Error: ${e instanceof Error ? e.message : String(e)}`);
    } finally {
      setLoading(false);
    }
  };

  const handleVerifyEvidence = async () => {
    if (!walletAddress || !nonce.trim()) return;
    setLoading(true);
    setVerifyResult(null);
    try {
      const res = await executeMCPTool(walletAddress, "closure_verify_evidence_v1", {
        domain_id: "generic",
        evidence_type: "HTTP_ECHO_SINK",
        nonce: nonce.trim(),
        agent_id: walletAddress,
      });
      const r = res as { result?: { verified?: boolean; evidence_hash?: string } };
      const verified = r.result?.verified === true;
      setVerifyResult({
        verified,
        evidence_hash: r.result?.evidence_hash,
        rendered: verified ? `Verified. Hash: ${r.result?.evidence_hash}` : "Not verified.",
      });
    } catch (e: unknown) {
      setVerifyResult({ verified: false, rendered: `Error: ${e instanceof Error ? e.message : String(e)}` });
    } finally {
      setLoading(false);
    }
  };

  const handleGenerateReceipt = async () => {
    if (!walletAddress || !verifyResult?.evidence_hash) return;
    setLoading(true);
    setReceiptResult(null);
    try {
      const res = await executeMCPTool(walletAddress, "closure_generate_receipt_v1", {
        domain_id: "generic",
        closure_class: "PROVISIONAL",
        evidence_hash: verifyResult.evidence_hash,
        residual_entropy: "0.0",
      });
      const r = res as { result?: { rendered_text?: string } };
      setReceiptResult(r.result?.rendered_text ?? JSON.stringify((res as { result?: unknown }).result));
    } catch (e: unknown) {
      setReceiptResult(`Error: ${e instanceof Error ? e.message : String(e)}`);
    } finally {
      setLoading(false);
    }
  };

  if (!isConnected) {
    return (
      <main className="mx-auto max-w-6xl px-4 py-6">
        <div className="rounded-xl border border-amber-800 bg-amber-950/50 p-6 text-amber-200">
          Connect your wallet to use the Closure Game.
        </div>
      </main>
    );
  }

  return (
    <main className="mx-auto max-w-6xl px-4 py-6">
      <div className="mb-4">
        <div className="text-xl font-semibold text-white">Closure Game</div>
        <div className="text-sm text-zinc-400">Evaluate claims, verify evidence, generate receipts. Wallet-anchored.</div>
      </div>

      <div className="grid gap-4 md:grid-cols-2">
        <div className="rounded-xl border border-zinc-800 bg-zinc-950 p-4">
          <div className="text-sm font-semibold text-white">Report</div>
          {err && <div className="mt-2 text-xs text-red-400">{err}</div>}
          {report && (
            <div className="mt-3 space-y-2 text-xs text-zinc-300">
              <div>Echo ledger: {report.echo_ledger_count ?? "—"}</div>
              <div>Total receipts: {report.total_receipts ?? "—"}</div>
              {report.last_10_receipts && report.last_10_receipts.length > 0 && (
                <div>
                  Last receipts:
                  {report.last_10_receipts.slice(0, 5).map((r, i) => (
                    <div key={i} className="mt-1 font-mono">
                      {r.domain_id} / {r.closure_class} @ {r.timestamp_utc}
                    </div>
                  ))}
                </div>
              )}
            </div>
          )}
        </div>

        <div className="rounded-xl border border-zinc-800 bg-zinc-950 p-4">
          <div className="text-sm font-semibold text-white">Evaluate Claim</div>
          <textarea
            value={claimText}
            onChange={(e) => setClaimText(e.target.value)}
            placeholder="Claim text..."
            className="mt-2 w-full rounded-md border border-zinc-700 bg-zinc-900 px-3 py-2 text-sm text-white placeholder-zinc-500"
            rows={3}
          />
          <button
            onClick={handleEvaluate}
            disabled={loading}
            className="mt-2 rounded-md bg-emerald-700 px-3 py-1 text-sm font-medium text-white hover:bg-emerald-600 disabled:opacity-50"
          >
            {loading ? "Evaluating..." : "Evaluate"}
          </button>
          {claimResult && (
            <pre className="mt-3 max-h-40 overflow-auto rounded-md bg-zinc-900 p-3 text-xs text-zinc-300">
              {claimResult}
            </pre>
          )}
        </div>

        <div className="rounded-xl border border-zinc-800 bg-zinc-950 p-4 md:col-span-2">
          <div className="text-sm font-semibold text-white">Submit Evidence</div>
          <p className="mt-1 text-xs text-zinc-400">Post a nonce to the echo sink (agent_id = wallet).</p>
          <div className="mt-2 flex gap-2">
            <input
              type="text"
              value={nonce}
              onChange={(e) => setNonce(e.target.value)}
              placeholder="Nonce (e.g. test_nonce_123)"
              className="flex-1 rounded-md border border-zinc-700 bg-zinc-900 px-3 py-2 text-sm text-white placeholder-zinc-500"
            />
            <button
              onClick={handleSubmitEvidence}
              disabled={loading || !nonce.trim()}
              className="rounded-md bg-emerald-700 px-3 py-1 text-sm font-medium text-white hover:bg-emerald-600 disabled:opacity-50"
            >
              {loading ? "Submitting..." : "Submit"}
            </button>
          </div>
          {submitEvidenceResult && (
            <div className="mt-2 text-xs text-emerald-400">{submitEvidenceResult}</div>
          )}
        </div>

        <div className="rounded-xl border border-zinc-800 bg-zinc-950 p-4">
          <div className="text-sm font-semibold text-white">Verify Evidence</div>
          <p className="mt-1 text-xs text-zinc-400">Verify nonce in ledger (HTTP_ECHO_SINK).</p>
          <button
            onClick={handleVerifyEvidence}
            disabled={loading || !nonce.trim()}
            className="mt-2 rounded-md bg-emerald-700 px-3 py-1 text-sm font-medium text-white hover:bg-emerald-600 disabled:opacity-50"
          >
            {loading ? "Verifying..." : "Verify"}
          </button>
          {verifyResult && (
            <pre className="mt-3 max-h-24 overflow-auto rounded-md bg-zinc-900 p-3 text-xs text-zinc-300">
              {verifyResult.rendered}
            </pre>
          )}
        </div>

        <div className="rounded-xl border border-zinc-800 bg-zinc-950 p-4">
          <div className="text-sm font-semibold text-white">Generate Receipt</div>
          <p className="mt-1 text-xs text-zinc-400">Produce CLOSURE_PERFORMED from evidence hash.</p>
          <button
            onClick={handleGenerateReceipt}
            disabled={loading || !verifyResult?.evidence_hash}
            className="mt-2 rounded-md bg-emerald-700 px-3 py-1 text-sm font-medium text-white hover:bg-emerald-600 disabled:opacity-50"
          >
            {loading ? "Generating..." : "Generate Receipt"}
          </button>
          {receiptResult && (
            <pre className="mt-3 max-h-40 overflow-auto rounded-md bg-zinc-900 p-3 text-xs text-zinc-300">
              {receiptResult}
            </pre>
          )}
        </div>
      </div>
    </main>
  );
}
