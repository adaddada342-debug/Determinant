from __future__ import annotations

from typing import Dict, List, Tuple

import pygame


class TileMap:
    def __init__(self, map_data: dict) -> None:
        self.width = map_data["width"]
        self.height = map_data["height"]
        self.tile_size = map_data["tile_size"]
        self.layers: Dict[str, List[List[int]]] = map_data["layers"]
        self.tileset = map_data["tileset"]

    def world_to_tile(self, x: float, y: float) -> Tuple[int, int]:
        return int(x // self.tile_size), int(y // self.tile_size)

    def is_blocked(self, x: float, y: float) -> bool:
        tx, ty = self.world_to_tile(x, y)
        if tx < 0 or ty < 0 or tx >= self.width or ty >= self.height:
            return True
        return self.layers["collision"][ty][tx] == 1

    def query_trigger(self, x: float, y: float) -> int:
        tx, ty = self.world_to_tile(x, y)
        if 0 <= tx < self.width and 0 <= ty < self.height:
            return self.layers["trigger"][ty][tx]
        return 0

    def render(self, surface: pygame.Surface, camera, layer_name: str = "visual") -> None:
        layer = self.layers[layer_name]
        start_x = max(0, int(camera.offset.x // self.tile_size) - 1)
        start_y = max(0, int(camera.offset.y // self.tile_size) - 1)
        end_x = min(self.width, start_x + surface.get_width() // self.tile_size + 3)
        end_y = min(self.height, start_y + surface.get_height() // self.tile_size + 3)

        for y in range(start_y, end_y):
            for x in range(start_x, end_x):
                tile = layer[y][x]
                if tile == 0:
                    continue
                color = self.tileset.get(str(tile), [80, 80, 80])
                rect = pygame.Rect(
                    x * self.tile_size - camera.offset.x + camera.drift.x,
                    y * self.tile_size - camera.offset.y + camera.drift.y,
                    self.tile_size,
                    self.tile_size,
                )
                pygame.draw.rect(surface, color, rect)
