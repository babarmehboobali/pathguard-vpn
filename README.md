# PathGuard VPN – Free Proxy

Free Android VPN and proxy app built with Flutter. Modes:

- **Free Servers** – public OpenVPN servers run by volunteers in the VPN Gate project
- **Tor** and **Stealth** (Tor with obfs4 / Snowflake bridges)
- **WARP** – Cloudflare WARP over WireGuard
- Split tunnelling, no account, no logs

The volunteer servers are operated by third parties, not by PathGuard; do not use them for sensitive activity.

Privacy policy: https://babarmehboobali.github.io/pathguard-vpn/privacy/

Contact: babarmehboobali+pathguard@gmail.com

## Build

```
git submodule update --init --recursive
./tool/fetch_ovpn.sh   # downloads the ics-openvpn engine into android/ovpn (needs swig)
flutter pub get
flutter build apk --release
```

Release signing reads `android/key.properties` (not included). Without key.properties the release APK is signed with a test key (fine for testing, not for Play).
GitHub Actions builds a test APK on every push (see the Releases / Actions tab).

## Credits

- vpngate-connector / [VPN Gate](https://www.vpngate.net/) (University of Tsukuba) – server list and connector
- [ics-openvpn](https://github.com/schwabe/ics-openvpn) (GPL-2.0) – OpenVPN engine
- [tor-android](https://github.com/guardianproject/tor-android) (Guardian Project) – Tor engine
- [IPtProxy](https://github.com/tladesignz/IPtProxy) – obfs4 / Snowflake pluggable transports
- [hev-socks5-tunnel](https://github.com/heiher/hev-socks5-tunnel) (MIT) – tun2socks for Tor modes
- [WireGuard](https://www.wireguard.com/) (wireguard-android, Apache-2.0) – WARP mode

See `NOTICE.md` for details.

## License

Copyright (C) 2026 SmartPath Apps. Licensed under the GNU General Public License v3.0 – see `LICENSE`.
