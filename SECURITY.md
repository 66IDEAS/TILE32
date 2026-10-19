# Security Policy

Report security vulnerabilities privately through GitHub Security Advisories.
Do not include window titles, screenshots of private windows, or user paths in a
public issue.

Only the latest released TILE32 version receives security fixes. TILE32 holds
the Accessibility permission, so changes must keep its footprint narrow: no
network access, no telemetry, no reading of window content, no window titles in
release logs, and undocumented macOS functions used read-only and only for
Spaces and window numbers. The app is signed with the hardened runtime and no
extra entitlements; keep it that way.
