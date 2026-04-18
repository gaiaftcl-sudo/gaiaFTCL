//! Identity Configuration for GaiaFTCL
//!
//! This is the single source of truth for the system's canonical identity.

pub struct IdentityConfig {
    pub canonical_name: &'static str,
    pub short_name: &'static str,
    pub public_aliases: &'static [&'static str],
    pub ui_display_name: &'static str,
    pub legal_notice: &'static str,
    pub founder_id: &'static str,
    pub founder_wallet: &'static str,
}

pub const IDENTITY: IdentityConfig = IdentityConfig {
    canonical_name: "GaiaFTCL",
    short_name: "FTCL",
    public_aliases: &["Gaia", "FTCL"],
    ui_display_name: "GaiaFTCL",
    legal_notice: "Trademark Safe. No third-party conflict.",
    founder_id: "FOUNDER_RICK",
    founder_wallet: "bc1q9573473rk54x3jdehz0n7kefrz3yygevntndfq",
};
