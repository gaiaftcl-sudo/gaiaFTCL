import { NextRequest, NextResponse } from "next/server";

function entropyBase(): string {
  // Server-side only; proxy keeps browser same-origin and avoids exposing internal network topology.
  return process.env.ENTROPY_API_URL ?? "http://entropy-api:8800";
}

export async function GET(req: NextRequest, ctx: { params: Promise<{ path: string[] }> }) {
  const base = entropyBase().replace(/\/+$/, "");
  const url = new URL(req.url);
  const qs = url.searchParams.toString();
  const p = await ctx.params;
  const path = (p.path ?? []).map(encodeURIComponent).join("/");

  // Our public API surface is /api/entropy/*; upstream service exposes /api/entropy/*.
  const upstream = `${base}/api/entropy/${path}${qs ? `?${qs}` : ""}`;
  const resp = await fetch(upstream, { cache: "no-store" });
  const text = await resp.text();
  return new NextResponse(text, {
    status: resp.status,
    headers: { "content-type": resp.headers.get("content-type") ?? "application/json" },
  });
}


