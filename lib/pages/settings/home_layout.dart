part of 'settings_page.dart';

/// The "Home Page Layout" settings screen (entry point A).
///
/// Shares its data model — [normalizeHomeLayout] / [saveHomeLayout] — with the
/// home page's long-press edit mode (entry point B). Both edit the same
/// `homeSections` setting, which syncs across devices via WebDAV like any other
/// setting.
class HomeLayoutSettings extends StatefulWidget {
  const HomeLayoutSettings({super.key});

  @override
  State<HomeLayoutSettings> createState() => _HomeLayoutSettingsState();
}

class _HomeLayoutSettingsState extends State<HomeLayoutSettings> {
  late List<HomeSectionConfig> layout = normalizeHomeLayout();

  void _persist() => saveHomeLayout(layout);

  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      var item = layout.removeAt(oldIndex);
      layout.insert(newIndex, item);
    });
    _persist();
  }

  void _toggle(String id) {
    setState(() {
      layout = layout
          .map((e) => e.id == id ? e.copyWith(visible: !e.visible) : e)
          .toList();
    });
    _persist();
  }

  void _reset() {
    setState(() => layout = defaultHomeLayout());
    _persist();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: Appbar(
        title: Text("Home Page Layout".tl),
        actions: [
          Tooltip(
            message: "Reset to Default".tl,
            child: IconButton(
              icon: const Icon(Icons.restart_alt),
              onPressed: _reset,
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Text(
              "Long press and drag to reorder.".tl,
              style: ts.s12.copyWith(color: context.colorScheme.outline),
            ),
          ),
          Expanded(
            child: ReorderableListView.builder(
              buildDefaultDragHandles: false,
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: layout.length,
              onReorder: _onReorder,
              itemBuilder: (context, index) {
                var config = layout[index];
                var meta = homeSectionMetaById(config.id)!;
                return _buildTile(context, config, meta, index);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTile(
    BuildContext context,
    HomeSectionConfig config,
    HomeSectionMeta meta,
    int index,
  ) {
    return Container(
      key: ValueKey(config.id),
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(
          color: context.colorScheme.outlineVariant,
          width: 0.6,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Opacity(
        opacity: config.visible ? 1 : 0.45,
        child: Row(
          children: [
            ReorderableDragStartListener(
              index: index,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 14, 8, 14),
                child: Icon(
                  Icons.drag_indicator,
                  size: 22,
                  color: context.colorScheme.outline,
                ),
              ),
            ),
            Icon(meta.icon, size: 22),
            const SizedBox(width: 14),
            Expanded(child: Text(meta.titleKey.tl, style: ts.s16)),
            Tooltip(
              message: config.visible ? "Hide".tl : "Show".tl,
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => _toggle(config.id),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 14, 12, 14),
                  child: Icon(
                    config.visible
                        ? Icons.visibility
                        : Icons.visibility_off_outlined,
                    size: 22,
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

/// The "Image Favorites Tabs" settings screen (feature 2).
///
/// Reorders / hides the Tags / Authors / Comics switcher inside the home page's
/// "Image Favorites" card. No long-press entry by design — that gesture is
/// reserved for the home page's section edit mode; this is reachable only from
/// Appearance settings. Shares the [normalizeImageFavoritesTabs] /
/// [saveImageFavoritesTabs] model, so it syncs and exports like any setting.
class ImageFavoritesTabsSettings extends StatefulWidget {
  const ImageFavoritesTabsSettings({super.key});

  @override
  State<ImageFavoritesTabsSettings> createState() =>
      _ImageFavoritesTabsSettingsState();
}

class _ImageFavoritesTabsSettingsState
    extends State<ImageFavoritesTabsSettings> {
  late List<HomeSectionConfig> tabs = normalizeImageFavoritesTabs();

  void _persist() => saveImageFavoritesTabs(tabs);

  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      var item = tabs.removeAt(oldIndex);
      tabs.insert(newIndex, item);
    });
    _persist();
  }

  void _toggle(String id) {
    var visibleCount = tabs.where((e) => e.visible).length;
    var target = tabs.firstWhere((e) => e.id == id);
    // Keep at least one tab visible — an empty switcher would render nothing.
    if (target.visible && visibleCount <= 1) {
      context.showMessage(message: "At least one tab must remain visible".tl);
      return;
    }
    setState(() {
      tabs = tabs
          .map((e) => e.id == id ? e.copyWith(visible: !e.visible) : e)
          .toList();
    });
    _persist();
  }

  void _reset() {
    setState(() => tabs = defaultImageFavoritesTabs());
    _persist();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: Appbar(
        title: Text("Image Favorites Tabs".tl),
        actions: [
          Tooltip(
            message: "Reset to Default".tl,
            child: IconButton(
              icon: const Icon(Icons.restart_alt),
              onPressed: _reset,
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Text(
              "Long press and drag to reorder.".tl,
              style: ts.s12.copyWith(color: context.colorScheme.outline),
            ),
          ),
          Expanded(
            child: ReorderableListView.builder(
              buildDefaultDragHandles: false,
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: tabs.length,
              onReorder: _onReorder,
              itemBuilder: (context, index) {
                var config = tabs[index];
                var meta = imageFavoritesTabMetaById(config.id)!;
                return _ImageFavoritesTabTile(
                  key: ValueKey(config.id),
                  meta: meta,
                  visible: config.visible,
                  index: index,
                  onToggle: () => _toggle(config.id),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// A single reorderable row in [ImageFavoritesTabsSettings].
class _ImageFavoritesTabTile extends StatelessWidget {
  const _ImageFavoritesTabTile({
    super.key,
    required this.meta,
    required this.visible,
    required this.index,
    required this.onToggle,
  });

  final HomeSectionMeta meta;
  final bool visible;
  final int index;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(
          color: context.colorScheme.outlineVariant,
          width: 0.6,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Opacity(
        opacity: visible ? 1 : 0.45,
        child: Row(
          children: [
            ReorderableDragStartListener(
              index: index,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 14, 8, 14),
                child: Icon(
                  Icons.drag_indicator,
                  size: 22,
                  color: context.colorScheme.outline,
                ),
              ),
            ),
            Icon(meta.icon, size: 22),
            const SizedBox(width: 14),
            Expanded(child: Text(meta.titleKey.tl, style: ts.s16)),
            Tooltip(
              message: visible ? "Hide".tl : "Show".tl,
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: onToggle,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 14, 12, 14),
                  child: Icon(
                    visible ? Icons.visibility : Icons.visibility_off_outlined,
                    size: 22,
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
