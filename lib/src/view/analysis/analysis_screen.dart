import 'dart:math' as math;
import 'dart:ui';

import 'package:chessground/chessground.dart' as cg;
import 'package:collection/collection.dart';
import 'package:dartchess/dartchess.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/constants.dart';
import 'package:lichess_mobile/src/model/analysis/analysis_controller.dart';
import 'package:lichess_mobile/src/model/common/chess.dart';
import 'package:lichess_mobile/src/model/common/eval.dart';
import 'package:lichess_mobile/src/model/engine/engine.dart';
import 'package:lichess_mobile/src/model/engine/evaluation_service.dart';
import 'package:lichess_mobile/src/model/game/player.dart';
import 'package:lichess_mobile/src/model/settings/analysis_preferences.dart';
import 'package:lichess_mobile/src/model/settings/board_preferences.dart';
import 'package:lichess_mobile/src/model/settings/brightness.dart';
import 'package:lichess_mobile/src/styles/lichess_colors.dart';
import 'package:lichess_mobile/src/styles/lichess_icons.dart';
import 'package:lichess_mobile/src/styles/styles.dart';
import 'package:lichess_mobile/src/utils/chessground_compat.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:lichess_mobile/src/view/engine/engine_gauge.dart';
import 'package:lichess_mobile/src/widgets/adaptive_action_sheet.dart';
import 'package:lichess_mobile/src/widgets/adaptive_bottom_sheet.dart';
import 'package:lichess_mobile/src/widgets/buttons.dart';
import 'package:lichess_mobile/src/widgets/list.dart';
import 'package:lichess_mobile/src/widgets/platform.dart';
import 'package:popover/popover.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'analysis_pgn_tags.dart';
import 'analysis_settings.dart';
import 'tree_view.dart';

class AnalysisScreen extends ConsumerWidget {
  const AnalysisScreen({
    required this.options,
    this.title,
  });

  final AnalysisOptions options;
  final String? title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ConsumerPlatformWidget(
      androidBuilder: _androidBuilder,
      iosBuilder: _iosBuilder,
      ref: ref,
    );
  }

  Widget _androidBuilder(BuildContext context, WidgetRef ref) {
    final ctrlProvider = analysisControllerProvider(options);

    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: _Title(options: options, title: title),
        actions: [
          _EngineDepth(ctrlProvider),
          SettingsButton(
            onPressed: () => showAdaptiveBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              builder: (_) => AnalysisSettings(options),
            ),
          ),
        ],
      ),
      body: _Body(options: options),
    );
  }

  Widget _iosBuilder(BuildContext context, WidgetRef ref) {
    final ctrlProvider = analysisControllerProvider(options);

    return CupertinoPageScaffold(
      resizeToAvoidBottomInset: false,
      navigationBar: CupertinoNavigationBar(
        padding: Styles.cupertinoAppBarTrailingWidgetPadding,
        middle: _Title(options: options, title: title),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _EngineDepth(ctrlProvider),
            SettingsButton(
              onPressed: () => showAdaptiveBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                builder: (_) => AnalysisSettings(options),
              ),
            ),
          ],
        ),
      ),
      child: _Body(options: options),
    );
  }
}

class _Title extends StatelessWidget {
  const _Title({
    required this.options,
    this.title,
  });
  final AnalysisOptions options;
  final String? title;

  @override
  Widget build(BuildContext context) {
    return title != null
        ? Text(title!)
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (options.variant != Variant.standard) ...[
                Icon(options.variant.icon),
                const SizedBox(width: 5.0),
              ],
              Text(context.l10n.analysis),
            ],
          );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.options});

  final AnalysisOptions options;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctrlProvider = analysisControllerProvider(options);
    final showEvaluationGauge = ref.watch(
      analysisPreferencesProvider.select((value) => value.showEvaluationGauge),
    );

    final isEngineAvailable = ref.watch(
      ctrlProvider.select(
        (value) => value.isEngineAvailable,
      ),
    );

    final hasEval =
        ref.watch(ctrlProvider.select((value) => value.hasAvailableEval));

    final showAnalysisSummary = ref.watch(
      ctrlProvider.select(
        (value) =>
            value.acplChartData != null &&
            value.displayMode == DisplayMode.summary,
      ),
    );

    return Column(
      children: [
        Expanded(
          child: SafeArea(
            bottom: false,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final aspectRatio = constraints.biggest.aspectRatio;
                final defaultBoardSize = constraints.biggest.shortestSide;
                final isTablet = defaultBoardSize > kTabletThreshold;
                final remainingHeight =
                    constraints.maxHeight - defaultBoardSize;
                final isSmallScreen =
                    remainingHeight < kSmallRemainingHeightLeftBoardThreshold;
                final boardSize = isTablet || isSmallScreen
                    ? defaultBoardSize - kTabletBoardTableSidePadding * 2
                    : defaultBoardSize;

                return aspectRatio > 1
                    ? Row(
                        mainAxisSize: MainAxisSize.max,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(
                              left: kTabletBoardTableSidePadding,
                              top: kTabletBoardTableSidePadding,
                              bottom: kTabletBoardTableSidePadding,
                            ),
                            child: Row(
                              children: [
                                _Board(ctrlProvider, boardSize),
                                if (hasEval && showEvaluationGauge)
                                  _EngineGaugeVertical(ctrlProvider),
                              ],
                            ),
                          ),
                          Flexible(
                            fit: FlexFit.loose,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.start,
                              children: [
                                if (isEngineAvailable)
                                  _EngineLines(
                                    ctrlProvider,
                                    isLandscape: true,
                                  ),
                                Expanded(
                                  child: PlatformCard(
                                    margin: const EdgeInsets.all(
                                      kTabletBoardTableSidePadding,
                                    ),
                                    semanticContainer: false,
                                    child: showAnalysisSummary
                                        ? ServerAnalysisSummary(options)
                                        : AnalysisTreeView(
                                            options,
                                            Orientation.landscape,
                                          ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.max,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          _ColumnTopTable(ctrlProvider),
                          if (isTablet)
                            Padding(
                              padding: const EdgeInsets.all(
                                kTabletBoardTableSidePadding,
                              ),
                              child: _Board(ctrlProvider, boardSize),
                            )
                          else
                            _Board(ctrlProvider, boardSize),
                          if (showAnalysisSummary)
                            Expanded(child: ServerAnalysisSummary(options))
                          else
                            Expanded(
                              child: AnalysisTreeView(
                                options,
                                Orientation.portrait,
                              ),
                            ),
                        ],
                      );
              },
            ),
          ),
        ),
        _BottomBar(options: options),
      ],
    );
  }
}

class _Board extends ConsumerWidget {
  const _Board(this.ctrlProvider, this.boardSize);

  final AnalysisControllerProvider ctrlProvider;
  final double boardSize;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final analysisState = ref.watch(ctrlProvider);
    final boardPrefs = ref.watch(boardPreferencesProvider);
    final showBestMoveArrow = ref.watch(
      analysisPreferencesProvider.select(
        (value) => value.showBestMoveArrow,
      ),
    );

    final evalBestMoves = ref.watch(
      engineEvaluationProvider.select((s) => s.eval?.bestMoves),
    );

    final currentNode = analysisState.currentNode;
    final annotation = _annotationFrom(
      currentNode.nags,
      fromLichessAnalysis: analysisState.hasServerAnalysis,
    );

    final bestMoves = evalBestMoves ?? currentNode.eval?.bestMoves;

    return cg.Board(
      size: boardSize,
      onMove: (move, {isDrop, isPremove}) =>
          ref.read(ctrlProvider.notifier).onUserMove(Move.fromUci(move.uci)!),
      data: cg.BoardData(
        orientation: analysisState.pov.cg,
        interactableSide: analysisState.position.isGameOver
            ? cg.InteractableSide.none
            : analysisState.position.turn == Side.white
                ? cg.InteractableSide.white
                : cg.InteractableSide.black,
        fen: analysisState.position.fen,
        isCheck: analysisState.position.isCheck,
        lastMove: analysisState.lastMove?.cg,
        sideToMove: analysisState.position.turn.cg,
        validMoves: analysisState.validMoves,
        shapes: showBestMoveArrow &&
                analysisState.isEngineAvailable &&
                bestMoves != null
            ? ISet(
                bestMoves.where((move) => move != null).mapIndexed(
                      (i, move) => cg.Arrow(
                        color:
                            const Color(0x40003088).withOpacity(0.4 - 0.15 * i),
                        orig: move!.cg.from,
                        dest: move.cg.to,
                      ),
                    ),
              )
            : null,
        annotations: currentNode.sanMove != null && annotation != null
            ? IMap({currentNode.sanMove!.move.cg.to: annotation})
            : null,
      ),
      settings: cg.BoardSettings(
        pieceAssets: boardPrefs.pieceSet.assets,
        colorScheme: boardPrefs.boardTheme.colors,
        showValidMoves: boardPrefs.showLegalMoves,
        showLastMove: boardPrefs.boardHighlights,
        enableCoordinates: boardPrefs.coordinates,
        animationDuration: boardPrefs.pieceAnimationDuration,
      ),
    );
  }
}

cg.Annotation? _annotationFrom(
  Iterable<int>? nags, {
  bool fromLichessAnalysis = false,
}) {
  final nag = nags?.firstOrNull;
  if (nag == null) {
    return null;
  }
  return switch (nag) {
    1 => const cg.Annotation(
        symbol: '!',
        color: Colors.lightGreen,
      ),
    3 => const cg.Annotation(
        symbol: '!!',
        color: Colors.teal,
      ),
    5 => const cg.Annotation(
        symbol: '!?',
        color: Colors.lightBlue,
      ),
    6 => cg.Annotation(
        symbol: '?!',
        color: fromLichessAnalysis ? LichessColors.cyan : Colors.amber,
      ),
    2 => cg.Annotation(
        symbol: '?',
        color: fromLichessAnalysis ? const Color(0xFFe69f00) : Colors.orange,
      ),
    4 => cg.Annotation(
        symbol: '??',
        color: fromLichessAnalysis ? const Color(0xFFdf5353) : Colors.red,
      ),
    int() => null,
  };
}

class _EngineGaugeVertical extends ConsumerWidget {
  const _EngineGaugeVertical(this.ctrlProvider);

  final AnalysisControllerProvider ctrlProvider;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final analysisState = ref.watch(ctrlProvider);

    return EngineGauge(
      displayMode: EngineGaugeDisplayMode.vertical,
      params: EngineGaugeParams(
        orientation: analysisState.pov,
        isLocalEngineAvailable: analysisState.isEngineAvailable,
        position: analysisState.position,
        savedEval: analysisState.currentNode.eval,
      ),
    );
  }
}

class _ColumnTopTable extends ConsumerWidget {
  const _ColumnTopTable(this.ctrlProvider);

  final AnalysisControllerProvider ctrlProvider;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final analysisState = ref.watch(ctrlProvider);
    final showEvaluationGauge = ref.watch(
      analysisPreferencesProvider.select((p) => p.showEvaluationGauge),
    );

    return analysisState.hasAvailableEval
        ? Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showEvaluationGauge)
                EngineGauge(
                  displayMode: EngineGaugeDisplayMode.horizontal,
                  params: EngineGaugeParams(
                    orientation: analysisState.pov,
                    isLocalEngineAvailable: analysisState.isEngineAvailable,
                    position: analysisState.position,
                    savedEval: analysisState.currentNode.eval ??
                        (analysisState.currentNode.pgnEval != null
                            ? ExternalEval(
                                eval: analysisState.currentNode.pgnEval!.pawns,
                                mate: analysisState.currentNode.pgnEval!.mate,
                                depth: analysisState.currentNode.pgnEval!.depth,
                              )
                            : null),
                  ),
                ),
              if (analysisState.isEngineAvailable)
                _EngineLines(ctrlProvider, isLandscape: false),
            ],
          )
        : kEmptyWidget;
  }
}

class _EngineLines extends ConsumerWidget {
  const _EngineLines(this.ctrlProvider, {required this.isLandscape});
  final AnalysisControllerProvider ctrlProvider;
  final bool isLandscape;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final analysisState = ref.watch(ctrlProvider);
    final numEvalLines = ref.watch(
      analysisPreferencesProvider.select(
        (p) => p.numEvalLines,
      ),
    );
    final engineEval = ref.watch(engineEvaluationProvider).eval;
    final eval = engineEval ?? analysisState.currentNode.eval;

    final emptyLines = List.filled(
      numEvalLines,
      _Engineline.empty(ctrlProvider),
    );

    final content = !analysisState.position.isGameOver
        ? (eval != null
            ? eval.pvs
                .take(numEvalLines)
                .map(
                  (pv) => _Engineline(ctrlProvider, eval.position, pv),
                )
                .toList()
            : emptyLines)
        : emptyLines;

    if (content.length < numEvalLines) {
      final padding = List.filled(
        numEvalLines - content.length,
        _Engineline.empty(ctrlProvider),
      );
      content.addAll(padding);
    }

    return Padding(
      padding: EdgeInsets.symmetric(
        vertical: isLandscape ? kTabletBoardTableSidePadding : 0.0,
        horizontal: isLandscape ? kTabletBoardTableSidePadding : 0.0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.start,
        children: content,
      ),
    );
  }
}

class _Engineline extends ConsumerWidget {
  const _Engineline(
    this.ctrlProvider,
    this.fromPosition,
    this.pvData,
  );

  const _Engineline.empty(this.ctrlProvider)
      : pvData = const PvData(moves: IListConst([])),
        fromPosition = Chess.initial;

  final AnalysisControllerProvider ctrlProvider;
  final Position fromPosition;
  final PvData pvData;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (pvData.moves.isEmpty) {
      return const SizedBox(
        height: kEvalGaugeSize,
        child: SizedBox.shrink(),
      );
    }

    final lineBuffer = StringBuffer();
    int ply = fromPosition.ply + 1;
    pvData.sanMoves(fromPosition).forEachIndexed((i, s) {
      lineBuffer.write(
        ply.isOdd
            ? '${(ply / 2).ceil()}. $s '
            : i == 0
                ? '${(ply / 2).ceil()}... $s '
                : '$s ',
      );
      ply += 1;
    });

    final brightness = ref.watch(currentBrightnessProvider);

    final evalString = pvData.evalString;
    return AdaptiveInkWell(
      onTap: () => ref
          .read(ctrlProvider.notifier)
          .onUserMove(Move.fromUci(pvData.moves[0])!),
      child: SizedBox(
        height: kEvalGaugeSize,
        child: Padding(
          padding: const EdgeInsets.all(2.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                decoration: BoxDecoration(
                  color: pvData.winningSide == Side.black
                      ? EngineGauge.backgroundColor(context, brightness)
                      : EngineGauge.valueColor(context, brightness),
                  borderRadius: BorderRadius.circular(4.0),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 4.0,
                  vertical: 2.0,
                ),
                child: Text(
                  evalString,
                  style: TextStyle(
                    color: pvData.winningSide == Side.black
                        ? Colors.white
                        : Colors.black,
                    fontSize: kEvalGaugeFontSize,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8.0),
              Expanded(
                child: Text(
                  lineBuffer.toString(),
                  maxLines: 1,
                  softWrap: false,
                  style: const TextStyle(
                    fontFamily: 'ChessFont',
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomBar extends ConsumerWidget {
  const _BottomBar({
    required this.options,
  });

  final AnalysisOptions options;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctrlProvider = analysisControllerProvider(options);
    final canGoBack =
        ref.watch(ctrlProvider.select((value) => value.canGoBack));
    final canGoNext =
        ref.watch(ctrlProvider.select((value) => value.canGoNext));
    final displayMode = ref.watch(
      ctrlProvider.select((value) => value.displayMode),
    );

    return Container(
      padding: Styles.horizontalBodyPadding,
      color: defaultTargetPlatform == TargetPlatform.iOS
          ? CupertinoTheme.of(context).barBackgroundColor
          : Theme.of(context).bottomAppBarTheme.color,
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            BottomBarButton(
              label: context.l10n.menu,
              shortLabel: context.l10n.menu,
              onTap: () {
                _showAnalysisMenu(context, ref);
              },
              icon: Icons.menu,
            ),
            if (options.serverAnalysis != null)
              BottomBarButton(
                label: context.l10n.computerAnalysis,
                shortLabel:
                    displayMode == DisplayMode.summary ? 'Moves' : 'Summary',
                onTap: () {
                  ref.read(ctrlProvider.notifier).toggleDisplayMode();
                },
                icon: displayMode == DisplayMode.summary
                    ? LichessIcons.flow_cascade
                    : Icons.area_chart,
              ),
            RepeatButton(
              onLongPress: canGoBack ? () => _moveBackward(ref) : null,
              child: BottomBarButton(
                key: const ValueKey('goto-previous'),
                onTap: canGoBack ? () => _moveBackward(ref) : null,
                label: 'Previous',
                shortLabel: 'Previous',
                icon: CupertinoIcons.chevron_back,
                showAndroidTooltip: false,
              ),
            ),
            RepeatButton(
              onLongPress: canGoNext ? () => _moveForward(ref) : null,
              child: BottomBarButton(
                key: const ValueKey('goto-next'),
                icon: CupertinoIcons.chevron_forward,
                label: context.l10n.next,
                shortLabel: context.l10n.next,
                onTap: canGoNext ? () => _moveForward(ref) : null,
                showAndroidTooltip: false,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _moveForward(WidgetRef ref) =>
      ref.read(analysisControllerProvider(options).notifier).userNext();
  void _moveBackward(WidgetRef ref) =>
      ref.read(analysisControllerProvider(options).notifier).userPrevious();

  Future<void> _showAnalysisMenu(BuildContext context, WidgetRef ref) {
    return showAdaptiveActionSheet(
      context: context,
      actions: [
        BottomSheetAction(
          label: Text(context.l10n.flipBoard),
          onPressed: (context) {
            ref
                .read(analysisControllerProvider(options).notifier)
                .toggleBoard();
          },
        ),
        BottomSheetAction(
          label: Text(context.l10n.studyShareAndExport),
          onPressed: (_) {
            showAdaptiveBottomSheet<void>(
              context: context,
              showDragHandle: true,
              isScrollControlled: true,
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.9,
              ),
              builder: (_) => SafeArea(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    AnalysisPgnTags(
                      options: options,
                    ),
                    Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: FatButton(
                        semanticsLabel: 'Share PGN',
                        onPressed: () {
                          Navigator.of(context).pop();
                          Share.share(
                            ref
                                .read(
                                  analysisControllerProvider(options).notifier,
                                )
                                .makeGamePgn(),
                          );
                        },
                        child: const Text('Share PGN'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _EngineDepth extends ConsumerWidget {
  const _EngineDepth(this.ctrlProvider);

  final AnalysisControllerProvider ctrlProvider;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isEngineAvailable = ref.watch(
      ctrlProvider.select(
        (value) => value.isEngineAvailable,
      ),
    );
    final currentNode = ref.watch(
      ctrlProvider.select((value) => value.currentNode),
    );
    final depth = ref.watch(
          engineEvaluationProvider.select((value) => value.eval?.depth),
        ) ??
        currentNode.eval?.depth;

    return isEngineAvailable && depth != null
        ? AppBarTextButton(
            onPressed: () {
              showPopover(
                context: context,
                bodyBuilder: (context) {
                  return _StockfishInfo(currentNode);
                },
                direction: PopoverDirection.top,
                width: 240,
                backgroundColor: defaultTargetPlatform == TargetPlatform.android
                    ? Theme.of(context).dialogBackgroundColor
                    : CupertinoDynamicColor.resolve(
                        CupertinoColors.tertiarySystemBackground,
                        context,
                      ),
                transitionDuration: Duration.zero,
                popoverTransitionBuilder: (_, child) => child,
              );
            },
            child: Container(
              width: 20.0,
              height: 20.0,
              padding: const EdgeInsets.all(2.0),
              decoration: BoxDecoration(
                color: defaultTargetPlatform == TargetPlatform.android
                    ? Theme.of(context).colorScheme.secondary
                    : CupertinoTheme.of(context).primaryColor,
                borderRadius: BorderRadius.circular(4.0),
              ),
              child: FittedBox(
                fit: BoxFit.contain,
                child: Text(
                  '${math.min(99, depth)}',
                  style: TextStyle(
                    color: defaultTargetPlatform == TargetPlatform.android
                        ? Theme.of(context).colorScheme.onSecondary
                        : CupertinoTheme.of(context).primaryContrastingColor,
                    fontFeatures: const [
                      FontFeature.tabularFigures(),
                    ],
                  ),
                ),
              ),
            ),
          )
        : const SizedBox.shrink();
  }
}

class _StockfishInfo extends ConsumerWidget {
  const _StockfishInfo(this.currentNode);

  final AnalysisCurrentNode currentNode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (eval: eval, state: engineState) =
        ref.watch(engineEvaluationProvider);

    final currentEval = eval ?? currentNode.eval;

    final knps = engineState == EngineState.computing
        ? ', ${eval?.knps.round()}kn/s'
        : '';
    final depth = currentEval?.depth ?? 0;
    final maxDepth = math.max(depth, kMaxEngineDepth);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        PlatformListTile(
          leading: Image.asset(
            'assets/images/stockfish/icon.png',
            width: 44,
            height: 44,
          ),
          title: const Text('Stockfish 16'),
          subtitle: Text(
            context.l10n.depthX(
              '$depth/$maxDepth$knps',
            ),
          ),
        ),
      ],
    );
  }
}

class ServerAnalysisSummary extends ConsumerWidget {
  const ServerAnalysisSummary(this.options);

  final AnalysisOptions options;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final serverAnalysis = options.serverAnalysis;
    final pgnHeaders = ref.watch(
      analysisControllerProvider(options).select((value) => value.pgnHeaders),
    );
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AcplChart(options),
          if (serverAnalysis != null) ...[
            const SizedBox(height: 16.0),
            _PlayerStats(Side.white, serverAnalysis.white, pgnHeaders),
            _PlayerStats(Side.black, serverAnalysis.black, pgnHeaders),
          ],
        ],
      ),
    );
  }
}

class _PlayerStats extends StatelessWidget {
  const _PlayerStats(this.side, this.data, this.pgnHeaders);

  final Side side;
  final PlayerAnalysis data;
  final IMap<String, String> pgnHeaders;

  @override
  Widget build(BuildContext context) {
    final playerTitle = side == Side.white
        ? pgnHeaders.get('WhiteTitle')
        : pgnHeaders.get('BlackTitle');
    final playerName = side == Side.white
        ? pgnHeaders.get('White') ?? context.l10n.white
        : pgnHeaders.get('Black') ?? context.l10n.black;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0, left: 16.0, right: 16.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${playerTitle != null ? '$playerTitle ' : ''}$playerName',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(context.l10n.nbInaccuracies(data.inaccuracies)),
          Text(context.l10n.nbMistakes(data.mistakes)),
          Text(context.l10n.nbBlunders(data.blunders)),
          if (data.acpl != null)
            Text('${data.acpl} ${context.l10n.averageCentipawnLoss}'),
          if (data.accuracy != null)
            Row(
              children: [
                Text('${data.accuracy}% ${context.l10n.accuracy}'),
                const SizedBox(width: 8.0),
                PlatformIconButton(
                  icon: Icons.info_outline_rounded,
                  semanticsLabel: 'More info',
                  padding: EdgeInsets.zero,
                  onTap: () async {
                    await launchUrl(
                      Uri.parse('https://lichess.org/page/accuracy'),
                    );
                  },
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class AcplChart extends ConsumerWidget {
  const AcplChart(this.options);

  final AnalysisOptions options;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mainLineColor = defaultTargetPlatform == TargetPlatform.iOS
        ? Colors.orange
        : Theme.of(context).colorScheme.secondary;
    // yes it looks like below/above are inverted in fl_chart
    final belowLineColor = Colors.white.withOpacity(0.7);
    final aboveLineColor = Colors.grey.shade800.withOpacity(0.8);

    final data = ref.watch(
      analysisControllerProvider(options)
          .select((value) => value.acplChartData),
    );

    final currentNode = ref.watch(
      analysisControllerProvider(options).select((value) => value.currentNode),
    );

    final isOnMainline = ref.watch(
      analysisControllerProvider(options).select((value) => value.isOnMainline),
    );

    if (data == null) {
      return const SizedBox.shrink();
    }

    final spots = data
        .mapIndexed(
          (i, e) => FlSpot(i.toDouble(), e.winningChances(Side.white)),
        )
        .toList(growable: false);

    return Center(
      child: AspectRatio(
        aspectRatio: 2.3,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: LineChart(
            LineChartData(
              lineTouchData: const LineTouchData(enabled: false),
              minY: -1.0,
              maxY: 1.0,
              lineBarsData: [
                LineChartBarData(
                  spots: spots,
                  isCurved: true,
                  barWidth: 1,
                  color: mainLineColor,
                  aboveBarData: BarAreaData(
                    show: true,
                    color: aboveLineColor,
                    applyCutOffY: true,
                  ),
                  belowBarData: BarAreaData(
                    show: true,
                    color: belowLineColor,
                    applyCutOffY: true,
                  ),
                  dotData: const FlDotData(
                    show: false,
                  ),
                ),
              ],
              extraLinesData: ExtraLinesData(
                verticalLines: [
                  if (isOnMainline)
                    VerticalLine(
                      x: (currentNode.position.ply - 1).toDouble(),
                      color: mainLineColor,
                      strokeWidth: 1.0,
                    ),
                ],
              ),
              gridData: const FlGridData(show: false),
              borderData: FlBorderData(show: false),
              titlesData: const FlTitlesData(show: false),
            ),
          ),
        ),
      ),
    );
  }
}
