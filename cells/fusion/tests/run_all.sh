#!/bin/bash
# Run full test suite. Loop stops only when all is 100%.
# Exit 0 = 100% pass. Exit 1 = not 100%, keep fixing.
pytest tests/ -v --tb=short "$@"
EXIT=$?
echo ""
if [ $EXIT -eq 0 ]; then
  echo "=== 100% PASS — Loop stops. All gaps closed. ==="
else
  echo "=== NOT 100% — Loop continues. Fix failures above. ==="
fi
exit $EXIT
