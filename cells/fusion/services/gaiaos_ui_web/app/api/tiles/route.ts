import { NextRequest, NextResponse } from "next/server";

export async function GET(req: NextRequest) {
  const base = process.env.CORE_AGENT_URL ?? "http://core-agent:8804";
  const url = new URL(req.url);
  const qs = url.searchParams.toString();
  const resp = await fetch(`${base}/api/tiles/recent${qs ? `?${qs}` : ""}`, { cache: "no-store" });
  const text = await resp.text();
  return new NextResponse(text, {
    status: resp.status,
    headers: { "content-type": resp.headers.get("content-type") ?? "application/json" },
  });
}


