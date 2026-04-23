from __future__ import annotations

import pygame


class Interactable:
    def __init__(self, iid: str, rect: pygame.Rect, prompt: str, action: dict) -> None:
        self.id = iid
        self.rect = rect
        self.prompt = prompt
        self.action = action
        self.enabled = True

    def render_hint(self, surface: pygame.Surface, camera, color=(210, 210, 255)) -> None:
        if not self.enabled:
            return
        draw_rect = camera.apply_rect(self.rect)
        pygame.draw.rect(surface, color, draw_rect, 1)
