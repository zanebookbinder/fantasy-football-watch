"""Turn ESPN's numeric stat dictionary into an ESPN-style stat line.

The watch never sees a stat id -- all of this happens server-side so a mid-season
id change is a Lambda deploy, not an app rebuild.

Build rule (design doc): a clause is emitted only when its stat is non-zero, so a
player who has not scored yields an empty line rather than a row of zeros. The
client renders the placeholder from ``gameState``.
"""

from . import constants as C


def _num(stats, key):
    """Read a stat id as a float, treating missing/None as 0."""
    try:
        return float(stats.get(key) or 0)
    except (TypeError, ValueError):
        return 0.0


def _fmt(value):
    """Render a stat value: whole numbers lose the trailing '.0'."""
    if value == int(value):
        return str(int(value))
    return f"{value:g}"


def _join(clauses):
    return ", ".join(c for c in clauses if c)


def _passing(stats):
    att = _num(stats, C.PASS_ATTEMPTS)
    comp = _num(stats, C.PASS_COMPLETIONS)
    yds = _num(stats, C.PASS_YARDS)
    tds = _num(stats, C.PASS_TDS)
    ints = _num(stats, C.PASS_INTS)
    two_pt = _num(stats, C.PASS_2PT)
    if not (att or comp or yds or tds or ints):
        return ""
    clauses = [f"{_fmt(comp)}/{_fmt(att)}", f"{_fmt(yds)} yd"]
    if tds:
        clauses.append(f"{_fmt(tds)} TD")
    if two_pt:
        clauses.append(f"{_fmt(two_pt)} 2PT")
    if ints:
        clauses.append(f"{_fmt(ints)} INT")
    return _join(clauses)


def _rushing(stats):
    car = _num(stats, C.RUSH_ATTEMPTS)
    yds = _num(stats, C.RUSH_YARDS)
    tds = _num(stats, C.RUSH_TDS)
    two_pt = _num(stats, C.RUSH_2PT)
    if not (car or yds or tds):
        return ""
    clauses = [f"{_fmt(car)} car", f"{_fmt(yds)} yd"]
    if tds:
        clauses.append(f"{_fmt(tds)} TD")
    if two_pt:
        clauses.append(f"{_fmt(two_pt)} 2PT")
    return _join(clauses)


def _receiving(stats):
    rec = _num(stats, C.RECEPTIONS)
    yds = _num(stats, C.REC_YARDS)
    tds = _num(stats, C.REC_TDS)
    two_pt = _num(stats, C.REC_2PT)
    targets = _num(stats, C.TARGETS)
    if not (rec or yds or tds or targets):
        return ""
    clauses = [f"{_fmt(rec)} rec", f"{_fmt(yds)} yd"]
    if tds:
        clauses.append(f"{_fmt(tds)} TD")
    if two_pt:
        clauses.append(f"{_fmt(two_pt)} 2PT")
    return _join(clauses)


def _fumbles(stats):
    lost = _num(stats, C.FUMBLES_LOST)
    return f"{_fmt(lost)} FUM" if lost else ""


def _kicking(stats):
    fg_made = _num(stats, C.FG_MADE)
    fg_att = _num(stats, C.FG_ATTEMPTED)
    xp_made = _num(stats, C.XP_MADE)
    xp_att = _num(stats, C.XP_ATTEMPTED)
    long_fg = _num(stats, C.FG_MADE_50_PLUS)
    clauses = []
    if fg_made or fg_att:
        clauses.append(f"{_fmt(fg_made)}/{_fmt(fg_att)} FG")
    if xp_made or xp_att:
        clauses.append(f"{_fmt(xp_made)}/{_fmt(xp_att)} XP")
    if long_fg:
        clauses.append(f"{_fmt(long_fg)} from 50+")
    return _join(clauses)


def _defense(stats):
    sacks = _num(stats, C.DST_SACKS)
    ints = _num(stats, C.DST_INTERCEPTIONS)
    fums = _num(stats, C.DST_FUMBLE_RECOVERIES)
    blocks = _num(stats, C.DST_BLOCKED_KICKS)
    safeties = _num(stats, C.DST_SAFETIES)
    tds = sum(_num(stats, sid) for sid in C.DST_TD_STAT_IDS)
    has_pa = C.DST_POINTS_ALLOWED in stats
    if not (has_pa or sacks or ints or fums or blocks or safeties or tds):
        return ""
    clauses = []
    if has_pa:
        clauses.append(f"{_fmt(_num(stats, C.DST_POINTS_ALLOWED))} PA")
    if sacks:
        clauses.append(f"{_fmt(sacks)} sack")
    if ints:
        clauses.append(f"{_fmt(ints)} INT")
    if fums:
        clauses.append(f"{_fmt(fums)} FR")
    if blocks:
        clauses.append(f"{_fmt(blocks)} BLK")
    if safeties:
        clauses.append(f"{_fmt(safeties)} SAF")
    if tds:
        clauses.append(f"{_fmt(tds)} TD")
    return _join(clauses)


def build_stat_map(stats):
    """The non-zero stats as named numbers, for the watch to diff.

    Deliberately position-agnostic: a key is present when the player has that
    stat at all, so comparing two snapshots is a plain dictionary difference.
    """
    if not stats:
        return {}
    out = {}
    for key, stat_id in C.STAT_FIELDS:
        value = _num(stats, stat_id)
        if value:
            out[key] = int(value) if value == int(value) else round(value, 1)
    # Defensive touchdowns are spread across four return types; the watch only
    # cares that a defense scored.
    dst_tds = sum(_num(stats, sid) for sid in C.DST_TD_STAT_IDS)
    if dst_tds:
        out["dTd"] = int(dst_tds)
    return out


def build_stat_line(position, stats):
    """Format a raw stat dict for a position.

    ``position`` is a label from ``constants.POSITIONS`` (QB, RB, WR, TE, K,
    D/ST); ``stats`` is the ``stats`` dict of the ``statSourceId == 0`` split for
    the current scoring period. Returns "" when the player has done nothing yet.
    """
    if not stats:
        return ""

    if position == "K":
        return _kicking(stats)
    if position == "D/ST":
        return _defense(stats)

    if position == "QB":
        groups = [_passing(stats), _rushing(stats), _receiving(stats)]
    elif position == "RB":
        groups = [_rushing(stats), _receiving(stats), _passing(stats)]
    else:  # WR, TE and any other skill position
        groups = [_receiving(stats), _rushing(stats), _passing(stats)]

    line = " · ".join(g for g in groups if g)
    fumbles = _fumbles(stats)
    if fumbles:
        line = f"{line} · {fumbles}" if line else fumbles
    return line
