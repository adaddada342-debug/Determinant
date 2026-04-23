from __future__ import annotations

import pygame


class AudioSystem:
    def __init__(self) -> None:
        self.enabled = False
        try:
            pygame.mixer.init()
            self.enabled = True
        except pygame.error:
            self.enabled = False
        self.layers: dict[str, float] = {"hum": 0.35, "noise": 0.2, "silence": 0.0}
        self.current_ambience = "hum"

    def set_ambience(self, layer: str) -> None:
        if layer in self.layers:
            self.current_ambience = layer

    def trigger(self, name: str) -> None:
        _ = name

    def update(self, _dt: float) -> None:
        pass
