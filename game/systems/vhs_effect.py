from __future__ import annotations

import random
import pygame


class VHSEffect:
    def __init__(self, width: int, height: int) -> None:
        self.width = width
        self.height = height
        self.jitter_strength = 2

    def apply(self, surface: pygame.Surface) -> None:
        for y in range(0, self.height, 3):
            pygame.draw.line(surface, (0, 0, 0, 25), (0, y), (self.width, y))

        if random.random() < 0.15:
            y = random.randint(0, self.height - 1)
            offset = random.randint(-8, 8)
            row = surface.subsurface(pygame.Rect(0, y, self.width, 1)).copy()
            surface.blit(row, (offset, y))

        jitter = random.randint(-self.jitter_strength, self.jitter_strength)
        if jitter:
            cp = surface.copy()
            surface.blit(cp, (jitter, 0))

        self._chromatic_aberration(surface)

    def _chromatic_aberration(self, surface: pygame.Surface) -> None:
        r = surface.copy()
        b = surface.copy()
        r.fill((255, 0, 0), special_flags=pygame.BLEND_MULT)
        b.fill((0, 0, 255), special_flags=pygame.BLEND_MULT)
        surface.blit(r, (-1, 0), special_flags=pygame.BLEND_ADD)
        surface.blit(b, (1, 0), special_flags=pygame.BLEND_ADD)
