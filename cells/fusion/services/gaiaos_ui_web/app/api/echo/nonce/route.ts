import { NextRequest, NextResponse } from "next/server";

const MCP_BASE_URL = process.env.MCP_BASE_URL || "http://localhost:8901";

export async function POST(request: NextRequest) {
  try {
    const body = await request.json();
    const walletAddress = request.headers.get("X-Wallet-Address")?.trim();
    if (!walletAddress) {
      return NextResponse.json(
        { error: "X-Wallet-Address header required; anonymous calls rejected" },
        { status: 400 }
      );
    }

    const nonce = body.nonce?.trim();
    const agent_id = body.agent_id?.trim() || walletAddress;
    if (!nonce) {
      return NextResponse.json(
        { error: "nonce required" },
        { status: 400 }
      );
    }

    const response = await fetch(`${MCP_BASE_URL}/echo/nonce`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ nonce, agent_id }),
    });

    const data = await response.json();
    return NextResponse.json(data, { status: response.status });
  } catch (error: unknown) {
    return NextResponse.json(
      { error: error instanceof Error ? error.message : "Echo nonce request failed" },
      { status: 500 }
    );
  }
}
