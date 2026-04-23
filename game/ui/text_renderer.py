from __future__ import annotations

import pygame


class TextRenderer:
    def __init__(self) -> None:
        pygame.font.init()
        self.font = pygame.font.SysFont("consolas", 12)

    def draw(self, surface: pygame.Surface, text: str, pos: tuple[int, int], color=(220, 220, 220), alpha=255) -> None:
        img = self.font.render(text, True, color)
        img.set_alpha(alpha)
        surface.blit(img, pos)
