import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../presentation/providers/members_provider.dart';

class RadarWarningBanner extends StatelessWidget {
  const RadarWarningBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<MembersProvider>(
      builder: (context, provider, _) {
        if (!provider.hasAlert) {
          return const SizedBox.shrink();
        }

        final warnings = <Widget>[];

        if (provider.alert.isLeaderSweeperFar) {
          warnings.add(
            Row(
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.white,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '⚠️ CHỐT ĐOÀN ĐANG BỊ BỎ XA (${provider.leaderSweeperDistance})',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          );
        }

        if (provider.alert.lostMembers.isNotEmpty) {
          final lostMembersText = provider.alert.lostMembers.join(', ');
          warnings.add(
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  const Icon(
                    Icons.person_off,
                    color: Colors.yellowAccent,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '🚨 TÁCH ĐOÀN: $lostMembersText đang nằm ngoài vùng an toàn!',
                      style: const TextStyle(
                        color: Colors.yellowAccent,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            color: Colors.red.shade800,
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: warnings,
            ),
          ),
        );
      },
    );
  }
}
