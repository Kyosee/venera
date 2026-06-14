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

  // 获取已关联的源
  const repository = ComicStateRepository();
  final relatedLinks = repository.isDomainReady
      ? repository.relatedSourcesFor(comic)
      : <DomainComicSourceLink>[];
  final acceptedLinks = relatedLinks
      .where((link) => link.status == 'accepted')
      .toList();

  final searchController = TextEditingController(text: comic.title);
  // 其他源默认全选
  final selectedSourceKeys = searchableSources
      .where((source) => !acceptedLinks.any(
          (link) => _sourceKeyFromPlatformId(link.platformId) == source.key))
      .map((source) => source.key)
      .toSet();
  var resultGroups = <_MigrationSearchGroup>[];
  Comic? selectedComic;
  DomainComicSourceLink? selectedLinkedSource; // 选中的关联源
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
                        // 显示已关联的源 - 单选快速迁移
                        if (acceptedLinks.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: context.colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      Icons.link,
                                      size: 20,
                                      color: context.colorScheme.onPrimaryContainer,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'Quick migrate to linked source'.tl,
                                        style: TextStyle(
                                          color: context.colorScheme.onPrimaryContainer,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Select one to migrate directly'.tl,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: context.colorScheme.onPrimaryContainer.withOpacity(0.7),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                for (final link in acceptedLinks)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: RadioListTile<DomainComicSourceLink>(
                                      dense: true,
                                      contentPadding: EdgeInsets.zero,
                                      value: link,
                                      groupValue: selectedLinkedSource,
                                      title: Row(
                                        children: [
                                          Icon(
                                            Icons.link,
                                            size: 16,
                                            color: context.colorScheme.primary,
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  link.sourceName,
                                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                                ),
                                                if (link.comicAuthor != null)
                                                  Text(
                                                    link.comicAuthor!,
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      color: context.colorScheme.onSurfaceVariant,
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                      onChanged: (value) {
                                        setState(() {
                                          selectedLinkedSource = value;
                                          // 清空搜索结果
                                          resultGroups = <_MigrationSearchGroup>[];
                                          selectedComic = null;
                                        });
                                      },
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        if (acceptedLinks.isNotEmpty) const SizedBox(height: 16),
                        if (acceptedLinks.isNotEmpty)
                          Row(
                            children: [
                              Expanded(child: Divider()),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                child: Text(
                                  'OR'.tl,
                                  style: TextStyle(
                                    color: context.colorScheme.onSurfaceVariant,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              Expanded(child: Divider()),
                            ],
                          ),
                        if (acceptedLinks.isNotEmpty) const SizedBox(height: 16),
                        // 其他源 - 搜索后迁移
                        Text(
                          acceptedLinks.isNotEmpty
                              ? 'Search from other sources'.tl
                              : 'Search and migrate'.tl,
                          style: ts.s14.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 12),
                        _SourceSelector(
                          sources: searchableSources,
                          selectedSourceKeys: selectedSourceKeys,
                          acceptedLinks: acceptedLinks,
                          onChanged: (next) {
                            setState(() {
                              selectedSourceKeys
                                ..clear()
                                ..addAll(next);
                              resultGroups = <_MigrationSearchGroup>[];
                              selectedComic = null;
                              // 清空关联源选择
                              selectedLinkedSource = null;
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
                            // 快速迁移：选中了关联源
                            if (selectedLinkedSource != null) {
                              setState(() {
                                isMigrating = true;
                              });
                              try {
                                final sourceKey = _sourceKeyFromPlatformId(
                                  selectedLinkedSource!.platformId,
                                );
                                final targetComic = Comic(
                                  selectedLinkedSource!.comicTitle,
                                  selectedLinkedSource!.comicCoverUri ?? '',
                                  selectedLinkedSource!.sourceComicId,
                                  null,
                                  null,
                                  '',
                                  sourceKey,
                                  null,
                                  null,
                                );
                                await SourceMigrationTaskManager.instance
                                    .migrateSingle(
                                      source: comic,
                                      target: favoriteItemFromComic(targetComic),
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
                              return;
                            }

                            // 搜索迁移：需要先选择搜索结果
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
            content: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Migrate @count comics'.tlParams({
                        'count': comics.length,
                      }),
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
    this.acceptedLinks = const <DomainComicSourceLink>[],
  });

  final List<ComicSource> sources;
  final Set<String> selectedSourceKeys;
  final List<DomainComicSourceLink> acceptedLinks;
  final ValueChanged<Set<String>> onChanged;

  @override
  Widget build(BuildContext context) {
    // 过滤出非关联源
    final linkedSourceKeys = acceptedLinks
        .map((link) => _sourceKeyFromPlatformId(link.platformId))
        .toSet();
    final otherSources = sources
        .where((source) => !linkedSourceKeys.contains(source.key))
        .toList();

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
                onChanged(otherSources.map((source) => source.key).toSet());
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
            for (final source in otherSources)
              _StableMigrationSourceFilterChip(
                selected: selectedSourceKeys.contains(source.key),
                label: source.name,
                isLinked: false,
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

class _StableMigrationSourceFilterChip extends StatelessWidget {
  const _StableMigrationSourceFilterChip({
    required this.label,
    required this.selected,
    required this.onSelected,
    this.isLinked = false,
  });

  final String label;
  final bool selected;
  final bool isLinked;
  final ValueChanged<bool> onSelected;

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      showCheckmark: false,
      labelPadding: const EdgeInsetsDirectional.only(start: 2, end: 8),
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 18,
            child: selected ? const Icon(Icons.check, size: 16) : null,
          ),
          if (isLinked) ...[
            Icon(
              Icons.link,
              size: 14,
              color: context.colorScheme.primary,
            ),
            const SizedBox(width: 4),
          ],
          Text(label),
        ],
      ),
      selected: selected,
      onSelected: onSelected,
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
