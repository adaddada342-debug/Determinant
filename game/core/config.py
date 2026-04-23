from pathlib import Path

SCREEN_WIDTH = 960
SCREEN_HEIGHT = 540
INTERNAL_WIDTH = 320
INTERNAL_HEIGHT = 180
TARGET_FPS = 60
TITLE = "The Afton Files"

DATA_DIR = Path(__file__).resolve().parent.parent / "data"
LORE_PATH = DATA_DIR / "lore_data.json"
LEVEL_PATH = DATA_DIR / "level_data.json"
ASSET_DIR = Path(__file__).resolve().parent.parent / "assets"
