from __future__ import annotations

import pygame


class LightingSystem:
    def __init__(self, width: int, height: int) -> None:
        self.overlay = pygame.Surface((width, height), pygame.SRCALPHA)
        self.intensity = 195
        self.radius = 90

    def set_profile(self, intensity: int, radius: int) -> None:
        self.intensity = max(0, min(255, intensity))
        self.radius = max(20, radius)

    def render(self, target: pygame.Surface, light_pos: tuple[int, int]) -> None:
        self.overlay.fill((0, 0, 0, self.intensity))
        pygame.draw.circle(self.overlay, (0, 0, 0, 0), light_pos, self.radius)
        target.blit(self.overlay, (0, 0))
