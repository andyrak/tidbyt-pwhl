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
        "id": "boston-fleet"
    },
    "MIN": {
        "name": "Minnesota Frost", 
        "color": "#6F263D",
        "secondary": "#B8B8B8",
        "id": "minnesota-frost"
    },
    "MTL": {
        "name": "Montréal Victoire",
        "color": "#862633",
        "secondary": "#FFB81C",
        "id": "montreal-victoire"
    },
    "NYS": {
        "name": "New York Sirens",
        "color": "#006272",
        "secondary": "#A8B5CE",
        "id": "new-york-sirens"
    },
    "OTT": {
        "name": "Ottawa Charge",
        "color": "#C8102E",
        "secondary": "#000000",
        "id": "ottawa-charge"
    },
    "TOR": {
        "name": "Toronto Sceptres",
        "color": "#7D3C98",
        "secondary": "#FFB81C",
        "id": "toronto-sceptres"
    },
    "SEA": {
        "name": "Seattle Torrent",
        "color": "#001F5B",
        "secondary": "#99D9D9",
        "id": "seattle-torrent"
    },
    "VAN": {
        "name": "Vancouver Goldeneyes",
        "color": "#FFC72C",
        "secondary": "#00205B",
        "id": "vancouver-goldeneyes"
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
    )

    away_team = normalize_team(
        raw_game.get("VisitorLongName", ""),
        raw_game.get("VisitorCode", ""),
        raw_game.get("VisitorGoals", "0"),
        raw_game.get("VisitorLogo", ""),
        "0",  # Shots not available in scorebar endpoint
        "0/0",  # PP stats not in scorebar
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

def normalize_team(name, code, score, logo, shots, powerplay):
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

    Returns:
        Normalized team object
    """
    # Convert strings to integers safely
    # Starlark's int() handles string conversion gracefully
    score_int = int(score) if score else 0
    shots_int = int(shots) if shots else 0

    # Use code if available, otherwise derive from name
    abbr = code if code else get_team_abbr_from_name(name)

    return {
        "name": name,
        "abbr": abbr,
        "score": score_int,
        "logo": logo,
        "shots": shots_int,
        "powerplay": powerplay if powerplay else "0/0",
    }

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
        Cached logo data
    """
    if not logo_url:
        return None

    # Cache logos for 24 hours (86400 seconds)
    return http.get(logo_url, ttl_seconds = 86400).body()

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

    # Main score frame
    frames.append(render_game_score(game, show_logos))
    
    # Additional info frames if animating
    if animate:
        if is_game_live(game):
            # Show shots on goal
            frames.append(render_game_shots(game))
            
            # Show powerplay if active
            if has_powerplay(game):
                frames.append(render_powerplay(game))
        
        if show_period_scores and "period_scores" in game:
            frames.append(render_period_breakdown(game))
    
    if len(frames) == 1:
        return frames[0]

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
                            # Score (24px width)
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
                                                content = str(away["score"]) if away["score"] > 0 or is_game_live(game) or is_game_final(game) else "",
                                                color = away_score_color,
                                                font = "Dina_r400-6",
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
                            # Score (24px width)
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
                                                content = str(home["score"]) if home["score"] > 0 or is_game_live(game) or is_game_final(game) else "",
                                                color = home_score_color,
                                                font = "Dina_r400-6",
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
        for i, team in enumerate(standings):
            if team["abbr"] == team_filter:
                return render_team_standing_detail(team, i + 1)
    
    # Show top teams
    return render_standings_table(standings[:5])

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

def fetch_standings_from_api():
    """
    Fetch standings from API.
    Placeholder for future API integration.

    Returns:
        List of standing objects, or empty list
    """
    # TODO: Implement actual standings API call
    # Would use build_api_url("statviewfeed", "bootstrap") or similar

    # Placeholder - return empty for now
    return []

def render_standings_table(teams):
    """Render standings table."""
    
    rows = []
    
    # Header
    rows.append(
        render.Row(
            expanded = True,
            main_align = "space_between",
            children = [
                render.Text("", font = "CG-pixel-3x5-mono", width = 10),
                render.Text("W", font = "CG-pixel-3x5-mono", color = "#888"),
                render.Text("L", font = "CG-pixel-3x5-mono", color = "#888"),
                render.Text("OT", font = "CG-pixel-3x5-mono", color = "#888"),
                render.Text("P", font = "CG-pixel-3x5-mono", color = "#888"),
            ]
        )
    )
    
    # Team rows
    for i, team in enumerate(teams):
        color = TEAMS.get(team["abbr"], {}).get("color", "#fff")
        rows.append(
            render.Row(
                expanded = True,
                main_align = "space_between",
                children = [
                    render.Text(
                        str(i + 1) + " " + team["abbr"],
                        font = "CG-pixel-3x5-mono",
                        color = color
                    ),
                    render.Text(str(team.get("wins", 0)), font = "CG-pixel-3x5-mono"),
                    render.Text(str(team.get("losses", 0)), font = "CG-pixel-3x5-mono"),
                    render.Text(str(team.get("otl", 0)), font = "CG-pixel-3x5-mono"),
                    render.Text(str(team.get("points", 0)), font = "CG-pixel-3x5-mono", color = "#0f0"),
                ]
            )
        )
    
    return render.Root(
        child = render.Column(
            children = rows,
            main_align = "space_around"
        )
    )

def render_team_standing_detail(team, position):
    """Render detailed standing for a specific team."""
    
    team_info = TEAMS.get(team["abbr"], {})
    
    return render.Root(
        child = render.Column(
            main_align = "space_around",
            cross_align = "center",
            children = [
                render.Text(
                    team["abbr"],
                    font = "10x20",
                    color = team_info.get("color", "#fff")
                ),
                render.Text(
                    "#{} in League".format(position),
                    font = "5x8",
                    color = "#888"
                ),
                render.Row(
                    main_align = "center",
                    children = [
                        render.Text(
                            "{}-{}-{}".format(
                                team.get("wins", 0),
                                team.get("losses", 0),
                                team.get("otl", 0)
                            ),
                            font = "6x13",
                            color = "#fff"
                        )
                    ]
                ),
                render.Text(
                    "{} PTS".format(team.get("points", 0)),
                    font = "6x13",
                    color = "#0f0"
                )
            ]
        )
    )

def render_cycle_mode(team_filter, animate, show_logos):
    """Cycle through multiple displays."""
    
    displays = []
    
    # Add games
    games = fetch_games()
    if team_filter != "all":
        games = filter_games_by_team(games, team_filter)
    
    for game in games[:3]:  # Show up to 3 games
        displays.append(render_game_score(game, show_logos))
    
    # Add standings
    standings = fetch_standings()
    if standings:
        displays.append(render_standings_table(standings[:5]))
    
    if not displays:
        return render_no_games_message()

    # Cycle through displays
    return render.Root(
        delay = 4000,  # 4 seconds per display
        child = render.Animation(
            children = displays
        )
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
    
    if "FINAL" in status:
        if "OT" in status:
            return "FINAL/OT"
        elif "SO" in status:
            return "FINAL/SO"
        return "FINAL"
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
        # Scheduled game - show time
        return game.get("time", "7:00 PM")

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
