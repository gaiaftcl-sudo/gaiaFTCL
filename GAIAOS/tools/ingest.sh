#!/bin/bash
# Conscious Ingestion Launcher
# Runs locally - communicates with Franklin via MCP only

cd "$(dirname "$0")/.."

case "$1" in
    discover)
        python3 tools/conscious_ingestion_orchestrator.py discover
        ;;
    ingest)
        if [ -z "$2" ]; then
            echo "Usage: ./tools/ingest.sh ingest <repo_name>"
            echo "Example: ./tools/ingest.sh ingest FoTProtein"
            exit 1
        fi
        python3 tools/conscious_ingestion_orchestrator.py ingest "$2"
        ;;
    monitor)
        python3 tools/conscious_ingestion_orchestrator.py monitor
        ;;
    status)
        python3 tools/conscious_ingestion_orchestrator.py status | jq .
        ;;
    summary)
        python3 tools/conscious_ingestion_orchestrator.py summary
        ;;
    *)
        echo "🧬 Conscious Ingestion Orchestrator"
        echo ""
        echo "Commands:"
        echo "  ./tools/ingest.sh discover        - List all repositories"
        echo "  ./tools/ingest.sh summary          - Show progress summary"
        echo "  ./tools/ingest.sh ingest <repo>    - Start ingestion"
        echo "  ./tools/ingest.sh monitor          - Live dashboard"
        echo "  ./tools/ingest.sh status           - Franklin's state"
        echo ""
        echo "Repositories: FoTProtein, FoTChemistry, FoTFluidDynamics, FoT8D_results, DomainHarvests"
        echo ""
        echo "Example: ./tools/ingest.sh ingest FoTProtein"
        exit 1
        ;;
esac
