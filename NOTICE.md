# NOTICE

PathGuard VPN – Free Proxy includes or depends on the following open-source components:

## ics-openvpn
- Repository: https://github.com/schwabe/ics-openvpn
- License: GNU GPL v2 (with additional terms as stated in its LICENSE)
- Usage: OpenVPN engine for VPN Gate free servers (included as submodule under `android/ovpn/`)

## tor-android / Orbot
- Repository: https://github.com/guardianproject/tor-android
- License: Various (see upstream)
- Usage: Tor privacy mode (via Maven artifact `info.guardianproject:tor-android` + `jtorctl`)

## VPN Gate
- Project: https://www.vpngate.net/ (University of Tsukuba)
- Usage: Public server list and OpenVPN configurations fetched at runtime

## WireGuard Android tunnel library
- Artifact: `com.wireguard.android:tunnel`
- License: Apache License 2.0
- Usage: Optional Fast mode (Cloudflare WARP WireGuard)

This application itself is licensed under the GNU GPL v3.0.
You must publish source code of any derivative works that use the ics-openvpn component.
