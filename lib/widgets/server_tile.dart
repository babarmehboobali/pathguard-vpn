import 'package:flutter/material.dart';
import '../models/server.dart';
import '../theme/app_theme.dart';
import '../utils/flag.dart';

class ServerTile extends StatelessWidget {
  final Server server;
  final bool isFavourite;
  final VoidCallback onTap;
  final VoidCallback onFavourite;

  const ServerTile({
    super.key,
    required this.server,
    required this.isFavourite,
    required this.onTap,
    required this.onFavourite,
  });

  @override
  Widget build(BuildContext context) {
    final ping = server.measuredPing ?? server.ping;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: ListTile(
        leading: Text(flagEmoji(server.countryShort), style: const TextStyle(fontSize: 32)),
        title: Text(server.countryLong, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text('${server.hostName} · ${ping}ms · ${server.numVpnSessions} sessions'),
        trailing: IconButton(
          icon: Icon(isFavourite ? Icons.star : Icons.star_border,
              color: isFavourite ? AppTheme.accentStart : null),
          onPressed: onFavourite,
        ),
        onTap: onTap,
      ),
    );
  }
}
