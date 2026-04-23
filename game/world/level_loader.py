from __future__ import annotations

import json
from pathlib import Path

from game.world.tilemap import TileMap


class LevelLoader:
    def __init__(self, level_file: Path) -> None:
        self.level_file = level_file
        self.data = json.loads(level_file.read_text(encoding="utf-8"))

    def get_zone(self, zone_name: str) -> dict:
        return self.data["zones"][zone_name]

    def load_tilemap(self, zone_name: str) -> TileMap:
        return TileMap(self.data["zones"][zone_name]["tilemap"])

    def get_spawn(self, zone_name: str) -> tuple[float, float]:
        spawn = self.data["zones"][zone_name]["spawn"]
        return float(spawn[0]), float(spawn[1])
