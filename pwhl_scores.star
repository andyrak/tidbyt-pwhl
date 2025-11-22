"""
PWHL Scores Advanced for Tidbyt.
Enhanced version with live game updates, player stats, and better animations.
Author: Andy Rakauskas
"""

load("render.star", "render")
load("http.star", "http")
load("encoding/base64.star", "base64")
load("encoding/json.star", "json")
load("time.star", "time")
load("cache.star", "cache")
load("schema.star", "schema")

# ============================================================================
# API CONFIGURATION
# ============================================================================
# Centralized API configuration following pwhl-remix patterns

API_BASE = "https://lscluster.hockeytech.com/feed/index.php"
CLIENT_CODE = "pwhl"
CLIENT_KEY = "694cfeed58c932ee"

# Cache configuration with versioned keys
CACHE_VERSION = "v4"  # Increment when data structure changes
CACHE_TTL_GAMES = 60  # 1 minute for live game updates
CACHE_TTL_STANDINGS = 300  # 5 minutes for standings
CACHE_TTL_FALLBACK = 3600  # 1 hour for stale cache fallback

# Team Information (2024-25 Season - 8 teams)
TEAMS = {
    "BOS": {
        "name": "Boston Fleet",
        "color": "#00205B",
        "secondary": "#C8102E",
        "id": "boston-fleet",
        "logo": "https://assets.leaguestat.com/pwhl/logos/50x50/1.png"
    },
    "MIN": {
        "name": "Minnesota Frost",
        "color": "#6F263D",
        "secondary": "#B8B8B8",
        "id": "minnesota-frost",
        "logo": "https://assets.leaguestat.com/pwhl/logos/50x50/2.png"
    },
    "MTL": {
        "name": "Montréal Victoire",
        "color": "#862633",
        "secondary": "#FFB81C",
        "id": "montreal-victoire",
        "logo": "https://assets.leaguestat.com/pwhl/logos/50x50/3.png"
    },
    "NYS": {
        "name": "New York Sirens",
        "color": "#006272",
        "secondary": "#A8B5CE",
        "id": "new-york-sirens",
        "logo": "https://assets.leaguestat.com/pwhl/logos/50x50/4.png"
    },
    "OTT": {
        "name": "Ottawa Charge",
        "color": "#C8102E",
        "secondary": "#000000",
        "id": "ottawa-charge",
        "logo": "https://assets.leaguestat.com/pwhl/logos/50x50/5.png"
    },
    "TOR": {
        "name": "Toronto Sceptres",
        "color": "#7D3C98",
        "secondary": "#FFB81C",
        "id": "toronto-sceptres",
        "logo": "https://assets.leaguestat.com/pwhl/logos/50x50/6.png"
    },
    "SEA": {
        "name": "Seattle Torrent",
        "color": "#001F5B",
        "secondary": "#99D9D9",
        "id": "seattle-torrent",
        "logo": "https://assets.leaguestat.com/pwhl/logos/50x50/8.png"
    },
    "VAN": {
        "name": "Vancouver Goldeneyes",
        "color": "#FFC72C",
        "secondary": "#00205B",
        "id": "vancouver-goldeneyes",
        "logo": "https://assets.leaguestat.com/pwhl/logos/50x50/9.png"
    }
}

# ============================================================================
# API HELPERS
# ============================================================================
# Centralized API request builders following pwhl-remix patterns

def build_api_url(feed, view):
    """
    Build API URL with authentication parameters.
    Follows pwhl-remix's requestWithKeys pattern.

    Args:
        feed: API feed type (e.g., 'modulekit', 'statviewfeed')
        view: API view type (e.g., 'scorebar', 'bootstrap')

    Returns:
        Complete API URL string
    """
    params = {
        "feed": feed,
        "view": view,
        "client_code": CLIENT_CODE,
        "key": CLIENT_KEY,
        "lang": "en",
    }

    # Build query string
    query_parts = []
    for key, value in params.items():
        query_parts.append("{}={}".format(key, value))

    return API_BASE + "?" + "&".join(query_parts)

def get_cache_key(resource_type):
    """
    Generate versioned cache key.

    Args:
        resource_type: Type of resource (e.g., 'games', 'standings')

    Returns:
        Versioned cache key string
    """
    return "pwhl_{}_{}".format(resource_type, CACHE_VERSION)

# ============================================================================
# MAIN ENTRY POINT
# ============================================================================

def main(config):
    """Main function to render the display."""
    
    # Get configuration
    team_filter = config.get("team", "all")
    display_mode = config.get("display_mode", "auto")
    show_logos = config.bool("show_logos", True)
    show_period_scores = config.bool("show_period_scores", False)
    animate = config.bool("animate", True)
    
    # Determine what to show
    if display_mode == "auto":
        # Show live games if any, otherwise show next games
        games = fetch_games()
        live_games = [g for g in games if is_game_live(g)]
        
        if live_games:
            if team_filter != "all":
                team_games = filter_games_by_team(live_games, team_filter)
                if team_games:
                    return render_game_animated(team_games[0], animate, show_logos, show_period_scores)
            return render_game_animated(live_games[0], animate, show_logos, show_period_scores)
        else:
            # No live games, show next upcoming or recent final
            if team_filter != "all":
                team_games = filter_games_by_team(games, team_filter)
                if team_games:
                    return render_game_animated(team_games[0], animate, show_logos, show_period_scores)
            
            # Show standings or next game
            if games:
                return render_game_animated(games[0], animate, show_logos, show_period_scores)
            else:
                return render_standings_animated(team_filter, animate)
    
    elif display_mode == "scores":
        games = fetch_games()
        if team_filter != "all":
            games = filter_games_by_team(games, team_filter)

        if games:
            return render_game_animated(games[0], animate, show_logos, show_period_scores)
        else:
            return render_no_games_message()
    
    elif display_mode == "standings":
        return render_standings_animated(team_filter, animate)
    
    elif display_mode == "cycle":
        # Cycle through multiple games/standings
        return render_cycle_mode(team_filter, animate, show_logos)
    
    else:
        return render_no_games_message()

# ============================================================================
# DATA FETCHING WITH ERROR HANDLING
# ============================================================================
# Following pwhl-remix's graceful degradation patterns

def fetch_games():
    """
    Fetch current/upcoming games with error handling and caching.
    Implements network-first with fallback strategy from pwhl-remix.

    Returns:
        List of normalized game objects
    """
    cache_key = get_cache_key("games")
    stale_cache_key = get_cache_key("games_stale")

    # Try fresh cache first
    cached = cache.get(cache_key)
    if cached:
        return json.decode(cached)

    # Fetch from API
    games = fetch_games_from_api()

    # Cache results if successful
    if games:
        cache.set(cache_key, json.encode(games), ttl_seconds = CACHE_TTL_GAMES)
        # Also cache with longer TTL for fallback
        cache.set(stale_cache_key, json.encode(games), ttl_seconds = CACHE_TTL_FALLBACK)
        return games

    # Fallback to stale cache on API failure
    stale_cached = cache.get(stale_cache_key)
    if stale_cached:
        return json.decode(stale_cached)

    return []

def fetch_games_from_api():
    """
    Fetch games from API with error handling.

    Returns:
        List of normalized games, or empty list on error
    """
    # Build API URL using helper
    url = build_api_url("modulekit", "scorebar")

    # Make API request
    rep = http.get(url, ttl_seconds = 30)  # 30 second HTTP cache

    # Validate response
    if rep.status_code != 200:
        return []

    # Parse JSON
    data = rep.json()
    if not data:
        return []

    # Validate response structure
    if "SiteKit" not in data or "Scorebar" not in data["SiteKit"]:
        return []

    raw_games = data["SiteKit"]["Scorebar"]

    # Normalize games with validation
    return normalize_games(raw_games)

# ============================================================================
# DATA NORMALIZATION
# ============================================================================
# Multi-layer transformation following pwhl-remix patterns

def normalize_games(raw_games):
    """
    Normalize and validate game data from API.
    Follows pwhl-remix's normalizeGames pattern with validation.

    Args:
        raw_games: List of raw game objects from API

    Returns:
        List of normalized and validated game objects
    """
    normalized = []

    for raw_game in raw_games:
        # Validate game data before normalization
        if not is_valid_game(raw_game):
            continue

        game = normalize_game(raw_game)
        if game:
            normalized.append(game)

    return normalized

def is_valid_game(raw_game):
    """
    Validate raw game data.
    Filters out invalid games like pwhl-remix filters TBD teams.

    Args:
        raw_game: Raw game object from API

    Returns:
        True if game is valid, False otherwise
    """
    # Check for required fields
    if not raw_game.get("ID"):
        return False

    # Filter out TBD teams (following pwhl-remix pattern)
    home_code = raw_game.get("HomeCode", "")
    visitor_code = raw_game.get("VisitorCode", "")
    home_name = raw_game.get("HomeLongName", "")
    visitor_name = raw_game.get("VisitorLongName", "")

    if "TBD" in home_code or "TBD" in visitor_code:
        return False

    if "TBD" in home_name or "TBD" in visitor_name:
        return False

    # Must have team names
    if not home_name or not visitor_name:
        return False

    return True

def normalize_game(raw_game):
    """
    Normalize a single game object.
    Converts API format to application format with type safety.

    Args:
        raw_game: Raw game object from API

    Returns:
        Normalized game object
    """
    # Normalize team data using correct API field names
    home_team = normalize_team(
        raw_game.get("HomeLongName", ""),
        raw_game.get("HomeCode", ""),
        raw_game.get("HomeGoals", "0"),
        raw_game.get("HomeLogo", ""),
        "0",  # Shots not available in scorebar endpoint
        "0/0",  # PP stats not in scorebar
        raw_game.get("HomeWins", "0"),
        raw_game.get("HomeRegulationLosses", "0"),
        raw_game.get("HomeOTLosses", "0"),
        raw_game.get("HomeShootoutLosses", "0"),
    )

    away_team = normalize_team(
        raw_game.get("VisitorLongName", ""),
        raw_game.get("VisitorCode", ""),
        raw_game.get("VisitorGoals", "0"),
        raw_game.get("VisitorLogo", ""),
        "0",  # Shots not available in scorebar endpoint
        "0/0",  # PP stats not in scorebar
        raw_game.get("VisitorWins", "0"),
        raw_game.get("VisitorRegulationLosses", "0"),
        raw_game.get("VisitorOTLosses", "0"),
        raw_game.get("VisitorShootoutLosses", "0"),
    )

    # Build normalized game object
    game = {
        "id": raw_game.get("ID", ""),
        "date": raw_game.get("GameDate", ""),
        "time": raw_game.get("ScheduledFormattedTime", ""),
        "home": home_team,
        "away": away_team,
        "status": raw_game.get("GameStatusStringLong", ""),
        "period": raw_game.get("Period", ""),
        "time_remaining": raw_game.get("GameClock", ""),
        "intermission": raw_game.get("Intermission", "0") == "1",
    }

    # Add period scores if available
    if "PeriodScoring" in raw_game:
        game["period_scores"] = raw_game["PeriodScoring"]

    return game

def normalize_team(name, code, score, logo, shots, powerplay, wins="0", reg_losses="0", ot_losses="0", so_losses="0"):
    """
    Normalize team data with type conversions.
    Handles string-to-int conversion like pwhl-remix.

    Args:
        name: Team name string
        code: Team code (e.g., "TOR", "MIN")
        score: Score as string
        logo: Logo URL string
        shots: Shots as string
        powerplay: Powerplay string (e.g., "1/3")
        wins: Wins as string
        reg_losses: Regulation losses as string
        ot_losses: OT losses as string
        so_losses: Shootout losses as string

    Returns:
        Normalized team object
    """
    # Convert strings to integers safely
    # Starlark's int() handles string conversion gracefully
    score_int = int(score) if score else 0
    shots_int = int(shots) if shots else 0
    wins_int = int(wins) if wins else 0
    reg_losses_int = int(reg_losses) if reg_losses else 0
    ot_losses_int = int(ot_losses) if ot_losses else 0
    so_losses_int = int(so_losses) if so_losses else 0

    # Use code if available, otherwise derive from name
    abbr = code if code else get_team_abbr_from_name(name)

    # PWHL combines OT and SO losses into one "OT" category
    total_ot_losses = ot_losses_int + so_losses_int

    return {
        "name": name,
        "abbr": abbr,
        "score": score_int,
        "logo": logo,
        "shots": shots_int,
        "powerplay": powerplay if powerplay else "0/0",
        "wins": wins_int,
        "losses": reg_losses_int,
        "ot_losses": total_ot_losses,
        "record": "{}-{}-{}".format(wins_int, reg_losses_int, total_ot_losses),
    }

# ============================================================================
# DATE HELPERS
# ============================================================================

def format_date_mm_dd(game_date):
    """
    Format game date as MM/DD.
    Input format: "Fri, Nov 21" or similar
    Output format: "11/21"

    Args:
        game_date: Date string from API (e.g., "Fri, Nov 21")

    Returns:
        Formatted date string (MM/DD)
    """
    if not game_date:
        return ""

    # Month name to number mapping
    months = {
        "Jan": "01", "Feb": "02", "Mar": "03", "Apr": "04",
        "May": "05", "Jun": "06", "Jul": "07", "Aug": "08",
        "Sep": "09", "Oct": "10", "Nov": "11", "Dec": "12",
    }

    # Parse "Fri, Nov 21" format
    parts = game_date.split(", ")
    if len(parts) != 2:
        return ""

    date_parts = parts[1].split(" ")
    if len(date_parts) != 2:
        return ""

    month_name = date_parts[0]
    day = date_parts[1]

    month_num = months.get(month_name, "")
    if not month_num:
        return ""

    # Format day with leading zero if needed
    day_int = int(day) if day else 0
    day_str = str(day_int) if day_int >= 10 else "0{}".format(day_int)

    return "{}/{}".format(month_num, day_str)

# ============================================================================
# TEAM HELPERS
# ============================================================================

def get_logo(logo_url):
    """
    Fetch and cache team logo.
    Follows NHL Scores pattern for logo fetching.

    Args:
        logo_url: URL to team logo

    Returns:
        Cached logo data, or None if fetch fails
    """
    if not logo_url:
        return None

    # Cache logos for 24 hours (86400 seconds)
    response = http.get(logo_url, ttl_seconds = 86400)
    if response.status_code != 200:
        return None

    body = response.body()
    if not body or len(body) == 0:
        return None

    return body

def get_team_abbr_from_name(name):
    """
    Get team abbreviation from full name.
    Handles name variations and edge cases.

    Args:
        name: Full team name string

    Returns:
        Three-letter team abbreviation
    """
    # Handle variations in team names
    name_lower = name.lower()

    if "boston" in name_lower or "fleet" in name_lower:
        return "BOS"
    elif "minnesota" in name_lower or "frost" in name_lower:
        return "MIN"
    elif "montreal" in name_lower or "montréal" in name_lower or "victoire" in name_lower:
        return "MTL"
    elif "new york" in name_lower or "sirens" in name_lower:
        return "NYS"
    elif "ottawa" in name_lower or "charge" in name_lower:
        return "OTT"
    elif "toronto" in name_lower or "sceptres" in name_lower:
        return "TOR"
    elif "seattle" in name_lower or "torrent" in name_lower:
        return "SEA"
    elif "vancouver" in name_lower or "goldeneyes" in name_lower:
        return "VAN"
    else:
        # Fallback to first 3 letters
        return name[:3].upper() if name else "UNK"

# ============================================================================
# GAME STATE HELPERS
# ============================================================================

def is_game_live(game):
    """Check if a game is currently live."""

    status = game.get("status", "").lower()
    for keyword in ["live", "in progress", "period", "intermission"]:
        if keyword in status:
            return True
    return False

def is_game_final(game):
    """Check if a game is final."""
    
    status = game.get("status", "").lower()
    return "final" in status

def filter_games_by_team(games, team_abbr):
    """
    Filter games by team abbreviation.

    Args:
        games: List of game objects
        team_abbr: Team abbreviation to filter by

    Returns:
        List of games involving the specified team
    """
    filtered = []
    for game in games:
        if game["home"]["abbr"] == team_abbr or game["away"]["abbr"] == team_abbr:
            filtered.append(game)

    return filtered

# ============================================================================
# RENDERING FUNCTIONS
# ============================================================================

def render_game_animated(game, animate, show_logos, show_period_scores):
    """Render an animated game display."""

    frames = []

    # Main score frame - extract child for Animation
    score_root = render_game_score(game, show_logos)
    frames.append(score_root.child)

    # Additional info frames if animating
    if animate:
        if is_game_live(game):
            # Show shots on goal - extract child for Animation
            shots_root = render_game_shots(game)
            frames.append(shots_root.child)

            # Show powerplay if active - extract child for Animation
            if has_powerplay(game):
                powerplay_root = render_powerplay(game)
                frames.append(powerplay_root.child)

        if show_period_scores and "period_scores" in game:
            # Show period breakdown - extract child for Animation
            period_root = render_period_breakdown(game)
            frames.append(period_root.child)

    if len(frames) == 1:
        # Single frame - return as Root
        return render.Root(child = frames[0])

    # Animate between frames
    return render.Root(
        delay = 3000,  # 3 seconds per frame
        child = render.Animation(
            children = frames
        )
    )

def render_game_score(game, show_logos):
    """
    Render the main game score display.
    Based on NHL Scores app 'colors' display mode.
    """
    home = game["home"]
    away = game["away"]

    # Determine status text and color
    status_text = get_status_text(game)
    status_color = get_status_color(game)

    # Score colors - yellow for winner, muted for loser (NHL Scores pattern)
    home_score_color = "#fff"
    away_score_color = "#fff"

    if is_game_final(game):
        if home["score"] > away["score"]:
            home_score_color = "#ff0"  # Yellow for winner
            away_score_color = "#fffc"  # Muted for loser
        elif away["score"] > home["score"]:
            away_score_color = "#ff0"
            home_score_color = "#fffc"

    # Team colors for backgrounds
    away_team_data = TEAMS.get(away["abbr"], {})
    home_team_data = TEAMS.get(home["abbr"], {})

    away_color = away_team_data.get("color", "#222")
    home_color = home_team_data.get("color", "#222")

    # Fetch logos if available and enabled
    away_logo = None
    home_logo = None
    if show_logos:
        if away.get("logo"):
            away_logo = get_logo(away["logo"])
        if home.get("logo"):
            home_logo = get_logo(home["logo"])

    # Determine what to show in score area (score or record)
    is_scheduled = not is_game_live(game) and not is_game_final(game)
    away_display = away.get("record", "0-0-0") if is_scheduled else str(away["score"]) if (away["score"] > 0 or is_game_live(game) or is_game_final(game)) else ""
    home_display = home.get("record", "0-0-0") if is_scheduled else str(home["score"]) if (home["score"] > 0 or is_game_live(game) or is_game_final(game)) else ""

    return render.Root(
        child = render.Column(
            expanded = True,
            main_align = "space_between",
            cross_align = "start",
            children = [
                # Status bar at top
                render.Box(
                    width = 64,
                    height = 8,
                    color = "#000",
                    child = render.Row(
                        expanded = True,
                        main_align = "center",
                        cross_align = "center",
                        children = [
                            render.Text(
                                content = status_text,
                                font = "CG-pixel-3x5-mono",
                                color = status_color,
                            ),
                        ],
                    ),
                ),
                # Away team row
                render.Box(
                    width = 64,
                    height = 12,
                    color = away_color,
                    child = render.Row(
                        expanded = True,
                        main_align = "start",
                        cross_align = "center",
                        children = [
                            # Logo (16px width)
                            render.Box(
                                width = 16,
                                height = 16,
                                child = render.Image(away_logo, width = 16, height = 16) if away_logo else render.Box(width = 16, height = 16),
                            ),
                            # Team abbreviation (24px width)
                            render.Box(
                                width = 24,
                                height = 12,
                                child = render.Stack(
                                    children = [
                                        render.Box(width = 24, height = 12, color = "#000a"),  # Semi-transparent dark background
                                        render.Box(
                                            width = 24,
                                            height = 12,
                                            child = render.Text(
                                                content = away["abbr"][:3],
                                                color = away_score_color,
                                                font = "Dina_r400-6",
                                            ),
                                        ),
                                    ],
                                ),
                            ),
                            # Score or record (24px width)
                            render.Box(
                                width = 24,
                                height = 12,
                                child = render.Stack(
                                    children = [
                                        render.Box(width = 24, height = 12, color = "#000a"),  # Semi-transparent dark background
                                        render.Box(
                                            width = 24,
                                            height = 12,
                                            child = render.Text(
                                                content = away_display,
                                                color = away_score_color,
                                                font = "tb-8" if is_scheduled else "Dina_r400-6",  # Smaller font for records
                                            ),
                                        ),
                                    ],
                                ),
                            ),
                        ],
                    ),
                ),
                # Home team row
                render.Box(
                    width = 64,
                    height = 12,
                    color = home_color,
                    child = render.Row(
                        expanded = True,
                        main_align = "start",
                        cross_align = "center",
                        children = [
                            # Logo (16px width)
                            render.Box(
                                width = 16,
                                height = 16,
                                child = render.Image(home_logo, width = 16, height = 16) if home_logo else render.Box(width = 16, height = 16),
                            ),
                            # Team abbreviation (24px width)
                            render.Box(
                                width = 24,
                                height = 12,
                                child = render.Stack(
                                    children = [
                                        render.Box(width = 24, height = 12, color = "#000a"),  # Semi-transparent dark background
                                        render.Box(
                                            width = 24,
                                            height = 12,
                                            child = render.Text(
                                                content = home["abbr"][:3],
                                                color = home_score_color,
                                                font = "Dina_r400-6",
                                            ),
                                        ),
                                    ],
                                ),
                            ),
                            # Score or record (24px width)
                            render.Box(
                                width = 24,
                                height = 12,
                                child = render.Stack(
                                    children = [
                                        render.Box(width = 24, height = 12, color = "#000a"),  # Semi-transparent dark background
                                        render.Box(
                                            width = 24,
                                            height = 12,
                                            child = render.Text(
                                                content = home_display,
                                                color = home_score_color,
                                                font = "tb-8" if is_scheduled else "Dina_r400-6",  # Smaller font for records
                                            ),
                                        ),
                                    ],
                                ),
                            ),
                        ],
                    ),
                ),
            ],
        ),
    )

def render_game_shots(game):
    """Render shots on goal display."""
    
    home = game["home"]
    away = game["away"]
    
    return render.Root(
        child = render.Column(
            main_align = "space_around",
            cross_align = "center",
            children = [
                render.Text("SHOTS ON GOAL", font = "CG-pixel-3x5-mono", color = "#888"),
                render.Box(height = 2),
                render.Row(
                    main_align = "space_around",
                    expanded = True,
                    children = [
                        render.Column(
                            cross_align = "center",
                            children = [
                                render.Text(away["abbr"], font = "5x8", color = "#888"),
                                render.Text(str(away.get("shots", 0)), font = "10x20", color = "#fff")
                            ]
                        ),
                        render.Column(
                            cross_align = "center",
                            children = [
                                render.Text(home["abbr"], font = "5x8", color = "#888"),
                                render.Text(str(home.get("shots", 0)), font = "10x20", color = "#fff")
                            ]
                        )
                    ]
                )
            ]
        )
    )

def render_powerplay(game):
    """Render powerplay information."""
    
    # This would show current powerplay status
    return render.Root(
        child = render.Column(
            main_align = "center",
            cross_align = "center",
            children = [
                render.Text("POWER PLAY", font = "5x8", color = "#ff0"),
                render.Box(height = 4),
                render.Text(get_powerplay_team(game), font = "10x20", color = "#ff0")
            ]
        )
    )

def render_period_breakdown(game):
    """Render period-by-period scoring."""
    
    # Would show period scores
    return render.Root(
        child = render.Column(
            main_align = "center",
            cross_align = "center",
            children = [
                render.Text("PERIOD SCORES", font = "CG-pixel-3x5-mono", color = "#888"),
                # Add period score details here
            ]
        )
    )

def render_standings_animated(team_filter, animate):
    """Render animated standings display."""

    standings = fetch_standings()

    if not standings:
        return render_no_games_message()

    if team_filter != "all":
        # Show specific team standing
        for team in standings:
            if team.get("team_code") == team_filter:
                return render_team_standing_detail(team)

    # Show all teams (standings are already sorted by rank)
    return render_standings_table(standings)

def fetch_standings():
    """
    Fetch current standings with error handling and caching.
    Uses same pattern as fetch_games().

    Returns:
        List of normalized standing objects
    """
    cache_key = get_cache_key("standings")
    stale_cache_key = get_cache_key("standings_stale")

    # Try fresh cache first
    cached = cache.get(cache_key)
    if cached:
        return json.decode(cached)

    # Fetch standings from API
    standings = fetch_standings_from_api()

    # Cache results if successful
    if standings:
        cache.set(cache_key, json.encode(standings), ttl_seconds = CACHE_TTL_STANDINGS)
        # Also cache with longer TTL for fallback
        cache.set(stale_cache_key, json.encode(standings), ttl_seconds = CACHE_TTL_FALLBACK)
        return standings

    # Fallback to stale cache on API failure
    stale_cached = cache.get(stale_cache_key)
    if stale_cached:
        return json.decode(stale_cached)

    return []

def normalize_standings(raw_standings):
    """
    Normalize standings data from API.

    Args:
        raw_standings: List of raw standing objects from API

    Returns:
        List of normalized standing objects
    """
    normalized = []

    for item in raw_standings:
        if "row" not in item:
            continue

        row = item["row"]

        # Helper to safely convert to int
        def safe_int(value, default=0):
            if not value or value == "":
                return default
            return int(value) if value else default

        # Calculate total wins
        reg_wins = safe_int(row.get("regulation_wins", "0"))
        ot_wins = safe_int(row.get("non_reg_wins", "0"))
        total_wins = reg_wins + ot_wins

        standing = {
            "rank": safe_int(row.get("rank", 0)),
            "team_code": row.get("team_code", ""),
            "name": row.get("name", ""),
            "gp": safe_int(row.get("games_played", "0")),
            "wins": total_wins,
            "reg_wins": reg_wins,
            "ot_wins": ot_wins,
            "ot_losses": safe_int(row.get("non_reg_losses", "0")),
            "losses": safe_int(row.get("losses", "0")),
            "points": safe_int(row.get("points", "0")),
            "goals_for": safe_int(row.get("goals_for", "0")),
            "goals_against": safe_int(row.get("goals_against", "0")),
        }

        # Map team_code to our abbreviation system
        # API uses "NY" but we use "NYS"
        if standing["team_code"] == "NY":
            standing["team_code"] = "NYS"

        normalized.append(standing)

    return normalized

def fetch_standings_from_api():
    """
    Fetch standings from API.
    Uses statviewfeed teams endpoint.

    Returns:
        List of standing objects, or empty list
    """
    # Build standings API URL
    # Following pwhl-remix pattern
    url = API_BASE + "?feed=statviewfeed&view=teams&groupTeamsBy=division&context=overall&site_id=2&season=8&special=false&key={}&client_code={}&lang=en".format(CLIENT_KEY, CLIENT_CODE)

    # Make API request
    rep = http.get(url, ttl_seconds = 300)  # 5 minute cache

    # Validate response
    if rep.status_code != 200:
        return []

    # Parse JSON - response is JSONP wrapped in parentheses
    response_text = rep.body()
    if not response_text:
        return []

    # Remove JSONP wrapper
    if response_text.startswith("(") and response_text.endswith(")"):
        response_text = response_text[1:-1]

    data = json.decode(response_text)
    if not data or len(data) == 0:
        return []

    # Extract standings data
    if "sections" not in data[0] or len(data[0]["sections"]) == 0:
        return []

    section = data[0]["sections"][0]
    if "data" not in section:
        return []

    raw_standings = section["data"]

    # Normalize standings
    return normalize_standings(raw_standings)

def render_standings_table(teams, show_logos=True, use_marquee=True):
    """
    Render standings display with smooth scrolling animation.
    Scrolls through all 8 teams vertically.

    Args:
        teams: List of standing objects
        show_logos: Whether to show team logos
        use_marquee: Whether to use marquee scrolling (False for static display in cycle mode)

    Returns:
        Root with scrolling or static standings
    """
    if not teams:
        return render_no_games_message()

    # Build list of team rows
    team_rows = []
    teams_to_display = teams if use_marquee else teams[:3]  # Show only top 3 in static mode

    for team in teams_to_display:
        team_code = team.get("team_code", "")
        team_data = TEAMS.get(team_code, {})
        team_color = team_data.get("color", "#222")

        # Get logo if enabled
        logo_widget = None
        if show_logos:
            logo_url = team_data.get("logo")
            if logo_url:
                logo_data = get_logo(logo_url)
                if logo_data:
                    logo_widget = render.Image(logo_data, width = 12, height = 12)

        # Format: RANK. ABBR  W-L-OT
        rank = str(team.get("rank", 0))
        wins = team.get("wins", 0)
        losses = team.get("losses", 0)
        ot_losses = team.get("ot_losses", 0)
        record = "{}-{}-{}".format(wins, losses, ot_losses)

        team_rows.append(
            render.Row(
                expanded = True,
                main_align = "start",
                cross_align = "center",
                children = [
                    # Logo (12px)
                    render.Box(
                        width = 12,
                        height = 8,
                        child = logo_widget if logo_widget else render.Box(width = 12, height = 8),
                    ),
                    render.Box(width = 2, height = 8),
                    # Rank (5px)
                    render.Box(
                        width = 5,
                        height = 8,
                        child = render.Text(
                            content = rank,
                            color = "#888",
                            font = "tb-8",
                        ),
                    ),
                    # Gap (4px - more space)
                    render.Box(width = 1, height = 8),
                    # Team code (14px - more room)
                    render.Box(
                        width = 16,
                        height = 8,
                        child = render.Text(
                            content = team_code,
                            color = team_color,
                            font = "tb-8",
                        ),
                    ),
                    # Gap (3px)
                    render.Box(width = 2, height = 8),
                    # Record (26px)
                    render.Box(
                        width = 26,
                        height = 8,
                        child = render.Text(
                            content = record,
                            color = "#fff",
                            font = "CG-pixel-3x5-mono",
                        ),
                    ),
                ],
            ),
        )

    # Create content (scrolling or static)
    standings_content = render.Column(
        main_align = "start",
        cross_align = "start",
        children = team_rows,
    )

    # Choose between marquee and static display
    standings_display = None
    if use_marquee:
        standings_display = render.Box(
            width = 64,
            height = 24,
            child = render.Marquee(
                height = 24,
                scroll_direction = "vertical",
                child = standings_content,
            ),
        )
    else:
        # Static display for cycle mode - just show the content directly
        standings_display = render.Box(
            width = 64,
            height = 24,
            child = standings_content,
        )

    return render.Root(
        child = render.Column(
            expanded = True,
            main_align = "start",
            cross_align = "start",
            children = [
                # Title bar
                render.Box(
                    width = 64,
                    height = 8,
                    color = "#000",
                    child = render.Row(
                        expanded = True,
                        main_align = "center",
                        cross_align = "center",
                        children = [
                            render.Text(
                                content = "STANDINGS",
                                font = "CG-pixel-3x5-mono",
                                color = "#ff0",
                            ),
                        ],
                    ),
                ),
                # Standings display (scrolling or static)
                standings_display,
            ],
        ),
    )

def render_team_standing_detail(team):
    """Render detailed standing for a specific team."""

    team_code = team.get("team_code", "")
    team_info = TEAMS.get(team_code, {})

    return render.Root(
        child = render.Column(
            main_align = "space_around",
            cross_align = "center",
            children = [
                render.Text(
                    team_code,
                    font = "10x20",
                    color = team_info.get("color", "#fff"),
                ),
                render.Text(
                    "#{} in League".format(team.get("rank", 0)),
                    font = "5x8",
                    color = "#888",
                ),
                render.Row(
                    main_align = "center",
                    children = [
                        render.Text(
                            "{}-{}-{}".format(
                                team.get("wins", 0),
                                team.get("losses", 0),
                                team.get("ot_losses", 0),
                            ),
                            font = "6x13",
                            color = "#fff",
                        ),
                    ],
                ),
                render.Text(
                    "{} PTS".format(team.get("points", 0)),
                    font = "6x13",
                    color = "#ff0",
                ),
            ],
        ),
    )

def render_cycle_mode(team_filter, animate, show_logos):
    """Cycle through multiple displays."""

    displays = []

    # Add games
    games = fetch_games()
    if team_filter != "all":
        games = filter_games_by_team(games, team_filter)

    for game in games[:3]:  # Show up to 3 games
        # Get the widget from render_game_score (extract child from Root)
        game_root = render_game_score(game, show_logos)
        displays.append(game_root.child)

    # Add standings - use static view for cycling (marquees don't work well in animations)
    standings = fetch_standings()
    if standings:
        standings_root = render_standings_table(standings, show_logos=show_logos, use_marquee=False)
        displays.append(standings_root.child)

    if not displays:
        return render_no_games_message()

    # Cycle through displays
    return render.Root(
        delay = 4000,  # 4 seconds per display
        child = render.Animation(
            children = displays,
        ),
    )

def render_no_games_message():
    """Render message when no games are available."""
    
    return render.Root(
        child = render.Column(
            main_align = "center",
            cross_align = "center",
            children = [
                render.Text("PWHL", font = "10x20", color = "#33058D"),
                render.Box(height = 4),
                render.Text("No Games", font = "5x8", color = "#888"),
                render.Text("Available", font = "5x8", color = "#888")
            ]
        )
    )

# ============================================================================
# DISPLAY HELPER FUNCTIONS
# ============================================================================

def get_status_text(game):
    """Get formatted status text for a game."""

    status = game.get("status", "").upper()
    game_date = game.get("date", "")
    formatted_date = format_date_mm_dd(game_date)

    if "FINAL" in status:
        # Show FINAL with date (MM/DD)
        base_status = ""
        if "OT" in status:
            base_status = "FINAL/OT"
        elif "SO" in status:
            base_status = "FINAL/SO"
        else:
            base_status = "FINAL"

        if formatted_date:
            return "{} {}".format(base_status, formatted_date)
        return base_status
    elif is_game_live(game):
        period = game.get("period", "")
        time_remaining = game.get("time_remaining", "")

        if game.get("intermission"):
            return "INTERMISSION"
        elif period == "1":
            return "1ST {}".format(time_remaining)
        elif period == "2":
            return "2ND {}".format(time_remaining)
        elif period == "3":
            return "3RD {}".format(time_remaining)
        elif period == "OT":
            return "OT {}".format(time_remaining)
        elif period == "SO":
            return "SHOOTOUT"
        else:
            return "LIVE"
    else:
        # Scheduled game - show date and time (MM/DD TIME)
        game_time = game.get("time", "")
        if formatted_date and game_time:
            return "{} {}".format(formatted_date, game_time)
        elif formatted_date:
            return formatted_date
        elif game_time:
            return game_time
        return "SCHEDULED"

def get_status_color(game):
    """Get color for status text."""
    
    if is_game_live(game):
        return "#f00"  # Red for live
    elif is_game_final(game):
        return "#888"  # Gray for final
    else:
        return "#fff"  # White for scheduled

def has_powerplay(game):
    """Check if there's an active powerplay."""
    
    # Would check actual powerplay status from API
    return False

def get_powerplay_team(game):
    """Get team on powerplay."""

    # Would return actual team on PP
    return ""

# ============================================================================
# CONFIGURATION SCHEMA
# ============================================================================

def get_schema():
    """Define configuration schema for the app."""
    
    team_options = [
        schema.Option(display = "All Teams", value = "all"),
        schema.Option(display = "Boston Fleet", value = "BOS"),
        schema.Option(display = "Minnesota Frost", value = "MIN"),
        schema.Option(display = "Montréal Victoire", value = "MTL"),
        schema.Option(display = "New York Sirens", value = "NYS"),
        schema.Option(display = "Ottawa Charge", value = "OTT"),
        schema.Option(display = "Toronto Sceptres", value = "TOR"),
        schema.Option(display = "Seattle Torrent", value = "SEA"),
        schema.Option(display = "Vancouver Goldeneyes", value = "VAN"),
    ]
    
    display_options = [
        schema.Option(display = "Auto (Live Priority)", value = "auto"),
        schema.Option(display = "Scores Only", value = "scores"),
        schema.Option(display = "Standings Only", value = "standings"),
        schema.Option(display = "Cycle All", value = "cycle"),
    ]
    
    return schema.Schema(
        version = "1",
        fields = [
            schema.Dropdown(
                id = "team",
                name = "Favorite Team",
                desc = "Filter by your favorite team",
                icon = "heart",
                default = "all",
                options = team_options,
            ),
            schema.Dropdown(
                id = "display_mode",
                name = "Display Mode",
                desc = "What information to display",
                icon = "display",
                default = "auto",
                options = display_options,
            ),
            schema.Toggle(
                id = "show_logos",
                name = "Show Team Logos",
                desc = "Display team logos when available",
                icon = "image",
                default = True,
            ),
            schema.Toggle(
                id = "show_period_scores",
                name = "Show Period Scores",
                desc = "Display period-by-period breakdown",
                icon = "list",
                default = False,
            ),
            schema.Toggle(
                id = "animate",
                name = "Enable Animations",
                desc = "Animate between different information displays",
                icon = "play",
                default = True,
            ),
        ],
    )
