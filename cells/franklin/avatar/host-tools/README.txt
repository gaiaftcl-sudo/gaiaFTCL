Host-built CLIs shipped so sprout Gates E–F can run on a fresh clone without a full Rust workspace checkout.

darwin-arm64/sign_bundle — cargo release build of tools/sign_bundle.
darwin-arm64/verify_bundle — cargo release build of tools/verify_bundle (plan phase 0).

Intel Mac / Linux: build target/release/{sign_bundle,verify_bundle} from the full avatar Cargo workspace, or add host-tools/<platform>/ copies the same way.
