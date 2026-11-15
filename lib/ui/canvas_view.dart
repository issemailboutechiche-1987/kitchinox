// Zone graphique : vue du dessus (plan réaliste), vue de face d'un mur, vue 3D.
// - Clic : sélection. Glisser un élément : déplacement (le moteur aimante et refuse les chevauchements).
// - Glisser le vide : déplacer la vue (plan / face) ou tourner autour de la pièce (3D).
// - Molette : zoom autour du curseur.

import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../engine/engine.dart';
import 'app_state.dart';
import 'finishes.dart';
import 'fronts.dart';
import 'net_symbols.dart';
import 'openings_ui.dart';
import 'scene3d.dart';
import 'theme.dart';
import 'toolbar.dart' show showIslandDialog;
import 'view3d.dart';
import 'i18n.dart';
import 'app_settings.dart';

const _wallThickness = 120.0;

/// Transformation monde (mm) → écran (px) des vues 2D.
class _View {
  final double k, ox, oy;
  final bool front;
  const _View(this.k, this.ox, this.oy, this.front);
  Offset toScreen(double a, double b) => front ? Offset(ox + a * k, oy - b * k) : Offset(ox + a * k, oy + b * k);
  (double, double) toWorld(Offset p) => front ? ((p.dx - ox) / k, (oy - p.dy) / k) : ((p.dx - ox) / k, (p.dy - oy) / k);
  Rect rect(double a0, double b0, double a1, double b1) => Rect.fromPoints(toScreen(a0, b0), toScreen(a1, b1));
}

/// Position à l'écran d'un point de réseau (null s'il n'est pas visible dans cette vue).
Offset? _netPos(AppState st, _View v, NetPoint x) {
  final room = st.project.room;
  if (x.hidden) return null;
  if (v.front) {
    if (x.onCeiling || x.wallId != st.wallId) return null;
    return v.toScreen(x.s, x.z);
  }
  if (x.onCeiling) return v.toScreen(x.s, x.z);
  if (x.wallId == 'I') {
    if (room.island == null) return null;
    final (px, py) = room.wall('I').toPlan(x.s, -40);
    return v.toScreen(px, py);
  }
  final (px, py) = room.wall(x.wallId).toPlan(x.s, -_wallThickness / 2);
  return v.toScreen(px, py);
}

double _netRadius(_View v) => v.front ? (v.k * 42).clamp(7.0, 16.0) : (v.k * 30).clamp(5.0, 11.0);

class PlannerCanvas extends StatefulWidget {
  final AppState state;
  final void Function(String message) onMessage;
  const PlannerCanvas({super.key, required this.state, required this.onMessage});

  @override
  State<PlannerCanvas> createState() => _PlannerCanvasState();
}

class _PlannerCanvasState extends State<PlannerCanvas> with SingleTickerProviderStateMixin {
  Ticker? _tickerOrNull;
  Ticker get _ticker => _tickerOrNull ??= createTicker(_tick);
  Duration _last = Duration.zero;

  void _tick(Duration elapsed) {
    final dt = ((elapsed - _last).inMicroseconds / 1e6).clamp(0.0, 0.1);
    _last = elapsed;
    if (!st.stepOpen(dt)) {
      _ticker.stop();
      _last = Duration.zero;
    }
  }

  @override
  void dispose() {
    _tickerOrNull?.dispose();
    super.dispose();
  }

  static const _pad = 72.0;
  _View? _view;
  Camera3d? _cam;
  List<HitFace> _hits3d = const [];

  // geste en cours
  String? _dragUid;
  bool _dragOpening = false;
  String? _dragPoint;
  // glisser d'un mur : vue figée pendant le geste pour éviter que le plan se recentre sous la souris
  String? _dragWall, _hoverWall;
  (double, double)? _dragIsland;
  double _wallApplied = 0;
  _View? _frozen;
  String? _wallError;
  bool _panning = false;
  Offset? _dragStartLocal;
  double _startS = 0, _startZ = 0, _grab = 0;
  String? _hoverUid;
  bool _snapped = false;

  AppState get st => widget.state;
  bool get _editCabinets => st.step == PlanStep.layout;
  bool get _editOpenings => st.step == PlanStep.space;

  _View _computeView(Size size) {
    final room = st.project.room;
    final front = st.view == ViewMode.front;
    final ww = front ? room.wall(st.wallId).length : room.width + 2 * _wallThickness;
    final wh = front ? room.height : room.depth + 2 * _wallThickness;
    final bottomExtra = front ? 70.0 : 30.0; // cotes sous le sol + sélecteur de vue
    final k0 = math.max(0.01, math.min((size.width - 2 * _pad - (front ? 120 : 0)) / ww, (size.height - 2 * _pad - bottomExtra) / wh));
    final k = k0 * st.zoom;
    final ox = (size.width - (front ? ww : room.width) * k) / 2 + st.panX;
    final oy = front
        ? size.height - (size.height - wh * k) / 2 - bottomExtra / 2 + st.panY
        : (size.height - room.depth * k) / 2 - bottomExtra / 2 + st.panY;
    return _View(k, ox, oy, front);
  }

  // ---------------------------------------------------------------- sélection

  /// (uid, est une ouverture)
  (String, bool)? _hit(Offset p) {
    if (st.view == ViewMode.view3d) {
      for (final h in _hits3d.reversed) {
        if (h.path.contains(p)) return (h.uid, false);
      }
      return null;
    }
    final v = _view;
    if (v == null) return null;
    // ouvertures d'abord à l'étape « espace »
    if (_editOpenings) {
      for (final o in st.project.openings) {
        if (_openingRect(v, o).inflate(6).contains(p)) return (o.uid, true);
      }
    }
    if (v.front) {
      final rects = st.engine.elevation(st.wallId).where((r) => r.onThisWall).toList();
      for (final r in _paintOrder(rects).reversed) {
        if (v.rect(r.s0, r.z0, r.s1, r.z1).contains(p)) return (r.uid, false);
      }
    } else {
      for (final s in _planOrder(st.engine.planView()).reversed) {
        final path = Path()..addPolygon([for (final (x, y) in s.points) v.toScreen(x, y)], true);
        if (path.contains(p)) return (s.uid, false);
      }
    }
    if (!_editOpenings) {
      for (final o in st.project.openings) {
        if (_openingRect(v, o).contains(p)) return (o.uid, true);
      }
    }
    return null;
  }

  Rect _openingRect(_View v, Opening o) {
    final room = st.project.room;
    if (v.front) {
      if (o.wallId != st.wallId) return Rect.zero;
      return v.rect(o.s, o.z, o.right, o.z + o.height);
    }
    final w = room.wall(o.wallId);
    final (ax, ay) = w.toPlan(o.s, -_wallThickness);
    final (bx, by) = w.toPlan(o.right, o.isDoor ? o.width : 0);
    return Rect.fromPoints(v.toScreen(ax, ay), v.toScreen(bx, by));
  }

  /// Objet de la pièce sous le pointeur (vue du dessus).
  String? _hitObject(Offset p) {
    final v = _view;
    if (v == null) return null;
    if (v.front && st.view == ViewMode.front) {
      // vue de face : objets contre le mur affiché (dessinés en élévation)
      final (sa, za) = v.toWorld(p);
      final wall = st.project.room.wall(st.wallId);
      for (final o in st.project.objects.reversed) {
        final (x0, y0, x1, y1) = o.footprint;
        final cs = [wall.toWall(x0, y0), wall.toWall(x1, y0), wall.toWall(x0, y1), wall.toWall(x1, y1)];
        final t0 = cs.map((c) => c.$2).reduce(math.min);
        if (t0 > 200 || t0 < -10) continue;
        final s0 = cs.map((c) => c.$1).reduce(math.min), s1 = cs.map((c) => c.$1).reduce(math.max);
        if (sa >= s0 && sa <= s1 && za >= o.z && za <= o.z + o.h) return o.uid;
      }
      return null;
    }
    if (v.front || st.view != ViewMode.plan) return null;
    final (wx, wy) = v.toWorld(p);
    for (final o in st.project.objects.reversed) {
      final (x0, y0, x1, y1) = o.footprint;
      if (wx >= x0 - 3 / v.k && wx <= x1 + 3 / v.k && wy >= y0 - 3 / v.k && wy <= y1 + 3 / v.k) return o.uid;
    }
    return null;
  }

  String? _dragObject;
  Offset _objGrab = Offset.zero;

  /// Îlot sous le pointeur (vue du dessus, hors caissons).
  bool _hitIsland(Offset p) {
    final v = _view, isl = st.project.room.island;
    if (v == null || v.front || isl == null || st.view != ViewMode.plan) return false;
    return v.rect(isl.x0, isl.y0, isl.x0 + isl.length, isl.y0 + Island.depth + isl.overhang).contains(p);
  }

  /// Mur sous le pointeur (bande grise du plan, avec un peu de tolérance).
  String? _hitWall(Offset p) {
    if (st.project.room.outline != null) return null;
    final v = _view;
    if (v == null || v.front || st.view != ViewMode.plan) return null;
    for (final w in st.project.room.walls) {
      final a = w.toPlan(0, -_wallThickness), b = w.toPlan(w.length, 0);
      final r = Rect.fromPoints(v.toScreen(a.$1, a.$2), v.toScreen(b.$1, b.$2)).inflate(6);
      if (r.contains(p)) return w.id;
    }
    return null;
  }

  /// Point de réseau sous le pointeur (les plus récents au-dessus).
  String? _hitPoint(Offset p) {
    final v = _view;
    if (v == null || !st.project.networks) return null;
    final r = _netRadius(v) + 3;
    for (final x in st.project.points.reversed) {
      final o = _netPos(st, v, x);
      if (o != null && (o - p).distance <= r) return x.uid;
    }
    return null;
  }

  Gap? _hitGap(Offset p) {
    final v = _view;
    if (v == null || !v.front || !_editCabinets) return null;
    for (final g in st.engine.gaps().where((g) => g.wallId == st.wallId && g.fillable)) {
      if (_gapRect(st, v, g).inflate(4).contains(p)) return g;
    }
    return null;
  }

  // ---------------------------------------------------------------- gestes

  // double clic (deux clics rapprochés sur le même meuble) : ouvrir / fermer en 3D
  DateTime? _lastTap;
  String? _lastTapUid;

  /// Cote extérieure de la pièce sous le doigt : 'w' (largeur) ou 'd' (profondeur).
  String? _hitRoomDim(Offset p) {
    final v = _view;
    if (v == null || v.front || st.view != ViewMode.plan || st.step == PlanStep.summary) return null;
    const t = _wallThickness;
    final r = st.project.room;
    final top = Offset.lerp(v.toScreen(0, -t), v.toScreen(r.width, -t), 0.5)! + const Offset(0, -26);
    final left = Offset.lerp(v.toScreen(-t, 0), v.toScreen(-t, r.depth), 0.5)! + const Offset(-26, 0);
    if (Rect.fromCenter(center: top, width: 140, height: 36).contains(p)) return 'w';
    if (Rect.fromCenter(center: left, width: 36, height: 140).contains(p)) return 'd';
    return null;
  }

  Future<void> _editRoomDim(String which) async {
    final r = st.project.room;
    final cur = which == 'w' ? r.width : r.depth;
    final c = TextEditingController(text: lenValue(cur));
    final v = await showDialog<double>(
      context: context,
      builder: (ctx) {
        void ok() => Navigator.pop(ctx, editedLen(c.text, cur));
        return AlertDialog(
          title: Text(which == 'w' ? tr('Largeur de la pièce') : tr('Profondeur de la pièce')),
          content: TextField(
            key: const Key('room-dim-field'),
            controller: c,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.allow(lenInputPattern)],
            decoration: InputDecoration(suffixText: lenSuffix, border: const OutlineInputBorder(), helperText: lenRange(1000, 15000)),
            onSubmitted: (_) => ok(),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Annuler'))),
            FilledButton(onPressed: ok, child: Text(tr('Valider'))),
          ],
        );
      },
    );
    c.dispose();
    if (v == null || v < 1000 || v > 15000) return;
    which == 'w' ? st.updateRoom(width: v) : st.updateRoom(depth: v);
    widget.onMessage('${which == 'w' ? 'Largeur' : 'Profondeur'} : ${lenText(v)}');
  }

  void _onTapUp(TapUpDetails d) {
    final dim = _hitRoomDim(d.localPosition);
    if (dim != null) {
      _editRoomDim(dim);
      return;
    }
    if (st.view == ViewMode.view3d) {
      final h = _hit(d.localPosition);
      final now = DateTime.now();
      if (h != null && !h.$2 && h.$1 == _lastTapUid && _lastTap != null && now.difference(_lastTap!) < const Duration(milliseconds: 400)) {
        st.toggleOpen(h.$1);
        _lastTap = null;
        _lastTapUid = null;
        return;
      }
      _lastTap = now;
      _lastTapUid = h?.$1;
    }
    final np = _hitPoint(d.localPosition);
    if (np != null) {
      st.selectPoint(np);
      return;
    }
    final ob = _hitObject(d.localPosition);
    if (ob != null) {
      st.selectObject(ob);
      return;
    }
    final h = _hit(d.localPosition);
    if (h == null && _hitIsland(d.localPosition) && st.step != PlanStep.summary) {
      // toucher l'îlot (hors de ses caissons) : ses réglages
      showIslandDialog(context, st, widget.onMessage);
      return;
    }
    if (h != null) {
      h.$2 ? st.selectOpening(h.$1) : st.select(h.$1);
      return;
    }
    final g = _hitGap(d.localPosition);
    if (g != null) {
      final err = st.edit(() => st.engine.fillGap(g));
      widget.onMessage(err ?? trp('Fileur de {0} ajouté', [lenText(g.width)]));
      return;
    }
    st.select(null);
    st.selectOpening(null);
    st.selectPoint(null);
    st.selectObject(null);
  }

  void _onPanStart(DragStartDetails d) {
    _dragStartLocal = d.localPosition;
    final ob = st.step == PlanStep.summary || st.view != ViewMode.plan ? null : _hitObject(d.localPosition);
    if (ob != null) {
      final o = st.project.objects.firstWhere((x) => x.uid == ob);
      final (wx, wy) = _view!.toWorld(d.localPosition);
      _objGrab = Offset(wx - o.x, wy - o.y);
      _dragObject = ob;
      st.selectObject(ob);
      st.beginDrag();
      return;
    }
    final np = st.step == PlanStep.summary ? null : _hitPoint(d.localPosition);
    if (np != null) {
      final x = st.project.pointByUid(np)!;
      // en plan, seuls les points du plafond se déplacent librement (les autres glissent le long du mur en vue de face)
      if (_view!.front || x.onCeiling) {
        st.selectPoint(np);
        _dragPoint = np;
        _startS = x.s;
        _startZ = x.z;
        st.beginDrag();
        return;
      }
    }
    final h = _hit(d.localPosition);
    // en 3D, on déplace les meubles aussi à l'étape Style
    final canDrag = h != null &&
        (h.$2 ? _editOpenings && st.view != ViewMode.view3d : _editCabinets || (st.view == ViewMode.view3d && st.step == PlanStep.style));
    if (!canDrag) {
      if (h == null && _hitIsland(d.localPosition) && st.step != PlanStep.summary) {
        final isl = st.project.room.island!;
        _dragIsland = (isl.x0, isl.y0);
        _frozen = _view;
        st.beginDrag();
        return;
      }
      final wall = h == null ? _hitWall(d.localPosition) : null;
      if (wall != null && st.step != PlanStep.summary) {
        _dragWall = wall;
        _wallApplied = 0;
        _wallError = null;
        _frozen = _view;
        st.beginDrag();
        return;
      }
      _panning = true;
      return;
    }
    final (uid, isOpening) = h;
    _dragUid = uid;
    _dragOpening = isOpening;
    final room = st.project.room;
    if (isOpening) {
      final o = st.project.openingByUid(uid)!;
      st.selectOpening(uid);
      _startS = o.s;
      final (wx, wy) = _view!.toWorld(d.localPosition);
      _grab = _view!.front ? 0 : room.wall(o.wallId).toWall(wx, wy).$1 - o.s;
    } else {
      final it = st.project.byUid(uid)!;
      st.select(uid);
      _startS = it.s;
      _startZ = it.z;
      if (_view != null) {
        final (wx, wy) = _view!.toWorld(d.localPosition);
        _grab = _view!.front ? 0 : room.wall(it.wallId).toWall(wx, wy).$1 - it.s;
      }
    }
    st.beginDrag();
  }

  void _onPanUpdate(DragUpdateDetails d) {
    if (_dragObject != null) {
      final (wx, wy) = _view!.toWorld(d.localPosition);
      st.dragObjectTo(_dragObject!, wx - _objGrab.dx, wy - _objGrab.dy);
      return;
    }
    if (_dragPoint != null) {
      final v = _view!;
      final delta = d.localPosition - _dragStartLocal!;
      st.dragPointTo(_dragPoint!, s: _startS + delta.dx / v.k, z: v.front ? _startZ - delta.dy / v.k : _startZ + delta.dy / v.k);
      return;
    }
    if (_panning) {
      if (st.view == ViewMode.view3d) {
        st.rotate3d(d.delta.dx * 0.008);
      } else {
        st.pan(d.delta.dx, d.delta.dy);
      }
      return;
    }
    if (_dragIsland != null) {
      final v = _frozen!;
      final move = (d.localPosition - _dragStartLocal!) / v.k;
      final (x0, y0) = _dragIsland!;
      final err = st.moveIsland((((x0 + move.dx) / 10).round() * 10).toDouble(), (((y0 + move.dy) / 10).round() * 10).toDouble());
      if (err != null && err != _wallError) {
        _wallError = err;
        widget.onMessage(err);
      }
      return;
    }
    if (_dragWall != null) {
      final v = _frozen!;
      final w = st.project.room.wall(_dragWall!);
      final move = (d.localPosition - _dragStartLocal!) / v.k;
      // vers l'extérieur = sens opposé à la normale intérieure ; pas de 10 mm
      final desired = ((move.dx * -w.nx + move.dy * -w.ny) / 10).round() * 10.0;
      if (desired != _wallApplied) {
        final step = desired - _wallApplied;
        final err = st.moveWall(_dragWall!, step);
        if (err == null) {
          // murs A et C : l'origine du plan bouge avec eux, on décale la vue pour qu'ils suivent la souris
          if (_dragWall == 'A') _frozen = _View(v.k, v.ox, v.oy - step * v.k, v.front);
          if (_dragWall == 'C') _frozen = _View(v.k, v.ox - step * v.k, v.oy, v.front);
          _wallApplied = desired;
          _wallError = null;
        } else if (_wallError != err) {
          _wallError = err;
          widget.onMessage(err);
        }
      }
      return;
    }
    final uid = _dragUid, v = _view;
    if (uid != null && st.view == ViewMode.view3d && _cam != null) {
      // 3D : le caisson glisse le long de son mur (et monte / descend pour les hauts)
      final it = st.project.byUid(uid);
      if (it == null) return;
      final cam = _cam!;
      final w = st.project.room.wall(it.wallId);
      final delta = d.localPosition - _dragStartLocal!;
      final du = cam.v(w.dx, w.dy, 0), dz = cam.v(0, 0, 1);
      double ds, dzv = 0;
      final canZ = st.engine.canMoveVertically(st.engine.modelOf(it));
      final det = du.dx * dz.dy - du.dy * dz.dx;
      if (canZ && det.abs() > 1e-9) {
        ds = (delta.dx * dz.dy - delta.dy * dz.dx) / det;
        dzv = (du.dx * delta.dy - du.dy * delta.dx) / det;
      } else {
        ds = (delta.dx * du.dx + delta.dy * du.dy) / math.max(1e-9, du.distanceSquared);
      }
      final r = st.dragTo(uid, s: _startS + ds, z: canZ ? _startZ + dzv : null);
      if (r.snapped != _snapped) setState(() => _snapped = r.snapped);
      return;
    }
    if (uid == null || v == null) return;
    final delta = d.localPosition - _dragStartLocal!;
    if (_dragOpening) {
      final o = st.project.openingByUid(uid);
      if (o == null) return;
      if (v.front) {
        st.dragOpeningTo(uid, s: _startS + delta.dx / v.k);
      } else {
        final (wx, wy) = v.toWorld(d.localPosition);
        final (wall, s) = _nearestWall(wx, wy, onlyEnabled: false);
        st.dragOpeningTo(uid, wallId: wall, s: s - (wall == o.wallId ? _grab : o.width / 2));
      }
      return;
    }
    final it = st.project.byUid(uid);
    if (it == null) return;
    MoveResult r;
    if (v.front) {
      if (it.wallId != st.wallId) return;
      r = st.dragTo(uid, s: _startS + delta.dx / v.k, z: _startZ - delta.dy / v.k);
    } else {
      final (wx, wy) = v.toWorld(d.localPosition);
      final (wall, s) = _nearestWall(wx, wy);
      r = st.dragTo(uid, wallId: wall, s: s - (wall == it.wallId ? _grab : it.width / 2));
    }
    if (r.snapped != _snapped) setState(() => _snapped = r.snapped);
  }

  void _onPanEnd([DragEndDetails? _]) {
    if (_dragObject != null) {
      _dragObject = null;
      st.endDrag();
      return;
    }
    if (_dragPoint != null) {
      _dragPoint = null;
      st.endDrag();
      return;
    }
    if (_panning) {
      _panning = false;
      return;
    }
    if (_dragIsland != null) {
      setState(() {
        _dragIsland = null;
        _frozen = null;
        _wallError = null;
      });
      st.endDrag();
      return;
    }
    if (_dragWall != null) {
      final r = st.project.room;
      final id = _dragWall!;
      setState(() {
        _dragWall = null;
        _frozen = null;
      });
      st.endDrag();
      if (_wallApplied != 0) {
        final along = id == 'A' || id == 'D' ? 'Profondeur' : 'Largeur';
        widget.onMessage(trp('{0} de la pièce : {1}', [along, lenText((id == 'A' || id == 'D' ? r.depth : r.width))]));
      }
      return;
    }
    if (_dragUid == null) return;
    _dragUid = null;
    _snapped = false;
    st.endDrag();
  }

  void _onScroll(PointerSignalEvent e) {
    if (e is! PointerScrollEvent) return;
    final f = e.scrollDelta.dy < 0 ? 1.12 : 1 / 1.12;
    final nz = (st.zoom * f).clamp(0.4, 6.0);
    final ratio = nz / st.zoom;
    final box = context.size!;
    // zoom autour du curseur
    final c = Offset(box.width / 2 + st.panX, box.height / 2 + st.panY);
    final p = e.localPosition;
    final np = p + (c - p) * ratio;
    st.setZoom(nz, px: np.dx - box.width / 2, py: np.dy - box.height / 2);
  }

  (String, double) _nearestWall(double x, double y, {bool onlyEnabled = true}) {
    String best = st.wallId;
    double bestD = double.infinity, bestS = 0;
    final room = st.project.room;
    for (final w in [...room.walls.where((w) => !onlyEnabled || w.enabled), if (room.island != null) room.wall('I')]) {
      final (s, t) = w.toWall(x, y);
      final sc = s.clamp(0.0, w.length);
      final dist = math.sqrt(math.pow(s - sc, 2) + t * t);
      if (dist < bestD) {
        bestD = dist;
        best = w.id;
        bestS = sc;
      }
    }
    return (best, bestS);
  }

  void _onDrop(DragTargetDetails<CabinetModel> d) {
    final box = context.findRenderObject() as RenderBox?;
    final v = _view;
    if (box == null) return;
    final m = d.data;
    final local = box.globalToLocal(d.offset + const Offset(40, 40));
    String? err;
    if (st.view == ViewMode.view3d || v == null) {
      err = st.addModel(m.id);
    } else if (v.front) {
      final (a, b) = v.toWorld(local);
      err = st.addModel(m.id, wall: st.wallId, s: a - m.defaultWidth / 2, z: m.kind.isHigh ? b - m.defaultHeight / 2 : null);
    } else {
      final (a, b) = v.toWorld(local);
      final (wall, s) = _nearestWall(a, b);
      err = st.addModel(m.id, wall: wall, s: s - m.defaultWidth / 2);
    }
    widget.onMessage(err ?? trp('{0} ajouté', [tr(m.name)]));
  }

  // ---------------------------------------------------------------- rendu

  @override
  Widget build(BuildContext context) {
    final pc = context.pc;
    final theme = Theme.of(context);
    return DragTarget<CabinetModel>(
      onAcceptWithDetails: _onDrop,
      builder: (context, candidates, _) => LayoutBuilder(
        builder: (context, c) {
          // vraie 3D (WebGL) dans le navigateur ; la vue dessinée reste pour les tests et les PDF
          if (st.view == ViewMode.view3d && webgl3dAvailable) return Kitchen3dView(state: st);
          final size = Size(c.maxWidth, c.maxHeight);
          if (st.view == ViewMode.view3d) {
            _cam = Camera3d.fit(st.project.room, st.yaw, size, zoom: st.zoom, panX: st.panX, panY: st.panY);
            if (st.animating && !_ticker.isActive) _ticker.start();
            _view = null;
          } else {
            _view = _frozen ?? _computeView(size);
            _cam = null;
          }
          return Listener(
            onPointerSignal: _onScroll,
            child: MouseRegion(
              cursor: (_dragWall ?? _hoverWall) != null
                  ? ((_dragWall ?? _hoverWall) == 'A' || (_dragWall ?? _hoverWall) == 'D'
                        ? SystemMouseCursors.resizeUpDown
                        : SystemMouseCursors.resizeLeftRight)
                  : _dragUid != null || _panning
                  ? SystemMouseCursors.grabbing
                  : _hoverUid != null
                  ? (st.view == ViewMode.view3d ? SystemMouseCursors.click : SystemMouseCursors.grab)
                  : SystemMouseCursors.basic,
              onHover: (e) {
                final h = _hitPoint(e.localPosition) ?? _hit(e.localPosition)?.$1;
                final w = h == null && st.step != PlanStep.summary ? _hitWall(e.localPosition) : null;
                if (h != _hoverUid || w != _hoverWall) {
                  setState(() {
                    _hoverUid = h;
                    _hoverWall = w;
                  });
                }
              },
              onExit: (_) => setState(() {
                _hoverUid = null;
                _hoverWall = null;
              }),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                dragStartBehavior: DragStartBehavior.down,
                onTapUp: _onTapUp,
                onPanStart: _onPanStart,
                onPanUpdate: _onPanUpdate,
                onPanEnd: _onPanEnd,
                onPanCancel: _onPanEnd,
                child: Semantics(
                  label: switch (st.view) {
                    ViewMode.plan => tr('Plan vu du dessus'),
                    ViewMode.front => trp('Vue de face, {0}', [Room.wallNames[st.wallId]]),
                    ViewMode.view3d => tr('Vue 3D de la cuisine'),
                  },
                  child: CustomPaint(
                    size: size,
                    painter: _PlannerPainter(
                      st: st,
                      view: _view,
                      cam: _cam,
                      pc: pc,
                      text: theme.textTheme.labelSmall!.copyWith(color: pc.dimension),
                      dropActive: candidates.isNotEmpty,
                      hover: _hoverUid,
                      wallFocus: _dragWall ?? _hoverWall,
                      wallDragging: _dragWall != null,
                      snapped: _snapped,
                      primary: theme.colorScheme.primary,
                      onHits: (h) => _hits3d = h,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

List<ElevationRect> _paintOrder(List<ElevationRect> rects) {
  int rank(ElevationRect r) => r.model.kind.isHigh ? 2 : (r.model.kind == CabinetKind.tall ? 1 : 0);
  return [...rects]..sort((a, b) => rank(a).compareTo(rank(b)));
}

List<PlanShape> _planOrder(List<PlanShape> shapes) {
  int rank(PlanShape s) => s.model.kind.isHigh ? 2 : (s.model.kind == CabinetKind.tall ? 1 : 0);
  return [...shapes]..sort((a, b) => rank(a).compareTo(rank(b)));
}

Rect _gapRect(AppState st, _View v, Gap g) {
  final std = st.project.standards;
  final (z0, z1) = g.band == Band.low
      ? (std.plinthHeight.toDouble(), std.baseTop.toDouble())
      : (std.wallBottomDefault.toDouble(), std.wallBottomDefault + 600.0);
  return v.rect(g.s0, z0, g.s1, z1);
}

class _PlannerPainter extends CustomPainter {
  final AppState st;
  final _View? view;
  final Camera3d? cam;
  final PlannerColors pc;
  final TextStyle text;
  final bool dropActive;
  final String? hover;
  final String? wallFocus;
  final bool wallDragging;
  final bool snapped;
  final Color primary;
  final void Function(List<HitFace>) onHits;

  _PlannerPainter({
    required this.st,
    required this.view,
    required this.cam,
    required this.pc,
    required this.text,
    required this.dropActive,
    required this.hover,
    this.wallFocus,
    this.wallDragging = false,
    required this.snapped,
    required this.primary,
    required this.onHits,
  });

  Project get p => st.project;
  Finish get front => frontFinish(p.style, p.style.frontLower ?? p.style.front);
  Finish get top => worktopFinish(p.style, p.style.worktop);

  Paint _stroke(Color c, double w) => Paint()
    ..color = c
    ..style = PaintingStyle.stroke
    ..strokeWidth = w;

  void _label(Canvas canvas, String s, Offset center, {TextStyle? style, double maxWidth = 260, Color? bg}) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: style ?? text),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: math.max(0, maxWidth));
    final o = center - Offset(tp.width / 2, tp.height / 2);
    if (bg != null) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(o.dx - 5, o.dy - 2, tp.width + 10, tp.height + 4), const Radius.circular(4)),
        Paint()..color = bg,
      );
    }
    tp.paint(canvas, o);
  }

  void _dashed(Canvas canvas, Offset a, Offset b, Paint p, {double dash = 6, double gap = 4}) {
    final d = b - a;
    final len = d.distance;
    if (len == 0) return;
    final u = d / len;
    for (var t = 0.0; t < len; t += dash + gap) {
      canvas.drawLine(a + u * t, a + u * math.min(len, t + dash), p);
    }
  }

  void _dashedPath(Canvas canvas, List<Offset> pts, Paint p) {
    for (var i = 0; i < pts.length; i++) {
      _dashed(canvas, pts[i], pts[(i + 1) % pts.length], p, dash: 5, gap: 3);
    }
  }

  /// Cote : trait fin, barres d'extrémité, valeur au milieu sur fond.
  void _dim(Canvas canvas, Offset a, Offset b, String value, {bool vertical = false}) {
    final p = _stroke(pc.dimension, 1);
    canvas.drawLine(a, b, p);
    final n = vertical ? const Offset(6, 0) : const Offset(0, 6);
    canvas.drawLine(a - n, a + n, p);
    canvas.drawLine(b - n, b + n, p);
    final mid = Offset.lerp(a, b, 0.5)!;
    final style = text.copyWith(fontSize: 12, fontWeight: FontWeight.w600);
    if (vertical) {
      canvas.save();
      canvas.translate(mid.dx, mid.dy);
      canvas.rotate(-math.pi / 2);
      _label(canvas, value, Offset.zero, bg: pc.canvas, style: style);
      canvas.restore();
    } else {
      _label(canvas, value, mid, bg: pc.canvas, style: style);
    }
  }

  /// Cote alignée le long d'un segment libre (pour les murs de forme personnalisée)
  void _dimAligned(Canvas canvas, Offset p0, Offset p1, Offset normal, double offsetDist, String value) {
    final a = p0 + normal * offsetDist;
    final b = p1 + normal * offsetDist;
    final p = _stroke(pc.dimension, 1.2);
    // Lignes de rappel depuis les extrémités du mur
    canvas.drawLine(p0 + normal * 4, a + normal * 6, _stroke(pc.dimension.withValues(alpha: 0.45), 0.8));
    canvas.drawLine(p1 + normal * 4, b + normal * 6, _stroke(pc.dimension.withValues(alpha: 0.45), 0.8));
    // Ligne de cote
    canvas.drawLine(a, b, p);
    // Ticks à 45°
    final dir = (b - a);
    if (dir.distanceSquared == 0) return;
    final u = dir / dir.distance;
    final n = Offset(-u.dy, u.dx);
    final tick = (u + n) * 5;
    canvas.drawLine(a - tick, a + tick, p);
    canvas.drawLine(b - tick, b + tick, p);
    // Étiquette orientée le long du mur
    final mid = Offset.lerp(a, b, 0.5)!;
    var ang = math.atan2(dir.dy, dir.dx);
    if (ang > math.pi / 2 || ang < -math.pi / 2) ang += math.pi;
    canvas.save();
    canvas.translate(mid.dx, mid.dy);
    canvas.rotate(ang);
    _label(canvas, value, const Offset(0, -9), bg: pc.canvas, style: text.copyWith(fontSize: 11, fontWeight: FontWeight.w700, color: pc.dimension));
    canvas.restore();
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = pc.canvas);
    if (cam != null) {
      final hits = Scene3dPainter(
        st.engine,
        cam!,
        selected: st.selected,
        hover: hover,
        selectColor: pc.selected,
        background: pc.canvas,
        open: st.openness,
        handles: st.db?.handles,
      ).paint(canvas, size);
      onHits(hits);
    } else if (view!.front) {
      _paintFront(canvas);
    } else {
      _paintPlan(canvas);
    }
    if (view != null && p.networks) _paintNetworks(canvas);
    if (view != null && cam == null && st.guides.isNotEmpty) _paintGuides(canvas, size);
    if (dropActive) canvas.drawRect((Offset.zero & size).deflate(3), _stroke(primary, 3));
  }

  // ================================================================ guides d'alignement

  void _paintGuides(Canvas canvas, Size size) {
    final v = view!;
    const col = Color(0xFFF26A1B);
    final paint = _stroke(col, 1.4);
    for (final g in st.guides) {
      Offset a, b;
      if (g.wall != null) {
        if (v.front) {
          if (g.wall != st.wallId) continue;
          a = v.toScreen(g.at, -150);
          b = v.toScreen(g.at, p.room.height + 150);
        } else {
          if (g.wall == 'I') continue;
          final w = p.room.wall(g.wall!);
          final (ax, ay) = w.toPlan(g.at, -_wallThickness - 200);
          final (bx, by) = w.toPlan(g.at, 1500);
          a = v.toScreen(ax, ay);
          b = v.toScreen(bx, by);
        }
      } else {
        if (v.front) continue;
        a = g.vertical ? v.toScreen(g.at, -_wallThickness) : v.toScreen(-_wallThickness, g.at);
        b = g.vertical ? v.toScreen(g.at, p.room.depth + _wallThickness) : v.toScreen(p.room.width + _wallThickness, g.at);
      }
      _dashed(canvas, a, b, paint);
      _label(canvas, g.label, Offset.lerp(a, b, 0.12)!, bg: col, style: text.copyWith(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 11));
    }
  }

  // ================================================================ réseaux

  void _paintNetworks(Canvas canvas) {
    final v = view!;
    final r = _netRadius(v);
    final std = p.standards;
    // en vue de face : un point derrière un caisson est dessiné un peu transparent
    final rects = v.front ? st.engine.elevation(st.wallId).where((e) => e.onThisWall).toList() : const <ElevationRect>[];
    NetPoint? sel;
    for (final x in p.points) {
      final o = _netPos(st, v, x);
      if (o == null) continue;
      final behind = v.front && rects.any((e) => x.s > e.s0 && x.s < e.s1 && x.z > e.z0 && x.z < e.z1);
      final selected = st.selectedPoint == x.uid;
      if (selected) sel = x;
      paintNetSymbol(canvas, o, x.kind, r, selected: selected || hover == x.uid, behind: behind);
    }
    // cotes du point sélectionné : depuis la gauche du mur et depuis le sol
    if (sel != null && v.front) {
      final o = v.toScreen(sel.s, sel.z);
      final floor = v.toScreen(sel.s, 0);
      final left = v.toScreen(0, sel.z);
      final dp = _stroke(netColor(sel.kind), 1.2);
      _dashed(canvas, left, o, dp);
      _dashed(canvas, floor, o, dp);
      _label(
        canvas,
        lenValue(sel.s),
        Offset.lerp(left, o, 0.5)! - const Offset(0, 10),
        bg: netColor(sel.kind),
        style: text.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
      );
      _label(
        canvas,
        'H ${lenValue(sel.z)}',
        Offset.lerp(floor, o, 0.5)! + const Offset(28, 0),
        bg: netColor(sel.kind),
        style: text.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
      );
      if (sel.z > std.worktopTop && sel.kind.network == 'elec') {
        _label(canvas, '+${lenValue((sel.z - std.worktopTop))} / plan', o + Offset(0, -r - 14), bg: pc.canvas, style: text);
      }
    }
  }

  // ================================================================ vue du dessus

  void _paintPlan(Canvas canvas) {
    final v = view!;
    final room = p.room;
    final w0 = room.width, d0 = room.depth;
    const t = _wallThickness;

    // murs (bande extérieure) puis sol en parquet ; pièce à contour libre : le sol suit les traits et les arcs
    final ff = floorFinish(p.style);
    if (room.outline == null) {
      final outer = v.rect(-t, -t, w0 + t, d0 + t);
      canvas.drawRect(outer, Paint()..color = pc.wallBand);
      final floor = v.rect(0, 0, w0, d0);
      canvas.drawRect(floor, Paint()..color = ff.color);
      if (!ff.textured) _parquet(canvas, v, w0, d0);
    } else {
      final path = Path()..addPolygon([for (final (x, y) in room.floorPolygon) v.toScreen(x, y)], true);
      // trait épais centré sur le contour : sa moitié extérieure fait l'épaisseur du mur
      canvas.drawPath(path, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2 * t * v.k
        ..strokeJoin = StrokeJoin.miter
        ..color = pc.wallBand);
      canvas.drawPath(path, Paint()..color = ff.color);
      canvas.save();
      canvas.clipPath(path);
      if (!ff.textured) _parquet(canvas, v, w0, d0);
      canvas.restore();
      // cotation architecturale de chaque mur le long de son orientation
      final wList = room.walls;
      final badgePositions = <Offset>[];
      for (var wi = 0; wi < wList.length; wi++) {
        final w = wList[wi];
        final p0 = v.toScreen(w.x0, w.y0);
        final (ex, ey) = w.end;
        final p1 = v.toScreen(ex, ey);
        final normScr = Offset(-w.nx, -w.ny);
        var off = math.max(26.0, (t + 40) * v.k);
        // Anti-collision entre badges de cotes proches (ex: mur court 54mm et mur 410mm)
        for (var tries = 0; tries < 5; tries++) {
          final mid = (p0 + p1) / 2 + normScr * off;
          final overlaps = badgePositions.any((bp) => (bp - mid).distance < 46);
          if (overlaps) {
            off += 26.0;
          } else {
            badgePositions.add(mid);
            break;
          }
        }
        _dimAligned(canvas, p0, p1, normScr, off, w.straight ? lenText(w.length) : 'arc ${lenText(w.length)}');
      }
    }

    // ouvertures
    for (final o in p.openings) {
      _planOpening(canvas, v, o);
    }

    // îlot : plan de travail avec débord repas (hachuré)
    final isl = room.island;
    if (isl != null) {
      final r = v.rect(isl.x0, isl.y0, isl.x0 + isl.length, isl.y0 + Island.depth + isl.overhang);
      canvas.drawRect(r, Paint()..color = top.color);
      canvas.drawRect(r, _stroke(const Color(0xFF6B6F75), wallFocus == 'I' ? 2.5 : 1.2));
      final over = v.rect(isl.x0, isl.y0 + Island.depth, isl.x0 + isl.length, isl.y0 + Island.depth + isl.overhang);
      canvas.save();
      canvas.clipRect(over);
      for (var d = -over.height; d < over.width; d += 10) {
        canvas.drawLine(Offset(over.left + d, over.bottom), Offset(over.left + d + over.height, over.top), _stroke(const Color(0x33000000), 1));
      }
      canvas.restore();
      _label(
        canvas,
        'Îlot ${lenText(isl.length)}',
        over.center,
        style: text.copyWith(fontWeight: FontWeight.w800, color: const Color(0xFF3F3A33)),
      );
    }

    // caissons vus de dessus
    final shapes = _planOrder(st.engine.planView());
    for (final s in shapes) {
      _planCabinet(canvas, v, s);
    }

    // objets de la pièce : sanitaires (symboles normalisés) et objets de décoration
    for (final o in p.objects) {
      _planObject(canvas, v, o);
    }

    // mur survolé ou en cours de déplacement : surligné, avec deux flèches perpendiculaires
    if (wallFocus != null) {
      final w = room.wall(wallFocus!);
      final a = w.toPlan(0, -t), b = w.toPlan(w.length, 0);
      final band = Rect.fromPoints(v.toScreen(a.$1, a.$2), v.toScreen(b.$1, b.$2));
      canvas.drawRect(band, Paint()..color = const Color(0xFF8CCDEA));
      final mid = w.toPlan(w.length / 2, -t / 2);
      final c = v.toScreen(mid.$1, mid.$2);
      final n = Offset(w.nx, w.ny); // vers l'intérieur
      final side = Offset(-n.dy, n.dx);
      final fill = Paint()..color = Colors.white;
      final ink = _stroke(const Color(0xFF55595F), 2);
      for (final dir in [n, -n]) {
        final tip = c + dir * 30;
        final base = c + dir * 14;
        final tri = Path()
          ..moveTo(tip.dx, tip.dy)
          ..lineTo((base + side * 9).dx, (base + side * 9).dy)
          ..lineTo((base - side * 9).dx, (base - side * 9).dy)
          ..close();
        canvas.drawPath(tri, fill);
        canvas.drawPath(tri, ink);
      }
      if (wallDragging) {
        final along = wallFocus == 'A' || wallFocus == 'D';
        final value = (along ? room.depth : room.width).round();
        _label(
          canvas,
          '${along ? 'Profondeur' : 'Largeur'} : $value mm',
          c + Offset(-n.dx, -n.dy) * (n.dx != 0 ? 110 : 40),
          bg: const Color(0xFFC94A10),
          style: text.copyWith(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13),
        );
      }
    }

    // cotes extérieures (pièce rectangulaire uniquement)
    if (room.outline == null) {
      _dim(canvas, v.toScreen(0, -t) + const Offset(0, -26), v.toScreen(w0, -t) + const Offset(0, -26), lenText(w0));
      _dim(canvas, v.toScreen(-t, 0) + const Offset(-26, 0), v.toScreen(-t, d0) + const Offset(-26, 0), lenText(d0), vertical: true);
    }

    // noms des murs, écrits dans l'épaisseur du mur (grisés si le mur ne reçoit pas de caissons)
    for (final w in room.walls) {
      final (cx, cy) = w.middle;
      final (mx, my) = (cx - w.nx * t / 2, cy - w.ny * t / 2);
      final mid = v.toScreen(mx, my);
      final style = text.copyWith(
        fontSize: 10,
        letterSpacing: 0.8,
        fontWeight: FontWeight.w800,
        color: w.enabled ? const Color(0xFF3D4650) : const Color(0xFF8A939D),
      );
      final label = 'MUR ${w.id}${w.enabled ? '' : ' · sans caissons'}';
      if (t * v.k < 10) continue;
      if (w.dx.abs() < 1e-6) {
        canvas.save();
        canvas.translate(mid.dx, mid.dy);
        canvas.rotate(w.nx < 0 ? math.pi / 2 : -math.pi / 2);
        _label(canvas, label, Offset.zero, style: style);
        canvas.restore();
      } else if (!w.orthogonal) {
        // mur oblique ou arc : nom dans le sens du mur
        canvas.save();
        canvas.translate(mid.dx, mid.dy);
        var ang = math.atan2(w.dy, w.dx);
        if (ang > math.pi / 2 || ang < -math.pi / 2) ang += math.pi;
        canvas.rotate(ang);
        _label(canvas, w.straight ? 'MUR ${w.id}' : 'ARC ${w.id}', Offset.zero, style: style);
        canvas.restore();
      } else {
        _label(canvas, label, mid, style: style);
      }
    }

    // surface au centre (si pas trop de monde)
    final area = room.area.toStringAsFixed(1).replaceAll('.', ',');
    final center = v.toScreen(w0 / 2, d0 / 2);
    _label(
      canvas,
      'Cuisine',
      center + const Offset(0, -10),
      style: text.copyWith(fontSize: 15, fontWeight: FontWeight.w600, color: const Color(0xFF3F3A33)),
    );
    _label(canvas, '$area m²', center + const Offset(0, 10), style: text.copyWith(fontSize: 12, color: const Color(0xFF3F3A33)));
  }

  /// Objet dos au mur affiché, dessiné en élévation (trait, sans rendu 3D).
  void _frontObject(Canvas canvas, _View v, Wall wall, RoomObject o) {
    final (x0, y0, x1, y1) = o.footprint;
    final corners = [wall.toWall(x0, y0), wall.toWall(x1, y0), wall.toWall(x0, y1), wall.toWall(x1, y1)];
    final t0 = corners.map((c) => c.$2).reduce(math.min);
    if (t0 > 200 || t0 < -10) return; // seulement les objets contre ce mur
    final s0 = corners.map((c) => c.$1).reduce(math.min), s1 = corners.map((c) => c.$1).reduce(math.max);
    final z0 = o.z, z1 = o.z + o.h;
    final r = v.rect(s0, z0, s1, z1);
    final k = v.k;
    final ink = _stroke(const Color(0xFF4A4F55), 1.2);
    final thin = _stroke(const Color(0x994A4F55), 1);
    final white = Paint()..color = const Color(0xFFFDFDFC);
    final steel = Paint()..color = const Color(0xFFB8BEC4);
    Rect at(double a0, double b0, double a1, double b1) => v.rect(s0 + a0, b0, s0 + a1, b1); // a : depuis la gauche, b : hauteur absolue
    final w = s1 - s0, mid = (s0 + s1) / 2;
    void tap(double cs, double z) {
      canvas.drawRect(v.rect(cs - 15, z, cs + 15, z + 150), steel);
      canvas.drawRect(v.rect(cs - 15, z + 120, cs + 70, z + 150), steel);
    }

    // objet contre le mur voisin, vu de profil : silhouette seulement
    final facing = wall.rot == o.rot % 360;
    final f = o.fixture;
    if (!facing) {
      final rr = RRect.fromRectAndRadius(r, Radius.circular(math.min(r.width, r.height) * 0.08));
      canvas.drawRRect(rr, f == null ? (Paint()..color = const Color(0xCCEDE6DE)) : white);
      canvas.drawRRect(rr, ink);
      if (st.selectedObject == o.uid) canvas.drawRect(r.inflate(4), _stroke(pc.selected, 2.2));
      return;
    }
    switch (f?.id) {
      case 'wc_suspendu' || 'bidet':
        final bowl = at(w * 0.04, z1 - 280, w * 0.96, z1 - 20);
        final rr = RRect.fromRectAndCorners(bowl, bottomLeft: Radius.circular(bowl.width * 0.45), bottomRight: Radius.circular(bowl.width * 0.45));
        canvas.drawRRect(rr, white);
        canvas.drawRRect(rr, ink);
        canvas.drawRect(at(0, z1 - 20, w, z1), white);
        canvas.drawRect(at(0, z1 - 20, w, z1), ink);
        if (f!.id == 'wc_suspendu') {
          final pl = v.rect(mid - 120, 980, mid + 120, 1140);
          canvas.drawRect(pl, steel);
          canvas.drawRect(pl, thin);
          canvas.drawLine(pl.topCenter, pl.bottomCenter, thin);
        } else {
          tap(mid, z1);
        }
      case 'wc_sol':
        final tank = at(w * 0.05, 400, w * 0.95, z1);
        canvas.drawRRect(RRect.fromRectAndRadius(tank, Radius.circular(4 * k + 1)), white);
        canvas.drawRRect(RRect.fromRectAndRadius(tank, Radius.circular(4 * k + 1)), ink);
        final bowl = at(0, 250, w, 420);
        canvas.drawRRect(RRect.fromRectAndCorners(bowl, bottomLeft: Radius.circular(bowl.width * 0.3), bottomRight: Radius.circular(bowl.width * 0.3)), white);
        canvas.drawRRect(RRect.fromRectAndCorners(bowl, bottomLeft: Radius.circular(bowl.width * 0.3), bottomRight: Radius.circular(bowl.width * 0.3)), ink);
        final foot = Path()
          ..addPolygon([v.toScreen(mid - w * 0.3, 260), v.toScreen(mid + w * 0.3, 260), v.toScreen(mid + w * 0.22, 0), v.toScreen(mid - w * 0.22, 0)], true);
        canvas.drawPath(foot, white);
        canvas.drawPath(foot, ink);
        canvas.drawRect(v.rect(mid - 30, z1, mid + 30, z1 + 8), steel);
      case 'lavabo' || 'vasque_double':
        canvas.drawRect(r, white);
        canvas.drawRect(r, ink);
        final n = f!.id == 'vasque_double' ? 2 : 1;
        for (var i = 0; i < n; i++) {
          final cs = s0 + w * (i + 0.5) / n;
          final bw = w / n * 0.6;
          canvas.drawLine(v.toScreen(cs - bw / 2, z1 - 20), v.toScreen(cs + bw / 2, z1 - 20), thin);
          tap(cs, z1);
          // siphon
          canvas.drawLine(v.toScreen(cs, z0), v.toScreen(cs, z0 - 250), _stroke(const Color(0xFF9AA0A6), math.max(1.5, 30 * k)));
          canvas.drawLine(v.toScreen(cs, z0 - 250), v.toScreen(cs - 1, 500), _stroke(const Color(0xFF9AA0A6), math.max(1.5, 30 * k)));
        }
      case 'baignoire':
        canvas.drawRRect(RRect.fromRectAndRadius(r, Radius.circular(30 * k)), white);
        canvas.drawRRect(RRect.fromRectAndRadius(r, Radius.circular(30 * k)), ink);
        canvas.drawLine(v.toScreen(s0, z1 - 60), v.toScreen(s1, z1 - 60), thin);
        tap(s0 + w * 0.15, z1 + 150);
      case 'douche' || 'douche_italienne':
        final tray = f!.id == 'douche';
        canvas.drawRect(v.rect(s0, 0, s1, tray ? 40 : 10), white);
        canvas.drawRect(v.rect(s0, 0, s1, tray ? 40 : 10), ink);
        final glassR = tray ? v.rect(s0, 40, s0 + w * 0.6, z1) : v.rect(s1 - 40, 10, s1, z1);
        canvas.drawRect(glassR, Paint()..color = const Color(0x445B9BD5));
        canvas.drawRect(glassR, _stroke(const Color(0xFF5B9BD5), 1.2));
        // colonne de douche
        canvas.drawLine(v.toScreen(mid, 900), v.toScreen(mid, 2000), _stroke(const Color(0xFF9AA0A6), math.max(1.5, 24 * k)));
        canvas.drawRect(v.rect(mid - 110, 1990, mid + 110, 2010), steel);
        canvas.drawRect(v.rect(mid - 40, 1050, mid + 40, 1150), steel);
      case 'seche_serviettes':
        canvas.drawRect(at(0, z0, 30, z1), steel);
        canvas.drawRect(at(w - 30, z0, w, z1), steel);
        for (var i = 0; i < 9; i++) {
          final zz = z0 + 40 + (o.h - 80) * i / 8;
          canvas.drawRect(at(0, zz - 11, w, zz + 11), steel);
        }
      case 'miroir':
        canvas.drawRect(r, Paint()
          ..shader = const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFEAF2F5), Color(0xFFC9D8DE), Color(0xFFEFF5F7)])
              .createShader(r));
        canvas.drawRect(r, _stroke(const Color(0xFF9AA0A6), 2));
        canvas.drawLine(Offset(r.left + r.width * 0.2, r.bottom), Offset(r.left + r.width * 0.55, r.top), _stroke(const Color(0x88FFFFFF), 6));
      case 'chauffe_eau':
        final rr = RRect.fromRectAndRadius(r, Radius.circular(r.width / 2));
        canvas.drawRRect(rr, white);
        canvas.drawRRect(rr, ink);
        canvas.drawLine(v.toScreen(mid - 60, z0), v.toScreen(mid - 60, z0 - 150), _stroke(const Color(0xFF9AA0A6), math.max(1.5, 24 * k)));
        canvas.drawLine(v.toScreen(mid + 60, z0), v.toScreen(mid + 60, z0 - 150), _stroke(const Color(0xFF9AA0A6), math.max(1.5, 24 * k)));
      default:
        // objet du catalogue libre : silhouette et nom
        final cat = st.objectCatalog.where((c) => c.id == o.ref).firstOrNull;
        final rr = RRect.fromRectAndRadius(r, Radius.circular(math.min(r.width, r.height) * 0.06));
        canvas.drawRRect(rr, Paint()..color = const Color(0xCCEDE6DE));
        canvas.drawRRect(rr, ink);
        if (cat != null && r.height > 18 && r.width > 40) {
          _label(canvas, cat.name, r.center, style: text.copyWith(fontSize: 9.5, color: const Color(0xFF4A4F55)));
        }
    }
    if (st.selectedObject == o.uid) canvas.drawRect(r.inflate(4), _stroke(pc.selected, 2.2));
  }

  /// Objet vu de dessus, dans son repère : u le long de la largeur, v du dos (contre le mur) vers l'avant.
  void _planObject(Canvas canvas, _View v, RoomObject o) {
    final c = v.toScreen(o.x, o.y);
    final k = v.k;
    final w = o.w * k, d = o.d * k;
    final sel = st.selectedObject == o.uid;
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(o.rot * math.pi / 180);
    final r = Rect.fromCenter(center: Offset.zero, width: w, height: d);
    final ink = _stroke(const Color(0xFF4A4F55), 1.2);
    final white = Paint()..color = const Color(0xFFFDFDFC);
    final f = o.fixture;
    if (f == null) {
      final cat = st.objectCatalog.where((x) => x.id == o.ref).firstOrNull;
      canvas.drawRRect(RRect.fromRectAndRadius(r, Radius.circular(math.min(w, d) * 0.08)), Paint()..color = const Color(0xFFEDE6DE));
      canvas.drawRRect(RRect.fromRectAndRadius(r, Radius.circular(math.min(w, d) * 0.08)), ink);
      if (r.shortestSide > 26 && cat != null) {
        canvas.save();
        canvas.rotate(-o.rot * math.pi / 180); // texte toujours lisible
        _label(canvas, cat.name, Offset.zero, style: text.copyWith(fontSize: 9.5, color: const Color(0xFF4A4F55)));
        canvas.restore();
      }
    } else {
      Offset at(double u, double vv) => Offset(-w / 2 + u * w, -d / 2 + vv * d); // u, v en fraction
      switch (f.id) {
        case 'wc_suspendu' || 'wc_sol' || 'bidet':
          if (f.id == 'wc_sol') {
            final tank = Rect.fromPoints(at(0.08, 0), at(0.92, 0.28));
            canvas.drawRRect(RRect.fromRectAndRadius(tank, const Radius.circular(3)), white);
            canvas.drawRRect(RRect.fromRectAndRadius(tank, const Radius.circular(3)), ink);
          }
          final bowl = Rect.fromPoints(at(0.06, f.id == 'wc_sol' ? 0.26 : 0.05), at(0.94, 1));
          canvas.drawOval(bowl, white);
          canvas.drawOval(bowl, ink);
          canvas.drawOval(bowl.deflate(bowl.shortestSide * 0.18), ink);
        case 'lavabo' || 'vasque_double':
          canvas.drawRect(r, white);
          canvas.drawRect(r, ink);
          final n = f.id == 'vasque_double' ? 2 : 1;
          for (var i = 0; i < n; i++) {
            final cx = (i + 0.5) / n;
            final bowl = Rect.fromCenter(center: at(cx, 0.55), width: w / n * 0.62, height: d * 0.62);
            canvas.drawOval(bowl, ink);
            canvas.drawCircle(at(cx, 0.55), 2.2, Paint()..color = const Color(0xFF4A4F55));
            canvas.drawCircle(at(cx, 0.12), 3, ink);
          }
        case 'baignoire':
          canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(4)), white);
          canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(4)), ink);
          canvas.drawRRect(RRect.fromRectAndRadius(r.deflate(math.min(w, d) * 0.09), Radius.circular(d * 0.32)), ink);
          canvas.drawCircle(at(0.12, 0.5), 3, ink);
        case 'douche' || 'douche_italienne':
          canvas.drawRect(r, Paint()..color = const Color(0xFFF2F6F8));
          canvas.drawRect(r, ink);
          if (f.id == 'douche') {
            canvas.drawLine(r.topLeft, r.bottomRight, _stroke(const Color(0x664A4F55), 1));
            canvas.drawLine(r.topRight, r.bottomLeft, _stroke(const Color(0x664A4F55), 1));
            canvas.drawCircle(Offset.zero, 4, ink);
            // paroi vitrée devant
            canvas.drawLine(at(0, 1), at(0.6, 1), _stroke(const Color(0xFF5B9BD5), 3));
          } else {
            canvas.drawLine(at(0.05, 0.85), at(0.95, 0.85), _stroke(const Color(0xFF4A4F55), 2.5));
          }
        case 'seche_serviettes':
          canvas.drawRect(r, white);
          canvas.drawRect(r, ink);
          for (var i = 1; i < 6; i++) {
            final x = -w / 2 + w * i / 6;
            canvas.drawLine(Offset(x, -d / 2), Offset(x, d / 2), _stroke(const Color(0x884A4F55), 1));
          }
        case 'chauffe_eau':
          canvas.drawOval(r, white);
          canvas.drawOval(r, ink);
          canvas.drawLine(Offset(-w * 0.2, 0), Offset(w * 0.2, 0), ink);
        default:
          canvas.drawRect(r, white);
          canvas.drawRect(r, ink);
      }
    }
    if (sel) {
      canvas.drawRect(r.inflate(3), _stroke(pc.selected, 2.2));
      // flèche « avant »
      canvas.drawLine(Offset(0, d / 2 + 4), Offset(0, d / 2 + 16), _stroke(pc.selected, 2));
    }
    canvas.restore();
  }

  void _parquet(Canvas canvas, _View v, double w0, double d0) {
    if (v.k * 180 < 5) return;
    final line = _stroke(pc.floorLine, 1);
    canvas.save();
    canvas.clipRect(v.rect(0, 0, w0, d0));
    var row = 0;
    for (var y = 0.0; y < d0; y += 180, row++) {
      canvas.drawLine(v.toScreen(0, y), v.toScreen(w0, y), line);
      // joints décalés, longueurs variées mais fixes (pas d'aléatoire : rendu stable)
      var x = -((row * 337) % 1200).toDouble();
      var i = 0;
      while (x < w0) {
        x += 900 + ((row * 7 + i * 13) % 5) * 150;
        i++;
        if (x > 0 && x < w0) canvas.drawLine(v.toScreen(x, y), v.toScreen(x, y + 180), line);
      }
    }
    canvas.restore();
  }

  void _planOpening(Canvas canvas, _View v, Opening o) {
    final w = p.room.wall(o.wallId);
    const t = _wallThickness;
    final sel = st.selectedOpening == o.uid;
    final hov = hover == o.uid;
    // symbole selon le modèle (battante, double, coulissante, galandage, pliante, pivot ; fenêtres)
    paintOpeningPlan(canvas, o, (s, tt) {
      final q = w.toPlan(s, tt);
      return v.toScreen(q.$1, q.$2);
    }, t, floor: pc.floorWood);
    if (sel || hov) {
      final r = Rect.fromPoints(
        v.toScreen(w.toPlan(o.s, -t).$1, w.toPlan(o.s, -t).$2),
        v.toScreen(w.toPlan(o.right, o.isDoor ? o.width - 80 : 0).$1, w.toPlan(o.right, o.isDoor ? o.width - 80 : 0).$2),
      );
      canvas.drawRect(r.inflate(3), _stroke(sel ? pc.selected : primary, sel ? 2.5 : 1.5));
      if (sel) {
        _label(
          canvas,
          '${o.isDoor ? 'Porte' : 'Fenêtre'} ${lenText(o.width)}',
          r.center,
          bg: pc.selected,
          style: text.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
        );
      }
    }
  }

  void _planCabinet(Canvas canvas, _View v, PlanShape s) {
    final it = p.byUid(s.uid)!;
    final m = s.model;
    final w = p.room.wall(it.wallId);
    final pts = [for (final (x, y) in s.points) v.toScreen(x, y)];
    final path = Path()..addPolygon(pts, true);
    final high = m.kind.isHigh;
    final edge = _stroke(const Color(0xFF6B6F75), 1);

    if (high) {
      // élément haut : vu au-dessus du plan de travail, contour pointillé
      canvas.drawPath(path, Paint()..color = front.color.withValues(alpha: 0.35));
      _dashedPath(canvas, pts, _stroke(const Color(0xFF6B6F75), 1.2));
    } else if (m.kind == CabinetKind.tall) {
      canvas.drawPath(path, Paint()..color = front.color);
      canvas.drawPath(path, edge);
      // croix légère = élément haut du sol au plafond
      canvas.drawLine(pts[0], pts[2], _stroke(const Color(0x22000000), 1));
      canvas.drawLine(pts[1], pts[3], _stroke(const Color(0x22000000), 1));
    } else {
      // élément bas : on voit le plan de travail (+ bande de façade côté pièce)
      final isWorktop = m.kind.isLow && m.kind != CabinetKind.fillerBase;
      canvas.drawPath(path, Paint()..color = isWorktop ? top.color : front.color);
      canvas.drawPath(path, edge);
      if (m.shape == CabinetShape.rect || m.shape == CabinetShape.blind) {
        final (fx0, fy0) = w.toPlan(it.s, it.depth - 20.0);
        final (fx1, fy1) = w.toPlan(it.right, it.depth.toDouble());
        canvas.drawRect(Rect.fromPoints(v.toScreen(fx0, fy0), v.toScreen(fx1, fy1)), Paint()..color = front.color);
        _appliance(canvas, v, w, it, m);
      }
    }

    final sel = st.selected == s.uid;
    if (hover == s.uid && !sel) canvas.drawPath(path, _stroke(primary, 2));
    if (sel) {
      canvas.drawPath(path, _stroke(pc.selected, 2.5));
      final b = path.getBounds();
      _label(
        canvas,
        '${it.width} mm',
        b.center,
        bg: pc.selected,
        style: text.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
      );
      if (snapped) {
        _label(
          canvas,
          'aimanté',
          b.topCenter + const Offset(0, -14),
          bg: primary,
          style: text.copyWith(color: Colors.white),
        );
      }
    }
  }

  /// Évier, plaque de cuisson : dessinés sur le plan de travail.
  void _appliance(Canvas canvas, _View v, Wall w, PlacedCabinet it, CabinetModel m) {
    final ink = _stroke(const Color(0xFF6B6F75), 1.2);
    Offset at(double s, double t) {
      final q = w.toPlan(s, t);
      return v.toScreen(q.$1, q.$2);
    }

    if (m.id.contains('vanity')) {
      // plan vasque : une ou deux cuves, robinet derrière
      final n = m.id.contains('double') && it.width >= 1000 ? 2 : 1;
      for (var i = 0; i < n; i++) {
        final cs = it.s + it.width * (i + 0.5) / n;
        final bw = math.min(it.width / n * 0.66, 520.0), bd = it.depth * 0.55;
        final r = Rect.fromPoints(at(cs - bw / 2, it.depth * 0.3), at(cs + bw / 2, it.depth * 0.3 + bd));
        canvas.drawOval(r, Paint()..color = const Color(0xFFF4F6F7));
        canvas.drawOval(r, ink);
        canvas.drawCircle(r.center, math.max(1.5, v.k * 18), ink);
        canvas.drawCircle(at(cs, it.depth * 0.14), math.max(1.5, v.k * 16), Paint()..color = const Color(0xFF9AA0A6));
      }
    } else if (m.id == 'base_sink') {
      final sk = KitchenFixtures.sink(p.style.sink);
      final bw = math.min(it.width - 60.0, sk.length.toDouble()), bd = math.min(sk.depth.toDouble(), 500.0);
      final s0 = it.s + (it.width - bw) / 2;
      final whole = Rect.fromPoints(at(s0, 70), at(s0 + bw, 70 + bd));
      canvas.drawRect(whole, Paint()..color = const Color(0xFFE6E9EB));
      canvas.drawRect(whole, _stroke(const Color(0xFF9AA0A6), 1));
      void bowl(double f0, double f1) {
        final r = Rect.fromPoints(at(s0 + bw * f0 + 30, 100), at(s0 + bw * f1 - 30, 70 + bd - 30));
        final rr = RRect.fromRectAndRadius(r, Radius.circular(math.max(2, v.k * 50)));
        canvas.drawRRect(rr, Paint()..color = const Color(0xFFD3D8DC));
        canvas.drawRRect(rr, ink);
        canvas.drawCircle(r.center, math.max(1.5, v.k * 22), ink);
      }

      switch (sk.layout) {
        case 'drainer':
          bowl(0, 0.56);
          for (var i = 1; i < 7; i++) {
            final f = 0.6 + 0.38 * i / 7;
            canvas.drawLine(at(s0 + bw * f, 110), at(s0 + bw * f, 70 + bd - 40), _stroke(const Color(0xFFB4BAC0), 1));
          }
        case '2':
          bowl(0, 0.56);
          bowl(0.56, 1);
        default:
          bowl(0, 1);
      }
      // robinet
      final ts = sk.layout == 'drainer' ? s0 + bw * 0.28 : it.s + it.width / 2;
      canvas.drawCircle(at(ts, 45), math.max(1.5, v.k * 18), Paint()..color = const Color(0xFF9AA0A6));
    } else if (m.id == 'base_cooktop_oven') {
      final r = Rect.fromPoints(at(it.s + 30, 60), at(it.right - 30, 560));
      canvas.drawRRect(RRect.fromRectAndRadius(r, Radius.circular(math.max(1, v.k * 20))), Paint()..color = const Color(0xFF1F2124));
      final ring = _stroke(const Color(0xFF8A8F96), 1);
      for (final (fs, ft, rad) in [(0.28, 0.3, 95.0), (0.72, 0.3, 75.0), (0.28, 0.72, 75.0), (0.72, 0.72, 95.0)]) {
        final c = Offset(r.left + r.width * fs, r.top + r.height * ft);
        canvas.drawCircle(c, rad * v.k, ring);
      }
    }
  }

  // ================================================================ vue de face

  void _paintFront(Canvas canvas) {
    final v = view!;
    final room = p.room;
    final std = p.standards;
    final wall = room.wall(st.wallId);
    final len = wall.length, h = room.height;

    // mur et sol
    final wf = wallFinish(p.style), sf = splashFinish(p.style), ff = floorFinish(p.style);
    final wallRect = v.rect(0, 0, len, h);
    canvas.drawRect(wallRect, Paint()..color = wf.color);
    void textured(Rect r, Finish f) {
      if (!f.textured) {
        canvas.drawRect(r, Paint()..color = f.color);
        return;
      }
      canvas.save();
      canvas.clipRect(r);
      canvas.translate(r.left, r.top);
      canvas.scale(v.k);
      canvas.drawRect(Rect.fromLTWH(0, 0, r.width / v.k, r.height / v.k), f.paint());
      canvas.restore();
    }

    textured(wallRect, wf);
    // crédence derrière les bas, jusqu'au bas des hauts
    if (p.style.splash != null) {
      for (final (a, b) in st.engine.runs(st.wallId, (m) => st.engine.kitchen && m.kind.isLow)) {
        var zTop = p.standards.worktopTop + 600.0;
        for (final c in p.items.where((c) => c.wallId == st.wallId && st.engine.modelOf(c).kind.isHigh && c.s < b && a < c.right)) {
          zTop = math.min(zTop, c.z);
        }
        textured(v.rect(a, p.standards.worktopTop.toDouble(), b, zTop), sf);
      }
    }
    textured(v.rect(-300, -150, len + 300, 0), ff);

    // repère de hauteur mini des hauts : seulement quand un élément haut est sélectionné
    final showMin = st.selectedModel?.kind.isHigh ?? false;
    if (showMin) {
      _dashed(
        canvas,
        v.toScreen(0, std.wallBottomMin.toDouble()),
        v.toScreen(len, std.wallBottomMin.toDouble()),
        _stroke(pc.dimension.withValues(alpha: 0.5), 1),
      );
    }

    // ouvertures
    for (final o in p.openings.where((o) => o.wallId == st.wallId)) {
      final r = v.rect(o.s, o.z, o.right, o.z + o.height);
      paintOpeningElevation(canvas, r, openingModelOf(o), door: o.isDoor, hinge: o.hinge, k: v.k);
      if (st.selectedOpening == o.uid || hover == o.uid) {
        canvas.drawRect(r.inflate(3), _stroke(st.selectedOpening == o.uid ? pc.selected : primary, 2.5));
      }
    }

    final rects = st.engine.elevation(st.wallId);

    // caissons des murs voisins vus de profil
    for (final r in rects.where((r) => !r.onThisWall)) {
      final rr = v.rect(r.s0, r.z0, r.s1, r.z1);
      canvas.drawRect(rr, Paint()..color = shade(front.color, -0.18));
      canvas.drawRect(rr, _stroke(const Color(0xFF8D9399), 1));
    }

    final mine = _paintOrder(rects.where((r) => r.onThisWall).toList());

    // plinthes (en retrait, plus foncées)
    for (final r in mine.where((r) => r.model.floorSupport && r.z0 > 0)) {
      canvas.drawRect(v.rect(r.s0, 0, r.s1, r.z0), Paint()..color = shade(front.color, -0.2));
    }

    // plan de travail continu
    for (final (a, b) in st.engine.runs(st.wallId, (m) => st.engine.kitchen && m.kind.isLow)) {
      final r = v.rect(a, std.baseTop.toDouble(), b, std.worktopTop.toDouble());
      canvas.drawRect(r, Paint()..color = top.color);
      if (top.textured) {
        canvas.save();
        canvas.clipRect(r);
        canvas.translate(r.left, r.top);
        canvas.scale(v.k);
        canvas.drawRect(Rect.fromLTWH(0, 0, r.width / v.k, r.height / v.k), top.paint());
        canvas.restore();
      }
      canvas.drawRect(Rect.fromLTWH(r.left, r.top, r.width, 1), Paint()..color = Colors.white54);
      canvas.drawRect(r, _stroke(shade(top.color, -0.25), 1));
    }

    // objets contre ce mur (sanitaires, décoration) : dessin en élévation
    for (final o in p.objects) {
      _frontObject(canvas, v, wall, o);
    }

    // caissons
    for (final r in mine) {
      final it = p.byUid(r.uid)!;
      final rr = v.rect(r.s0, r.z0, r.s1, r.z1);
      final sel = st.selected == r.uid;
      final fr = frontOfItem(p.style, it, r.model);
      // rendu réaliste dans le repère mm de la façade (texture à l'échelle)
      canvas.save();
      canvas.translate(rr.left, rr.top);
      canvas.scale(v.k);
      paintFront(
        canvas,
        Rect.fromLTWH(0, 0, rr.width / v.k, rr.height / v.k),
        r.model,
        fill: fr.color,
        stroke: shade(fr.color, -0.35),
        line: lineOn(fr.color),
        opening: it.opening,
        variant: it.variant,
        handle: p.style.handle,
        handleSize: handleLook(p.style, st.db?.handles).$2,
        handleColor: handleLook(p.style, st.db?.handles).$3,

        tallXxl: p.style.tallXxl,
        fillPaint: fr.paint(vertical: true),
        cells: frontCells(r.model, it, realistic: true),
        realistic: true,
        pxPerMm: 1,
        appliances: appliancesOf(r.model, it),
        carcass: finishById(carcasses, p.style.carcass).color,
        gloss: fr.gloss,
      );
      canvas.restore();
      if (r.model.id.contains('mirror')) {
        // portes miroir : glace claire avec reflets en biais (on voit encore les joints dessous)
        final g = rr.deflate(math.max(1, v.k * 12));
        canvas.drawRect(
            g,
            Paint()
              ..shader = const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xDDEAF2F5), Color(0xCCC9D8DE), Color(0xDDEFF5F7)])
                  .createShader(g));
        canvas.save();
        canvas.clipRect(g);
        final shine = _stroke(const Color(0x88FFFFFF), math.max(1, v.k * 30));
        canvas.drawLine(Offset(g.left + g.width * 0.15, g.bottom), Offset(g.left + g.width * 0.55, g.top), shine);
        canvas.drawLine(Offset(g.left + g.width * 0.35, g.bottom), Offset(g.left + g.width * 0.7, g.top), _stroke(const Color(0x55FFFFFF), math.max(1, v.k * 14)));
        canvas.restore();
      }
      if (r.model.id.contains('vanity')) {
        // plan vasque en céramique et robinet(s) au-dessus du meuble
        final n = r.model.id.contains('double') && it.width >= 1000 ? 2 : 1;
        final top = v.rect(r.s0, r.z1, r.s1, r.z1 + 40);
        canvas.drawRect(top, Paint()..color = const Color(0xFFF7F8F8));
        canvas.drawRect(top, _stroke(const Color(0xFF6B6F75), 1));
        for (var i = 0; i < n; i++) {
          final cs = r.s0 + (r.s1 - r.s0) * (i + 0.5) / n;
          canvas.drawRect(v.rect(cs - 12, r.z1 + 40, cs + 12, r.z1 + 190), Paint()..color = const Color(0xFFB8BEC4));
          canvas.drawRect(v.rect(cs - 12, r.z1 + 160, cs + 80, r.z1 + 190), Paint()..color = const Color(0xFFB8BEC4));
        }
      }
      canvas.drawRect(rr, _stroke(shade(fr.color, -0.35).withValues(alpha: 0.6), 0.8));
      if (hover == r.uid && !sel) canvas.drawRect(rr, _stroke(primary, 2));
      if (sel) {
        canvas.drawRect(rr.inflate(2), _stroke(pc.selected, 3));
        _label(
          canvas,
          '${lenValue(r.width)} × ${lenValue(r.height)}',
          rr.center,
          bg: pc.selected,
          style: text.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
        );
        if (snapped) {
          _label(
            canvas,
            'aimanté',
            rr.topCenter + const Offset(0, -14),
            bg: primary,
            style: text.copyWith(color: Colors.white),
          );
        }
      }
    }

    // écarts en direct vers les voisins de l'élément sélectionné (mode position)
    final sel = st.selectedItem;
    if (sel != null && sel.wallId == st.wallId && !st.engine.modelOf(sel).kind.isCorner) {
      final (gl, gr) = st.engine.neighbourGaps(sel.uid);
      final y = sel.z + sel.height / 2;
      final ink = _stroke(pc.selected, 1.4);
      void gapDim(double a0, double a1, double gap) {
        if (gap < 1) return;
        final pa = v.toScreen(a0, y), pb = v.toScreen(a1, y);
        canvas.drawLine(pa, pb, ink);
        canvas.drawLine(pa + const Offset(0, -6), pa + const Offset(0, 6), ink);
        canvas.drawLine(pb + const Offset(0, -6), pb + const Offset(0, 6), ink);
        _label(
          canvas,
          lenText(gap),
          Offset.lerp(pa, pb, 0.5)! + const Offset(0, -10),
          bg: Colors.white,
          style: text.copyWith(color: pc.selected, fontWeight: FontWeight.w700),
        );
      }

      gapDim(sel.s - gl, sel.s, gl);
      gapDim(sel.right, sel.right + gr, gr);
    }

    // vides à combler
    if (st.step == PlanStep.layout) {
      for (final g in st.engine.gaps().where((g) => g.wallId == st.wallId)) {
        final gr = _gapRect(st, v, g);
        _dashed(canvas, gr.topLeft, gr.bottomLeft, _stroke(pc.gap, 1.5));
        _dashed(canvas, gr.topRight, gr.bottomRight, _stroke(pc.gap, 1.5));
        canvas.drawRect(gr, Paint()..color = pc.gap.withValues(alpha: 0.12));
        _label(
          canvas,
          g.fillable ? '+ fileur ${lenValue(g.width)}' : lenValue(g.width),
          gr.center,
          maxWidth: math.max(gr.width + 60, 60),
          bg: Colors.white,
          style: text.copyWith(color: pc.gap, fontWeight: FontWeight.w700),
        );
      }
    }

    // chaîne de cotes sous le sol : chaque élément du bas
    final chain = <double>{0, len};
    for (final r in mine.where((r) => !r.model.kind.isHigh)) {
      chain
        ..add(r.s0.clamp(0, len))
        ..add(r.s1.clamp(0, len));
    }
    final ticks = chain.toList()..sort();
    final y = v.toScreen(0, 0).dy + 30;
    final ln = _stroke(pc.dimension, 1);
    canvas.drawLine(Offset(v.toScreen(0, 0).dx, y), Offset(v.toScreen(len, 0).dx, y), ln);
    for (var i = 0; i < ticks.length; i++) {
      final x = v.toScreen(ticks[i], 0).dx;
      canvas.drawLine(Offset(x, y - 5), Offset(x, y + 5), ln);
      if (i + 1 < ticks.length) {
        final seg = ticks[i + 1] - ticks[i];
        final w = (ticks[i + 1] - ticks[i]) * v.k;
        if (w > 26) _label(canvas, lenValue(seg), Offset(x + w / 2, y - 9), maxWidth: w, style: text.copyWith(fontSize: 11));
      }
    }
    _dim(canvas, v.toScreen(0, 0) + const Offset(0, 58), v.toScreen(len, 0) + const Offset(0, 58), 'Mur ${wall.id} · ${lenText(len)}');
    _dim(canvas, v.toScreen(0, 0) + const Offset(-28, 0), v.toScreen(0, h) + const Offset(-28, 0), lenText(h), vertical: true);
    final tagStyle = text.copyWith(fontSize: 11, fontWeight: FontWeight.w600);
    _label(canvas, '${std.worktopTop}', v.toScreen(len, std.worktopTop.toDouble()) + const Offset(24, 0), style: tagStyle);
    if (st.selectedModel?.kind.isHigh ?? false) {
      _label(
        canvas,
        'bas des hauts : ${std.wallBottomMin} mini (plan + ${std.wallClearanceMin})',
        v.toScreen(len, std.wallBottomMin.toDouble()) + const Offset(-120, -9),
        style: tagStyle,
        bg: const Color(0xFFF4F2ED),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PlannerPainter old) => true;
}
