import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../presentation/providers/members_provider.dart';

class RadarInfoPanel extends StatelessWidget {
  const RadarInfoPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<MembersProvider>(
      builder: (context, provider, _) {
        final leaderText = provider.leaderId ?? 'Đang chờ...';
        final sweeperText = provider.sweeperId ?? 'Đang chờ...';
        final distanceText = provider.leaderSweeperDistance.isEmpty
            ? 'Chờ Leader & Sweeper...'
            : 'Khoảng cách: ${provider.leaderSweeperDistance}';

        final distanceColor = provider.alert.isLeaderSweeperFar
            ? Colors.red.shade700
            : Colors.black87;

        return Positioned(
          bottom: 24,
          left: 16,
          right: 16,
          child: Card(
            color: Colors.white.withOpacity(0.95),
            elevation: 8,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          children: [
                            const Text(
                              'Leader',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              leaderText,
                              style: const TextStyle(
                                color: Colors.blue,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),

                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Icon(
                          Icons.compare_arrows,
                          color: Colors.grey.shade400,
                          size: 24,
                        ),
                      ),

                      Expanded(
                        child: Column(
                          children: [
                            const Text(
                              'Sweeper',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              sweeperText,
                              style: const TextStyle(
                                color: Colors.green,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Container(height: 1, color: Colors.grey.shade300),
                  ),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          distanceText,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: distanceColor,
                            fontSize: 13,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Icon(
                          provider.alert.isLeaderSweeperFar
                              ? Icons.warning_rounded
                              : Icons.check_circle_rounded,
                          color: provider.alert.isLeaderSweeperFar
                              ? Colors.red.shade700
                              : Colors.green,
                          size: 20,
                        ),
                      ),
                    ],
                  ),

                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Row(
                      children: [
                        Icon(
                          Icons.group,
                          color: Colors.grey.shade600,
                          size: 18,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${provider.totalMembers} thành viên',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
