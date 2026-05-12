part of 'components.dart';

const _migrationVisibleResultCount = 5;

void showSourceMigrationDialog(BuildContext context, FavoriteItem comic) {
  final searchableSources = ComicSource.all()
      .where(
        (source) =>
            source.key != comic.sourceKey &&
            (source.searchPageData?.loadPage != null ||
                source.searchPageData?.loadNext != null),
      )
      .toList();
  if (searchableSources.isEmpty) {
    context.showMessage(message: 'No searchable sources'.tl);
    return;
  }
  final searchController = TextEditingController(text: comic.title);
  final selectedSourceKeys = searchableSources
      .map((source) => source.key)
      .toSet();
  var resultGroups = <_MigrationSearchGroup>[];
  Comic? selectedComic;
  bool isSearching = false;
  bool isMigrating = false;
  bool migrateHistory = true;
  bool replaceFavorite = true;

  Future<void> runSearch(StateSetter setState, BuildContext context) async {
    final keyword = searchController.text.trim();
    if (keyword.isEmpty) {
      context.showMessage(message: 'Invalid input'.tl);
      return;
    }
    final selectedSources = searchableSources
        .where((source) => selectedSourceKeys.contains(source.key))
        .toList();
    if (selectedSources.isEmpty) {
      context.showMessage(message: 'No target sources selected'.tl);
      return;
    }
    setState(() {
      isSearching = true;
      selectedComic = null;
      resultGroups = <_MigrationSearchGroup>[];
    });
    for (final source in selectedSources) {
      final searchData = source.searchPageData;
      if (searchData == null) {
        setState(() {
          resultGroups.add(
            _MigrationSearchGroup(
              source: source,
              error: 'Source unavailable'.tl,
            ),
          );
        });
        continue;
      }
      final options =
          searchData.searchOptions
              ?.map((option) => option.defaultValue)
              .toList() ??
          const <String>[];
      try {
        final res = searchData.loadPage != null
            ? await searchData.loadPage!(keyword, 1, options)
            : await searchData.loadNext!(keyword, null, options);
        if (!context.mounted) {
          return;
        }
        final comics = res.dataOrNull ?? const <Comic>[];
        setState(() {
          resultGroups.add(
            _MigrationSearchGroup(
              source: source,
              results: comics,
              error: comics.isEmpty ? res.errorMessage : null,
            ),
          );
        });
      } catch (e) {
        if (!context.mounted) {
          return;
        }
        setState(() {
          resultGroups.add(
            _MigrationSearchGroup(source: source, error: e.toString()),
          );
        });
      }
    }
    if (!context.mounted) {
      return;
    }
    setState(() {
      isSearching = false;
    });
  }

  showDialog(
    context: App.rootContext,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) {
          return Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: context.brightness == Brightness.dark
                  ? BorderSide(color: context.colorScheme.outlineVariant)
                  : BorderSide.none,
            ),
            insetPadding: context.width < 400
                ? const EdgeInsets.symmetric(horizontal: 4)
                : const EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(
              width: math.min(640, math.max(300, context.width - 64)),
              height: math.min(680, math.max(420, context.height - 96)),
              child: Column(
                children: [
                  Appbar(
                    leading: IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: context.pop,
                    ),
                    title: Text('Migrate Source'.tl),
                    backgroundColor: Colors.transparent,
                  ),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      children: [
                        Text(
                          comic.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: ts.s16,
                        ),
                        const SizedBox(height: 12),
                        _SourceSelector(
                          sources: searchableSources,
                          selectedSourceKeys: selectedSourceKeys,
                          onChanged: (next) {
                            setState(() {
                              selectedSourceKeys
                                ..clear()
                                ..addAll(next);
                              resultGroups = <_MigrationSearchGroup>[];
                              selectedComic = null;
                            });
                          },
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: searchController,
                          decoration: InputDecoration(
                            labelText: 'Search by title'.tl,
                            border: const OutlineInputBorder(),
                            suffixIcon: IconButton(
                              icon: const Icon(Icons.search),
                              onPressed: isSearching
                                  ? null
                                  : () => runSearch(setState, context),
                            ),
                          ),
                          onSubmitted: (_) => runSearch(setState, context),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: CheckboxListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                value: migrateHistory,
                                title: Text('Migrate reading progress'.tl),
                                onChanged: (value) {
                                  setState(() {
                                    migrateHistory = value ?? true;
                                  });
                                },
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: CheckboxListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                value: replaceFavorite,
                                title: Text('Replace favorite'.tl),
                                onChanged: (value) {
                                  setState(() {
                                    replaceFavorite = value ?? true;
                                  });
                                },
                              ),
                            ),
                          ],
                        ),
                        Button.filled(
                          isLoading: isSearching,
                          onPressed: () => runSearch(setState, context),
                          child: Text('Search'.tl),
                        ),
                        const SizedBox(height: 12),
                        if (isSearching)
                          const Padding(
                            padding: EdgeInsets.only(bottom: 12),
                            child: LinearProgressIndicator(),
                          ),
                        if (resultGroups.isEmpty)
                          Text(
                            'Search Results'.tl,
                            style: TextStyle(
                              color: context.colorScheme.onSurfaceVariant,
                            ),
                          )
                        else
                          for (final group in resultGroups)
                            _MigrationSearchGroupTile(
                              group: group,
                              selectedComic: selectedComic,
                              onSelected: (result) {
                                setState(() {
                                  selectedComic = result;
                                });
                              },
                              onToggleShowAll: () {
                                setState(() {
                                  group.showAll = !group.showAll;
                                });
                              },
                            ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Button.text(
                          onPressed: () {
                            if (!isMigrating) {
                              context.pop();
                            }
                          },
                          child: Text('Cancel'.tl),
                        ),
                        const SizedBox(width: 8),
                        Button.filled(
                          isLoading: isMigrating,
                          onPressed: () async {
                            if (selectedComic == null) {
                              context.showMessage(message: 'Invalid input'.tl);
                              return;
                            }
                            setState(() {
                              isMigrating = true;
                            });
                            try {
                              await SourceMigrationTaskManager.instance
                                  .migrateSingle(
                                    source: comic,
                                    target: favoriteItemFromComic(
                                      selectedComic!,
                                    ),
                                    migrateHistory: migrateHistory,
                                    replaceFavorite: replaceFavorite,
                                  );
                              if (context.mounted) {
                                context.pop();
                                App.rootContext.showMessage(
                                  message: 'Migration completed'.tl,
                                );
                              }
                            } catch (e) {
                              App.rootContext.showMessage(
                                message: e.toString(),
                              );
                              setState(() {
                                isMigrating = false;
                              });
                            }
                          },
                          child: Text('Migrate'.tl),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  ).whenComplete(searchController.dispose);
}

void showBatchSourceMigrationDialog(
  BuildContext context, {
  required String folder,
  required List<FavoriteItem> comics,
  VoidCallback? onStarted,
}) {
  if (comics.isEmpty) {
    context.showMessage(message: 'No comics selected'.tl);
    return;
  }
  final searchableSources = ComicSource.all()
      .where(
        (source) =>
            source.searchPageData?.loadPage != null ||
            source.searchPageData?.loadNext != null,
      )
      .toList();
  if (searchableSources.isEmpty) {
    context.showMessage(message: 'No searchable sources'.tl);
    return;
  }
  final selectedSourceKeys = searchableSources
      .map((source) => source.key)
      .toSet();
  bool migrateHistory = true;
  bool replaceFavorite = true;
  bool confirmEach = false;

  showDialog(
    context: App.rootContext,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) {
          return ContentDialog(
            title: 'Batch migrate source'.tl,
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Migrate @count comics'.tlParams({'count': comics.length}),
                  ).toAlign(Alignment.centerLeft),
                  const SizedBox(height: 12),
                  _SourceSelector(
                    sources: searchableSources,
                    selectedSourceKeys: selectedSourceKeys,
                    onChanged: (next) {
                      setState(() {
                        selectedSourceKeys
                          ..clear()
                          ..addAll(next);
                      });
                    },
                  ),
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: migrateHistory,
                    title: Text('Migrate reading progress'.tl),
                    onChanged: (value) {
                      setState(() {
                        migrateHistory = value ?? true;
                      });
                    },
                  ),
                  CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: replaceFavorite,
                    title: Text('Replace favorite'.tl),
                    onChanged: (value) {
                      setState(() {
                        replaceFavorite = value ?? true;
                      });
                    },
                  ),
                  CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: confirmEach,
                    title: Text('Confirm each match'.tl),
                    onChanged: (value) {
                      setState(() {
                        confirmEach = value ?? false;
                      });
                    },
                  ),
                ],
              ),
            ),
            actions: [
              Button.text(onPressed: context.pop, child: Text('Cancel'.tl)),
              Button.filled(
                onPressed: () {
                  if (selectedSourceKeys.isEmpty) {
                    context.showMessage(
                      message: 'No target sources selected'.tl,
                    );
                    return;
                  }
                  SourceMigrationTaskManager.instance.startBatch(
                    folder: folder,
                    favorites: comics,
                    targetSourceKeys: selectedSourceKeys.toList(),
                    migrateHistory: migrateHistory,
                    replaceFavorite: replaceFavorite,
                    confirmEach: confirmEach,
                  );
                  context.pop();
                  onStarted?.call();
                  App.rootContext.showMessage(message: 'Task started'.tl);
                },
                child: Text('Start'.tl),
              ),
            ],
          );
        },
      );
    },
  );
}

class _MigrationSearchGroup {
  _MigrationSearchGroup({
    required this.source,
    this.results = const <Comic>[],
    this.error,
  });

  final ComicSource source;
  final List<Comic> results;
  final String? error;
  bool showAll = false;

  bool get hasError => error != null && error!.isNotEmpty;
}

class _SourceSelector extends StatelessWidget {
  const _SourceSelector({
    required this.sources,
    required this.selectedSourceKeys,
    required this.onChanged,
  });

  final List<ComicSource> sources;
  final Set<String> selectedSourceKeys;
  final ValueChanged<Set<String>> onChanged;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 8),
      title: Text('Target Sources'.tl),
      subtitle: Text(
        'Selected @count sources'.tlParams({
          'count': selectedSourceKeys.length,
        }),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      children: [
        Row(
          children: [
            Button.text(
              onPressed: () {
                onChanged(sources.map((source) => source.key).toSet());
              },
              child: Text('Select All'.tl),
            ),
            const SizedBox(width: 8),
            Button.text(
              onPressed: () {
                onChanged(<String>{});
              },
              child: Text('Clear'.tl),
            ),
          ],
        ).toAlign(Alignment.centerLeft),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final source in sources)
              FilterChip(
                selected: selectedSourceKeys.contains(source.key),
                label: Text(source.name),
                onSelected: (selected) {
                  final next = selectedSourceKeys.toSet();
                  if (selected) {
                    next.add(source.key);
                  } else {
                    next.remove(source.key);
                  }
                  onChanged(next);
                },
              ),
          ],
        ).toAlign(Alignment.centerLeft),
      ],
    );
  }
}

class _MigrationSearchGroupTile extends StatelessWidget {
  const _MigrationSearchGroupTile({
    required this.group,
    required this.selectedComic,
    required this.onSelected,
    required this.onToggleShowAll,
  });

  final _MigrationSearchGroup group;
  final Comic? selectedComic;
  final ValueChanged<Comic> onSelected;
  final VoidCallback onToggleShowAll;

  @override
  Widget build(BuildContext context) {
    final visibleResults = group.showAll
        ? group.results
        : group.results.take(_migrationVisibleResultCount);
    final subtitle = group.hasError
        ? group.error!
        : 'Found @count comics'.tlParams({'count': group.results.length});
    final toggleText = group.showAll
        ? 'Collapse'.tl
        : 'Show @count more'.tlParams({
            'count': group.results.length - _migrationVisibleResultCount,
          });
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      initiallyExpanded: false,
      title: Text(group.source.name),
      subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      children: [
        if (group.hasError)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              group.error ?? '',
              style: TextStyle(color: context.colorScheme.error),
            ).toAlign(Alignment.centerLeft),
          )
        else if (group.results.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'No match found'.tl,
              style: TextStyle(color: context.colorScheme.onSurfaceVariant),
            ).toAlign(Alignment.centerLeft),
          )
        else ...[
          for (final result in visibleResults)
            _MigrationSearchResultTile(
              comic: result,
              selected: selectedComic == result,
              onTap: () {
                onSelected(result);
              },
            ),
          if (group.results.length > _migrationVisibleResultCount)
            Button.text(
              onPressed: onToggleShowAll,
              child: Text(toggleText),
            ).toAlign(Alignment.centerLeft),
        ],
      ],
    );
  }
}

class _MigrationSearchResultTile extends StatelessWidget {
  const _MigrationSearchResultTile({
    required this.comic,
    required this.selected,
    required this.onTap,
  });

  final Comic comic;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      selected: selected,
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: SizedBox(
          width: 42,
          height: 56,
          child: AnimatedImage(
            image: CachedImageProvider(
              comic.cover,
              sourceKey: comic.sourceKey,
              cid: comic.id,
            ),
            fit: BoxFit.cover,
          ),
        ),
      ),
      title: Text(comic.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [
          ComicSource.find(comic.sourceKey)?.name ?? comic.sourceKey,
          if (comic.subtitle != null && comic.subtitle!.isNotEmpty)
            comic.subtitle!,
        ].join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: selected ? const Icon(Icons.check_circle) : null,
      onTap: onTap,
    );
  }
}
