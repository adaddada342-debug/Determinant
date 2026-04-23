from __future__ import annotations

import random
import pygame


class Camera:
    def __init__(self, width: int, height: int) -> None:
        self.rect = pygame.Rect(0, 0, width, height)
        self.offset = pygame.Vector2()
        self.drift = pygame.Vector2()
        self.follow_lerp = 0.1
        self.drift_strength = 1.8
        self.enable_drift = True

    def update(self, target_rect: pygame.Rect, dt: float) -> None:
        desired = pygame.Vector2(
            target_rect.centerx - self.rect.width / 2,
            target_rect.centery - self.rect.height / 2,
        )
        self.offset = self.offset.lerp(desired, min(1.0, self.follow_lerp + dt * 0.8))
        if self.enable_drift:
            self.drift.x = random.uniform(-self.drift_strength, self.drift_strength)
            self.drift.y = random.uniform(-self.drift_strength, self.drift_strength)
        else:
            self.drift.update(0, 0)

    def world_to_screen(self, world_pos: pygame.Vector2) -> pygame.Vector2:
        return pygame.Vector2(world_pos.x - self.offset.x + self.drift.x, world_pos.y - self.offset.y + self.drift.y)

    def apply_rect(self, rect: pygame.Rect) -> pygame.Rect:
        return rect.move(-self.offset.x + self.drift.x, -self.offset.y + self.drift.y)
