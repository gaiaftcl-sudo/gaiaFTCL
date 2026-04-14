#!/usr/bin/env zsh
# Fix test protocols - actor isolation and API corrections

set -e

cd "$(dirname "$0")/.."

echo "Fixing test protocol files..."

# Fix all gameState.requestPlantSwap -> playbackController.requestPlantSwap
find Tests/Protocols -name "*.swift" -exec sed -i '' 's/gameState\.requestPlantSwap/await playbackController.requestPlantSwap/g' {} \;

# Fix enum references to string literals
find Tests/Protocols -name "*.swift" -exec sed -i '' 's/to: \.tokamak/to: "tokamak"/g' {} \;
find Tests/Protocols -name "*.swift" -exec sed -i '' 's/to: \.stellarator/to: "stellarator"/g' {} \;
find Tests/Protocols -name "*.swift" -exec sed -i '' 's/to: \.iter/to: "iter"/g' {} \;
find Tests/Protocols -name "*.swift" -exec sed -i '' 's/to: \.spheromak/to: "spheromak"/g' {} \;
find Tests/Protocols -name "*.swift" -exec sed -i '' 's/to: \.reversed_field/to: "reversed_field"/g' {} \;
find Tests/Protocols -name "*.swift" -exec sed -i '' 's/to: \.magnetic_mirror/to: "magnetic_mirror"/g' {} \;
find Tests/Protocols -name "*.swift" -exec sed -i '' 's/to: \.frc/to: "frc"/g' {} \;
find Tests/Protocols -name "*.swift" -exec sed -i '' 's/to: \.icf_laser/to: "icf_laser"/g' {} \;
find Tests/Protocols -name "*.swift" -exec sed -i '' 's/to: \.icf_z_pinch/to: "icf_z_pinch"/g' {} \;

# Fix gameState.errorBoundaryActive -> add stub property
# Fix gameState.appCrashed -> add stub property

echo "✅ Test protocol files fixed"
