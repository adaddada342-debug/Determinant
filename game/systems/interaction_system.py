from __future__ import annotations

import pygame

from game.entities.interactable import Interactable


class InteractionSystem:
    def __init__(self, interactables: list[Interactable], radius: float = 20) -> None:
        self.interactables = interactables
        self.radius = radius
        self.nearby: Interactable | None = None

    def update(self, player_rect: pygame.Rect) -> None:
        self.nearby = None
        p = pygame.Vector2(player_rect.center)
        closest = 10e6
        for interactable in self.interactables:
            if not interactable.enabled:
                continue
            d = p.distance_to(interactable.rect.center)
            if d <= self.radius and d < closest:
                self.nearby = interactable
                closest = d

    def interact(self):
        if self.nearby:
            return self.nearby.action
        return None
