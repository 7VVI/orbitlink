import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/models.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_theme.dart';
import '../app_scope.dart';
import '../widgets/ui_kit.dart';

class SearchOverlay extends StatefulWidget {
  const SearchOverlay({super.key});

  @override
  State<SearchOverlay> createState() => _SearchOverlayState();
}

class _SearchOverlayState extends State<SearchOverlay> {
  final TextEditingController _query = TextEditingController();
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _query.addListener(() => setState(() {}));
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _query.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final q = _query.text.trim().toLowerCase();
    final results = <_SearchHit>[];
    if (q.isNotEmpty &&
        '本机 ${controller.identity.name} ${controller.identity.id}'
            .toLowerCase()
            .contains(q)) {
      results.add(_SearchHit(
        name: controller.identity.name,
        id: controller.displayId,
        isSelf: true,
      ));
    }
    for (final device in controller.config.recents) {
      if (q.isEmpty ||
          device.name.toLowerCase().contains(q) ||
          device.id.contains(q)) {
        results.add(_SearchHit(
          name: device.name,
          id: formatDeviceId(device.id),
          rawId: device.id,
          platform: device.platform,
        ));
      }
    }

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            controller.toggleSearch(false),
      },
      child: Focus(
        autofocus: true,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => controller.toggleSearch(false),
                child: const ColoredBox(color: Color(0x33101828)),
              ),
            ),
            Positioned(
              top: 92,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  width: 560,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.border),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x26101828),
                        blurRadius: 44,
                        offset: Offset(0, 18),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(18, 6, 10, 6),
                        child: Row(
                          children: [
                            const Icon(AppIcons.search,
                                size: 19, color: AppColors.textTertiary),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextField(
                                controller: _query,
                                focusNode: _focus,
                                cursorColor: AppColors.primary,
                                style: const TextStyle(
                                  fontSize: 15,
                                  color: AppColors.textPrimary,
                                  height: 1.5,
                                ),
                                decoration: const InputDecoration(
                                  isDense: true,
                                  filled: false,
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  contentPadding:
                                      EdgeInsets.symmetric(vertical: 14),
                                  hintText: '搜索设备名称或识别码',
                                  hintStyle: TextStyle(
                                    fontSize: 14.5,
                                    color: AppColors.placeholder,
                                  ),
                                ),
                              ),
                            ),
                            if (_query.text.isNotEmpty)
                              AppIconButton(
                                icon: AppIcons.close,
                                size: 16,
                                color: AppColors.textTertiary,
                                onTap: () => _query.clear(),
                              ),
                            Container(
                              margin: const EdgeInsets.only(left: 6),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppColors.surfaceMuted,
                                borderRadius: BorderRadius.circular(5),
                                border: Border.all(color: AppColors.border),
                              ),
                              child: const Text(
                                'ESC',
                                style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.4,
                                  color: AppColors.textTertiary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Hairline(),
                      if (results.isEmpty)
                        _EmptyResult(query: q)
                      else
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 330),
                          child: ListView(
                            shrinkWrap: true,
                            padding: const EdgeInsets.all(8),
                            children: [
                              Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(10, 6, 10, 6),
                                child: Text(
                                  q.isEmpty
                                      ? '最近设备'
                                      : '搜索结果 · ${results.length}',
                                  style: AppText.tiny,
                                ),
                              ),
                              for (final hit in results)
                                _SearchRow(
                                  hit: hit,
                                  onTap: () {
                                    controller.toggleSearch(false);
                                    if (hit.isSelf) {
                                      controller.showToast('这是本机设备');
                                    } else if (hit.rawId != null) {
                                      controller.prefillAssist(hit.rawId!);
                                    }
                                  },
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyResult extends StatelessWidget {
  const _EmptyResult({required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 42),
      child: Column(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: const BoxDecoration(
              color: AppColors.surfaceMuted,
              shape: BoxShape.circle,
            ),
            child: const Icon(AppIcons.search,
                size: 24, color: AppColors.textTertiary),
          ),
          const SizedBox(height: 14),
          Text(
            query.isEmpty ? '输入设备名称或识别码开始搜索' : '未找到相关设备',
            style: AppText.bodySecondary,
          ),
          const SizedBox(height: 4),
          const Text('也可以直接输入 9 位识别码发起远程协助', style: AppText.tiny),
        ],
      ),
    );
  }
}

class _SearchHit {
  _SearchHit({
    required this.name,
    required this.id,
    this.rawId,
    this.isSelf = false,
    this.platform = 'win',
  });

  final String name;
  final String id;
  final String? rawId;
  final bool isSelf;
  final String platform;
}

class _SearchRow extends StatelessWidget {
  const _SearchRow({required this.hit, required this.onTap});

  final _SearchHit hit;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final icon = switch (hit.platform) {
      'android' => AppIcons.android,
      _ => AppIcons.desktop,
    };
    return HoverBuilder(
      builder: (hovered) => GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          height: 58,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: hovered ? AppColors.surfaceMuted : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.surfaceMuted,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.border),
                ),
                child: Icon(icon, size: 17, color: AppColors.textSecondary),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hit.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.bodyStrong.copyWith(fontSize: 13),
                    ),
                    const SizedBox(height: 2),
                    Text(hit.id, style: AppText.tiny),
                  ],
                ),
              ),
              if (hit.isSelf)
                const Text('本机', style: AppText.tiny)
              else
                Row(
                  children: [
                    Text(
                      '发起协助',
                      style: AppText.link.copyWith(fontSize: 12),
                    ),
                    const Icon(AppIcons.arrowRight,
                        size: 15, color: AppColors.primary),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
