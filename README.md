# PWHL Scores for Tidbyt

A Tidbyt app that displays live scores, game schedules, and standings for the Professional Women's Hockey League (PWHL).

## Features

- **Live Game Scores**: Real-time score updates during games
- **Team Logos**: Official PWHL team logos from HockeyTech API (cached 24 hours)
- **Team Colors**: Full-width colored backgrounds using official PWHL team colors
- **Winner Highlighting**: Yellow scores for winners, muted for losers (NHL Scores style)
- **Game Status**: Period, time remaining, intermission indicators
- **Team Filtering**: Follow your favorite team
- **Multiple Display Modes**:
  - Auto: Prioritizes live games, falls back to upcoming/recent games
  - Scores: Shows game scores only
  - Standings: Shows league standings (when available)
  - Cycle: Rotates through multiple displays
- **Animations**: Smooth transitions between different information displays
- **Professional Layout**: NHL Scores-inspired design with logos, team colors, and clean typography
- **Robust Caching**: Multi-tier caching with stale fallback during API outages
- **Data Validation**: Filters invalid games and validates all API responses

## Supported Teams (2024-25 Season)

- Boston Fleet (BOS)
- Minnesota Frost (MIN)
- Montréal Victoire (MTL)
- New York Sirens (NYS)
- Ottawa Charge (OTT)
- Toronto Sceptres (TOR)
- Seattle Torrent (SEA)
- Vancouver Goldeneyes (VAN)

## Installation

### Prerequisites

1. Install [Pixlet](https://github.com/tidbyt/pixlet):
```bash
# macOS
brew install tidbyt/tidbyt/pixlet

# Linux/WSL
curl -LO https://github.com/tidbyt/pixlet/releases/download/v0.33.0/pixlet_0.33.0_linux_amd64.tar.gz
tar -xvf pixlet_0.33.0_linux_amd64.tar.gz
sudo mv pixlet /usr/local/bin/
```

2. Ensure you have a Tidbyt device and the mobile app installed

### Local Testing

1. Clone or download the repository:
```bash
git clone https://github.com/andyrak/tidbyt-pwhl.git
cd tidbyt-pwhl
```

2. Test the app locally:
```bash
# Render with default settings
pixlet render pwhl_scores.star

# Render with configuration options
pixlet render pwhl_scores.star team=TOR display_mode=auto animate=true
```

3. View the app in your browser:
```bash
pixlet serve pwhl_scores.star
# Open http://localhost:8080 in your browser
```

### Push to Your Tidbyt

1. Get your Tidbyt device ID and API key from the mobile app:
   - Open Tidbyt mobile app
   - Go to Settings > General > Get API key

2. Push the app to your device:
```bash
# Push with default settings
pixlet push --api-token YOUR_API_TOKEN YOUR_DEVICE_ID pwhl_scores.star

# Push with custom configuration
pixlet push --api-token YOUR_API_TOKEN YOUR_DEVICE_ID pwhl_scores.star \
  --installation-id pwhl-scores \
  team=TOR \
  display_mode=auto \
  animate=true
```

## Configuration Options

| Option | Default | Values | Description |
|--------|---------|--------|-------------|
| `team` | `all` | `all`, `BOS`, `MIN`, `MTL`, `NYS`, `OTT`, `TOR`, `SEA`, `VAN` | Filter by specific team |
| `display_mode` | `auto` | `auto`, `scores`, `standings`, `cycle` | Display mode (auto prioritizes live games) |
| `show_logos` | `true` | `true`, `false` | Show team logos when available |
| `show_period_scores` | `false` | `true`, `false` | Show period-by-period breakdown |
| `animate` | `true` | `true`, `false` | Enable animations between displays |

## Architecture

### API Integration

The app uses the **HockeyTech API** for PWHL data:
- **Endpoint**: `https://lscluster.hockeytech.com/feed/index.php`
- **Feed**: `modulekit` with `scorebar` view for games
- **Authentication**: Client code and API key parameters

Key features:
- Centralized `build_api_url()` helper for consistent request building
- Automatic retry with HTTP-level caching (30 seconds)
- Comprehensive response validation

### Caching Strategy

Multi-tier caching for reliability and performance:

| Cache Type | TTL | Purpose |
|------------|-----|---------|
| Fresh cache | 60 seconds | Live game updates |
| Stale cache | 1 hour | Fallback during API outages |
| HTTP cache | 30 seconds | Network-level caching |

The app uses versioned cache keys (`v3`) to handle data structure updates safely.

### Data Flow

1. **Fetch** → Check fresh cache → API call → Validate response
2. **Normalize** → Filter invalid games → Convert types → Validate teams
3. **Render** → Select display mode → Apply team filter → Animate

### Error Handling

- Network-first strategy with graceful degradation
- Falls back to stale cache on API failures
- Filters TBD teams and invalid game data
- Returns empty results instead of crashing

## Development

### File Structure

```
tidbyt-pwhl/
├── pwhl_scores.star           # Main application
├── manifest.yaml              # App metadata
├── README.md                  # User documentation
├── API_INTEGRATION.md         # API integration notes
├── REFACTORING_SUMMARY.md     # Architecture documentation
└── pwhl_scores.webp           # Preview image
```

### Code Organization

The application is organized into logical sections:

1. **API Configuration** (lines 15-28) - Centralized API settings and cache config
2. **Team Metadata** (lines 30-80) - Team colors and information
3. **API Helpers** (lines 82-124) - URL building and cache key generation
4. **Main Entry Point** (lines 126-183) - Display mode routing
5. **Data Fetching** (lines 185-252) - API calls with error handling
6. **Data Normalization** (lines 254-391) - Multi-layer data transformation
7. **Game State Helpers** (lines 431-466) - Game filtering and state detection
8. **Rendering Functions** (lines 468-859) - UI rendering
9. **Display Helpers** (lines 861-918) - Status formatting and utilities
10. **Configuration Schema** (lines 920-980) - User configuration options

### Customization

You can customize the app by modifying:

1. **Team Colors** (lines 30-80): Edit the `TEAMS` dictionary
2. **Display Layout**: Modify the `render_*` functions (lines 468+)
3. **Animation Timing**: Adjust `delay` values in animation functions
4. **Cache TTL** (lines 24-28): Update cache duration values
5. **API Endpoints**: Update `build_api_url()` if official APIs become available

### Adding Features

The modular architecture makes it easy to add new features:

**Data Layer Enhancements:**
- Implement `fetch_standings_from_api()` for real standings data
- Add player statistics endpoints
- Fetch goal scorer information
- Add game summary details

**Rendering Enhancements:**
- Complete `render_powerplay()` implementation
- Enhance `render_period_breakdown()` with actual period scores
- Add team logo display (when `show_logos=true`)
- Create new animation frames for additional stats

**Configuration Options:**
- Add more granular animation controls
- Team-specific color customization
- Font size preferences

## Troubleshooting

### No Games Showing

The app displays "No Games Available" when:
- PWHL is in off-season
- No games scheduled for today
- API is temporarily unavailable (checks stale cache first)

**Solutions:**
- Verify the season is active
- Check internet connection
- Wait 1-2 minutes for cache to refresh
- The app automatically falls back to 1-hour stale cache during outages

### API Errors

The app has robust error handling:
- **Fresh cache (60s)**: Primary data source
- **Stale cache (1 hour)**: Automatic fallback during API failures
- **Empty display**: Only shown when both caches are empty

If you see persistent errors:
- Check `pixlet render pwhl_scores.star` for error messages
- Verify API endpoint is accessible: `curl https://lscluster.hockeytech.com/feed/index.php`
- Clear cache by incrementing `CACHE_VERSION` in the code

### Wrong Times Displayed

- Set your Tidbyt timezone correctly in the mobile app
- Times are shown as provided by the API (typically Eastern Time)

### Team Filter Not Working

- Verify team abbreviation: `BOS`, `MIN`, `MTL`, `NYS`, `OTT`, `TOR`, `SEA`, `VAN`
- Check team name variations in API response
- TBD teams are automatically filtered out

## Contributing

We welcome contributions! To contribute:

1. **Test locally**: Run `pixlet check pwhl_scores.star` for syntax validation
2. **Verify rendering**: Use `pixlet serve pwhl_scores.star` to test in browser
3. **Test configurations**: Try different team filters and display modes
4. **Document changes**: Update relevant documentation files
5. **Follow patterns**: Maintain the existing code organization

### Development Checklist

- [ ] Code passes `pixlet check`
- [ ] All display modes tested
- [ ] Team filtering works correctly
- [ ] Error handling tested (API failures)
- [ ] Documentation updated
- [ ] Cache versioning updated if data structure changes

## Community App Submission

To submit as a Tidbyt community app:

1. Fork the [Tidbyt Community](https://github.com/tidbyt/community) repo
2. Create app directory: `apps/pwhlscores/`
3. Copy application files
4. Run `pixlet check` to validate
5. Test thoroughly with different configurations
6. Submit pull request

**Requirements:**
- ✅ App renders without errors
- ✅ Robust error handling (implemented)
- ✅ Appropriate caching (multi-tier with fallback)
- ✅ Configuration schema (5 options)
- ✅ Data validation (filters TBD teams)
- ✅ Follows Tidbyt guidelines

## Architecture Notes

This application follows patterns from modern web applications:

- **pwhl-remix reference**: Data normalization, error handling, and caching patterns adapted from the pwhl-remix TypeScript application
- **Separation of concerns**: Clear boundaries between API, normalization, and rendering layers
- **Type safety**: String-to-int conversions and data validation throughout
- **Graceful degradation**: Multi-tier caching ensures reliability during API outages

See `REFACTORING_SUMMARY.md` for detailed architecture documentation.

## Credits

`"Everybody watches women's sports."`

- **Author**: Andy Rakauskas [@andyrak](https://github.com/andyrak)
- **Foundational Work**: This project was made possible by [Sasha Moak's](https://github.com/smoak) excellent work on [PWHL Remix](https://github.com/smoak/pwhl-remix), which provided the inspiration and basis for this app.
- **Data Source**: HockeyTech API (publicly available PWHL data)
- **Team Information**: Official PWHL sources

## License

MIT License - Feel free to modify and distribute

## Support

For issues or questions:
- Check the [Tidbyt Community Forum](https://discuss.tidbyt.com)
- Review [Tidbyt Developer Docs](https://tidbyt.dev)
- File issues on GitHub

## Disclaimer

This is an unofficial app and is not affiliated with or endorsed by the Professional Women's Hockey League (PWHL).
