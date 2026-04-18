import { NextResponse } from "next/server";

export async function GET() {
  const base = process.env.CORE_AGENT_URL ?? "http://core-agent:8804";
  const resp = await fetch(`${base}/api/reflection`, { cache: "no-store" });
  const text = await resp.text();
  return new NextResponse(text, {
    status: resp.status,
    headers: { "content-type": resp.headers.get("content-type") ?? "application/json" },
  });
}


